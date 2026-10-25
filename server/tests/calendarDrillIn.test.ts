import { getFunctionName, type FunctionReference } from "convex/server";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { generationFingerprint } from "../lib/generationIdempotency";
import { createPageAssembly } from "../lib/pageAssembly";
import { expansionEventGuidance } from "../lib/prompt";
import type { Block } from "../lib/schema";

const mocks = vi.hoisted(() => ({
  auth: vi.fn(),
  createStream: vi.fn(),
  query: vi.fn(),
  mutation: vi.fn(),
}));
vi.mock("@/lib/auth", async (original) => ({
  ...(await original<typeof import("../lib/auth")>()),
  requestAuth: mocks.auth,
}));
vi.mock("@/lib/rateLimit", async (original) => ({
  ...(await original<typeof import("../lib/rateLimit")>()),
  allowRequests: async () => true,
}));
vi.mock("@/lib/provider", async (original) => ({
  ...(await original<typeof import("../lib/provider")>()),
  resolveInferenceProfile: () => ({}),
}));
vi.mock("@/lib/inferenceTelemetry", async (original) => ({
  ...(await original<typeof import("../lib/inferenceTelemetry")>()),
  createInferenceSession: () => ({}),
}));
vi.mock("@/lib/generationStream", () => ({ createStream: mocks.createStream }));
const { POST } = await import("../app/api/generate/route");

type StreamInput = {
  persist: {
    calendarEvent?: { title: string; timeRange: string; dayLabel: string; place?: string };
    articleNeedsCover?: boolean;
    articleContext?: string;
    conversationKey: string;
  };
};

const event = {
  title: "Dentist",
  dayLabel: "Monday, Oct 26",
  timeRange: "9:00 – 10:00 AM",
  place: "Smile Clinic",
  attendees: ["Dr. Ana Ruiz"],
};

const name = (ref: unknown) => getFunctionName(ref as FunctionReference<"query">);

function generate(body: Record<string, unknown> = {}) {
  return POST(
    new Request("https://emblem.test/api/generate", {
      method: "POST",
      body: JSON.stringify({
        messages: [{ role: "user", content: "Dentist" }],
        parentPageKey: "calendar",
        sourceCardKey: "event-1",
        sourceCardTitle: "Dentist",
        calendarEvent: event,
        ...body,
      }),
    }),
  );
}

function streamed(): StreamInput {
  expect(mocks.createStream).toHaveBeenCalledTimes(1);
  return mocks.createStream.mock.calls[0][0] as StreamInput;
}

function signIn() {
  mocks.auth.mockResolvedValue({
    authenticated: true,
    status: "authenticated",
    ownerKey: "https://issuer.test|alice",
    convex: { query: mocks.query, mutation: mocks.mutation },
  });
}

beforeEach(() => {
  mocks.auth.mockReset().mockResolvedValue({
    authenticated: false,
    status: "guest",
    ownerKey: null,
    convex: { query: mocks.query, mutation: mocks.mutation },
  });
  mocks.createStream.mockReset().mockReturnValue(new Response("streamed"));
  mocks.query.mockReset().mockImplementation(async () => null);
  mocks.mutation
    .mockReset()
    .mockImplementation(async (ref) =>
      name(ref) === "pages:claimGeneration" ? { state: "claimed", leaseGeneration: 1 } : null,
    );
});

describe("calendar event drill-in", () => {
  it("opens a static calendar row from the event in the request", async () => {
    expect((await generate()).status).toBe(200);
    const { persist } = streamed();
    expect(persist.calendarEvent).toEqual(event);
    expect(persist.articleNeedsCover).toBe(false);
    expect(persist.articleContext).toBe(
      "SELECTED: Dentist: Monday, Oct 26 · 9:00 – 10:00 AM · Smile Clinic · with Dr. Ana Ruiz",
    );
    expect(expansionEventGuidance(persist.calendarEvent!)).toContain(
      'the calendar event "Dentist" on Monday, Oct 26, 9:00 – 10:00 AM at Smile Clinic',
    );
    const lead: Block = { type: "titleBlock", id: "lead", title: "Dentist" };
    const page = createPageAssembly({
      persist: { prompt: "Dentist", requestId: "r", timezone: "UTC", ...persist },
      articleLead: true,
      messages: [],
      weatherPayloads: [],
      sources: new Map(),
      researchNotesText: "",
      verifiedActionURLs: new Set(),
      hotelCatalogs: new Map(),
      hotelSummaries: new Map(),
      places: new Map(),
      hotelGalleryTarget: null,
    }).projectPage([lead]);
    expect(page.find((block) => block.type === "titleBlock")).toMatchObject({
      icon: { image: { query: "tooth", kind: "object" } },
    });
  });

  it.each([
    ["without a card drill-in", { parentPageKey: undefined, sourceCardKey: undefined }],
    ["with an unknown field", { calendarEvent: { ...event, notes: "bring forms" } }],
    ["with an empty title", { calendarEvent: { ...event, title: " " } }],
    ["with a long title", { calendarEvent: { ...event, title: "x".repeat(201) } }],
    ["with a long day", { calendarEvent: { ...event, dayLabel: "x".repeat(81) } }],
    ["with too many attendees", { calendarEvent: { ...event, attendees: Array(13).fill("Bo") } }],
    ["with a long attendee", { calendarEvent: { ...event, attendees: ["x".repeat(81)] } }],
  ])("rejects a calendar event %s", async (_, body) => {
    const response = await generate(body);
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ code: "invalid_request" });
    expect(mocks.createStream).not.toHaveBeenCalled();
  });

  it("needs no conversation or persisted parent page when signed in", async () => {
    signIn();
    expect((await generate()).status).toBe(200);
    expect(mocks.query.mock.calls.map(([ref]) => name(ref))).not.toContain("pages:byPageKey");
    const claim = mocks.mutation.mock.calls.find(([ref]) => name(ref) === "pages:claimGeneration");
    expect(claim?.[1]).toMatchObject({
      conversationKey: "anonymous",
      parentPageKey: "calendar",
      sourceCardKey: "event-1",
    });
    expect(streamed().persist).toMatchObject({
      conversationKey: "anonymous",
      calendarEvent: event,
    });
  });

  it("still finds the event on a generated page's event card", async () => {
    signIn();
    mocks.query.mockImplementation(async (ref) =>
      name(ref) === "pages:byPageKey"
        ? {
            blocks: JSON.stringify([
              {
                type: "eventCard",
                id: "day",
                dayLabel: "Monday",
                events: [{ title: "Dentist", timeRange: "9 AM", place: "Smile Clinic" }],
              },
            ]),
            sources: null,
          }
        : null,
    );
    await generate({ calendarEvent: undefined, conversationKey: "c1", parentPageKey: "page-1" });
    expect(streamed().persist.calendarEvent).toEqual({
      title: "Dentist",
      timeRange: "9 AM",
      place: "Smile Clinic",
      dayLabel: "Monday",
    });
  });

  it("treats a different event under the same request ID as different input", () => {
    const input = { messages: [{ role: "user", content: "Dentist" }], calendarEvent: event };
    expect(generationFingerprint(input)).not.toBe(
      generationFingerprint({ ...input, calendarEvent: { ...event, timeRange: "11 AM" } }),
    );
  });
});
