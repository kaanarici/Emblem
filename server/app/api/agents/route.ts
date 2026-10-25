import { logError } from "@/lib/log";
import { JSON_BODY_LIMITS, jsonResponse, readJsonBody } from "@/lib/http";

import { api } from "@/convex/_generated/api";
import {
  MAX_DAILY_UPDATE_TIMES,
  validateBriefingTimes,
  validateDailyUpdateTimes,
  validateSchedule,
} from "@/lib/automationSchedule";
import { authFailure, requestAuth } from "@/lib/auth";
import { AUTOMATION_ERROR_STATUS, readAutomationError } from "@/lib/automationErrors";
import { AUTOMATION_SOURCES } from "@/lib/executionGrant";
import { z } from "zod";

const id = z.string().trim().min(1).max(200);
const scheduleSchema = z
  .object({
    hour: z.number(),
    minute: z.number(),
    weekdays: z.array(z.number()).max(7).optional(),
    timezone: z.string().trim().min(1).max(100),
  })
  .strict()
  .superRefine((schedule, context) => {
    try {
      validateSchedule(schedule.hour, schedule.minute, schedule.weekdays, schedule.timezone);
    } catch {
      context.addIssue({ code: "custom", message: "invalid schedule" });
    }
  });
const briefingTime = z
  .object({
    hour: z.number(),
    minute: z.number(),
  })
  .strict();
const briefingTimes = z
  .object({
    morning: briefingTime.optional(),
    afternoon: briefingTime.optional(),
    evening: briefingTime.optional(),
  })
  .strict();
const dailyBriefConfiguration = z
  .object({
    enabled: z.boolean(),
    timezone: z.string().trim().min(1).max(100),
    times: briefingTimes,
    memory: z.boolean().optional(),
  })
  .strict()
  .superRefine((configuration, context) => {
    try {
      validateBriefingTimes(configuration.times, configuration.timezone);
    } catch {
      context.addIssue({ code: "custom", message: "invalid briefing schedule" });
    }
  });
const dailyUpdateConfiguration = z
  .object({
    timezone: z.string().trim().min(1).max(100),
    times: z.array(briefingTime).max(MAX_DAILY_UPDATE_TIMES),
    memory: z.boolean().optional(),
  })
  .strict()
  .superRefine((configuration, context) => {
    try {
      validateDailyUpdateTimes(configuration.times, configuration.timezone);
    } catch {
      context.addIssue({ code: "custom", message: "invalid daily update schedule" });
    }
  });
const createSchema = z
  .object({
    action: z.literal("create"),
    title: z.string().trim().max(200).optional(),
    prompt: z.string().trim().min(1).max(4000),
    schedule: scheduleSchema,
    conversationKey: z.string().trim().max(200).optional(),
    timezone: z.string().trim().max(100).optional(),
    sources: z.array(z.enum(AUTOMATION_SOURCES)).max(AUTOMATION_SOURCES.length).optional(),
    requestId: id.optional(),
  })
  .strict();
const actionSchema = z.union([
  createSchema,
  z
    .object({
      action: z.literal("syncDailyBrief"),
      schedule: scheduleSchema.optional(),
      briefing: dailyBriefConfiguration.optional(),
      updates: dailyUpdateConfiguration.optional(),
    })
    .strict()
    .superRefine((body, context) => {
      if ([body.schedule, body.briefing, body.updates].filter(Boolean).length > 1) {
        context.addIssue({
          code: "custom",
          message: "choose one briefing schedule format",
        });
      }
    }),
  z
    .object({
      action: z.enum(["dispatch", "retry"]),
      id,
      requestId: id.optional(),
    })
    .strict(),
  z.object({ action: z.literal("cancel"), runId: id }).strict(),
  z.object({ action: z.enum(["pause", "resume", "delete"]), id }).strict(),
]);

