import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalAction, internalMutation, mutation, query } from "./_generated/server";
import { failAutomation } from "../lib/automationErrors";
import {
  briefingScheduleTimes,
  computeNextRunAt,
  computeNextRunAtForTimes,
  scheduleTimes,
  type BriefingTimes,
  type ScheduleTime,
  validateBriefingTimes,
  validateDailyUpdateTimes,
  validateSchedule,
} from "../lib/automationSchedule";
import { verifyExecutionGrant, type AutomationSource } from "../lib/executionGrant";
import { GenerationFailedError } from "../lib/generationProtocol";
import { logError } from "../lib/log";
import { MAX_MEMORIES } from "../lib/memoryPolicy";
import { formatLocalRunTime } from "../lib/presentationTime";
import { generatePage, summarize } from "./automationExecution";
import {
  automationForRun,
  cancelClaimedRun,
  cancelOrphanedRun,
  claimAutomationRun,
  deleteAutomationRuns,
  isScheduledAutomation,
  isVisibleAutomation,
  pruneAutomationRuns,
  DEFAULT_SOURCES,
  MAX_AUTOMATIONS_PER_USER,
  MAX_RUNS_PER_AUTOMATION,
} from "./automationRuns";
import { scheduleBackground, RUN_LEASE_MS } from "./background";
import {
  claimCompletedGenerationAction,
  recordCompletedGenerationAction,
  type CompletedGenerationActionContext,
} from "./generationActions";
import { isOwnerErased, ownerKey } from "./ownership";
import {
  automationFields,
  automationRunFields,
  automationSourceValidator,
  briefingTimesValidator,
  dailyUpdateTimesValidator,
} from "./schema";

const nullableNumber = v.union(v.number(), v.null());
const runListItem = v.object({
  runId: v.id("automationRuns"),
  status: automationRunFields.status,
  title: automationRunFields.title,
  error: automationRunFields.error,
  startedAt: v.number(),
  finishedAt: automationRunFields.finishedAt,
});
const automationListItem = v.object({
  _id: v.id("automations"),
  preset: automationFields.preset,
  title: v.string(),
  prompt: v.string(),
  briefingTimes: automationFields.briefingTimes,
  updateTimes: automationFields.updateTimes,
  hour: automationFields.hour,
  minute: automationFields.minute,
  weekdays: automationFields.weekdays,
  timezone: automationFields.timezone,
  enabled: v.boolean(),
  nextRunAt: automationFields.nextRunAt,
  lastRunAt: automationFields.lastRunAt,
  conversationKey: automationFields.conversationKey,
  sources: v.array(automationSourceValidator),
  latestRun: v.union(runListItem, v.null()),
});

function ownsAutomation(
  automation: Doc<"automations"> | null,
  owner: string | null,
): automation is Doc<"automations"> {
  return automation !== null && owner !== null && automation.userTokenIdentifier === owner;
}

const PRIOR_RUNS = 3;
const DAILY_BRIEF_TITLE = "Daily brief";
const DAILY_BRIEF_PROMPT =
  "Prepare my next daily update for the current local time. Use today's calendar, relevant email since the prior update, saved preferences, and live weather only when an exact location is available. In the morning, orient me to the day; in the afternoon, focus on changes and what remains; in the evening, close open loops and preview tomorrow. Prioritize security, payment failures, same-day deadlines, explicit asks, customers, legal, hiring, product, finance, and partnerships; ignore marketing, routine receipts, and mail with no action. Compose it as a visual Emblem page, never a memo: lead the spoken intro with the single most important thing, show today's schedule as a timeline or event cards, messages that need me as a media row list with safe one-line previews, live weather as the weather block when available, and quick statuses as one compact fact list. Never write labeled prose sections such as 'Status and Context', 'Critical Actions', or 'Maintenance and Follow-ups'; the components carry the structure, and every section states what to do, not a log of what happened. Make personal claims only from successful source reads, and say briefly when a requested source is disconnected or unavailable. Never expose access codes, tokens, links, account numbers, email addresses, or unnecessary quotes.";
const DAILY_BRIEF_SOURCES: AutomationSource[] = ["googlecalendar", "gmail", "weather", "memory"];
const DAILY_BRIEF_BASE_SOURCES = DAILY_BRIEF_SOURCES.filter((source) => source !== "memory");
const CREATE_ACTION_KEY = "automation.create";

