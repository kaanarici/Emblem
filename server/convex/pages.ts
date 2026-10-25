import { draftUpdateSchema, replaceDraft } from "../lib/writing";
import { ownerKey, requireOwnerKey } from "./ownership";
import { internalMutation, mutation, query } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";
import { pageFields } from "./schema";
import { deleteRunReceipts, findGenerationRun } from "./generationActions";
import { syncConversationSummary } from "./conversations";
import { GENERATION_CANCELLED } from "../lib/generationProtocol";
import { asRecord } from "../lib/records";
import type { Doc } from "./_generated/dataModel";
import type { MutationCtx, QueryCtx } from "./_generated/server";

const GENERATION_LEASE_MS = 3 * 60_000;
const GENERATION_RUN_RETENTION_MS = 30 * 24 * 60 * 60_000;
const RUN_PURGE_BATCH = 100;
const terminalStatus = v.union(v.literal("completed"), v.literal("failed"));
const claimResult = v.union(
  v.object({ state: v.literal("deleted") }),
  v.object({ state: v.literal("conflict") }),
  v.object({ state: v.literal("running") }),
  v.object({ state: v.literal("claimed"), leaseGeneration: v.number() }),
  v.object({
    state: v.literal("replay"),
    status: v.union(terminalStatus, v.literal("cancelled")),
    blocks: v.string(),
    activities: v.union(v.string(), v.null()),
    sources: v.union(v.string(), v.null()),
    failure: v.union(v.string(), v.null()),
    persisted: v.boolean(),
  }),
);
const CANCELLATION_FAILURE = JSON.stringify(GENERATION_CANCELLED);
const PRECLAIM_CANCELLATION_FINGERPRINT = "cancelled-before-claim";

function storedFailureIsRetryable(failure?: string): boolean {
  if (!failure) return false;
  try {
    return asRecord(JSON.parse(failure))?.retryable === true;
  } catch {
    return false;
  }
}

async function completedPage(ctx: Pick<QueryCtx, "db">, run: Doc<"generationRuns">) {
  const page = run.pageId ? await ctx.db.get("pages", run.pageId) : null;
  return page?.userTokenIdentifier === run.userTokenIdentifier &&
    page.conversationKey === run.conversationKey
    ? page
    : null;
}

export const claimGeneration = mutation({
  args: {
    requestId: v.string(),
    fingerprint: v.string(),
    conversationKey: v.string(),
    previousPageKey: v.optional(v.string()),
    parentPageKey: v.optional(v.string()),
    sourceCardKey: v.optional(v.string()),
    retry: v.optional(v.boolean()),
  },
  returns: claimResult,
  handler: async (ctx, args) => {
    const userTokenIdentifier = await requireOwnerKey(ctx);
    const requestId = args.requestId.trim();
    if (!requestId || requestId.length > 200) throw new Error("invalid request id");
    if (!args.fingerprint || args.fingerprint.length > 200) {
      throw new Error("invalid generation fingerprint");
    }
    const parentPageKey = args.parentPageKey?.trim();
    const sourceCardKey = args.sourceCardKey?.trim();
    if (
      Boolean(parentPageKey) !== Boolean(sourceCardKey) ||
      (parentPageKey?.length ?? 0) > 200 ||
      (sourceCardKey?.length ?? 0) > 200
    ) {
      throw new Error("invalid expansion identity");
    }
    if (
      args.previousPageKey !== undefined &&
      (!args.previousPageKey.trim() || args.previousPageKey.length > 200)
    ) {
      throw new Error("invalid previous page identity");
    }
    const expansion = parentPageKey && sourceCardKey ? { parentPageKey, sourceCardKey } : {};

    const existing = await findGenerationRun(ctx, userTokenIdentifier, requestId);
    const now = Date.now();
    const cancelledBeforeClaim =
      existing?.fingerprint === PRECLAIM_CANCELLATION_FINGERPRINT &&
      existing.status === "cancelled";
    if (cancelledBeforeClaim) {
      if (existing.tombstoned) return { state: "deleted" as const };
      if (existing.conversationKey !== args.conversationKey) {
        return { state: "conflict" as const };
      }
      if (args.retry !== true) {
        return {
          state: "replay" as const,
          status: "cancelled" as const,
          blocks: "[]",
          activities: null,
          sources: null,
          failure: existing.failure ?? CANCELLATION_FAILURE,
          persisted: false,
        };
      }
    } else if (existing) {
      if (existing.fingerprint !== args.fingerprint) {
        return { state: "conflict" as const };
      }
      if (existing.tombstoned) return { state: "deleted" as const };

      if (existing.status === "completed") {
        const page = await completedPage(ctx, existing);
        if (!page) return { state: "deleted" as const };
        return {
          state: "replay" as const,
          status: "completed" as const,
          blocks: page.blocks,
          activities: page.activities ?? null,
          sources: page.sources ?? null,
          failure: null,
          persisted: true,
        };
      }
      const canExplicitlyRetry =
        args.retry === true &&
        ((existing.status === "failed" && storedFailureIsRetryable(existing.failure)) ||
          existing.status === "cancelled");
      if (!canExplicitlyRetry) {
        if (existing.status === "failed" || existing.status === "cancelled") {
          return {
            state: "replay" as const,
            status: existing.status,
            blocks: "[]",
            activities: null,
            sources: null,
            failure: existing.failure ?? null,
            persisted: false,
          };
        }
        if (!(existing.leaseExpiresAt <= now)) {
          return { state: "running" as const };
        }
      }
    }

    const leaseGeneration = existing ? existing.leaseGeneration + 1 : 1;
    const lease = {
      status: "running" as const,
      leaseGeneration,
      leaseExpiresAt: now + GENERATION_LEASE_MS,
    };
    if (existing) {
      await ctx.db.patch("generationRuns", existing._id, {
        ...lease,
        failure: undefined,
        ...(cancelledBeforeClaim
          ? { fingerprint: args.fingerprint, ...expansion, previousPageKey: args.previousPageKey }
          : {}),
      });
    } else {
      await ctx.db.insert("generationRuns", {
        userTokenIdentifier,
        requestId,
        fingerprint: args.fingerprint,
        conversationKey: args.conversationKey,
        previousPageKey: args.previousPageKey,
        ...expansion,
        ...lease,
        tombstoned: false,
      });
    }
    return { state: "claimed" as const, leaseGeneration };
  },
});

