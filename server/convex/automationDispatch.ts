import { logEvent } from "../lib/log";
import { scheduleBackground, RUN_LEASE_MS } from "./background";
import { isOwnerErased } from "./ownership";
import { internalMutation } from "./_generated/server";
import { v } from "convex/values";
import type { MutationCtx } from "./_generated/server";
import { computeNextRunAtForTimes, scheduleTimes } from "../lib/automationSchedule";
import { inferenceSummaryValidator } from "./inferenceTypes";
import {
  claimAutomationRun,
  automationForRun,
  cancelOrphanedRun,
  MAX_AUTOMATIONS_PER_USER,
  pruneAutomationRuns,
} from "./automationRuns";

const DISPATCH_BATCH = 10;
const MAX_ACTIVE_RUNS = 100;

const DISPATCH_SCAN = DISPATCH_BATCH * (MAX_AUTOMATIONS_PER_USER + 1);

async function activeRunCount(ctx: MutationCtx): Promise<number> {
  const active = await Promise.all(
    (["queued", "running"] as const).map((status) =>
      ctx.db
        .query("automationRuns")
        .withIndex("by_status_and_startedAt", (q) => q.eq("status", status))
        .take(MAX_ACTIVE_RUNS),
    ),
  );
  return active[0].length + active[1].length;
}

export const dispatchDue = internalMutation({
  args: {},
  returns: v.object({ more: v.boolean() }),
  handler: async (ctx): Promise<{ more: boolean }> => {
    const now = Date.now();
    await failStaleRuns(ctx, now);

    if (!process.env.GENERATE_ORIGIN || !process.env.AUTOMATION_SERVICE_KEY) {
      logEvent("error", "automations: set GENERATE_ORIGIN and AUTOMATION_SERVICE_KEY");
      return { more: false };
    }

    const budget = Math.min(
      DISPATCH_BATCH,
      Math.max(0, MAX_ACTIVE_RUNS - (await activeRunCount(ctx))),
    );
    const due = await ctx.db
      .query("automations")
      .withIndex("by_enabled_and_nextRunAt", (q) =>
        q.eq("enabled", true).gt("nextRunAt", 0).lte("nextRunAt", now),
      )
      .take(DISPATCH_SCAN);
    const visitedOwners = new Set<string>();
    let claimed = 0;
    for (const automation of due) {
      if (claimed === budget) break;
      if (await isOwnerErased(ctx, automation.userTokenIdentifier)) continue;
      const times = scheduleTimes(automation);
      if (!automation.timezone || times.length === 0) {
        await ctx.db.patch("automations", automation._id, { enabled: false });
        continue;
      }
      if (visitedOwners.has(automation.userTokenIdentifier)) continue;
      visitedOwners.add(automation.userTokenIdentifier);
      const scheduledAt = automation.nextRunAt!;
      const runId = await claimAutomationRun(ctx, automation, {
        trigger: "schedule",
        occurrenceKey: `schedule:${automation._id}:${scheduledAt}`,
        throwIfBusy: false,
      });

      if (!runId) continue;
      claimed += 1;
      await ctx.db.patch("automations", automation._id, {
        nextRunAt: computeNextRunAtForTimes(times, automation.weekdays, automation.timezone, now),
      });
    }
    return { more: due.length > 0 && claimed === budget };
  },
});

async function failStaleRuns(ctx: MutationCtx, now: number): Promise<void> {
  const queued = await ctx.db
    .query("automationRuns")
    .withIndex("by_status_and_startedAt", (q) =>
      q.eq("status", "queued").lte("startedAt", now - RUN_LEASE_MS),
    )
    .take(DISPATCH_BATCH);
  const expired = await ctx.db
    .query("automationRuns")
    .withIndex("by_status_and_leaseExpiresAt", (q) =>
      q.eq("status", "running").gt("leaseExpiresAt", 0).lte("leaseExpiresAt", now),
    )
    .take(DISPATCH_BATCH);
  for (const [stuck, error] of [
    [queued, "dispatch timed out"],
    [expired, "timed out"],
  ] as const) {
    for (const run of stuck) {
      if (await isOwnerErased(ctx, run.userTokenIdentifier)) continue;
      if (await cancelOrphanedRun(ctx, run)) continue;
      await ctx.db.patch("automationRuns", run._id, {
        status: "failed",
        error,
        finishedAt: now,
      });
      await pruneAutomationRuns(ctx, run.automationId);
    }
  }
}

export const completeRun = internalMutation({
  args: {
    runId: v.id("automationRuns"),
    leaseGeneration: v.number(),
    title: v.optional(v.string()),
    blocks: v.string(),

    summary: v.optional(v.string()),
    terminalBlockCount: v.optional(v.number()),
  },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const run = await ctx.db.get("automationRuns", args.runId);
    if (run && (await isOwnerErased(ctx, run.userTokenIdentifier))) return null;

    if (run && (await cancelOrphanedRun(ctx, run))) return null;
    if (
      !run ||
      run.status !== "running" ||
      run.leaseGeneration !== args.leaseGeneration ||
      run.leaseExpiresAt == null ||
      run.leaseExpiresAt <= Date.now()
    )
      return null;
    const automation = await automationForRun(ctx, run);
    if (!automation) return null;
    const now = Date.now();
    await ctx.db.patch("automationRuns", args.runId, {
      status: "completed",
      title: args.title,
      blocks: args.blocks,
      summary: args.summary,
      terminalBlockCount: args.terminalBlockCount,
      finishedAt: now,
    });
    await ctx.db.patch("automations", automation._id, { lastRunAt: now });
    await pruneAutomationRuns(ctx, run.automationId);
    await scheduleBackground(ctx);
    return null;
  },
});

export const recordRunInference = internalMutation({
  args: {
    runId: v.id("automationRuns"),
    leaseGeneration: v.number(),
    inference: inferenceSummaryValidator,
  },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const run = await ctx.db.get("automationRuns", args.runId);
    if (run && (await isOwnerErased(ctx, run.userTokenIdentifier))) return null;
    if (
      !run ||
      run.status !== "completed" ||
      run.leaseGeneration !== args.leaseGeneration ||
      args.inference.requestId !== String(args.runId)
    )
      return null;
    await ctx.db.patch("automationRuns", args.runId, {
      inference: { ...args.inference, calls: args.inference.calls.slice(0, 12) },
    });
    return null;
  },
});

export const failRun = internalMutation({
  args: {
    runId: v.id("automationRuns"),
    leaseGeneration: v.number(),
    message: v.string(),
    inference: v.optional(inferenceSummaryValidator),
  },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const run = await ctx.db.get("automationRuns", args.runId);
    if (run && (await isOwnerErased(ctx, run.userTokenIdentifier))) return null;
    if (run && (await cancelOrphanedRun(ctx, run))) return null;
    if (
      !run ||
      run.status !== "running" ||
      run.leaseGeneration !== args.leaseGeneration ||
      run.leaseExpiresAt == null ||
      run.leaseExpiresAt <= Date.now()
    )
      return null;
    await ctx.db.patch("automationRuns", args.runId, {
      status: "failed",
      error: args.message.slice(0, 500),
      inference:
        args.inference?.requestId === String(args.runId)
          ? { ...args.inference, calls: args.inference.calls.slice(0, 12) }
          : undefined,
      finishedAt: Date.now(),
    });
    await pruneAutomationRuns(ctx, run.automationId);
    await scheduleBackground(ctx);
    return null;
  },
});