const scheduleValidator = v.object({
  hour: v.number(),
  minute: v.number(),
  weekdays: v.optional(v.array(v.number())),
  timezone: v.string(),
});

const dailyBriefConfigurationValidator = v.object({
  enabled: v.boolean(),
  timezone: v.string(),
  times: briefingTimesValidator,
  memory: v.optional(v.boolean()),
});

const dailyUpdateConfigurationValidator = v.object({
  timezone: v.string(),
  times: dailyUpdateTimesValidator,
  memory: v.optional(v.boolean()),
});

type DailyBriefConfiguration = {
  enabled: boolean;
  timezone: string;
  times: BriefingTimes;
  memory?: boolean;
};

type DailyUpdateConfiguration = {
  timezone: string;
  times: ScheduleTime[];
  memory?: boolean;
};

type DailyBriefUpdate = {
  enabled: boolean;
  timezone: string;
  weekdays: number[] | undefined;
  hour: number | undefined;
  minute: number | undefined;
  updateTimes: ScheduleTime[] | undefined;
  briefingTimes: BriefingTimes | undefined;
};

type CreatedAutomation = {
  id: string;
  nextRunAt: number | null;
};

function creationResult(value: string): CreatedAutomation | null {
  try {
    const parsed: unknown = JSON.parse(value);
    if (!parsed || typeof parsed !== "object") return null;
    const result = parsed as { id?: unknown; nextRunAt?: unknown };
    return typeof result.id === "string" &&
      (result.nextRunAt === null ||
        (typeof result.nextRunAt === "number" && Number.isFinite(result.nextRunAt)))
      ? (result as CreatedAutomation)
      : null;
  } catch {
    return null;
  }
}

function validateBriefingConfiguration(configuration: DailyBriefConfiguration): void {
  try {
    validateBriefingTimes(configuration.times, configuration.timezone);
  } catch {
    failAutomation("invalid_input", "invalid briefing schedule");
  }
}

function validateDailyUpdateConfiguration(configuration: DailyUpdateConfiguration): void {
  try {
    validateDailyUpdateTimes(configuration.times, configuration.timezone);
  } catch {
    failAutomation("invalid_input", "invalid daily update schedule");
  }
}

function dailyBriefUpdate(
  schedule:
    | {
        hour: number;
        minute: number;
        weekdays?: number[];
        timezone: string;
      }
    | undefined,
  briefing: DailyBriefConfiguration | undefined,
  updates: DailyUpdateConfiguration | undefined,
): DailyBriefUpdate | null {
  if ([schedule, briefing, updates].filter(Boolean).length > 1) {
    failAutomation("invalid_input", "choose one briefing schedule format");
  }
  if (schedule) {
    try {
      validateSchedule(schedule.hour, schedule.minute, schedule.weekdays, schedule.timezone);
    } catch {
      failAutomation("invalid_input", "invalid schedule");
    }
    return {
      enabled: true,
      timezone: schedule.timezone,
      weekdays: schedule.weekdays,
      hour: schedule.hour,
      minute: schedule.minute,
      updateTimes: undefined,
      briefingTimes: undefined,
    };
  }
  if (updates) {
    validateDailyUpdateConfiguration(updates);
    const first = updates.times[0];
    return {
      enabled: updates.times.length > 0,
      timezone: updates.timezone,
      weekdays: undefined,
      hour: first?.hour,
      minute: first?.minute,
      updateTimes: updates.times,
      briefingTimes: undefined,
    };
  }
  if (!briefing) return null;
  validateBriefingConfiguration(briefing);
  const first = briefingScheduleTimes(briefing.times)[0];
  return {
    enabled: briefing.enabled,
    timezone: briefing.timezone,
    weekdays: undefined,
    hour: first.hour,
    minute: first.minute,
    updateTimes: undefined,
    briefingTimes: briefing.times,
  };
}

function sameUpdateTimes(
  left: readonly ScheduleTime[] | undefined,
  right: readonly ScheduleTime[] | undefined,
): boolean {
  if (!left || !right) return left === right;
  return (
    left.length === right.length &&
    left.every(
      (time, index) => time.hour === right[index]?.hour && time.minute === right[index]?.minute,
    )
  );
}