export const generationCompletion = query({
  args: { requestId: v.string(), leaseGeneration: v.number() },
  returns: v.union(v.id("pages"), v.null()),
  handler: async (ctx, args) => {
    const userTokenIdentifier = await requireOwnerKey(ctx);
    const run = await findGenerationRun(ctx, userTokenIdentifier, args.requestId);
    if (
      !run ||
      run.tombstoned ||
      run.status !== "completed" ||
      run.leaseGeneration !== args.leaseGeneration ||
      !run.pageId
    )
      return null;
    return (await completedPage(ctx, run))?._id ?? null;
  },
});

export const generationTerminal = query({
  args: {
    requestId: v.string(),
    leaseGeneration: v.number(),
    status: v.union(v.literal("failed"), v.literal("cancelled")),
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const userTokenIdentifier = await requireOwnerKey(ctx);
    const run = await findGenerationRun(ctx, userTokenIdentifier, args.requestId);
    return run?.leaseGeneration === args.leaseGeneration && run.status === args.status;
  },
});

export const completeGeneration = mutation({
  args: {
    requestId: v.string(),
    leaseGeneration: v.number(),
    prompt: v.string(),
    title: v.optional(v.string()),
    blocks: v.string(),
    activities: v.optional(v.string()),
    sources: v.optional(v.string()),
    coverImageQuery: pageFields.coverImageQuery,
    coverImageKind: pageFields.coverImageKind,
    coverImageAspect: pageFields.coverImageAspect,
    coverImageUrl: pageFields.coverImageUrl,
  },
  returns: v.union(v.id("pages"), v.null()),
  handler: async (ctx, args) => {
    const userTokenIdentifier = await requireOwnerKey(ctx);
    const run = await findGenerationRun(ctx, userTokenIdentifier, args.requestId);
    if (!run) throw new Error("generation claim not found");
    if (run.status === "completed") {
      if (run.tombstoned || run.leaseGeneration !== args.leaseGeneration || !run.pageId) {
        return null;
      }
      return (await completedPage(ctx, run))?._id ?? null;
    }
    if (
      run.status !== "running" ||
      run.leaseGeneration !== args.leaseGeneration ||
      run.leaseExpiresAt <= Date.now()
    ) {
      return null;
    }

    const parsedBlocks: unknown = JSON.parse(args.blocks);
    if (!Array.isArray(parsedBlocks)) throw new Error("page blocks must be an array");
    const pageId = await ctx.db.insert("pages", {
      conversationKey: run.conversationKey,
      pageKey: run.requestId,
      previousPageKey: run.previousPageKey,
      parentPageKey: run.parentPageKey,
      sourceCardKey: run.sourceCardKey,
      requestedAt: run._creationTime,
      prompt: args.prompt,
      title: args.title,
      blocks: args.blocks,
      activities: args.activities,
      sources: args.sources,
      coverImageQuery: args.coverImageQuery,
      coverImageKind: args.coverImageKind,
      coverImageAspect: args.coverImageAspect,
      coverImageUrl: isCoverURL(args.coverImageUrl) ? args.coverImageUrl : undefined,
      userTokenIdentifier,
    });
    await ctx.db.patch("generationRuns", run._id, {
      status: "completed",
      pageId,
    });
    const page = await ctx.db.get("pages", pageId);
    if (page) await syncConversationSummary(ctx, page);
    return pageId;
  },
});

