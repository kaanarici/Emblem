import { ownerKey, requireOwnerKey } from "./ownership";
import { action, internalMutation, mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { MutationCtx } from "./_generated/server";
import type { Id } from "./_generated/dataModel";
import { MAX_MEMORIES, MAX_MEMORY_CHARS } from "../lib/memoryPolicy";
import { sha256Hex } from "../lib/signing";
import {
  claimGenerationAction,
  recordGenerationAction,
  type GenerationActionContext,
} from "./generationActions";

const COMPACTION_BATCH = 80;
const CLEAR_MAX_BATCHES = 100;
const CLEAR_DEADLINE_MS = 10_000;

function tokenize(text: string): Set<string> {
  return new Set(
    text
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, " ")
      .split(/\s+/)
      .filter((w) => w.length > 2),
  );
}

async function saveMemory(
  ctx: MutationCtx,
  owner: string,
  text: string,
): Promise<Id<"memories"> | null> {
  const existing = await ctx.db
    .query("memories")
    .withIndex("by_ownerKey", (q) => q.eq("ownerKey", owner))
    .order("desc")
    .take(MAX_MEMORIES);
  if (existing.some((memory) => memory.text.trim().toLowerCase() === text.toLowerCase())) {
    await compactMemoryBatch(ctx, owner);
    return null;
  }
  const id = await ctx.db.insert("memories", {
    ownerKey: owner,
    text,
    createdAt: Date.now(),
  });
  await compactMemoryBatch(ctx, owner);
  return id;
}

async function forgetMemory(ctx: MutationCtx, owner: string, text: string): Promise<string | null> {
  const rows = await ctx.db
    .query("memories")
    .withIndex("by_ownerKey", (q) => q.eq("ownerKey", owner))
    .order("desc")
    .take(MAX_MEMORIES);
  if (rows.length === 0) return null;

  const exactNeedle = text.trim().toLocaleLowerCase();
  const exact = rows.find((row) => row.text.trim().toLocaleLowerCase() === exactNeedle);
  if (exact) {
    await ctx.db.delete("memories", exact._id);
    return exact.text;
  }

  const wanted = tokenize(text);
  if (wanted.size === 0) return null;

  let best: { id: (typeof rows)[number]["_id"]; text: string; score: number } | null = null;
  for (const row of rows) {
    const tokens = tokenize(row.text);
    let overlap = 0;
    for (const word of wanted) if (tokens.has(word)) overlap += 1;
    if (!best || overlap > best.score) {
      best = { id: row._id, text: row.text, score: overlap };
    }
  }
  const threshold = wanted.size === 1 ? 1 : 2;
  if (!best || best.score < threshold) return null;

  await ctx.db.delete("memories", best.id);
  return best.text;
}

export const list = query({
  args: {},
  returns: v.array(v.string()),
  handler: async (ctx) => {
    const owner = await ownerKey(ctx);
    if (!owner) return [];
    const rows = await ctx.db
      .query("memories")
      .withIndex("by_ownerKey", (q) => q.eq("ownerKey", owner))
      .order("desc")
      .take(MAX_MEMORIES);
    return rows.map((r) => r.text);
  },
});

async function compactMemoryBatch(ctx: MutationCtx, owner: string) {
  const rows = await ctx.db
    .query("memories")
    .withIndex("by_ownerKey", (q) => q.eq("ownerKey", owner))
    .order("desc")
    .take(MAX_MEMORIES + COMPACTION_BATCH);
  for (const stale of rows.slice(MAX_MEMORIES)) {
    await ctx.db.delete("memories", stale._id);
  }
  if (rows.length === MAX_MEMORIES + COMPACTION_BATCH) {
    await ctx.scheduler.runAfter(0, internal.memories.compact, { ownerKey: owner });
  }
}

export const compact = internalMutation({
  args: { ownerKey: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    await compactMemoryBatch(ctx, args.ownerKey);
    return null;
  },
});

