import { logError, logWarning } from "@/lib/log";
import {
  readGenerationBody,
  savedSelectionMessages,
  savedSelectionSchema,
} from "@/lib/savedSelection";
import {
  selectedHotelFromBlocks,
  retainedHotelContextFromBlocks,
  type HotelSelection,
} from "@/lib/travel/hotelContent";
import { conversationMayNeedWeather } from "@/lib/requestIntent";
import { api } from "@/convex/_generated/api";
import { articleGroundingFrom, storedGenerationSources } from "@/lib/articleGrounding";
import {
  calendarEventGrounding,
  calendarEventSchema,
  selectedCalendarEvent,
  type SelectedCalendarEvent,
} from "@/lib/calendarEventDrillIn";
import { authFailure, requestAuth } from "@/lib/auth";
import {
  ANONYMOUS_CONVERSATION_KEY,
  finishGenerationFailure,
  generationFingerprint,
  generationReplayResponse,
  type GenerationLease,
} from "@/lib/generationIdempotency";
import { generationFailure, type GenerationSource } from "@/lib/generationProtocol";
import {
  protocolFailureResponse,
  retryOnConnectTimeout,
  serviceRequest,
  withRequestContext,
} from "@/lib/generationRequest";
import { createStream } from "@/lib/generationStream";
import { createInferenceSession } from "@/lib/inferenceTelemetry";
import type { LatencyStages } from "@/lib/latency";
import { MAX_MEMORIES, MAX_MEMORY_CHARS, type UserProfile } from "@/lib/memoryPolicy";
import { profileSection } from "@/lib/prompt";
import {
  InferenceCapabilityError,
  InferenceConfigurationError,
  resolveInferenceProfile,
  userInferenceCredential,
  type UserInferenceCredential,
} from "@/lib/provider";
import { admitMetered, METERED_ROUTES } from "@/lib/meteredAccess";
import { jsonResponse, readJsonBody } from "@/lib/http";
import { asRecord } from "@/lib/records";
import type { ConvexHttpClient } from "convex/browser";
import { z } from "zod";

export const maxDuration = 240;