export const finishGeneration = mutation({
  args: {
    requestId: v.string(),
    leaseGeneration: v.number(),
    status: v.union(v.literal("failed"), v.literal("cancelled")),
    failure: v.optional(v.string()),
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const userTokenIdentifier = await requireOwnerKey(ctx);
    const run = await findGenerationRun(ctx, userTokenIdentifier, args.requestId);
    if (!run || run.leaseGeneration !== args.leaseGeneration) return false;
    if (run.status === args.status) return true;
    if (run.status !== "running" || run.leaseExpiresAt <= Date.now()) return false;
    await ctx.db.patch("generationRuns", run._id, {
      status: args.status,
      failure: args.failure,
    });
    return true;
  },
});

export const cancelGeneration = mutation({
  args: {
    requestId: v.string(),
    conversationKey: v.optional(v.string()),
  },
  returns: v.union(
    v.object({ state: v.literal("missing") }),
    v.object({ state: v.literal("cancelled") }),
    v.object({ state: v.literal("terminal"), status: terminalStatus }),
  ),
  handler: async (ctx, args) => {
    const userTokenIdentifier = await requireOwnerKey(ctx);
    const requestId = args.requestId.trim();
    if (!requestId || requestId.length > 200) throw new Error("invalid request id");
    const conversationKey = args.conversationKey?.trim();
    if (conversationKey !== undefined && (!conversationKey || conversationKey.length > 200)) {
      throw new Error("invalid conversation key");
    }
    const run = await findGenerationRun(ctx, userTokenIdentifier, requestId);
    if (!run) {
      if (!conversationKey) return { state: "missing" as const };
      await ctx.db.insert("generationRuns", {
        userTokenIdentifier,
        requestId,
        fingerprint: PRECLAIM_CANCELLATION_FINGERPRINT,
        conversationKey,
        status: "cancelled",
        tombstoned: false,
        leaseGeneration: 1,
        leaseExpiresAt: Date.now(),
        failure: CANCELLATION_FAILURE,
      });
      return { state: "cancelled" as const };
    }
    if (run.tombstoned) return { state: "missing" as const };
    if (run.status === "cancelled") return { state: "cancelled" as const };
    if (run.status !== "running") {
      return { state: "terminal" as const, status: run.status };
    }
    await ctx.db.patch("generationRuns", run._id, {
      status: "cancelled",
      failure: CANCELLATION_FAILURE,
    });
    return { state: "cancelled" as const };
  },
});

export const setCoverImageUrl = mutation({
  args: { pageId: v.id("pages"), url: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const owner = await requireOwnerKey(ctx);
    const page = await ctx.db.get("pages", args.pageId);
    if (!page || page.userTokenIdentifier !== owner) throw new Error("page not found");
    if (!isCoverURL(args.url)) throw new Error("invalid cover URL");
    await ctx.db.patch("pages", args.pageId, { coverImageUrl: args.url });
    await syncConversationSummary(ctx, { ...page, coverImageUrl: args.url });
  },
});

function isCoverURL(value?: string): value is string {
  if (value === undefined || value.length > 2048) return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password;
  } catch {
    return false;
  }
}

export const byPageKey = query({
  args: { conversationKey: v.string(), pageKey: v.string() },
  returns: v.union(v.null(), v.object({ blocks: v.string(), sources: v.optional(v.string()) })),
  handler: async (ctx, args) => {
    const owner = await ownerKey(ctx);
    if (!owner) return null;
    const keyed = await ctx.db
      .query("pages")
      .withIndex("by_userTokenIdentifier_and_conversationKey_and_pageKey", (q) =>
        q
          .eq("userTokenIdentifier", owner)
          .eq("conversationKey", args.conversationKey)
          .eq("pageKey", args.pageKey),
      )
      .first();
    return keyed ? { blocks: keyed.blocks, sources: keyed.sources } : null;
  },
});