function sameBriefingTimes(
  left: BriefingTimes | undefined,
  right: BriefingTimes | undefined,
): boolean {
  if (!left || !right) return left === right;
  return (["morning", "afternoon", "evening"] as const).every(
    (period) =>
      left[period]?.hour === right[period]?.hour && left[period]?.minute === right[period]?.minute,
  );
}

function findDailyBrief(
  automations: readonly Doc<"automations">[],
): Doc<"automations"> | undefined {
  return automations.find((automation) => automation.preset === "daily_brief");
}

function dailyBriefSources(
  existing: Doc<"automations"> | undefined,
  memory: boolean | undefined,
): AutomationSource[] {
  const includeMemory = memory ?? existing?.sources?.includes("memory") ?? true;
  return includeMemory ? DAILY_BRIEF_SOURCES : DAILY_BRIEF_BASE_SOURCES;
}

function nextDailyBriefRunAt(update: DailyBriefUpdate): number | undefined {
  if (!update.enabled) return undefined;
  return computeNextRunAtForTimes(scheduleTimes(update), update.weekdays, update.timezone);
}

export const syncDailyBrief = mutation({
  args: {
    schedule: v.optional(scheduleValidator),
    briefing: v.optional(dailyBriefConfigurationValidator),
    updates: v.optional(dailyUpdateConfigurationValidator),
  },
  returns: v.object({
    id: v.union(v.id("automations"), v.null()),
    nextRunAt: nullableNumber,
    created: v.boolean(),
    updated: v.boolean(),
  }),
  handler: async (ctx, args) => {
    const owner = await ownerKey(ctx);
    if (!owner) throw new Error("sign in to configure Daily brief");
    const scheduleUpdate = dailyBriefUpdate(args.schedule, args.briefing, args.updates);

    const owned = await ctx.db
      .query("automations")
      .withIndex("by_userTokenIdentifier", (q) => q.eq("userTokenIdentifier", owner))
      .order("desc")
      .take(MAX_AUTOMATIONS_PER_USER + 10);
    const visible = owned.filter(isVisibleAutomation);
    const existing = findDailyBrief(visible);
    const sources = dailyBriefSources(existing, args.updates?.memory ?? args.briefing?.memory);
    if (existing) {
      const sourcesCurrent =
        existing.sources?.length === sources.length &&
        existing.sources.every((source, index) => source === sources[index]);
      const scheduleCurrent =
        !scheduleUpdate ||
        (existing.hour === scheduleUpdate.hour &&
          existing.minute === scheduleUpdate.minute &&
          existing.timezone === scheduleUpdate.timezone &&
          JSON.stringify(existing.weekdays) === JSON.stringify(scheduleUpdate.weekdays) &&
          sameUpdateTimes(existing.updateTimes, scheduleUpdate.updateTimes) &&
          sameBriefingTimes(existing.briefingTimes, scheduleUpdate.briefingTimes) &&
          existing.enabled === scheduleUpdate.enabled &&
          (scheduleUpdate.enabled ? existing.nextRunAt != null : existing.nextRunAt == null));
      const updated =
        existing.preset !== "daily_brief" ||
        existing.title !== DAILY_BRIEF_TITLE ||
        existing.prompt !== DAILY_BRIEF_PROMPT ||
        !sourcesCurrent ||
        !scheduleCurrent;
      const nextRunAt =
        scheduleUpdate && !scheduleCurrent
          ? nextDailyBriefRunAt(scheduleUpdate)
          : existing.nextRunAt;
      if (updated) {
        await ctx.db.patch("automations", existing._id, {
          preset: "daily_brief",
          title: DAILY_BRIEF_TITLE,
          prompt: DAILY_BRIEF_PROMPT,
          sources,
          ...(scheduleUpdate
            ? {
                hour: scheduleUpdate.hour,
                minute: scheduleUpdate.minute,
                weekdays: scheduleUpdate.weekdays,
                timezone: scheduleUpdate.timezone,
                enabled: scheduleUpdate.enabled,
                updateTimes: scheduleUpdate.updateTimes,
                briefingTimes: scheduleUpdate.briefingTimes,
                nextRunAt,
              }
            : {}),
        });
      }
      await scheduleBackground(ctx);
      return {
        id: existing._id,
        nextRunAt: nextRunAt ?? null,
        created: false,
        updated,
      };
    }

    if (!scheduleUpdate || !scheduleUpdate.enabled) {
      return { id: null, nextRunAt: null, created: false, updated: false };
    }
    if (visible.length >= MAX_AUTOMATIONS_PER_USER) {
      failAutomation("limit_reached", `limit of ${MAX_AUTOMATIONS_PER_USER} agents reached`);
    }
    const nextRunAt = nextDailyBriefRunAt(scheduleUpdate)!;
    const id = await ctx.db.insert("automations", {
      userTokenIdentifier: owner,
      preset: "daily_brief",
      title: DAILY_BRIEF_TITLE,
      prompt: DAILY_BRIEF_PROMPT,
      hour: scheduleUpdate.hour,
      minute: scheduleUpdate.minute,
      weekdays: scheduleUpdate.weekdays,
      timezone: scheduleUpdate.timezone,
      enabled: true,
      nextRunAt,
      updateTimes: scheduleUpdate.updateTimes,
      briefingTimes: scheduleUpdate.briefingTimes,
      sources,
    });
    await scheduleBackground(ctx);
    return { id, nextRunAt, created: true, updated: false };
  },
});