const requestSchema = z
  .object({
    messages: z
      .array(
        z.object({
          role: z.enum(["user", "assistant"]),
          content: z.string().max(200_000),
        }),
      )
      .min(1)
      .max(20),
    requestId: z.string().uuid().optional(),
    retry: z.boolean().optional(),
    previousPageKey: z.string().trim().min(1).max(200).optional(),
    conversationKey: z.string().min(1).max(200).optional(),
    parentPageKey: z.string().min(1).max(200).optional(),
    sourceCardKey: z.string().min(1).max(200).optional(),
    sourceCardTitle: z.string().trim().min(1).max(300).optional(),

    sourceCardHasImage: z.boolean().optional(),
    drillInPresentation: z.enum(["normal", "article", "weather"]).optional(),
    calendarEvent: calendarEventSchema.optional(),
    savedSelection: savedSelectionSchema.optional(),
    attachments: z
      .array(
        z.object({
          kind: z.enum(["image", "pdf", "file"]),
          name: z.string().min(1).max(500),
          dataURL: z.string().max(25_000_000),
          text: z.string().max(500_000).optional(),
        }),
      )
      .max(5)
      .optional(),
    location: z
      .object({
        city: z.string().max(200).optional(),
        region: z.string().max(200).optional(),
        country: z.string().max(200).optional(),
        latitude: z.number().min(-90).max(90).optional(),
        longitude: z.number().min(-180).max(180).optional(),
      })
      .optional(),
    timezone: z.string().max(100).optional(),
    device: z
      .array(z.enum(["home"]))
      .max(4)
      .optional(),
    memory: z.boolean().optional(),
    memoryContext: z.array(z.string().max(MAX_MEMORY_CHARS)).max(MAX_MEMORIES).optional(),
  })
  .refine(
    ({ parentPageKey, sourceCardKey, savedSelection }) =>
      Boolean(savedSelection) || Boolean(parentPageKey) === Boolean(sourceCardKey),
    {
      message: "parentPageKey and sourceCardKey must be provided together",
    },
  )
  .refine(
    ({ drillInPresentation, parentPageKey, savedSelection }) =>
      drillInPresentation === undefined || Boolean(parentPageKey) || Boolean(savedSelection),
    { message: "drillInPresentation requires a card drill-in" },
  )
  .refine(({ calendarEvent, parentPageKey }) => !calendarEvent || Boolean(parentPageKey), {
    message: "calendarEvent requires a card drill-in",
  })
  .superRefine((value, context) => {
    const selection = value.savedSelection;
    if (!selection) return;
    if (
      value.messages.length !== 1 ||
      value.messages[0]?.role !== "user" ||
      !value.messages[0].content.trim() ||
      (value.attachments?.length ?? 0) !== 0 ||
      value.location !== undefined ||
      value.calendarEvent !== undefined ||
      value.memory !== false ||
      (value.memoryContext?.length ?? 0) !== 0 ||
      (value.parentPageKey !== undefined && value.parentPageKey !== selection.parentPageKey) ||
      (value.sourceCardKey !== undefined && value.sourceCardKey !== selection.sourceCardKey) ||
      (value.previousPageKey !== undefined && value.previousPageKey !== selection.parentPageKey)
    ) {
      context.addIssue({
        code: "custom",
        message: "saved selection requires isolated input and matching lineage",
      });
    }
  })
  .transform((value) =>
    value.savedSelection
      ? {
          ...value,
          parentPageKey: value.savedSelection.parentPageKey,
          sourceCardKey: value.savedSelection.sourceCardKey,
          sourceCardTitle: value.savedSelection.card.title,
          sourceCardHasImage: Boolean(
            value.savedSelection.card.image || value.savedSelection.card.imageURL,
          ),
        }
      : value,
  );

const cancellationSchema = z.object({
  requestId: z.string().uuid(),
  conversationKey: z.string().min(1).max(200).optional(),
});

type GenerationRequest = z.infer<typeof requestSchema>;

export async function DELETE(req: Request) {
  const auth = await requestAuth(req);
  const authError = authFailure(auth);
  if (authError) return authError;
  const raw = await readJsonBody(req);
  if (raw instanceof Response) return raw;
  const parsed = cancellationSchema.safeParse(raw);
  if (!parsed.success) {
    return jsonResponse({ error: "invalid cancellation request", code: "invalid_request" }, 400);
  }
  if (!auth.authenticated) return jsonResponse({ state: "guest" });
  if (!auth.convex) {
    return jsonResponse(
      { error: "generation state unavailable", code: "generation_state_unavailable" },
      503,
    );
  }
  const { requestId, conversationKey } = parsed.data;
  try {
    const result = await auth.convex.mutation(api.pages.cancelGeneration, {
      requestId,
      ...(conversationKey ? { conversationKey } : {}),
    });
    return jsonResponse(result);
  } catch (error) {
    logError("generation cancellation failed", error);
    return jsonResponse(
      { error: "generation state unavailable", code: "generation_state_unavailable" },
      503,
    );
  }
}

async function claimGeneration(
  convex: ConvexHttpClient,
  requestId: string,
  input: GenerationRequest,
): Promise<GenerationLease | Response> {
  try {
    const claim = await retryOnConnectTimeout(() =>
      convex.mutation(api.pages.claimGeneration, {
        requestId,
        fingerprint: generationFingerprint(input),
        conversationKey: input.conversationKey ?? ANONYMOUS_CONVERSATION_KEY,
        ...(input.previousPageKey ? { previousPageKey: input.previousPageKey } : {}),
        ...(input.parentPageKey && input.sourceCardKey
          ? { parentPageKey: input.parentPageKey, sourceCardKey: input.sourceCardKey }
          : {}),
        ...(input.retry === true ? { retry: true } : {}),
      }),
    );
    switch (claim.state) {
      case "replay":
        return generationReplayResponse(claim);
      case "conflict":
        return protocolFailureResponse(
          "This request identifier was already used for different input.",
          "idempotency_conflict",
          false,
        );
      case "deleted":
        return protocolFailureResponse(
          "This response was deleted from your conversation history.",
          "generation_result_deleted",
          false,
        );
      case "running":
        return protocolFailureResponse(
          "This response is already being generated. Try again in a moment.",
          "generation_in_progress",
          true,
        );
      default:
        return { requestId, leaseGeneration: claim.leaseGeneration };
    }
  } catch (error) {
    logError("generation claim failed", error, { requestId });
    return protocolFailureResponse(
      "I couldn't safely start this response. Try again in a moment.",
      "generation_state_unavailable",
      true,
    );
  }
}

