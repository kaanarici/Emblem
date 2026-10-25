import { scheduleBackground } from "./background";
import { isOwnerErased } from "./ownership";

import { internal } from "./_generated/api";
import type { MutationCtx } from "./_generated/server";
import type { Doc, Id } from "./_generated/dataModel";
import type { AutomationSource } from "../lib/executionGrant";
import { failAutomation } from "../lib/automationErrors";
import { scheduleTimes } from "../lib/automationSchedule";

export const MAX_RUNS_PER_AUTOMATION = 20;
export const MAX_AUTOMATIONS_PER_USER = 10;
export const DEFAULT_SOURCES: AutomationSource[] = ["web", "weather"];
const PRUNE_SCAN = 100;
const MANUAL_DISPATCH_CAPACITY = 6;
const MANUAL_DISPATCH_REFILL_PER_MS = 6 / (60 * 60 * 1000);

type ClaimOptions = {
  trigger: "manual" | "schedule";
  occurrenceKey: string;
  throwIfBusy: boolean;
  dispatchBudget?: "throw" | "skip";
};

export function isScheduledAutomation(automation: Doc<"automations">): boolean {
  return Boolean(automation.timezone) && scheduleTimes(automation).length > 0;
}

export function isVisibleAutomation(automation: Doc<"automations">): boolean {
  return automation.preset === "daily_brief" || isScheduledAutomation(automation);
}

export async function automationForRun(
  ctx: MutationCtx,
  run: Doc<"automationRuns">,
): Promise<Doc<"automations"> | null> {
  const automation = await ctx.db.get("automations", run.automationId);
  return automation?.userTokenIdentifier === run.userTokenIdentifier &&
    isScheduledAutomation(automation)
    ? automation
    : null;
}

export async function cancelOrphanedRun(
  ctx: MutationCtx,
  run: Doc<"automationRuns">,
): Promise<boolean> {
  if (!["queued", "running"].includes(run.status) || (await automationForRun(ctx, run)))
    return false;
  const now = Date.now();
  await ctx.db.patch("automationRuns", run._id, {
    status: "cancelled",
    error: "automation no longer scheduled",
    finishedAt: now,
  });
  await scheduleBackground(ctx);
  return true;
}

export async function claimAutomationRun(
  ctx: MutationCtx,
  automation: Doc<"automations">,
  options: ClaimOptions,
): Promise<Id<"automationRuns"> | null> {
  if (await isOwnerErased(ctx, automation.userTokenIdentifier)) return null;
  if (!isScheduledAutomation(automation)) {
    if (options.throwIfBusy) failAutomation("invalid_state", "automation requires a schedule");
    return null;
  }
  const duplicate = await ctx.db
    .query("automationRuns")
    .withIndex("by_automationId_and_occurrenceKey", (q) =>
      q.eq("automationId", automation._id).eq("occurrenceKey", options.occurrenceKey),
    )
    .unique();
  if (duplicate) return duplicate._id;
  for (const status of ["queued", "running"] as const) {
    const pending = await ctx.db
      .query("automationRuns")
      .withIndex("by_userTokenIdentifier_and_status", (q) =>
        q.eq("userTokenIdentifier", automation.userTokenIdentifier).eq("status", status),
      )
      .take(MAX_AUTOMATIONS_PER_USER + 1);
    let busy = pending.length > MAX_AUTOMATIONS_PER_USER;
    for (const run of pending) {
      if (!(await cancelOrphanedRun(ctx, run))) busy = true;
    }
    if (busy) {
      if (options.throwIfBusy) failAutomation("busy", "another automation run is already active");
      return null;
    }
  }
  if (
    options.dispatchBudget &&
    !(await consumeManualDispatchBudget(
      ctx,
      automation.userTokenIdentifier,
      options.dispatchBudget === "throw",
    ))
  )
    return null;
  const runId = await ctx.db.insert("automationRuns", {
    automationId: automation._id,
    userTokenIdentifier: automation.userTokenIdentifier,
    status: "queued",
    startedAt: Date.now(),
    trigger: options.trigger,
    occurrenceKey: options.occurrenceKey,
    attempt: 0,
    leaseGeneration: 0,
    instruction: automation.prompt,
    timezone: automation.timezone,
    sources: automation.sources ?? DEFAULT_SOURCES,
  });
  await ctx.scheduler.runAfter(0, internal.automations.executeRun, { runId });
  await scheduleBackground(ctx);
  return runId;
}

async function consumeManualDispatchBudget(
  ctx: MutationCtx,
  owner: string,
  throwIfEmpty: boolean,
): Promise<boolean> {
  const now = Date.now();
  const budget = await ctx.db
    .query("automationDispatchBudgets")
    .withIndex("by_ownerKey", (q) => q.eq("ownerKey", owner))
    .unique();
  const available = budget
    ? Math.min(
        MANUAL_DISPATCH_CAPACITY,
        budget.tokens + (now - budget.updatedAt) * MANUAL_DISPATCH_REFILL_PER_MS,
      )
    : MANUAL_DISPATCH_CAPACITY;
  if (available < 1) {
    if (throwIfEmpty) failAutomation("rate_limited", "manual dispatch limit reached");
    return false;
  }
  const next = { tokens: available - 1, updatedAt: now };
  if (budget) {
    await ctx.db.patch("automationDispatchBudgets", budget._id, next);
  } else {
    await ctx.db.insert("automationDispatchBudgets", { ownerKey: owner, ...next });
  }
  return true;
}

export async function cancelClaimedRun(
  ctx: MutationCtx,
  run: Doc<"automationRuns">,
): Promise<boolean> {
  if (await cancelOrphanedRun(ctx, run)) return true;
  if (run.status !== "queued" && run.status !== "running") return false;
  await ctx.db.patch("automationRuns", run._id, {
    status: "cancelled",
    error: "cancelled",
    finishedAt: Date.now(),
  });
  await pruneAutomationRuns(ctx, run.automationId);
  await scheduleBackground(ctx);
  return true;
}

export async function pruneAutomationRuns(
  ctx: MutationCtx,
  automationId: Id<"automations">,
): Promise<void> {
  const runs = await ctx.db
    .query("automationRuns")
    .withIndex("by_automationId", (q) => q.eq("automationId", automationId))
    .order("desc")
    .take(PRUNE_SCAN);
  let terminalCount = 0;
  let deleted = 0;
  for (const run of runs) {
    if (run.status === "queued" || run.status === "running") continue;
    terminalCount += 1;
    if (terminalCount <= MAX_RUNS_PER_AUTOMATION) continue;
    await ctx.db.delete("automationRuns", run._id);
    deleted += 1;
  }
  if (runs.length === PRUNE_SCAN && deleted > 0) {
    await ctx.scheduler.runAfter(0, internal.automations.pruneRuns, { automationId });
  }
}

export async function deleteAutomationRuns(
  ctx: MutationCtx,
  automationId: Id<"automations">,
): Promise<void> {
  const batch = await ctx.db
    .query("automationRuns")
    .withIndex("by_automationId", (q) => q.eq("automationId", automationId))
    .take(100);
  for (const run of batch) await ctx.db.delete("automationRuns", run._id);
  if (batch.length === 100) {
    await ctx.scheduler.runAfter(0, internal.automations.deleteRuns, { automationId });
  }
}
