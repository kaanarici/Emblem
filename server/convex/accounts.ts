import { internal } from "./_generated/api";
import {
  internalMutation,
  mutation,
  query,
  type MutationCtx,
  type QueryCtx,
} from "./_generated/server";
import { v } from "convex/values";
import { fenceOwnerWrites, isOwnerErased, ownerScopeHash } from "./ownership";

const BATCH = 80;
const BATCH_READ_BYTES = 1024 * 1024;
type ReadCtx = Pick<QueryCtx, "db">;
type PurgeResult = { done: boolean; deleted: number };

async function signedInOwner(ctx: QueryCtx): Promise<string> {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) throw new Error("authentication required");
  return identity.tokenIdentifier;
}

export const isErased = query({
  args: {},
  returns: v.boolean(),
  handler: async (ctx) => {
    return await isOwnerErased(ctx, await signedInOwner(ctx));
  },
});

export const beginErasure = mutation({
  args: {},
  returns: v.null(),
  handler: async (ctx) => {
    const owner = await signedInOwner(ctx);
    await fenceOwnerWrites(ctx, owner);
    await ctx.scheduler.runAfter(0, internal.accounts.continuePurge, { owner });
    return null;
  },
});

export const purgeSelf = mutation({
  args: {},
  returns: v.object({ done: v.boolean(), deleted: v.number() }),
  handler: async (ctx): Promise<PurgeResult> => {
    return await purgeAndContinue(ctx, await signedInOwner(ctx));
  },
});

export const purgeStatus = query({
  args: {},
  returns: v.object({ done: v.boolean() }),
  handler: async (ctx) => {
    const owner = await signedInOwner(ctx);
    const user = await ctx.db
      .query("users")
      .withIndex("by_tokenIdentifier", (q) => q.eq("tokenIdentifier", owner))
      .unique();
    return { done: !user && !(await hasScopedData(ctx, owner, await ownerScopeHash(owner))) };
  },
});

export const continuePurge = internalMutation({
  args: { owner: v.string() },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    await purgeAndContinue(ctx, args.owner);
    return null;
  },
});

async function purgeAndContinue(ctx: MutationCtx, owner: string): Promise<PurgeResult> {
  const result = await purgeBatch(ctx, owner);
  if (!result.done) {
    await ctx.scheduler.runAfter(0, internal.accounts.continuePurge, { owner });
  }
  return result;
}

async function purgeBatch(ctx: MutationCtx, owner: string): Promise<PurgeResult> {
  let deleted = 0;
  const scope = await fenceOwnerWrites(ctx, owner);

  for (const { table, query } of scopedQueries(ctx, owner, scope)) {
    if (!(await query().first())) continue;
    const batch = await query().paginate({
      cursor: null,
      numItems: BATCH,
      maximumRowsRead: BATCH,
      maximumBytesRead: BATCH_READ_BYTES,
    });
    for (const row of batch.page) {
      if ("storageId" in row) await ctx.storage.delete(row.storageId);
      await ctx.db.delete(table, row._id);
      deleted += 1;
    }
    break;
  }

  const done = !(await hasScopedData(ctx, owner, scope));
  if (done) {
    const user = await ctx.db
      .query("users")
      .withIndex("by_tokenIdentifier", (q) => q.eq("tokenIdentifier", owner))
      .unique();
    if (user) {
      await ctx.db.delete("users", user._id);
      deleted += 1;
    }
  }
  return { done, deleted };
}

function scopedQueries(ctx: ReadCtx, owner: string, scope: string) {
  return [
    {
      table: "pages",
      query: () =>
        ctx.db
          .query("pages")
          .withIndex("by_userTokenIdentifier_and_conversationKey_and_requestedAt", (q) =>
            q.eq("userTokenIdentifier", owner),
          ),
    },
    {
      table: "conversationSummaries",
      query: () =>
        ctx.db
          .query("conversationSummaries")
          .withIndex("by_userTokenIdentifier_and_conversationKey", (q) =>
            q.eq("userTokenIdentifier", owner),
          ),
    },
    {
      table: "generationRuns",
      query: () =>
        ctx.db
          .query("generationRuns")
          .withIndex("by_userTokenIdentifier_and_requestId", (q) =>
            q.eq("userTokenIdentifier", owner),
          ),
    },
    {
      table: "generationActions",
      query: () =>
        ctx.db
          .query("generationActions")
          .withIndex("by_userTokenIdentifier", (q) => q.eq("userTokenIdentifier", owner)),
    },
    {
      table: "memories",
      query: () =>
        ctx.db.query("memories").withIndex("by_ownerKey", (q) => q.eq("ownerKey", owner)),
    },
    {
      table: "profiles",
      query: () =>
        ctx.db.query("profiles").withIndex("by_ownerKey", (q) => q.eq("ownerKey", owner)),
    },
    {
      table: "automationRuns",
      query: () =>
        ctx.db
          .query("automationRuns")
          .withIndex("by_userTokenIdentifier", (q) => q.eq("userTokenIdentifier", owner)),
    },
    {
      table: "automations",
      query: () =>
        ctx.db
          .query("automations")
          .withIndex("by_userTokenIdentifier", (q) => q.eq("userTokenIdentifier", owner)),
    },
    {
      table: "automationDispatchBudgets",
      query: () =>
        ctx.db
          .query("automationDispatchBudgets")
          .withIndex("by_ownerKey", (q) => q.eq("ownerKey", owner)),
    },
    {
      table: "generatedImages",
      query: () =>
        ctx.db
          .query("generatedImages")
          .withIndex("by_ownerScopeHash", (q) => q.eq("ownerScopeHash", scope)),
    },
  ] as const;
}

async function hasScopedData(ctx: ReadCtx, owner: string, scope: string): Promise<boolean> {
  for (const { query } of scopedQueries(ctx, owner, scope)) {
    if (await query().first()) return true;
  }
  return false;
}