async function personalContext(convex: ConvexHttpClient, includeMemories: boolean) {
  const [memories, profile] = await Promise.all([
    includeMemories
      ? convex.query(api.memories.list, {}).catch((error) => {
          logError("convex memories.list failed", error);
          return [] as string[];
        })
      : Promise.resolve([] as string[]),
    convex.query(api.profiles.get, {}).catch((error): UserProfile | null => {
      logError("convex profiles.get failed", error);
      return null;
    }),
  ]);
  return { memories, profile };
}

type ParentEvidence = {
  context?: string;
  sources: GenerationSource[];
  hotelSelection?: HotelSelection;
  calendarEvent?: SelectedCalendarEvent;
};

const BOOK_ACTION_UNSET_FIELDS = [
  "url",
  "conversation",
  "native",
  "destination",
  "openAutomation",
  "automation",
  "calendar",
];

function offersBookAction(blocksJSON: string, prompt: string): boolean {
  const blocks: unknown = JSON.parse(blocksJSON);
  return (
    Array.isArray(blocks) &&
    blocks.some((block: unknown) => {
      const meta = asRecord(block);
      const action = meta?.type === "pageMeta" ? asRecord(meta.dockAction) : null;
      return (
        action?.label === "Book" &&
        action.prompt === prompt &&
        BOOK_ACTION_UNSET_FIELDS.every((key) => action[key] == null)
      );
    })
  );
}

async function parentPageEvidence(
  convex: ConvexHttpClient,
  {
    conversationKey,
    pageKey,
    sourceCardTitle,
    sourceCardKey,
    bookPrompt,
  }: {
    conversationKey: string;
    pageKey: string;
    sourceCardTitle?: string;
    sourceCardKey?: string;
    bookPrompt?: string;
  },
): Promise<ParentEvidence> {
  try {
    const parent = await convex.query(api.pages.byPageKey, { conversationKey, pageKey });
    if (!parent) return { sources: [] };
    if (!sourceCardKey && !(bookPrompt && offersBookAction(parent.blocks, bookPrompt))) {
      return { sources: [] };
    }
    return {
      context: articleGroundingFrom(parent.blocks, sourceCardTitle),
      calendarEvent: sourceCardKey
        ? selectedCalendarEvent(parent.blocks, sourceCardTitle)
        : undefined,
      hotelSelection: sourceCardKey
        ? selectedHotelFromBlocks(parent.blocks, sourceCardKey)
        : retainedHotelContextFromBlocks(parent.blocks),
      sources: storedGenerationSources(parent.sources),
    };
  } catch (error) {
    logWarning("article context fetch failed; falling back to research", error);
    return { sources: [] };
  }
}