export const updateWritingDraft = mutation({
  args: {
    conversationKey: v.string(),
    pageKey: v.string(),
    blockID: v.string(),
    draftID: v.string(),
    previousBody: v.string(),
    body: v.string(),
  },
  returns: v.union(v.literal("saved"), v.literal("conflict"), v.literal("missing")),
  handler: async (ctx, args) => {
    const owner = await requireOwnerKey(ctx);
    const update = draftUpdateSchema.parse(args);
    const page = await ctx.db
      .query("pages")
      .withIndex("by_userTokenIdentifier_and_conversationKey_and_pageKey", (q) =>
        q
          .eq("userTokenIdentifier", owner)
          .eq("conversationKey", update.conversationKey)
          .eq("pageKey", update.pageKey),
      )
      .first();
    if (!page) return "missing" as const;
    const blocks = replaceDraft(JSON.parse(page.blocks), update);
    if (!blocks) return "conflict" as const;
    const updated = { ...page, blocks: JSON.stringify(blocks) };
    await ctx.db.patch("pages", page._id, { blocks: updated.blocks });
    await syncConversationSummary(ctx, updated);
    return "saved" as const;
  },
});

async function purgeRunReceipts(
  ctx: MutationCtx,
  run: Doc<"generationRuns">,
  limit: number,
): Promise<{ deleted: boolean; receipts: number }> {
  const receipts = await deleteRunReceipts(ctx, run, limit);
  if (receipts.more) {
    await ctx.scheduler.runAfter(0, internal.pages.purgeExpiredRun, { runId: run._id });
    return { deleted: false, receipts: receipts.deleted };
  }
  await ctx.db.delete("generationRuns", run._id);
  return { deleted: true, receipts: receipts.deleted };
}

const EXPIRING_RUNS = [
  { status: "running", tombstoned: false },
  { status: "failed", tombstoned: false },
  { status: "failed", tombstoned: true },
  { status: "cancelled", tombstoned: false },
  { status: "cancelled", tombstoned: true },
  { status: "completed", tombstoned: true },
] as const;

function expires(run: Doc<"generationRuns">, now: number): boolean {
  return (
    run._creationTime < now - GENERATION_RUN_RETENTION_MS &&
    (run.status === "completed"
      ? run.tombstoned
      : run.status !== "running" || run.leaseExpiresAt <= now)
  );
}

export const purgeExpiredRun = internalMutation({
  args: { runId: v.id("generationRuns") },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const run = await ctx.db.get("generationRuns", args.runId);
    if (run && expires(run, Date.now())) await purgeRunReceipts(ctx, run, RUN_PURGE_BATCH);
    return null;
  },
});

export const purgeExpiredRuns = internalMutation({
  args: {
    phase: v.optional(v.number()),
    cursor: v.optional(v.string()),
    cutoff: v.optional(v.number()),
  },
  returns: v.object({ deleted: v.number(), more: v.boolean() }),
  handler: async (ctx, args): Promise<{ deleted: number; more: boolean }> => {
    const now = Date.now();
    const cutoff = Math.min(
      args.cutoff ?? now - GENERATION_RUN_RETENTION_MS,
      now - GENERATION_RUN_RETENTION_MS,
    );
    const phase = args.phase ?? 0;
    const range = EXPIRING_RUNS[phase];
    if (!range) return { deleted: 0, more: false };
    const expired = await ctx.db
      .query("generationRuns")
      .withIndex("by_status_and_tombstoned", (q) =>
        q.eq("status", range.status).eq("tombstoned", range.tombstoned).lt("_creationTime", cutoff),
      )
      .paginate({
        numItems: RUN_PURGE_BATCH,
        cursor: args.cursor ?? null,
        maximumBytesRead: 1024 * 1024,
      });
    let deleted = 0;
    let receiptBudget = RUN_PURGE_BATCH;
    let pendingReceipts = false;
    for (const run of expired.page) {
      if (!expires(run, now)) continue;
      const result = await purgeRunReceipts(ctx, run, receiptBudget);
      receiptBudget -= result.receipts;
      if (result.deleted) deleted += 1;
      else pendingReceipts = true;
    }
    const next = expired.isDone
      ? { phase: phase + 1, cutoff }
      : { phase, cursor: expired.continueCursor, cutoff };
    if (EXPIRING_RUNS[next.phase]) {
      await ctx.scheduler.runAfter(0, internal.pages.purgeExpiredRuns, next);
    }
    return { deleted, more: Boolean(EXPIRING_RUNS[next.phase]) || pendingReceipts };
  },
});
