import { logError } from "./log";
import { savedSelectionSchema, type SavedSelection } from "./savedSelection";
import type { SelectedCalendarEvent } from "./calendarEventDrillIn";
import type { ConvexHttpClient } from "convex/browser";
import type { FunctionReturnType } from "convex/server";
import type { Id } from "@/convex/_generated/dataModel";
import { api } from "@/convex/_generated/api";
import type { CoverImage } from "./blockImages";
import { resolveImageCached } from "./imageResolve";
import {
  ndjsonLine,
  generationFailure,
  generationPageSnapshot,
  generationTerminal,
  isRenderablePage,
  NDJSON_HEADERS,
  type GenerationActivity,
  type GenerationFailure,
  type GenerationSource,
  type GenerationSources,
} from "./generationProtocol";
import { blockSchema } from "./schema";
import { createHash } from "node:crypto";

export const ANONYMOUS_CONVERSATION_KEY = "anonymous";

export type GenerationLease = {
  requestId: string;
  leaseGeneration: number;
};

type GenerationReplay = Extract<
  FunctionReturnType<typeof api.pages.claimGeneration>,
  { state: "replay" }
>;

type FingerprintInput = {
  savedSelection?: SavedSelection;
  messages: { role: string; content: string }[];
  conversationKey?: string;
  previousPageKey?: string;
  parentPageKey?: string;
  sourceCardKey?: string;
  sourceCardTitle?: string;
  drillInPresentation?: "normal" | "article" | "weather";
  calendarEvent?: SelectedCalendarEvent;
  attachments?: {
    kind: string;
    name: string;
    dataURL: string;
    text?: string;
  }[];
  location?: unknown;
  timezone?: string;
  memory?: boolean;
  memoryContext?: string[];
};

type PageWrite = {
  prompt: string;
  title?: string;
  blocks: string;
  activities?: string;
  sources?: string;
  coverImageQuery?: string;
  coverImageKind?: "photo" | "poster" | "still";
  coverImageAspect?: "square" | "portrait" | "landscape";
  coverImageUrl?: string;
};

function hashField(hash: ReturnType<typeof createHash>, value: string): void {
  hash.update(`${Buffer.byteLength(value)}:`);
  hash.update(value);
}

export function generationFingerprint(input: FingerprintInput): string {
  const hash = createHash("sha256");
  if (input.savedSelection) {
    hashField(hash, "saved-selection-v1");
    hashField(hash, JSON.stringify(savedSelectionSchema.parse(input.savedSelection)));
  }
  hashField(hash, "conversation");
  hashField(hash, input.conversationKey ?? ANONYMOUS_CONVERSATION_KEY);
  if (input.previousPageKey !== undefined) {
    hashField(hash, "previous-page");
    hashField(hash, input.previousPageKey);
  }
  hashField(hash, "expansion");
  hashField(hash, input.parentPageKey ?? "");
  hashField(hash, input.sourceCardKey ?? "");
  hashField(hash, input.sourceCardTitle ?? "");
  if (input.drillInPresentation !== undefined) {
    hashField(hash, "drill-in-presentation");
    hashField(hash, input.drillInPresentation);
  }
  if (input.calendarEvent !== undefined) {
    hashField(hash, "calendar-event-v1");
    hashField(hash, JSON.stringify(input.calendarEvent));
  }
  hashField(hash, "messages");
  hashField(hash, String(input.messages.length));
  for (const message of input.messages) {
    hashField(hash, message.role);
    hashField(hash, message.content);
  }
  hashField(hash, "attachments");
  hashField(hash, String(input.attachments?.length ?? 0));
  for (const attachment of input.attachments ?? []) {
    hashField(hash, attachment.kind);
    hashField(hash, attachment.name);
    hashField(hash, attachment.dataURL);
    hashField(hash, attachment.text ?? "");
  }
  hashField(hash, "location");
  hashField(hash, JSON.stringify(input.location ?? null));
  hashField(hash, "timezone");
  hashField(hash, input.timezone ?? "UTC");
  hashField(hash, "memory");
  hashField(hash, String(input.memory !== false));
  hashField(hash, "memoryContext");
  hashField(hash, String(input.memoryContext?.length ?? 0));
  for (const memory of input.memoryContext ?? []) hashField(hash, memory);
  return hash.digest("hex");
}