export const create = mutation({
  args: {
    title: v.optional(v.string()),
    prompt: v.string(),
    schedule: scheduleValidator,
    conversationKey: v.optional(v.string()),
    sources: v.optional(v.array(automationSourceValidator)),
    requestId: v.optional(v.string()),
    timezone: v.optional(v.string()),
  },
  returns: v.object({ id: v.id("automations"), nextRunAt: nullableNumber }),
  handler: async (ctx, args) => {
    const owner = await ownerKey(ctx);
    if (!owner) throw new Error("sign in to create automations");
    const prompt = args.prompt.trim();
    if (!prompt) failAutomation("invalid_input", "prompt required");
    if (prompt.length > 4000) failAutomation("invalid_input", "prompt too long");

    const requestId = args.requestId?.trim();
    if (args.requestId !== undefined && (!requestId || requestId.length > 200)) {
      failAutomation("invalid_input", "invalid request id");
    }
    const action: CompletedGenerationActionContext | null = requestId
      ? {
          requestId,
          actionKey: CREATE_ACTION_KEY,
          fingerprint: JSON.stringify({
            title: args.title,
            prompt,
            schedule: args.schedule,
            conversationKey: args.conversationKey,
            sources: args.sources,
            timezone: args.timezone,
          }),
        }
      : null;
    if (action) {
      const claim = await claimCompletedGenerationAction(ctx, owner, action);
      if (claim.state === "replay") {
        const stored = creationResult(claim.result);
        const id = stored ? ctx.db.normalizeId("automations", stored.id) : null;
        const automation = id ? await ctx.db.get("automations", id) : null;
        if (!stored || !id || !ownsAutomation(automation, owner)) {
          failAutomation("not_found", "agent no longer exists");
        }
        return { id, nextRunAt: stored.nextRunAt };
      }
      if (claim.state === "conflict") {
        failAutomation("invalid_state", "agent action conflicts with its first use");
      }
      if (claim.state === "rejected") {
        failAutomation("invalid_state", "agent action is no longer available");
      }
    }

    const existing = await ctx.db
      .query("automations")
      .withIndex("by_userTokenIdentifier", (q) => q.eq("userTokenIdentifier", owner))
      .take(MAX_AUTOMATIONS_PER_USER + 10);
    const visible = existing.filter(isVisibleAutomation);
    if (visible.length >= MAX_AUTOMATIONS_PER_USER) {
      failAutomation("limit_reached", `limit of ${MAX_AUTOMATIONS_PER_USER} agents reached`);
    }

    const schedule = args.schedule;
    let nextRunAt: number;
    try {
      validateSchedule(schedule.hour, schedule.minute, schedule.weekdays, schedule.timezone);
      nextRunAt = computeNextRunAt(
        schedule.hour,
        schedule.minute,
        schedule.weekdays,
        schedule.timezone,
      );
    } catch {
      failAutomation("invalid_input", "invalid schedule");
    }
    const id = await ctx.db.insert("automations", {
      userTokenIdentifier: owner,
      title: args.title?.trim() || prompt.slice(0, 60),
      prompt,
      hour: schedule.hour,
      minute: schedule.minute,
      weekdays: schedule.weekdays,
      timezone: schedule.timezone,
      enabled: true,
      nextRunAt,
      conversationKey: args.conversationKey,
      sources: args.sources ? Array.from(new Set(args.sources)) : DEFAULT_SOURCES,
    });
    await scheduleBackground(ctx);
    const result = { id, nextRunAt: nextRunAt ?? null };
    if (action) {
      await recordCompletedGenerationAction(ctx, owner, action, JSON.stringify(result));
    }
    return result;
  },
});

