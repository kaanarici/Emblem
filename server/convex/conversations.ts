import { v } from "convex/values";
import { firstTextBody, storedConversationCover } from "../lib/blockImages";
import type { Doc } from "./_generated/dataModel";
import { mutation, query, type MutationCtx, type QueryCtx } from "./_generated/server";
import { deleteRunReceipts } from "./generationActions";
import { ownerKey, requireOwnerKey } from "./ownership";
import { coverImageValidator } from "./schema";

const MAX_LIST_PAGE = 100;
const MAX_HISTORY_PAGE = 50;
const PAGE_BYTES = 4 * 1024 * 1024;
const PURGE_BATCH = 100;
const PURGE_BYTES = 1024 * 1024;
const MAX_TITLE = 120;
const MAX_CHANGE_KEYS = 100;

const conversationValidator = v.object({
  key: v.string(),
  title: v.string(),
  updatedAt: v.number(),
  archived: v.boolean(),
  pinnedAt: v.optional(v.number()),
  preview: v.union(v.string(), v.null()),
  image: v.optional(coverImageValidator),
  imageURL: v.optional(v.string()),
});

const historyPageValidator = v.object({
  pageKey: v.string(),
  previousPageKey: v.optional(v.string()),
  parentPageKey: v.optional(v.string()),
  sourceCardKey: v.optional(v.string()),
  prompt: v.string(),
  title: v.optional(v.string()),
  blocks: v.string(),
  activities: v.optional(v.string()),
  sources: v.optional(v.string()),
});

const listValidator = v.union(v.literal("pinned"), v.literal("recent"), v.literal("archived"));

export async function conversationSummary(
  ctx: QueryCtx,
  owner: string,
  conversationKey: string,
): Promise<Doc<"conversationSummaries"> | null> {
  return await ctx.db
    .query("conversationSummaries")
    .withIndex("by_userTokenIdentifier_and_conversationKey", (q) =>
      q.eq("userTokenIdentifier", owner).eq("conversationKey", conversationKey),
    )
    .unique();
}

export async function syncConversationSummary(ctx: MutationCtx, page: Doc<"pages">): Promise<void> {
  if (page.parentPageKey) return;
  const existing = await conversationSummary(ctx, page.userTokenIdentifier, page.conversationKey);
  const updatedAt = page.requestedAt ?? page._creationTime;
  if (existing && existing.pageId !== page._id && existing.updatedAt > updatedAt) return;
  const cover = storedConversationCover(page);
  const generated = {
    pageId: page._id,
    title: page.title || page.prompt,
    updatedAt,
    preview: firstTextBody(page.blocks),
    image: cover.image,
    imageURL: cover.imageURL,
  };
  if (existing) {
    await ctx.db.patch("conversationSummaries", existing._id, generated);
    return;
  }
  await ctx.db.insert("conversationSummaries", {
    userTokenIdentifier: page.userTokenIdentifier,
    conversationKey: page.conversationKey,
    archived: false,
    ...generated,
  });
}

function conversationView(summary: Doc<"conversationSummaries">) {
  return {
    key: summary.conversationKey,
    title: summary.customTitle ?? summary.title,
    updatedAt: summary.updatedAt,
    archived: summary.archived,
    ...(summary.pinnedAt !== undefined ? { pinnedAt: summary.pinnedAt } : {}),
    preview: summary.preview ?? null,
    ...(summary.image ? { image: summary.image } : {}),
    ...(summary.imageURL ? { imageURL: summary.imageURL } : {}),
  };
}

function pageSize(limit: number, max: number): number {
  return Number.isFinite(limit) ? Math.min(max, Math.max(1, Math.floor(limit))) : max;
}

function summariesIn(ctx: QueryCtx, owner: string, list: "pinned" | "recent" | "archived") {
  const summaries = ctx.db.query("conversationSummaries");
  if (list === "archived") {
    return summaries.withIndex("by_userTokenIdentifier_and_archived_and_updatedAt", (q) =>
      q.eq("userTokenIdentifier", owner).eq("archived", true),
    );
  }
  return summaries.withIndex(
    "by_userTokenIdentifier_and_archived_and_pinnedAt_and_updatedAt",
    (q) =>
      list === "pinned"
        ? q.eq("userTokenIdentifier", owner).eq("archived", false).gt("pinnedAt", 0)
        : q.eq("userTokenIdentifier", owner).eq("archived", false).eq("pinnedAt", undefined),
  );
}

