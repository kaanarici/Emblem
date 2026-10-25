import { api } from "@/convex/_generated/api";
import { authFailure, requestAuth } from "@/lib/auth";
import { presentCalendarEvents, type CalendarEventRow } from "@/lib/connectorPresentation";
import {
  classifyConnectorFailure,
  connectorsEnabled,
  connectorStates,
  controlPlaneCall,
  getComposio,
} from "@/lib/connectors";
import { jsonResponse } from "@/lib/http";
import { logError, logWarning } from "@/lib/log";
import { admitMetered, METERED_ROUTES } from "@/lib/meteredAccess";
import { z } from "zod";

const MAX_SPAN_MS = 45 * 24 * 60 * 60 * 1000;
const MAX_PAGES = 4;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function validTimeZone(value: string): boolean {
  if (!/^[A-Za-z][A-Za-z0-9_+\-/]*$/.test(value)) return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value });
    return true;
  } catch {
    return false;
  }
}

const rangeSchema = z
  .object({
    start: z.iso.datetime({ offset: true }),
    end: z.iso.datetime({ offset: true }),
    timeZone: z.string().max(100).refine(validTimeZone).optional(),
  })
  .refine(({ start, end }) => {
    const span = Date.parse(end) - Date.parse(start);
    return span > 0 && span <= MAX_SPAN_MS;
  });

type Range = z.infer<typeof rangeSchema>;

const googleState = (state: "notConnected" | "unavailable") => ({
  google: { state, accounts: [] },
  events: [],
});

async function readAccount(ownerKey: string, accountId: string, range: Range, signal: AbortSignal) {
  const composio = await getComposio();
  const events: CalendarEventRow[] = [];
  let calendar: string | null = null;
  let pageToken: string | undefined;
  for (let page = 0; page < MAX_PAGES; page++) {
    const result = await controlPlaneCall(
      (callSignal) =>
        composio.tools.execute(
          "GOOGLECALENDAR_EVENTS_LIST",
          {
            userId: ownerKey,
            connectedAccountId: accountId,
            dangerouslySkipVersionCheck: true,
            arguments: {
              calendarId: "primary",
              timeMin: range.start,
              timeMax: range.end,
              singleEvents: true,
              orderBy: "startTime",
              maxResults: 250,
              ...(range.timeZone ? { timeZone: range.timeZone } : {}),
              ...(pageToken ? { pageToken } : {}),
            },
          },
          { signal: callSignal },
        ),
      signal,
    );
    if (!result.successful) throw result;
    const presented = presentCalendarEvents(result);
    calendar ??= presented.calendar;
    events.push(...presented.events);
    pageToken = presented.nextPageToken;
    if (!pageToken) break;
  }
  return { calendar, events };
}

export async function GET(req: Request) {
  const auth = await requestAuth(req);
  const failure = authFailure(auth);
  if (failure) return failure;
  const query = new URL(req.url).searchParams;
  const parsed = rangeSchema.safeParse({
    start: query.get("start") ?? undefined,
    end: query.get("end") ?? undefined,
    timeZone: query.get("timeZone") ?? undefined,
  });
  if (!parsed.success) {
    return jsonResponse({ error: "invalid calendar range", code: "invalid_request" }, 400);
  }
  const { authenticated, ownerKey, convex } = auth;
  if (!authenticated || !ownerKey || !connectorsEnabled()) {
    return jsonResponse(googleState("notConnected"));
  }
  if (!(await admitMetered(req, METERED_ROUTES.calendarEvents, auth))) {
    return jsonResponse({ error: "too many requests" }, 429);
  }
  let connection;
  try {
    if (!convex) throw new Error("account status unavailable");
    if (await convex.query(api.accounts.isErased, {})) {
      return jsonResponse({ error: "account erased", code: "account_erased" }, 403);
    }
    connection = (await connectorStates(ownerKey, false, req.signal)).find(
      (state) => state.slug === "googlecalendar",
    );
  } catch (error) {
    logError("calendar connection lookup failed", error, {
      code: classifyConnectorFailure(error, true).code,
    });
    return jsonResponse(googleState("unavailable"));
  }
  if (connection?.status !== "connected") {
    return jsonResponse(
      googleState(connection?.status === "needs_attention" ? "unavailable" : "notConnected"),
    );
  }
  const reads = await Promise.all(
    (connection.accounts ?? [])
      .filter((account) => account.status === "connected")
      .map(async (account) => {
        try {
          const { calendar, events } = await readAccount(
            ownerKey,
            account.id,
            parsed.data,
            req.signal,
          );
          const email = calendar && EMAIL.test(calendar) ? calendar : account.label;
          return {
            email,
            state: "ok",
            events: events.map((event) => ({ ...event, account: email })),
          };
        } catch (error) {
          logWarning("calendar events read failed", error, {
            code: classifyConnectorFailure(error).code,
          });
          return { email: account.label, state: "failed", events: [] };
        }
      }),
  );
  return jsonResponse({
    google: { state: "connected", accounts: reads.map(({ email, state }) => ({ email, state })) },
    events: reads.flatMap((read) => read.events),
  });
}
