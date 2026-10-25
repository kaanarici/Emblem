import { logEvent } from "@/lib/log";
import { createComposeErrorDiagnostics } from "@/lib/composeErrorDiagnostics";
import { prepareDraftStepImages, prepareGeneratedStepImages } from "@/lib/generatedStepImages";
import { classifyProviderError, errorChain } from "@/lib/generationErrors";
import type { GenerationEmitter } from "@/lib/generationEvents";
import type { GenerationEvidence } from "@/lib/generationEvidence";
import {
  draftBodyText,
  nullTolerantDraft,
  previewProjection,
  progressiveArrayOutput,
} from "@/lib/generationPreview";
import { pageCompositionIssues } from "@/lib/generationProtocol";
import type { InferenceSession } from "@/lib/inferenceTelemetry";
import type { LatencyStages } from "@/lib/latency";
import type { createPageAssembly } from "@/lib/pageAssembly";
import { usesOpenAIStrictSchema } from "@/lib/provider";
import { EXPANSION_ARTICLE_GUIDANCE } from "@/lib/prompt";
import { reasoningOptions } from "@/lib/reasoning";
import { isPageFinish, pageFinishSchema, type PageFinish } from "@/lib/responsePlan";
import { type Block } from "@/lib/schema";
import {
  compositionEnvelopeSchema,
  compositionEnvelopeTextCatalog,
  nullsAsOmitted,
  isForeignComposerElement,
} from "@/lib/composerSchema";
import { temporalGrounding } from "@/lib/temporalGrounding";
import { Output, streamText, type ModelMessage, type Schema } from "ai";

const ATTEMPTS = 2;
const PAGE_MAX_OUTPUT_TOKENS = 12_288;
const RETRY_INPUT_CHARS = 60_000;
const SALVAGE_MIN_CONTENT_BLOCKS = 2;
const ARTICLE_MAX_OUTPUT_TOKENS = 3_072;
const RETRY_TEMPERATURE = 0.4;
const REPORTED_ISSUES = 8;
const REPORTED_BLOCK_TYPES = 24;
const WEATHER_GUIDANCE =
  "\n\n[Server-owned weather] The server inserts one native weather component per place after your introduction: today with its hours, and the week, where each day opens its own hours in place. Write only the introduction around it; never emit weather blocks, day-by-day sections or restate its numbers. Fulfill EVERY other part of the user request (movies, places, decisions, etc.) with the appropriate normal components. Weather alone needs only a concise contextual introduction and pageFinish; do not invent extra sections, component families, or activities to fill a quota.";
const GENERIC_RETRY = [
  "[Full-page visual composition retry]",
  "Return the complete repaired page with pageMeta first and one strong primary visual.",
  "Finish the centerpiece and every required item before adding optional support. Keep the page concise, but do not collapse a multi-item set or sequence to one item.",
].join("\n");
const CONCISE_RETRY =
  "The previous attempt ran out of output space. Be concise: at most five supporting sections, at most six cards per carousel, one-sentence captions, no repeated facts, and copy image queries exactly as supplied without expanding them.";

type ComposeRequest = {
  messages: ModelMessage[];
  systemPrompt: string;
  requestPrompt: string;
  datePrompt: string;
  inference: InferenceSession;
  persist: { requestId: string; timezone: string };
  articleLead: boolean;
  previewEnabled: boolean;
  evidence: GenerationEvidence;
  assembly: ReturnType<typeof createPageAssembly>;
  emitter: GenerationEmitter;
  stepImageOptions: { ownerScope: string; tokenSecret: string } | null;
  warm: (node: unknown) => void;
  signals: { request: AbortSignal; model: AbortSignal; deadline: AbortSignal };
  addTiming: (stage: string, duration: number) => void;
  stages: LatencyStages;
};

type ComposeResult = { ok: true; blocks: Block[] } | { ok: false; error: unknown };