export const list = query({
  args: { list: listValidator, cursor: v.union(v.string(), v.null()), limit: v.number() },
  returns: v.object({
    conversations: v.array(conversationValidator),
    nextCursor: v.union(v.string(), v.null()),
  }),
  handler: async (ctx, args) => {
    const owner = await ownerKey(ctx);
    if (!owner) return { conversations: [], nextCursor: null };
    const result = await summariesIn(ctx, owner, args.list)
      .order("desc")
      .paginate({ numItems: pageSize(args.limit, MAX_LIST_PAGE), cursor: args.cursor });
    return {
      conversations: result.page.map(conversationView),
      nextCursor: result.isDone ? null : result.continueCursor,
    };
  },
});

export const history = query({
  args: { conversationKey: v.string(), cursor: v.union(v.string(), v.null()), limit: v.number() },
  returns: v.object({
    pages: v.array(historyPageValidator),
    nextCursor: v.union(v.string(), v.null()),
  }),
  handler: async (ctx, args) => {
    const owner = await ownerKey(ctx);
    if (!owner) return { pages: [], nextCursor: null };
    const result = await ctx.db
      .query("pages")
      .withIndex("by_userTokenIdentifier_and_conversationKey_and_requestedAt", (q) =>
        q.eq("userTokenIdentifier", owner).eq("conversationKey", args.conversationKey),
      )
      .order("desc")
      .paginate({
        numItems: pageSize(args.limit, MAX_HISTORY_PAGE),
        cursor: args.cursor,
        maximumBytesRead: PAGE_BYTES,
      });
    return {
      pages: result.page.reverse().map((page) => ({
        pageKey: page.pageKey,
        previousPageKey: page.previousPageKey,
        parentPageKey: page.parentPageKey,
        sourceCardKey: page.sourceCardKey,
        prompt: page.prompt,
        title: page.title,
        blocks: page.blocks,
        activities: page.activities,
        sources: page.sources,
      })),
      nextCursor: result.isDone ? null : result.continueCursor,
    };
  },
});

async function updateSummary(
  ctx: MutationCtx,
  conversationKey: string,
  patch: Partial<Pick<Doc<"conversationSummaries">, "pinnedAt" | "archived" | "customTitle">>,
): Promise<boolean> {
  const owner = await requireOwnerKey(ctx);
  const summary = await conversationSummary(ctx, owner, conversationKey);
  if (!summary) return false;
  await ctx.db.patch("conversationSummaries", summary._id, patch);
  return true;
}

export const setPinned = mutation({
  args: { conversationKey: v.string(), pinned: v.boolean() },
  returns: v.boolean(),
  handler: async (ctx, args) =>
    await updateSummary(ctx, args.conversationKey, {
      pinnedAt: args.pinned ? Date.now() : undefined,
    }),
});

export const setArchived = mutation({
  args: { conversationKeys: v.array(v.string()), archived: v.boolean() },
  returns: v.number(),
  handler: async (ctx, args) => {
    if (args.conversationKeys.length > MAX_CHANGE_KEYS) throw new Error("too many conversations");
    let changed = 0;
    for (const conversationKey of new Set(args.conversationKeys)) {
      if (await updateSummary(ctx, conversationKey, { archived: args.archived })) changed++;
    }
    return changed;
  },
});

export const rename = mutation({
  args: { conversationKey: v.string(), title: v.string() },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const customTitle = args.title.trim().slice(0, MAX_TITLE);
    if (!customTitle) throw new Error("title required");
    return await updateSummary(ctx, args.conversationKey, { customTitle });
  },
});

export const purge = mutation({
  args: { conversationKey: v.string() },
  returns: v.number(),
  handler: async (ctx, args) => {
    const owner = await requireOwnerKey(ctx);
    const pages = await ctx.db
      .query("pages")
      .withIndex("by_userTokenIdentifier_and_conversationKey_and_requestedAt", (q) =>
        q.eq("userTokenIdentifier", owner).eq("conversationKey", args.conversationKey),
      )
      .paginate({ numItems: PURGE_BATCH, cursor: null, maximumBytesRead: PURGE_BYTES });
    for (const page of pages.page) await ctx.db.delete("pages", page._id);
    const summary = await conversationSummary(ctx, owner, args.conversationKey);
    if (summary) await ctx.db.delete("conversationSummaries", summary._id);
    const runs = await ctx.db
      .query("generationRuns")
      .withIndex("by_userTokenIdentifier_and_conversationKey_and_tombstoned", (q) =>
        q
          .eq("userTokenIdentifier", owner)
          .eq("conversationKey", args.conversationKey)
          .eq("tombstoned", false),
      )
      .take(PURGE_BATCH);
    let receiptBudget = PURGE_BATCH;
    for (const run of runs) {
      const receipts = await deleteRunReceipts(ctx, run, receiptBudget);
      receiptBudget -= receipts.deleted;
      await ctx.db.patch("generationRuns", run._id, {
        status: run.status === "running" ? "cancelled" : run.status,
        tombstoned: !receipts.more,
      });
    }
    return pages.page.length + runs.length;
  },
});
