import { Output, type Schema } from "ai";
import { z } from "zod";
import { blockSchema, type Block } from "./schema";
import { withoutNulls } from "./composerSchema";
import { hasDuplicateJSONKeys, wellFormedStrings } from "./compositionJSON";
import { isGeneratedStepImageQuery } from "./generatedStepImages";
import {
  markOwnedPreviewFailure,
  ownValidationError,
  type OwnedPreviewFailureKind,
} from "./composeErrorDiagnostics";

type CompositionProgress<Element> = {
  complete: Element[];
  draft?: Element;
};

export function progressiveArrayOutput<Element>(options: {
  element: Schema<Element>;
  name: string;
  description: string;
  draft?: (value: unknown, text: string) => unknown;
  skip?: (value: unknown) => boolean;
}): Output.Output<Element[], CompositionProgress<Element>, never> {
  const completeOutput = Output.array(options);
  const partialParser = Output.object({ schema: z.unknown() });
  let previous = "";
  let offset = 0;
  let depth = 0;
  let inString = false;
  let escaped = false;
  let stringStart = 0;
  let rootKey = "";
  let elements = false;
  let start: number | undefined;
  let invalid = false;
  let invalidFailureKind: OwnedPreviewFailureKind | undefined;
  let invalidValidationError: unknown;
  let complete: Element[] = [];
  let draftStart: number | undefined;
  let safeDraft: Element | undefined;

  function withoutSkipped(text: string): string {
    if (!options.skip) return text;
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      return text;
    }
    const elements = (parsed as { elements?: unknown } | null)?.elements;
    if (!Array.isArray(elements) || !elements.some(options.skip)) return text;
    return JSON.stringify({
      ...(parsed as object),
      elements: elements.filter((element) => !options.skip!(element)),
    });
  }

  function reset() {
    offset = depth = stringStart = 0;
    inString = escaped = elements = invalid = false;
    invalidFailureKind = undefined;
    invalidValidationError = undefined;
    rootKey = "";
    start = undefined;
    draftStart = undefined;
    safeDraft = undefined;
    complete = [];
  }

  return {
    ...completeOutput,
    async parseCompleteOutput(options, context) {
      if (hasDuplicateJSONKeys(options.text))
        throw markOwnedPreviewFailure(
          new Error("Generation contains duplicate JSON object keys"),
          "duplicateKeys",
        );
      const output = await completeOutput.parseCompleteOutput(
        { ...options, text: withoutSkipped(options.text) },
        context,
      );
      if (!wellFormedStrings(output))
        throw markOwnedPreviewFailure(new Error("Generation contains invalid Unicode"), "Unicode");
      return output;
    },
    createElementStreamTransform: () => undefined,
    async parsePartialOutput({ text }) {
      if (!text.startsWith(previous)) reset();
      previous = text;
      if (hasDuplicateJSONKeys(text))
        throw markOwnedPreviewFailure(
          new Error("Duplicate composition preview keys"),
          "duplicateKeys",
        );
      const closed: string[] = [];
      for (; offset < text.length; offset++) {
        const c = text[offset]!;
        if (inString) {
          if (escaped) escaped = false;
          else if (c === "\\") escaped = true;
          else if (c === '"') {
            inString = false;
            if (depth === 1) {
              rootKey = JSON.parse(text.slice(stringStart, offset + 1));
            }
          }
          continue;
        }
        if (elements && depth === 2 && start === undefined && !/[\s,\]{]/.test(c)) {
          invalid = true;
        }
        if (c === '"') {
          inString = true;
          stringStart = offset;
        } else if (c === "{" || c === "[") {
          if (depth === 1 && c === "[" && rootKey === "elements") elements = true;
          if (elements && depth === 2 && c === "{") start = offset;
          depth++;
        } else if (c === "}" || c === "]") {
          depth--;
          if (elements && depth === 2 && c === "}" && start !== undefined) {
            JSON.parse(text.slice(0, offset + 1) + "]}");
            closed.push(text.slice(start, offset + 1));
            start = undefined;
          }
          if (elements && depth === 1 && c === "]") elements = false;
        }
      }
      for (const raw of closed) {
        if (hasDuplicateJSONKeys(raw)) {
          if (!invalid) invalidFailureKind = "duplicateKeys";
          invalid = true;
          continue;
        }
        const value: unknown = JSON.parse(raw);
        if (options.skip?.(value)) continue;
        if (!wellFormedStrings(value)) {
          if (!invalid) invalidFailureKind = "Unicode";
          invalid = true;
          continue;
        }
        const validation = await options.element.validate!(value);
        if (!validation.success) {
          if (!invalid) {
            invalidFailureKind = "closedElementValidation";
            invalidValidationError = ownValidationError(validation);
          }
          invalid = true;
        } else if (!invalid) complete.push(validation.value);
      }
      if (invalid) {
        const error = new Error("Invalid composition preview element");
        throw invalidFailureKind
          ? markOwnedPreviewFailure(error, invalidFailureKind, invalidValidationError)
          : error;
      }
      const progress: CompositionProgress<Element> = { complete: [...complete] };
      if (start !== draftStart) {
        draftStart = start;
        safeDraft = undefined;
      }
      if (start !== undefined && options.draft) {
        const tail = text.slice(start);
        JSON.parse(text.slice(0, start) + "null]}");
        const parsed = await partialParser.parsePartialOutput({ text: tail });
        const candidate = options.draft(parsed?.partial, tail);
        if (candidate) {
          const validated = await options.element.validate!(candidate);
          if (validated.success && wellFormedStrings(validated.value)) safeDraft = validated.value;
        }
        if (safeDraft) progress.draft = safeDraft;
      }
      return { partial: progress };
    },
  };
}