export async function POST(req: Request) {
  const requestStarted = performance.now();
  const stages: LatencyStages = {};

  const authStarted = performance.now();
  const auth = await requestAuth(req);
  stages.auth = performance.now() - authStarted;
  const authError = authFailure(auth);
  if (authError) return authError;
  const serviceStarted = performance.now();
  const service = await serviceRequest(req, auth.convex);
  stages.serviceGrant = performance.now() - serviceStarted;
  if (service.attempted && !service.accepted) {
    return jsonResponse(
      service.unavailable
        ? { error: "service execution unavailable", code: "service_authority_unavailable" }
        : { error: "invalid service execution grant", code: "invalid_service_grant" },
      service.unavailable ? 503 : 401,
    );
  }
  const serviceCall = service.accepted;
  const { convex, authenticated, ownerKey } = auth;
  if (!serviceCall && !authenticated && !(await admitMetered(req, METERED_ROUTES.generate, auth))) {
    return protocolFailureResponse(
      "You've reached the guest limit for now. Sign in to keep going.",
      "rate_limited",
      true,
      { "X-Rate-Limited": "1" },
    );
  }

  const parseStarted = performance.now();
  let input: GenerationRequest;
  try {
    const raw = await readGenerationBody(req);
    if (raw instanceof Response) return raw;
    input = requestSchema.parse(raw);
  } catch {
    return jsonResponse({ error: "invalid generation request", code: "invalid_request" }, 400);
  }
  stages.parse = performance.now() - parseStarted;
  if (input.savedSelection && serviceCall) {
    return jsonResponse(
      { error: "Saved selection requires an interactive request", code: "invalid_request" },
      400,
    );
  }
  const {
    messages,
    attachments,
    parentPageKey,
    drillInPresentation,
    sourceCardTitle,
    savedSelection,
    timezone,
  } = input;
  const homeControl = input.device?.includes("home") ?? false;

  const unreadable = attachments?.find(
    (attachment) => attachment.kind !== "image" && !attachment.text?.trim(),
  );
  if (unreadable) {
    return protocolFailureResponse(
      `I couldn't read text from ${unreadable.name}. Try a text-based PDF or plain-text file.`,
      "unreadable_attachment",
      false,
    );
  }

  let userCredential: UserInferenceCredential | undefined;
  try {
    userCredential = userInferenceCredential(req.headers);
  } catch (error) {
    if (!(error instanceof InferenceConfigurationError)) throw error;
    return jsonResponse({ error: error.message, code: "invalid_inference_credential" }, 400);
  }
  if (userCredential && (serviceCall || !authenticated)) {
    return jsonResponse(
      {
        error: serviceCall
          ? "background runs use platform inference"
          : "sign in to use your inference provider",
        code: "user_inference_not_allowed",
      },
      serviceCall ? 403 : 401,
    );
  }

  const requestId = service.requestId ?? input.requestId ?? crypto.randomUUID();
  const interactive = !serviceCall && authenticated && convex ? convex : null;
  const interactiveMemory =
    !savedSelection && Boolean(interactive && ownerKey && input.memory !== false);
  const serviceMemory =
    !savedSelection && serviceCall && Boolean(service.sources?.includes("memory"));
  const weatherExpansion =
    !savedSelection &&
    Boolean(parentPageKey) &&
    drillInPresentation !== "article" &&
    conversationMayNeedWeather(messages);
  const articleLead =
    Boolean(parentPageKey) &&
    (drillInPresentation === "article" || (drillInPresentation === undefined && !weatherExpansion));
  const roomBrowse = /^show me the room options at .+\.$/i.test(
    messages.at(-1)?.content.trim() ?? "",
  );
  const evidencePageKey = parentPageKey ?? (roomBrowse ? input.previousPageKey : undefined);
  let lease: GenerationLease | null = null;
  let memories = serviceMemory ? (input.memoryContext ?? []) : [];
  let profile: UserProfile | null = null;
  let parent: ParentEvidence = { sources: [] };
  if (interactive) {
    const claimed = await claimGeneration(interactive, requestId, input);
    if (claimed instanceof Response) return claimed;
    lease = claimed;
    const contextStarted = performance.now();
    const [allowed, personal, parentEvidence] = await Promise.all([
      admitMetered(req, METERED_ROUTES.generate, auth),
      savedSelection ? null : personalContext(interactive, interactiveMemory),
      !savedSelection && !input.calendarEvent && evidencePageKey && input.conversationKey
        ? parentPageEvidence(interactive, {
            conversationKey: input.conversationKey,
            pageKey: evidencePageKey,
            sourceCardTitle,
            sourceCardKey: input.sourceCardKey,
            bookPrompt: parentPageKey ? undefined : messages.at(-1)?.content,
          })
        : null,
    ]);
    stages.memory = performance.now() - contextStarted;
    if (!allowed) {
      const message = "That's a lot of pages in a short burst. Give it a minute and try again.";
      await finishGenerationFailure(
        convex,
        lease,
        generationFailure("rate_limited", message, true),
      );
      return protocolFailureResponse(message, "rate_limited", true, { "X-Rate-Limited": "1" });
    }
    void interactive
      .mutation(api.users.ensure, {})
      .catch((error) => logError("convex users.ensure failed", error));
    if (personal) ({ memories, profile } = personal);
    if (parentEvidence) parent = parentEvidence;
  }
  const hotelSelection = savedSelection
    ? selectedHotelFromBlocks(
        JSON.stringify([
          { type: "cardCarousel", id: savedSelection.blockID, cards: [savedSelection.card] },
        ]),
        savedSelection.sourceCardKey,
      )
    : parent.hotelSelection;
  const calendarEvent = input.calendarEvent ?? parent.calendarEvent;
  const scope = serviceCall
    ? { ownerKey: service.ownerKey, sources: service.sources }
    : { ownerKey, sources: undefined };

  try {
    const inference = createInferenceSession(
      resolveInferenceProfile(userCredential, {
        images: attachments?.some((attachment) => attachment.kind === "image"),
        managedModel: serviceCall ? undefined : req.headers.get("x-emblem-managed-model"),
      }),
      { requestId, kind: serviceCall ? "background" : authenticated ? "interactive" : "guest" },
    );
    return createStream({
      previewEnabled: req.headers.get("X-Emblem-Preview") === "v1",
      messages: withRequestContext(
        savedSelection ? savedSelectionMessages(savedSelection, messages[0]!.content) : messages,
        attachments,
        input.location,
        timezone,
        homeControl,
      ),
      homeControl,
      attachments: attachments ?? [],
      persist: {
        conversationKey: input.conversationKey ?? ANONYMOUS_CONVERSATION_KEY,
        prompt: messages.at(-1)?.content ?? "",
        requestId,
        timezone: timezone ?? "UTC",
        articleLead,
        normalDrillIn: Boolean(parentPageKey) && drillInPresentation === "normal",
        articleTitle: sourceCardTitle,
        articleNeedsCover: articleLead && input.sourceCardHasImage === false && !calendarEvent,
        calendarEvent: articleLead ? calendarEvent : undefined,
        articleContext:
          parent.context ?? (input.calendarEvent && calendarEventGrounding(input.calendarEvent)),
        articleSources: parent.sources,
        hotelSelection,
      },
      inference,
      convex: interactive,
      generationLease: lease,
      memory: interactiveMemory || serviceMemory ? { facts: memories } : null,
      context: profileSection(profile),
      ownerKey: scope.ownerKey,
      isolatedSelection: Boolean(savedSelection),
      allowedSources: parentPageKey
        ? weatherExpansion
          ? ["web", "weather"]
          : ["web"]
        : scope.sources,
      timing: { requestStarted, stages, signal: req.signal },
    });
  } catch (error) {
    logError("generation setup failed", error, { requestId });
    const [code, message, retryable] =
      error instanceof InferenceCapabilityError
        ? (["unsupported_image_model", error.message, false] as const)
        : error instanceof InferenceConfigurationError
          ? ([
              "inference_unavailable",
              "I can't reach the model right now. Try again in a moment.",
              true,
            ] as const)
          : ([
              "generation_unavailable",
              "I couldn't start this response. Try again in a moment.",
              true,
            ] as const);
    await finishGenerationFailure(convex, lease, generationFailure(code, message, retryable));
    return protocolFailureResponse(message, code, retryable);
  }
}