export async function GET(req: Request) {
  const auth = await requestAuth(req);
  const failure = authFailure(auth);
  if (failure) return failure;
  const { convex, authenticated } = auth;
  if (!convex || !authenticated) return jsonResponse({ agents: [] });

  try {
    const runsFor = new URL(req.url).searchParams.get("runsFor")?.trim();
    if (runsFor) {
      const rows = await convex.query(api.automations.runsFor, {
        automationId: runsFor,
      });
      return jsonResponse({
        runs: rows.map((row) => ({
          id: row._id,
          title: row.title,
          summary: row.summary,
          createdAt: row.startedAt,
          blocks: row.blocks,
        })),
      });
    }
    const rows = await convex.query(api.automations.list, {});
    const agents = rows.map((row) => ({
      id: row._id,
      preset: row.preset,
      title: row.title,
      prompt: row.prompt,
      briefingTimes: row.briefingTimes,
      updateTimes: row.updateTimes,
      schedule:
        row.hour != null && row.minute != null && row.timezone != null
          ? {
              hour: row.hour,
              minute: row.minute,
              weekdays: row.weekdays,
              timezone: row.timezone,
            }
          : null,
      enabled: row.enabled,
      conversationKey: row.conversationKey,
      nextRunAt: row.nextRunAt,
      lastRunAt: row.lastRunAt,
      latestRun: row.latestRun,
      sources: row.sources,
    }));
    return jsonResponse({ agents });
  } catch (error) {
    logError("automations list failed", error);
    return jsonResponse({ error: "agents unavailable" }, 500);
  }
}

export async function POST(req: Request) {
  const auth = await requestAuth(req);
  const failure = authFailure(auth);
  if (failure) return failure;
  const raw = await readJsonBody(req, JSON_BODY_LIMITS.automation);
  if (raw instanceof Response) return raw;
  const parsed = actionSchema.safeParse(raw);
  if (!parsed.success) return jsonResponse({ error: "invalid agent action" }, 400);
  const body = parsed.data;
  const { convex, authenticated } = auth;
  if (!convex) return jsonResponse({ error: "backend unavailable" }, 503);
  if (!authenticated) {
    return jsonResponse({ error: "sign in required" }, 401);
  }

  try {
    if (body.action === "syncDailyBrief") {
      const synced = await convex.mutation(api.automations.syncDailyBrief, {
        schedule: body.schedule,
        briefing: body.briefing,
        updates: body.updates,
      });
      return jsonResponse({ ok: true, action: body.action, ...synced });
    }

    if (body.action === "create") {
      const created = await convex.mutation(api.automations.create, {
        title: body.title || undefined,
        prompt: body.prompt,
        schedule: body.schedule,
        conversationKey: body.conversationKey || undefined,
        timezone: body.timezone || undefined,
        requestId: body.requestId,
        sources: body.sources ? Array.from(new Set(body.sources)) : undefined,
      });
      return jsonResponse({
        ok: true,
        action: "create",
        id: created.id,
        nextRunAt: created.nextRunAt,
      });
    }

    if (body.action === "dispatch" || body.action === "retry") {
      const { runId } = await convex.mutation(api.automations.dispatch, {
        id: body.id,
        requestId: body.requestId ?? crypto.randomUUID(),
      });
      return jsonResponse({ ok: true, action: body.action, runId });
    }

    if (body.action === "cancel") {
      const cancelled = await convex.mutation(api.automations.cancel, {
        runId: body.runId,
      });
      return jsonResponse({ ok: true, action: "cancel", cancelled });
    }

    if (body.action === "pause" || body.action === "resume" || body.action === "delete") {
      if (body.action === "delete") {
        await convex.mutation(api.automations.remove, { id: body.id });
      } else {
        await convex.mutation(api.automations.setEnabled, {
          id: body.id,
          enabled: body.action === "resume",
        });
      }
      return jsonResponse({ ok: true, action: body.action });
    }
    return jsonResponse({ error: "invalid agent action" }, 400);
  } catch (error) {
    const domain = readAutomationError(error);
    if (domain) {
      return jsonResponse(
        { error: domain.message, code: domain.code },
        AUTOMATION_ERROR_STATUS[domain.code],
      );
    }
    logError("automation action failed", error);
    return jsonResponse({ error: "agent action failed" }, 500);
  }
}
