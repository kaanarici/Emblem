import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  auth: vi.fn(),
  allow: vi.fn(),
  list: vi.fn(),
  execute: vi.fn(),
}));
vi.mock("@/lib/auth", async (original) => ({
  ...(await original<typeof import("../lib/auth")>()),
  requestAuth: mocks.auth,
}));
vi.mock("@/lib/rateLimit", async (original) => ({
  ...(await original<typeof import("../lib/rateLimit")>()),
  allowRequests: mocks.allow,
}));
vi.mock("@composio/core", () => ({
  Composio: class {
    connectedAccounts = { list: mocks.list };
    tools = { execute: mocks.execute };
  },
}));
vi.mock("@composio/vercel", () => ({ VercelProvider: class {} }));
const { GET } = await import("../app/api/calendar/events/route");

const OWNER = "https://issuer.test|alice";
const START = "2026-10-26T00:00:00-04:00";
const END = "2026-11-02T00:00:00-05:00";

function events(query = `start=${START}&end=${END}&timeZone=America/New_York`) {
  return GET(new Request(`https://emblem.test/api/calendar/events?${query}`));
}

function account(id: string, createdAt: string) {
  return { id, status: "ACTIVE", createdAt, toolkit: { slug: "googlecalendar" } };
}

function signIn() {
  mocks.auth.mockResolvedValue({
    authenticated: true,
    status: "authenticated",
    ownerKey: OWNER,
    convex: { query: async () => false },
  });
}

const notConnected = { google: { state: "notConnected", accounts: [] }, events: [] };

beforeEach(() => {
  vi.stubEnv("COMPOSIO_API_KEY", "synthetic-connector-key");
  mocks.auth.mockReset().mockResolvedValue({
    authenticated: false,
    status: "guest",
    ownerKey: null,
    convex: null,
  });
  mocks.allow.mockReset().mockResolvedValue(true);
  mocks.list.mockReset().mockResolvedValue({ items: [], nextCursor: null });
  mocks.execute.mockReset();
});
afterEach(() => vi.unstubAllEnvs());

describe("GET /api/calendar/events", () => {
  it.each([
    ["no range", ""],
    ["a local time without an offset", "start=2026-10-26T00:00:00&end=2026-10-27T00:00:00Z"],
    ["an end before its start", "start=2026-10-27T00:00:00Z&end=2026-10-26T00:00:00Z"],
    ["more than 45 days", "start=2026-10-01T00:00:00Z&end=2026-11-15T00:00:01Z"],
    ["an unknown time zone", `start=${START}&end=${END}&timeZone=Mars/Olympus`],
  ])("refuses %s", async (_, query) => {
    signIn();
    const response = await events(query);
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ code: "invalid_request" });
    expect(mocks.list).not.toHaveBeenCalled();
  });

  it("tells a guest Google Calendar is not connected without reading it", async () => {
    const response = await events();
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(notConnected);
    expect(mocks.allow).not.toHaveBeenCalled();
    expect(mocks.list).not.toHaveBeenCalled();
  });

  it("says not connected when connectors are off or no calendar account is linked", async () => {
    signIn();
    vi.stubEnv("COMPOSIO_API_KEY", "");
    expect(await (await events()).json()).toEqual(notConnected);
    expect(mocks.list).not.toHaveBeenCalled();
    vi.stubEnv("COMPOSIO_API_KEY", "synthetic-connector-key");
    expect(await (await events()).json()).toEqual(notConnected);
    expect(mocks.list).toHaveBeenCalled();
    expect(mocks.execute).not.toHaveBeenCalled();
  });

  it("admits signed-in reads through their own small bucket", async () => {
    signIn();
    mocks.allow.mockResolvedValue(false);
    expect((await events()).status).toBe(429);
    expect(mocks.allow.mock.calls[0][0]).toEqual([
      { key: `calendar-events:user:${OWNER}`, capacity: 30, refillPerHour: 120 },
    ]);
    expect(mocks.list).not.toHaveBeenCalled();
  });

  it("returns only allowlisted event fields and keeps one account's failure to itself", async () => {
    signIn();
    mocks.list.mockResolvedValue({
      items: [account("work", "2026-01-01"), account("home", "2026-02-01")],
      nextCursor: null,
    });
    const meeting = {
      id: "event-1_20261026T140000Z",
      iCalUID: "event-1@google.com",
      status: "confirmed",
      summary: "Design review",
      description: "Agenda: private notes",
      location: "Room 4",
      htmlLink: "https://www.google.com/calendar/event?eid=abc",
      hangoutLink: "https://meet.google.com/abc-defg-hij",
      start: { dateTime: "2026-10-26T10:00:00-04:00", timeZone: "America/New_York" },
      end: { dateTime: "2026-10-26T11:00:00-04:00", timeZone: "America/New_York" },
      organizer: { email: "lead@example.com", displayName: "Lead" },
      extendedProperties: { private: { crmToken: "secret-token" } },
      attendees: [
        { email: "me@example.com", self: true, responseStatus: "accepted", comment: "late" },
        { email: "ana@example.com", displayName: "Ana Ruiz" },
        ...Array.from({ length: 12 }, (_, index) => ({ email: `guest${index}@example.com` })),
      ],
    };
    mocks.execute.mockImplementation(async (_slug, body) => {
      if (body.connectedAccountId === "home") throw { status: 503, message: "secret-value" };
      return body.arguments.pageToken
        ? {
            successful: true,
            data: {
              summary: "me@example.com",
              items: [
                {
                  id: "trip",
                  summary: "Lisbon",
                  start: { date: "2026-10-30" },
                  end: { date: "2026-11-02" },
                },
                {
                  id: "gone",
                  status: "cancelled",
                  start: { date: "2026-10-30" },
                  end: { date: "2026-10-31" },
                },
              ],
            },
          }
        : {
            successful: true,
            data: { summary: "me@example.com", nextPageToken: "page-2", items: [meeting] },
          };
    });

    const response = await events();
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body).toEqual({
      google: {
        state: "connected",
        accounts: [
          { email: "me@example.com", state: "ok" },
          { email: "Account 2", state: "failed" },
        ],
      },
      events: [
        {
          id: "event-1_20261026T140000Z",
          iCalUID: "event-1@google.com",
          title: "Design review",
          start: "2026-10-26T14:00:00Z",
          end: "2026-10-26T15:00:00Z",
          allDay: false,
          location: "Room 4",
          calendar: "me@example.com",
          color: null,
          account: "me@example.com",
          url: "https://www.google.com/calendar/event?eid=abc",
          attendees: [
            "me@example.com",
            "Ana Ruiz",
            ...Array.from({ length: 10 }, (_, i) => `guest${i}@example.com`),
          ],
        },
        {
          id: "trip",
          iCalUID: null,
          title: "Lisbon",
          start: "2026-10-30",
          end: "2026-11-02",
          allDay: true,
          location: null,
          calendar: "me@example.com",
          color: null,
          account: "me@example.com",
          url: null,
          attendees: [],
        },
      ],
    });
    expect(JSON.stringify(body)).not.toMatch(/secret|private notes|meet\.google/);
    expect(mocks.execute).toHaveBeenCalledWith(
      "GOOGLECALENDAR_EVENTS_LIST",
      expect.objectContaining({
        userId: OWNER,
        connectedAccountId: "work",
        arguments: expect.objectContaining({
          calendarId: "primary",
          timeMin: START,
          timeMax: END,
          singleEvents: true,
          orderBy: "startTime",
          timeZone: "America/New_York",
        }),
      }),
      expect.anything(),
    );
  });
});
