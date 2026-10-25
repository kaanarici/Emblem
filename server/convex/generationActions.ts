import type { Doc } from "./_generated/dataModel";
import type { MutationCtx, QueryCtx } from "./_generated/server";

const MAX_REQUEST_ID = 200;
const MAX_ACTION_KEY = 100;
const MAX_FINGERPRINT = 25_000;
const MAX_RESULT = 25_000;

type GenerationActionClaim =
  | { state: "execute" }
  | { state: "replay"; result: string }
  | { state: "conflict" }
  | { state: "rejected" };

export type GenerationActionContext = {
  requestId: string;
  leaseGeneration: number;
  actionKey: string;
  fingerprint: string;
};

export type CompletedGenerationActionContext = Omit<GenerationActionContext, "leaseGeneration">;

function validIdentity(args: CompletedGenerationActionContext): boolean {
  return (
    args.requestId.trim().length > 0 &&
    args.requestId.length <= MAX_REQUEST_ID &&
    args.actionKey.trim().length > 0 &&
    args.actionKey.length <= MAX_ACTION_KEY &&
    args.fingerprint.length <= MAX_FINGERPRINT
  );
}

function validContext(args: GenerationActionContext): boolean {
  return validIdentity(args) && Number.isInteger(args.leaseGeneration) && args.leaseGeneration > 0;
}

export async function findGenerationRun(
  ctx: QueryCtx,
  userTokenIdentifier: string,
  requestId: string,
) {
  const canonical = requestId.trim();
  if (!canonical || canonical.length > MAX_REQUEST_ID) throw new Error("invalid request id");
  return await ctx.db
    .query("generationRuns")
    .withIndex("by_userTokenIdentifier_and_requestId", (q) =>
      q.eq("userTokenIdentifier", userTokenIdentifier).eq("requestId", canonical),
    )
    .unique();
}

async function claimReceipt(
  ctx: MutationCtx,
  userTokenIdentifier: string,
  args: CompletedGenerationActionContext,
): Promise<GenerationActionClaim> {
  const receipt = await ctx.db
    .query("generationActions")
    .withIndex("by_userTokenIdentifier_and_requestId_and_actionKey", (q) =>
      q
        .eq("userTokenIdentifier", userTokenIdentifier)
        .eq("requestId", args.requestId.trim())
        .eq("actionKey", args.actionKey.trim()),
    )
    .unique();
  if (!receipt) return { state: "execute" };
  return receipt.fingerprint === args.fingerprint
    ? { state: "replay", result: receipt.result }
    : { state: "conflict" };
}

export async function claimGenerationAction(
  ctx: MutationCtx,
  userTokenIdentifier: string,
  args: GenerationActionContext,
): Promise<GenerationActionClaim> {
  if (!validContext(args)) return { state: "rejected" };
  const run = await findGenerationRun(ctx, userTokenIdentifier, args.requestId);
  if (
    !run ||
    run.tombstoned ||
    run.status !== "running" ||
    run.leaseGeneration !== args.leaseGeneration ||
    run.leaseExpiresAt <= Date.now()
  ) {
    return { state: "rejected" };
  }

  return await claimReceipt(ctx, userTokenIdentifier, args);
}

export async function claimCompletedGenerationAction(
  ctx: MutationCtx,
  userTokenIdentifier: string,
  args: CompletedGenerationActionContext,
): Promise<GenerationActionClaim> {
  if (!validIdentity(args)) return { state: "rejected" };
  const run = await findGenerationRun(ctx, userTokenIdentifier, args.requestId);
  if (!run || run.tombstoned || run.status !== "completed" || !run.pageId) {
    return { state: "rejected" };
  }
  return await claimReceipt(ctx, userTokenIdentifier, args);
}

export async function recordGenerationAction(
  ctx: MutationCtx,
  userTokenIdentifier: string,
  args: GenerationActionContext,
  result: string,
): Promise<void> {
  if (!validContext(args)) {
    throw new Error("invalid generation action receipt");
  }
  await recordCompletedGenerationAction(ctx, userTokenIdentifier, args, result);
}

export async function recordCompletedGenerationAction(
  ctx: MutationCtx,
  userTokenIdentifier: string,
  args: CompletedGenerationActionContext,
  result: string,
): Promise<void> {
  if (!validIdentity(args) || result.length > MAX_RESULT) {
    throw new Error("invalid generation action receipt");
  }
  await ctx.db.insert("generationActions", {
    userTokenIdentifier,
    requestId: args.requestId.trim(),
    actionKey: args.actionKey.trim(),
    fingerprint: args.fingerprint,
    result,
  });
}

export async function deleteRunReceipts(
  ctx: MutationCtx,
  run: Doc<"generationRuns">,
  limit: number,
): Promise<{ deleted: number; more: boolean }> {
  const receipts = await ctx.db
    .query("generationActions")
    .withIndex("by_userTokenIdentifier_and_requestId_and_actionKey", (q) =>
      q.eq("userTokenIdentifier", run.userTokenIdentifier).eq("requestId", run.requestId),
    )
    .take(limit + 1);
  const batch = receipts.slice(0, limit);
  for (const receipt of batch) await ctx.db.delete("generationActions", receipt._id);
  return { deleted: batch.length, more: receipts.length > limit };
}
