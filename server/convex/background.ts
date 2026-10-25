import { v } from "convex/values";
import { internal } from "./_generated/api";
import { internalMutation } from "./_generated/server";
import type { MutationCtx } from "./_generated/server";

export const RUN_LEASE_MS = 3 * 60_000;
const BACKLOG_RETRY_MS = 60_000;
const DISPATCH_FOLLOW_UP_MS = 2_000;

export async function scheduleBackground(ctx: MutationCtx): Promise<void> {
  await ctx.scheduler.runAfter(0, internal.background.initialize, {});
}

async function reconcileBackground(
  ctx: MutationCtx,
  backlogDelayMs = BACKLOG_RETRY_MS,
): Promise<void> {
  const now = Date.now();
  const wakeup = await ctx.db.query("backgroundWakeup").unique();
  const automation = await ctx.db
    .query("automations")
    .withIndex("by_enabled_and_nextRunAt", (q) => q.eq("enabled", true).gt("nextRunAt", 0))
    .first();
  const queued = await ctx.db
    .query("automationRuns")
    .withIndex("by_status_and_startedAt", (q) => q.eq("status", "queued"))
    .first();
  const running = await ctx.db
    .query("automationRuns")
    .withIndex("by_status_and_leaseExpiresAt", (q) =>
      q.eq("status", "running").gt("leaseExpiresAt", 0),
    )
    .first();
  const deadlines = [
    automation?.nextRunAt,
    queued ? queued.startedAt + RUN_LEASE_MS : undefined,
    running?.leaseExpiresAt,
  ].filter((time): time is number => time !== undefined);

  const nextDeadline = Math.min(...deadlines);
  const backlog = deadlines.length > 0 && nextDeadline <= now;
  const scheduledAt = deadlines.length
    ? backlog
      ? now + backlogDelayMs
      : nextDeadline
    : undefined;
  if (
    wakeup &&
    (wakeup.scheduledAt === scheduledAt ||
      (backlog && wakeup.scheduledAt !== undefined && wakeup.scheduledAt <= now + backlogDelayMs))
  ) {
    if (scheduledAt === undefined) return;
    const job = wakeup.scheduledId
      ? await ctx.db.system.get("_scheduled_functions", wakeup.scheduledId)
      : null;
    if (job?.state.kind === "pending" || job?.state.kind === "inProgress") return;
  }
  if (wakeup?.scheduledId) await ctx.scheduler.cancel(wakeup.scheduledId);
  const scheduledId =
    scheduledAt === undefined
      ? undefined
      : await ctx.scheduler.runAt(scheduledAt, internal.background.wake, { scheduledAt });
  if (wakeup) {
    await ctx.db.patch("backgroundWakeup", wakeup._id, { scheduledAt, scheduledId });
  } else if (scheduledId) {
    await ctx.db.insert("backgroundWakeup", { scheduledAt, scheduledId });
  }
}

export const wake = internalMutation({
  args: { scheduledAt: v.number() },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const wakeup = await ctx.db.query("backgroundWakeup").unique();
    if (wakeup?.scheduledAt !== args.scheduledAt) return null;
    await ctx.db.patch("backgroundWakeup", wakeup._id, {
      scheduledAt: undefined,
      scheduledId: undefined,
    });
    const dispatched: { more: boolean } = await ctx.runMutation(
      internal.automationDispatch.dispatchDue,
      {},
    );
    await reconcileBackground(ctx, dispatched.more ? DISPATCH_FOLLOW_UP_MS : BACKLOG_RETRY_MS);
    return null;
  },
});

export const initialize = internalMutation({
  args: {},
  returns: v.null(),
  handler: async (ctx): Promise<null> => {
    await reconcileBackground(ctx);
    return null;
  },
});