function clipGroundedInput(messages: ModelMessage[], max: number): ModelMessage[] {
  const last = messages.at(-1);
  if (!last || last.role !== "user") return messages;
  const marker = "\n[Research notes shortened to fit; use only what is shown]";
  const clip = (text: string) => (text.length > max ? text.slice(0, max) + marker : text);
  const content =
    typeof last.content === "string"
      ? clip(last.content)
      : last.content.map((part) =>
          part.type === "text" ? { ...part, text: clip(part.text) } : part,
        );
  return [...messages.slice(0, -1), { ...last, content } as ModelMessage];
}

function continuationFeedback(prefix: Block[], truncated: boolean): string {
  return [
    "[Continuation of a page that is already partly visible]",
    "These blocks are already shown to the user, in this order. Do not repeat, rewrite or reorder them, and do not emit another pageMeta:",
    JSON.stringify(prefix),
    "Return only the blocks that follow them, then exactly one terminal pageFinish element.",
    ...(truncated ? [CONCISE_RETRY] : []),
  ].join("\n");
}

const contentBlockCount = (blocks: readonly Block[]) =>
  blocks.filter((block) => !["pageMeta", "sectionHeader", "chipRow"].includes(block.type)).length;

function rejectionFeedback(
  requestId: string,
  attempt: number,
  issues: string[],
  page: Block[],
  incomplete: boolean,
): string {
  const blockTypes = Array.from(new Set(page.map(({ type }) => type))).slice(
    0,
    REPORTED_BLOCK_TYPES,
  );
  const reported = issues.slice(0, REPORTED_ISSUES);
  logEvent("warn", "compose page rejected", {
    requestId,
    attempt,
    issues: reported.join(" | "),
    blockTypes: blockTypes.join(","),
  });
  return [
    "[Full-page visual composition retry]",
    `Exact issues: ${JSON.stringify(reported)}`,
    `Emitted block types: ${JSON.stringify(blockTypes)}`,
    "Return the complete repaired page with pageMeta first and one strong primary visual.",
    ...(incomplete
      ? [
          "The prior structured page ended incompletely. Rebuild the entire page; never return a partial set, sequence, carousel, recipe, or routine.",
        ]
      : []),
    "Finish the planned centerpiece and every required item before adding optional support. Keep the page concise, but do not collapse a multi-item set or sequence to one item.",
  ].join("\n");
}

let googleCatalog: Promise<string> | undefined;
const googleCatalogPrompt = () =>
  (googleCatalog ??= compositionEnvelopeTextCatalog(pageFinishSchema).then(
    (schema) =>
      `\n\nReturn a JSON object with an "elements" array. Every element must match this JSON Schema:\n${JSON.stringify(schema)}`,
  ));