export function nullTolerantDraft(value: unknown, text: string): unknown | undefined {
  const step = draftStepBody(text, withoutNulls);
  if (step) return step;
  return draftBodyText(withoutNulls(value), text);
}

const TEXT_DRAFT_FIELDS = new Set(["type", "id", "style", "body", "highlights"]);

export function draftBodyText(value: unknown, text: string): unknown | undefined {
  const step = draftStepBody(text);
  if (step) return step;
  if (!value || typeof value !== "object" || Array.isArray(value)) return;
  const block = value as Record<string, unknown>;
  if (Object.keys(block).some((key) => !TEXT_DRAFT_FIELDS.has(key))) return;
  if (
    block.type !== "text" ||
    typeof block.id !== "string" ||
    !block.id ||
    (block.style !== "intro" && block.style !== "body" && block.style !== "footnote") ||
    typeof block.body !== "string" ||
    !block.body.trim()
  )
    return;
  const header = closedTextFields(text);
  if (!header || ["type", "id", "style"].some((key) => header.get(key) !== block[key])) return;

  const syntaxValid = ['"}', "}", ""].some((suffix) => {
    try {
      const closed = JSON.parse(text + suffix);
      return (
        closed.type === block.type &&
        closed.id === block.id &&
        closed.style === block.style &&
        closed.body === block.body
      );
    } catch {
      return false;
    }
  });
  if (!syntaxValid) return;
  return { type: "text", id: block.id, style: block.style, body: block.body };
}

function draftStepBody(
  text: string,
  normalize: (value: unknown) => unknown = (value) => value,
): Block | undefined {
  if (!endsAtStepBody(text) || hasDuplicateJSONKeys(text)) return;
  for (const suffix of ['"}]}', "}]}"]) {
    try {
      const source = normalize(JSON.parse(text + suffix));
      if (!stepSourceKeys(source)) continue;
      const parsed = blockSchema.safeParse(source);
      if (!parsed.success || parsed.data.type !== "stepCarousel" || !wellFormedStrings(parsed.data))
        continue;
      const block = parsed.data;
      if (!block.id || block.steps.length < 2 || !block.steps.at(-1)!.body.trim()) continue;

      if (!block.steps.slice(0, -1).some((step) => step.image?.kind !== "photo")) continue;
      return block;
    } catch {}
  }
}

function stepSourceKeys(value: unknown): boolean {
  const object = (node: unknown): node is Record<string, unknown> =>
    !!node && typeof node === "object" && !Array.isArray(node);
  const keys = (node: Record<string, unknown>, allowed: string[]) =>
    Object.keys(node).every((key) => allowed.includes(key));
  const image = (node: unknown) => object(node) && keys(node, ["query", "kind", "aspect"]);
  const icon = (node: unknown) =>
    object(node) &&
    keys(node, ["emoji", "sym", "image"]) &&
    (!Object.hasOwn(node, "image") || image(node.image));
  return (
    object(value) &&
    value.type === "stepCarousel" &&
    keys(value, ["type", "id", "continuity", "steps"]) &&
    Array.isArray(value.steps) &&
    value.steps.every(
      (step) =>
        object(step) &&
        keys(step, ["title", "body", "meta", "sym", "railLabel", "imageScene", "image", "icon"]) &&
        (!Object.hasOwn(step, "image") || image(step.image)) &&
        (!Object.hasOwn(step, "icon") || icon(step.icon)),
    )
  );
}

function endsAtStepBody(text: string): boolean {
  type Frame = { kind: "root" | "steps" | "step" | "other"; key?: string; expectingKey: boolean };
  const stack: Frame[] = [];
  let start: number | undefined,
    escaped = false,
    isKey = false,
    closedBody = false;
  const bodyCursor = () =>
    stack.length === 3 && stack[2]?.kind === "step" && stack[2].key === "body";
  for (let index = 0; index < text.length; index++) {
    const c = text[index]!;
    if (start !== undefined) {
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c === "\\") {
        escaped = true;
        continue;
      }
      if (c !== '"') continue;
      if (isKey) {
        try {
          stack.at(-1)!.key = JSON.parse(text.slice(start, index + 1));
        } catch {
          return false;
        }
        stack.at(-1)!.expectingKey = false;
      }
      closedBody = !isKey && bodyCursor();
      start = undefined;
      continue;
    }
    if (/\s/.test(c)) continue;
    closedBody = false;
    const parent = stack.at(-1);
    if (c === '"') {
      start = index;
      isKey = parent?.expectingKey ?? false;
    } else if (c === "{")
      stack.push({
        kind: !parent ? "root" : parent.kind === "steps" ? "step" : "other",
        expectingKey: true,
      });
    else if (c === "[")
      stack.push({
        kind: parent?.kind === "root" && parent.key === "steps" ? "steps" : "other",
        expectingKey: false,
      });
    else if (c === "}" || c === "]") stack.pop();
    else if (c === "," && parent) {
      parent.expectingKey = parent.kind !== "steps";
      parent.key = undefined;
    }
  }
  return closedBody || (start !== undefined && !isKey && bodyCursor());
}