export const setEnabled = mutation({
  args: { id: v.string(), enabled: v.boolean() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const owner = await ownerKey(ctx);
    const id = ctx.db.normalizeId("automations", args.id.trim());
    if (!id) failAutomation("invalid_input", "invalid agent id");
    const automation = await ctx.db.get("automations", id);
    if (!ownsAutomation(automation, owner)) failAutomation("not_found", "agent not found");

    const patch: { enabled: boolean; nextRunAt?: number } = {
      enabled: args.enabled,
    };
    if (args.enabled) {
      const times = scheduleTimes(automation);
      if (!automation.timezone || times.length === 0) {
        failAutomation("invalid_state", "automation requires a schedule");
      }
      patch.nextRunAt = computeNextRunAtForTimes(times, automation.weekdays, automation.timezone);
    }
    await ctx.db.patch("automations", id, patch);
    await scheduleBackground(ctx);
    return null;
  },
});

export const remove = mutation({
  args: { id: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const owner = await ownerKey(ctx);
    const id = ctx.db.normalizeId("automations", args.id.trim());
    if (!id) failAutomation("invalid_input", "invalid agent id");
    const automation = await ctx.db.get("automations", id);
    if (!ownsAutomation(automation, owner)) failAutomation("not_found", "agent not found");
    await deleteAutomationRuns(ctx, id);
    await ctx.db.delete("automations", id);
    await scheduleBackground(ctx);
    return null;
  },
});

export const runsFor = query({
  args: { automationId: v.string() },
  returns: v.array(
    v.object({ _id: v.id("automationRuns"), _creationTime: v.number(), ...automationRunFields }),
  ),
  handler: async (ctx, args) => {
    const owner = await ownerKey(ctx);
    const automationId = ctx.db.normalizeId("automations", args.automationId.trim());
    if (!automationId) return [];
    const automation = await ctx.db.get("automations", automationId);
    if (!ownsAutomation(automation, owner)) return [];
    const runs = await ctx.db
      .query("automationRuns")
      .withIndex("by_automationId", (q) => q.eq("automationId", automationId))
      .order("desc")
      .take(MAX_RUNS_PER_AUTOMATION + 10);
    return runs.filter((run) => run.status === "completed").slice(0, 10);
  },
});

export const dispatch = mutation({
  args: { id: v.string(), requestId: v.string() },
  returns: v.object({ runId: v.id("automationRuns") }),
  handler: async (ctx, args) => {
    const owner = await ownerKey(ctx);
    const automationId = ctx.db.normalizeId("automations", args.id.trim());
    if (!automationId) failAutomation("invalid_input", "invalid agent id");
    const automation = await ctx.db.get("automations", automationId);
    if (!ownsAutomation(automation, owner)) failAutomation("not_found", "agent not found");
    const requestId = args.requestId.trim();
    if (!requestId || requestId.length > 200) {
      failAutomation("invalid_input", "invalid request id");
    }
    const runId = await claimAutomationRun(ctx, automation, {
      trigger: "manual",
      occurrenceKey: `manual:${requestId}`,
      throwIfBusy: true,
      dispatchBudget: "throw",
    });
    return { runId: runId! };
  },
});

export const homeUpdate = query({
  args: {},
  returns: v.union(
    v.null(),
    v.object({
      id: v.id("automations"),
      nextRunAt: nullableNumber,
      latestRun: v.union(
        v.null(),
        v.object({
          status: automationRunFields.status,
          summary: v.union(v.string(), v.null()),
          finishedAt: nullableNumber,
        }),
      ),
    }),
  ),
  handler: async (ctx) => {
    const owner = await ownerKey(ctx);
    if (!owner) return null;
    const automations = await ctx.db
      .query("automations")
      .withIndex("by_userTokenIdentifier", (q) => q.eq("userTokenIdentifier", owner))
      .order("desc")
      .take(MAX_AUTOMATIONS_PER_USER + 10);
    const automation = findDailyBrief(automations);
    if (!automation) return null;
    const latest = await ctx.db
      .query("automationRuns")
      .withIndex("by_automationId", (q) => q.eq("automationId", automation._id))
      .order("desc")
      .take(1);
    const run = latest[0];
    return {
      id: automation._id,
      nextRunAt: automation.enabled ? (automation.nextRunAt ?? null) : null,
      latestRun: run
        ? {
            status: run.status,
            summary: run.summary ?? null,
            finishedAt: run.finishedAt ?? null,
          }
        : null,
    };
  },
});