function storedArray<T>(value: string | null): T[] {
  if (!value) return [];
  const parsed: unknown = JSON.parse(value);
  if (!Array.isArray(parsed)) throw new Error("stored generation array is invalid");
  return parsed as T[];
}

export function generationReplayResponse(replay: GenerationReplay): Response {
  try {
    const activities = storedArray<GenerationActivity>(replay.activities);
    const storedBlocks = storedArray<unknown>(replay.blocks);
    const blocks =
      replay.status === "completed" ? storedBlocks.map((block) => blockSchema.parse(block)) : [];
    const sources = storedArray<GenerationSource>(replay.sources);
    if (replay.status === "completed" && !isRenderablePage(blocks)) {
      throw new Error("stored generation page is not renderable");
    }
    const lines: unknown[] =
      replay.status === "completed" ? [generationPageSnapshot(1, blocks)] : [];
    if (replay.status === "completed") lines.push(...activities);
    if (replay.status === "completed" && sources.length > 0) {
      lines.push({
        type: "sources",
        id: "sources",
        items: sources,
      } satisfies GenerationSources);
    }
    if (replay.failure) lines.push(JSON.parse(replay.failure));
    lines.push(
      generationTerminal(replay.status, blocks.length, {
        persisted: replay.persisted,
        ...(replay.status === "completed" ? { revision: 1 } : {}),
      }),
    );
    return new Response(lines.map(ndjsonLine).join(""), {
      status: 200,
      headers: { ...NDJSON_HEADERS, "X-Emblem-Replayed": "1" },
    });
  } catch (error) {
    logError("generation replay failed", error);
    const failure: GenerationFailure = generationFailure(
      "generation_replay_invalid",
      "I couldn't safely restore this response.",
      false,
    );
    const terminal = generationTerminal("failed", 0, { persisted: false });
    return new Response(ndjsonLine(failure) + ndjsonLine(terminal), {
      status: 200,
      headers: NDJSON_HEADERS,
    });
  }
}

async function settleLease<T>(
  event: string,
  write: () => Promise<T>,
  reconcile: () => Promise<T>,
  fallback: T,
): Promise<T> {
  try {
    return await write();
  } catch (firstError) {
    logError(`${event} response was ambiguous`, firstError);
    try {
      return await write();
    } catch (retryError) {
      logError(`${event} retry was ambiguous`, retryError);
    }
    return await reconcile().catch((reconcileError) => {
      logError(`${event} reconciliation failed`, reconcileError);
      return fallback;
    });
  }
}

export async function completeGenerationPage(
  convex: ConvexHttpClient | null,
  lease: GenerationLease | null,
  page: PageWrite,
): Promise<Id<"pages"> | null> {
  if (!convex || !lease) return null;
  return await settleLease(
    "generation completion",
    () => convex.mutation(api.pages.completeGeneration, { ...lease, ...page }),
    () => convex.query(api.pages.generationCompletion, lease),
    null,
  );
}

export function persistGenerationCover(
  convex: ConvexHttpClient,
  pageId: Id<"pages">,
  cover: CoverImage,
): void {
  void resolveImageCached(cover.query, cover.kind, cover.aspect)
    .then((url) => (url ? convex.mutation(api.pages.setCoverImageUrl, { pageId, url }) : null))
    .catch((error) => logError("conversation cover resolution failed", error));
}

export async function finishGenerationFailure(
  convex: ConvexHttpClient | null,
  lease: GenerationLease | null,
  failure: GenerationFailure,
  status: "failed" | "cancelled" = "failed",
): Promise<boolean> {
  if (!convex || !lease) return false;
  return await settleLease(
    "generation terminal",
    () =>
      convex.mutation(api.pages.finishGeneration, {
        ...lease,
        status,
        failure: JSON.stringify(failure),
      }),
    () => convex.query(api.pages.generationTerminal, { ...lease, status }),
    false,
  );
}