function closedTextFields(text: string): Map<string, unknown> | undefined {
  const seen = new Set<string>();
  const values = new Map<string, unknown>();
  let depth = 0;
  let inString = false;
  let escaped = false;
  let start = 0;
  let role: "key" | "value" = "key";
  let tokenRole: "key" | "value" | undefined;
  let key: string | undefined;
  for (let index = 0; index < text.length; index++) {
    const c = text[index]!;
    if (inString) {
      if (escaped) escaped = false;
      else if (c === "\\") escaped = true;
      else if (c === '"') {
        inString = false;
        if (tokenRole) {
          const value = JSON.parse(text.slice(start, index + 1));
          if (tokenRole === "key") {
            if (!TEXT_DRAFT_FIELDS.has(value) || seen.has(value)) return;
            key = value;
            seen.add(value);
          } else if (key) values.set(key, value);
        }
        tokenRole = undefined;
      }
      continue;
    }
    if (c === '"') {
      inString = true;
      start = index;
      tokenRole = depth === 1 ? role : undefined;
    } else if (c === "{" || c === "[") depth++;
    else if (c === "}" || c === "]") depth--;
    else if (depth === 1 && c === ":") role = "value";
    else if (depth === 1 && c === ",") {
      role = "key";
      key = undefined;
    }
  }

  if (inString && tokenRole === "key") return;
  return values;
}

export function asksQuestions(blocks: readonly Block[]): boolean {
  return blocks.some((block) => {
    if (block.type !== "questionList") return false;
    const [item, ...rest] = block.items;
    const kind = item?.input?.kind;
    return (
      rest.length > 0 ||
      !(
        kind === "count" ||
        kind === "area" ||
        (item?.input?.options?.length && (kind === "choice" || kind === "place"))
      )
    );
  });
}

const deferredTypes = new Set(["chipRow", "questionList", "timeAsk", "quiz", "whatIf"]);
const executableKeys = new Set([
  "dockAction",
  "actions",
  "action",
  "prompt",
  "conversation",
  "automation",
  "openAutomation",
  "native",
  "input",
  "imageURL",
]);
function inertAction(value: unknown): { label: string }[] {
  const label = (value as { label?: unknown } | undefined)?.label;
  return typeof label === "string" && label.trim() ? [{ label }] : [];
}

function withInertActions(projected: Block, source: Block): Block {
  if (projected.type === "titleBlock" && source.type === "titleBlock") {
    const actions = (source.actions ?? []).flatMap(inertAction);
    return actions.length ? ({ ...projected, actions } as Block) : projected;
  }
  if (projected.type === "mediaRowList" && source.type === "mediaRowList") {
    const rows = projected.rows.map((row, index) => {
      const [action] = inertAction(source.rows[index]?.action);
      return action ? { ...row, action } : row;
    });
    return { ...projected, rows } as Block;
  }
  return projected;
}

export function previewProjection(
  blocks: readonly Block[],
  context?: {
    activeDraft?: { type: "stepCarousel"; id: string };
  },
): Block[] {
  function strip(value: unknown): unknown {
    if (Array.isArray(value)) return value.map(strip);
    if (!value || typeof value !== "object") return value;
    return Object.fromEntries(
      Object.entries(value)
        .filter(([key]) => !executableKeys.has(key))
        .map(([key, child]) => [key, strip(child)]),
    );
  }
  const asks = asksQuestions(blocks);
  return blocks.flatMap((block) => {
    if (deferredTypes.has(block.type)) return [];
    if (asks && block.type === "pageMeta") block = { ...block, ask: true };
    const stripped = strip(block) as Block;
    if (
      stripped.type === "stepCarousel" &&
      context?.activeDraft?.type === "stepCarousel" &&
      stripped.id === context.activeDraft.id
    ) {
      stripped.steps = stripped.steps.map(({ icon, ...step }, index, steps) => {
        if (!icon) return step;
        const { image, ...nonImage } = icon;
        if (
          index < steps.length - 1 &&
          image?.kind === "generated" &&
          isGeneratedStepImageQuery(image.query)
        )
          return { ...step, icon };
        const hasContent = Object.values(nonImage).some(
          (value) => typeof value === "string" && value.trim(),
        );
        return { ...step, ...(hasContent ? { icon: nonImage } : {}) };
      });
    }
    const parsed = blockSchema.safeParse(stripped);
    return parsed.success ? [withInertActions(parsed.data, block)] : [];
  });
}