export const list = query({
  args: {},
  returns: v.array(automationListItem),
  handler: async (ctx) => {
    const owner = await ownerKey(ctx);
    if (!owner) return [];
    const automations = await ctx.db
      .query("automations")
      .withIndex("by_userTokenIdentifier", (q) => q.eq("userTokenIdentifier", owner))
      .order("desc")
      .take(MAX_AUTOMATIONS_PER_USER + 10);
    const out = [];
    for (const automation of automations) {
      if (!isVisibleAutomation(automation)) continue;
      const latest = await ctx.db
        .query("automationRuns")
        .withIndex("by_automationId", (q) => q.eq("automationId", automation._id))
        .order("desc")
        .take(1);
      out.push({
        _id: automation._id,
        preset: automation.preset,
        title: automation.title,
        prompt: automation.prompt,
        briefingTimes: automation.briefingTimes,
        updateTimes: automation.updateTimes,
        hour: automation.hour,
        minute: automation.minute,
        weekdays: automation.weekdays,
        timezone: automation.timezone,
        enabled: automation.enabled,
        nextRunAt: automation.nextRunAt,
        lastRunAt: automation.lastRunAt,
        conversationKey: automation.conversationKey,
        sources: automation.sources ?? DEFAULT_SOURCES,
        latestRun: latest[0]
          ? {
              runId: latest[0]._id,
              status: latest[0].status,
              title: latest[0].title,
              error: latest[0].error,
              startedAt: latest[0].startedAt,
              finishedAt: latest[0].finishedAt,
            }
          : null,
      });
    }
    return out;
  },
});

export const cancel = mutation({
  args: { runId: v.string() },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const owner = await ownerKey(ctx);
    const runId = ctx.db.normalizeId("automationRuns", args.runId.trim());
    if (!runId) failAutomation("invalid_input", "invalid run id");
    const run = await ctx.db.get("automationRuns", runId);
    if (!run || !owner || run.userTokenIdentifier !== owner) {
      failAutomation("not_found", "agent run not found");
    }
    return await cancelClaimedRun(ctx, run);
  },
});

export const executionAuthority = mutation({
  args: { grant: v.string(), checkId: v.string() },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    if (!args.checkId || args.checkId.length > 100) return false;
    const secret = process.env.AUTOMATION_SERVICE_KEY;
    if (!secret) throw new Error("execution authority unavailable");
    const grant = await verifyExecutionGrant(args.grant, secret);
    if (!grant) return false;
    const id = ctx.db.normalizeId("automationRuns", grant.runId);
    const run = id ? await ctx.db.get("automationRuns", id) : null;
    if (
      !run ||
      run.status !== "running" ||
      run.leaseGeneration !== grant.leaseGeneration ||
      run.userTokenIdentifier !== grant.ownerKey ||
      !run.leaseExpiresAt ||
      run.leaseExpiresAt <= Date.now() ||
      !run.sources ||
      run.sources.length !== grant.sources.length ||
      !run.sources.every((source, index) => source === grant.sources[index])
    )
      return false;
    if (await isOwnerErased(ctx, run.userTokenIdentifier)) return false;
    const automation = await ctx.db.get("automations", run.automationId);
    return Boolean(
      automation &&
      automation.userTokenIdentifier === run.userTokenIdentifier &&
      isScheduledAutomation(automation),
    );
  },
});