export async function composePage(request: ComposeRequest): Promise<ComposeResult> {
  const { inference, evidence, assembly, emitter, signals } = request;
  const started = performance.now();
  const googleCompose = inference.profile.compose.provider === "google";
  const openAICompose = usesOpenAIStrictSchema(inference.profile.compose);
  const envelope: Schema<Block | PageFinish> = compositionEnvelopeSchema(pageFinishSchema);
  const outputSchema = openAICompose ? nullsAsOmitted(envelope) : envelope;
  const dateGrounding = temporalGrounding(
    request.datePrompt,
    [...evidence.sources.values(), ...evidence.datedSources],
    request.persist.timezone,
  );
  const compositionPrompt =
    request.systemPrompt +
    (request.articleLead ? EXPANSION_ARTICLE_GUIDANCE : "") +
    (evidence.weatherPayloads.length ? WEATHER_GUIDANCE : "") +
    request.requestPrompt +
    (googleCompose ? await googleCatalogPrompt() : "") +
    dateGrounding.context;
  const outputOptions = {
    element: outputSchema,
    name: "blocks",
    description: request.articleLead
      ? "Only the supporting article body beneath the client-owned lead, followed by exactly one terminal pageFinish element"
      : "A complete coherent visual page: pageMeta first, one strong primary visual chosen from the content's shape, distinct titled supporting sections, and exactly one terminal pageFinish element",
  };

  let lastError: unknown = null;
  let retryFeedback: string | null = null;
  let messages = request.messages;
  let prefix: Block[] = [];
  let shownCount = 0;
  let requiredInputSeen = false;
  let salvage: Block[] | null = null;
  let truncatedAttempt = false;
  for (let attempt = 0; attempt < ATTEMPTS; attempt++) {
    if (signals.deadline.aborted) break;
    emitter.beginPreviewAttempt(attempt + 1);
    request.addTiming("compose.attempts", 1);
    let streamError: unknown = null;
    let refused = false;
    let truncated = false;
    let streamedChars = 0;
    const continuing = prefix.length > 0;
    const prefixIDs = new Set(prefix.map(({ id }) => id));
    let restarted = false;
    const page: Block[] = [];
    let finish: PageFinish | null = null;
    const diagnostics = createComposeErrorDiagnostics(request.persist.requestId);
    const recordStreamError = (error: unknown, source: "sdk-onError" | "compose-catch") => {
      if (streamError == null) {
        inference.fail("compose");
        streamError = error;
      }
      const diagnostic = diagnostics(error, source);
      if (diagnostic)
        console.error(
          JSON.stringify({
            event: "generate stream error",
            attempt,
            ...diagnostic,
            streamedChars,
            parsedElements: page.length,
          }),
        );
    };
    const accept = (element: Block | PageFinish) => {
      if (isPageFinish(element)) {
        finish = element;
        if (element.requiredInput) requiredInputSeen = true;
        return;
      }
      if (continuing && !restarted && element.type === "pageMeta") {
        restarted = true;
        page.length = 0;
      }
      if (continuing && !restarted && prefixIDs.has(element.id)) return;
      let block = assembly.canonicalComposerBlock(element);
      if (request.stepImageOptions)
        block = prepareGeneratedStepImages([block], request.stepImageOptions)[0]!;
      page.push(block);
      request.warm(block);
    };
    const callOptions = {
      model: inference.models.compose,
      system: retryFeedback ? `${compositionPrompt}\n\n${retryFeedback}` : compositionPrompt,
      messages,
      ...reasoningOptions(
        inference.profile.compose.provider,
        "none",
        inference.profile.compose.modelId,
      ),
      ...(googleCompose ? { providerOptions: { google: { structuredOutputs: false } } } : {}),
      temperature: attempt === 0 ? 0 : RETRY_TEMPERATURE,
      maxOutputTokens: request.articleLead ? ARTICLE_MAX_OUTPUT_TOKENS : PAGE_MAX_OUTPUT_TOKENS,
      abortSignal: signals.model,
      onLanguageModelCallStart(event: Parameters<InferenceSession["start"]>[1]) {
        inference.start("compose", event);
      },
      onLanguageModelCallEnd(event: Parameters<InferenceSession["record"]>[1]) {
        request.addTiming("compose.model", event.performance.responseTimeMs);
        if (event.performance.timeToFirstOutputMs != null) {
          request.addTiming("compose.modelFirstOutput", event.performance.timeToFirstOutputMs);
        }
        inference.record("compose", event);
      },
      onChunk({ chunk }: { chunk: { type: string; text?: string } }) {
        if (typeof chunk.text === "string") streamedChars += chunk.text.length;
      },
      onError({ error }: { error: unknown }) {
        recordStreamError(error, "sdk-onError");
      },
      onFinish(event: { finishReason: string }) {
        if (event.finishReason === "length") truncated = true;
        if (event.finishReason !== "content-filter") return;
        refused = true;
        emitter.preview([]);
      },
    };
    const options = continuing
      ? {
          ...outputOptions,
          description:
            "Only the blocks that follow the already-visible page prefix, followed by exactly one terminal pageFinish element",
        }
      : outputOptions;

    try {
      if (request.previewEnabled) {
        const result = streamText({
          ...callOptions,
          output: progressiveArrayOutput({
            ...options,
            draft: openAICompose ? nullTolerantDraft : draftBodyText,
            skip: isForeignComposerElement,
          }),
        });
        let consumed = 0;
        for await (const progress of result.partialOutputStream) {
          signals.request.throwIfAborted();
          for (const element of progress.complete.slice(consumed)) accept(element);
          consumed = progress.complete.length;
          let draft =
            progress.draft && !isPageFinish(progress.draft)
              ? assembly.canonicalComposerBlock(progress.draft)
              : null;
          if (draft?.type === "stepCarousel" && request.stepImageOptions) {
            draft = prepareDraftStepImages(draft, request.stepImageOptions);
            request.warm(draft);
          }
          const visible = [
            ...(restarted ? [] : prefix),
            ...page,
            ...(draft && !(continuing && !restarted && draft.type === "pageMeta") ? [draft] : []),
          ];
          const shown = assembly.finalizePage(visible, null, dateGrounding);
          const projected = previewProjection(assembly.projectPage(shown.blocks), {
            activeDraft: progress.draft?.type === "stepCarousel" ? progress.draft : undefined,
          });
          if (
            shown.issues.length === 0 &&
            pageCompositionIssues(projected).length === 0 &&
            (attempt === 0 || projected.length >= shownCount)
          ) {
            emitter.preview(projected, false, draft?.id ?? null);
            shownCount = projected.length;
          }
        }
        const output = await result.output;
        page.length = 0;
        finish = null;
        restarted = false;
        for (const element of output) accept(element);
      } else {
        const result = streamText({ ...callOptions, output: Output.array(options) });
        for await (const element of result.elementStream) accept(element);
        await Promise.resolve(result.output);
      }
    } catch (error) {
      recordStreamError(error, "compose-catch");
    }
    if (refused) throw new Error("Generation refused");
    request.stages.compose = performance.now() - started;
    truncated ||= errorChain(streamError).some((link) => link.finishReason === "length");
    truncatedAttempt ||= truncated;

    const combined = restarted ? [...page] : [...prefix, ...page];
    const { blocks, issues } = assembly.finalizePage(combined, finish, dateGrounding);
    if (!streamError && issues.length === 0 && blocks.length > 0) {
      return { ok: true, blocks };
    }
    if (streamError && !requiredInputSeen) {
      const bare =
        issues.length === 0 ? null : assembly.finalizePage(combined, null, dateGrounding);
      const candidate = !bare ? blocks : bare.issues.length === 0 ? bare.blocks : null;
      if (candidate && combined.length > prefix.length) prefix = combined;
      if (
        candidate &&
        truncatedAttempt &&
        contentBlockCount(combined) >= SALVAGE_MIN_CONTENT_BLOCKS &&
        candidate.length > (salvage?.length ?? 0)
      )
        salvage = candidate;
    }
    if (truncated) {
      logEvent("warn", "compose output cap reached", {
        requestId: request.persist.requestId,
        attempt: attempt + 1,
        streamedChars,
        parsedElements: combined.length,
      });
      messages = clipGroundedInput(messages, RETRY_INPUT_CHARS);
    }
    const planError = issues.length > 0 ? new Error(issues.join("; ")) : null;
    if (prefix.length > 0) {
      retryFeedback = continuationFeedback(prefix, truncated);
    } else if (planError) {
      retryFeedback = rejectionFeedback(
        request.persist.requestId,
        attempt + 1,
        issues,
        combined,
        errorChain(streamError).some((link) => link.name === "AI_NoObjectGeneratedError"),
      );
      if (truncated) retryFeedback += `\n${CONCISE_RETRY}`;
    } else {
      retryFeedback = truncated ? `${GENERIC_RETRY}\n${CONCISE_RETRY}` : GENERIC_RETRY;
    }
    lastError = streamError ?? planError ?? lastError ?? new Error("incomplete generation");
    if (streamError && classifyProviderError(streamError) === "provider_auth") break;
    if (signals.request.aborted || signals.deadline.aborted) break;
  }
  if (salvage && !requiredInputSeen && !signals.request.aborted && !signals.deadline.aborted) {
    logEvent("warn", "compose salvaged valid prefix", {
      requestId: request.persist.requestId,
      blocks: salvage.length,
    });
    return { ok: true, blocks: salvage };
  }
  return { ok: false, error: lastError ?? new Error("empty generation") };
}