async function clearMemoryBatch(ctx: MutationCtx): Promise<{ deleted: number; done: boolean }> {
  const owner = await requireOwnerKey(ctx);
  const rows = await ctx.db
    .query("memories")
    .withIndex("by_ownerKey", (q) => q.eq("ownerKey", owner))
    .take(COMPACTION_BATCH);
  for (const row of rows) await ctx.db.delete("memories", row._id);
  const remaining = await ctx.db
    .query("memories")
    .withIndex("by_ownerKey", (q) => q.eq("ownerKey", owner))
    .first();
  return { deleted: rows.length, done: remaining === null };
}

export const clearBatch = internalMutation({
  args: {},
  returns: v.object({ deleted: v.number(), done: v.boolean() }),
  handler: clearMemoryBatch,
});

export const clear = action({
  args: {},
  returns: v.number(),
  handler: async (ctx): Promise<number> => {
    if (!(await ctx.auth.getUserIdentity())) return 0;
    const deadline = Date.now() + CLEAR_DEADLINE_MS;
    let deleted = 0;
    for (let batch = 0; batch < CLEAR_MAX_BATCHES; batch++) {
      if (Date.now() >= deadline) throw new Error("memory clear incomplete");
      const result: { deleted: number; done: boolean } = await ctx.runMutation(
        internal.memories.clearBatch,
        {},
      );
      deleted += result.deleted;
      if (Date.now() >= deadline) throw new Error("memory clear incomplete");
      if (result.done) return deleted;
    }
    throw new Error("memory clear incomplete");
  },
});

export const forget = mutation({
  args: { text: v.string() },
  returns: v.union(v.null(), v.string()),
  handler: async (ctx, args) => {
    const owner = await ownerKey(ctx);
    if (!owner) return null;
    return await forgetMemory(ctx, owner, args.text);
  },
});

const generationActionValidator = v.union(
  v.object({ kind: v.literal("save"), text: v.string() }),
  v.object({ kind: v.literal("forget"), text: v.string() }),
);

const generationActionResultValidator = v.union(
  v.object({
    kind: v.literal("save"),
    saved: v.union(v.string(), v.null()),
  }),
  v.object({
    kind: v.literal("forget"),
    forgotten: v.union(v.string(), v.null()),
  }),
);

type GenerationMemoryResult =
  { kind: "save"; saved: string | null } | { kind: "forget"; forgotten: string | null };

export const applyGenerationAction = mutation({
  args: {
    requestId: v.string(),
    leaseGeneration: v.number(),
    action: generationActionValidator,
  },
  returns: generationActionResultValidator,
  handler: async (ctx, args) => {
    const owner = await ownerKey(ctx);
    const text = args.action.text.trim();
    if (!owner) throw new Error("generation memory action rejected");
    if (args.action.kind === "save" && text.length > MAX_MEMORY_CHARS) {
      throw new Error("memory too long");
    }
    const fingerprint = JSON.stringify({ kind: args.action.kind, text });
    const action: GenerationActionContext = {
      requestId: args.requestId,
      leaseGeneration: args.leaseGeneration,
      actionKey: `memory:${await sha256Hex(fingerprint)}`,
      fingerprint,
    };
    const claim = await claimGenerationAction(ctx, owner, action);
    if (claim.state === "replay") {
      return JSON.parse(claim.result) as GenerationMemoryResult;
    }
    if (claim.state !== "execute") {
      throw new Error("generation memory action rejected");
    }

    let result: GenerationMemoryResult;
    if (args.action.kind === "save") {
      const id = text ? await saveMemory(ctx, owner, text) : null;
      result = {
        kind: "save" as const,
        saved: id ? text : null,
      };
    } else {
      const forgotten = await forgetMemory(ctx, owner, text);
      result = {
        kind: "forget" as const,
        forgotten: forgotten?.slice(0, MAX_MEMORY_CHARS) ?? null,
      };
    }
    await recordGenerationAction(ctx, owner, action, JSON.stringify(result));
    return result;
  },
});