export const startRun = internalMutation({
  args: { runId: v.id("automationRuns") },
  returns: v.union(
    v.null(),
    v.object({
      prompt: v.string(),
      timezone: v.string(),
      priorSection: v.string(),
      ownerKey: v.string(),
      sources: v.array(automationSourceValidator),
      memories: v.array(v.string()),
      leaseGeneration: v.number(),
    }),
  ),
  handler: async (ctx, args) => {
    const run = await ctx.db.get("automationRuns", args.runId);
    if (run && (await isOwnerErased(ctx, run.userTokenIdentifier))) return null;
    if (!run || run.status !== "queued") return null;
    const automation = await automationForRun(ctx, run);
    if (!automation) {
      await cancelOrphanedRun(ctx, run);
      return null;
    }
    let priorSection = "";
    const prompt = run.instruction ?? automation.prompt;
    const timezone = run.timezone ?? automation.timezone ?? "UTC";
    const sources = run.sources ?? automation.sources ?? DEFAULT_SOURCES;
    const recent = await ctx.db
      .query("automationRuns")
      .withIndex("by_automationId", (q) => q.eq("automationId", automation._id))
      .order("desc")
      .take(PRIOR_RUNS * 3 + 1);
    const prior = recent
      .filter(
        (candidate) =>
          candidate._id !== args.runId && candidate.status === "completed" && candidate.summary,
      )
      .slice(0, PRIOR_RUNS);
    if (prior.length > 0) {
      priorSection =
        "\n\n[What you reported in your previous runs, most recent first. Build on it: update and add, don't repeat verbatim.]\n" +
        prior
          .map(
            (candidate) =>
              `- (${formatLocalRunTime(candidate.startedAt, timezone)}) ${candidate.summary}`,
          )
          .join("\n");
    }

    const memories = sources.includes("memory")
      ? (
          await ctx.db
            .query("memories")
            .withIndex("by_ownerKey", (q) => q.eq("ownerKey", run.userTokenIdentifier))
            .order("desc")
            .take(MAX_MEMORIES)
        ).map((memory) => memory.text)
      : [];
    const leaseGeneration = (run.leaseGeneration ?? 0) + 1;
    const now = Date.now();
    await ctx.db.patch("automationRuns", args.runId, {
      status: "running",
      instruction: prompt,
      timezone,
      sources,
      runningAt: now,
      attempt: (run.attempt ?? 0) + 1,
      leaseGeneration,
      leaseExpiresAt: now + RUN_LEASE_MS,
    });
    await scheduleBackground(ctx);
    return {
      prompt,
      timezone,
      priorSection,
      ownerKey: run.userTokenIdentifier,
      sources,
      memories,
      leaseGeneration,
    };
  },
});

export const executeRun = internalAction({
  args: { runId: v.id("automationRuns") },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const context: {
      prompt: string;
      timezone: string;
      priorSection: string;
      ownerKey: string;
      sources: AutomationSource[];
      memories: string[];
      leaseGeneration: number;
    } | null = await ctx.runMutation(internal.automations.startRun, {
      runId: args.runId,
    });
    if (!context) return null;
    try {
      const { title, blocks, terminalBlockCount, inference } = await generatePage(
        context.prompt + context.priorSection,
        context.timezone,
        {
          ownerKey: context.ownerKey,
          runId: args.runId,
          leaseGeneration: context.leaseGeneration,
          sources: context.sources,
          memories: context.memories,
        },
      );
      await ctx.runMutation(internal.automationDispatch.completeRun, {
        runId: args.runId,
        leaseGeneration: context.leaseGeneration,
        title,
        blocks: JSON.stringify(blocks),
        summary: summarize(title, blocks),
        terminalBlockCount,
      });
      if (inference) {
        await ctx
          .runMutation(internal.automationDispatch.recordRunInference, {
            runId: args.runId,
            leaseGeneration: context.leaseGeneration,
            inference,
          })
          .catch((error) =>
            logError("automation run inference audit failed", error, { runId: args.runId }),
          );
      }
    } catch (error) {
      logError("automation run failed", error, { runId: args.runId });
      const inference = error instanceof GenerationFailedError ? error.inference : undefined;
      await ctx.runMutation(internal.automationDispatch.failRun, {
        runId: args.runId,
        leaseGeneration: context.leaseGeneration,
        message: String(error),
        ...(inference ? { inference } : {}),
      });
    }
    return null;
  },
});

export const pruneRuns = internalMutation({
  args: { automationId: v.id("automations") },
  returns: v.null(),
  handler: async (ctx, args) => {
    await pruneAutomationRuns(ctx, args.automationId);
    return null;
  },
});

export const deleteRuns = internalMutation({
  args: { automationId: v.id("automations") },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    await deleteAutomationRuns(ctx, args.automationId);
    await scheduleBackground(ctx);
    return null;
  },
});
