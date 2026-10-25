import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { convexTest } from "convex-test";
import { describe, expect, it, vi } from "vitest";
import { api } from "../convex/_generated/api";
import schema from "../convex/schema";
import { classifyProviderError, friendlyProviderMessage } from "../lib/generationErrors";
import { createGenerationEmitter } from "../lib/generationEvents";
import { generationReplayResponse } from "../lib/generationIdempotency";
import {
  GENERATION_CANCELLED,
  generationFailure,
  isRenderablePage,
  parseGenerationNDJSON,
  type GenerationActivity,
  type GenerationSources,
} from "../lib/generationProtocol";
import { protocolFailureResponse } from "../lib/generationRequest";
import { createInferenceSession } from "../lib/inferenceTelemetry";
import type { InferenceTarget } from "../lib/provider";
import { pageFinishSchema } from "../lib/responsePlan";
import { blockSchema } from "../lib/schema";
import { sampleBlocks } from "./support/blockSamples";

const FIXTURES = new URL("../../contracts/fixtures/", import.meta.url);
const modules = import.meta.glob("../convex/**/*.ts");
const auth = vi.hoisted(() => ({ convex: null as unknown }));

vi.mock("@/lib/auth", () => ({
  requestAuth: async () => ({
    convex: auth.convex,
    authenticated: auth.convex !== null,
    ownerKey: auth.convex ? "https://clerk.example|fixture" : null,
    status: auth.convex ? "authenticated" : "guest",
  }),
  authFailure: () => null,
}));

const { POST: home } = await import("../app/api/home/route");
const { GET: listConversations } = await import("../app/api/conversations/route");
const { GET: readHistory } = await import("../app/api/history/route");
const { POST: changeConversation } = await import("../app/api/conversation/route");

const blocks = sampleBlocks();
const blocksOf = (type: string) => blocks.filter((block) => block.type === type);
const page = [
  blocksOf("pageMeta")[0],
  blocksOf("hero")[0],
  blocksOf("titleBlock")[0],
  blocksOf("text")[0],
  blocksOf("cardCarousel")[0],
  blocksOf("chipRow")[0],
];
const activity: GenerationActivity = {
  type: "activity",
  id: "activity-web",
  source: "web",
  category: "web",
  title: "Web search",
  status: "succeeded",
  message: "Found 2 sources",
};
const sources: GenerationSources = {
  type: "sources",
  id: "sources",
  items: [
    {
      id: "source-1",
      title: "Lisbon travel guide",
      url: "https://example.com/lisbon",
      domain: "example.com",
      favicon: "https://example.com/favicon.ico",
      publishedAt: "2026-10-01",
      snippet: "Where to eat in Alfama.",
    },
  ],
};

function deterministicClock() {
  let now = 0;
  vi.spyOn(performance, "now").mockImplementation(() => (now += 25));
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(Date.UTC(2026, 9, 25, 14, 0, 0));
}

async function emitted(
  previewEnabled: boolean,
  run: (emitter: ReturnType<typeof createGenerationEmitter>) => void,
) {
  const platform: InferenceTarget = {
    provider: "openrouter",
    modelId: "fixture-model",
    credentialSource: "platform",
    supportsImages: false,
  };
  const inference = createInferenceSession(
    { profile: { research: platform, compose: platform }, models: {} as never },
    { requestId: "request-fixture", kind: "interactive" },
  );
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      run(
        createGenerationEmitter({
          controller,
          signal: new AbortController().signal,
          isCancelled: () => false,
          previewEnabled,
          timing: { requestStarted: performance.now(), stages: {}, signal: AbortSignal.any([]) },
          inference,
        }),
      );
      controller.close();
    },
  });
  return await new Response(stream).text();
}

async function generateStreams(): Promise<Record<string, string>> {
  const providerCode = classifyProviderError(new Error("provider unavailable"));
  return {
    "generate-completed.ndjson": await emitted(true, (emitter) => {
      emitter.status("Searching the web…");
      emitter.preview(page.slice(0, 4) as never, true);
      emitter.completed(page, true, [activity, sources]);
    }),
    "generate-guest.ndjson": await emitted(false, (emitter) => {
      emitter.status("Laying out your page…", "status-compose");
      emitter.completed(page, undefined, []);
    }),
    "generate-failed.ndjson": await emitted(true, (emitter) =>
      emitter.failed(
        generationFailure(providerCode, friendlyProviderMessage(providerCode, false), true),
      ),
    ),
    "generate-cancelled.ndjson": await emitted(true, (emitter) =>
      emitter.failed(GENERATION_CANCELLED),
    ),
    "generate-replay.ndjson": await generationReplayResponse({
      state: "replay",
      status: "completed",
      blocks: JSON.stringify(page),
      activities: JSON.stringify([activity]),
      sources: JSON.stringify(sources.items),
      failure: null,
      persisted: true,
    }).text(),
    "generate-guest-limited.ndjson": await protocolFailureResponse(
      "You've reached the guest limit for now. Sign in to keep going.",
      "rate_limited",
      true,
    ).text(),
  };
}

const json = (value: unknown) => `${JSON.stringify(value, null, 2)}\n`;

async function get(handler: (req: Request) => Promise<Response>, path: string) {
  const response = await handler(new Request(`https://emblem.test${path}`));
  expect(response.status).toBe(200);
  return await response.text();
}

async function homeStream() {
  const response = await home(
    new Request("https://emblem.test/api/home", {
      method: "POST",
      body: JSON.stringify({
        name: "Sam",
        timezone: "America/New_York",
        nextEventTitle: "Dinner with Alex",
        nextEventStart: String(Date.now() / 1000 + 3 * 60 * 60),
      }),
    }),
  );
  expect(response.status).toBe(200);
  return await response.text();
}

async function signedInFixtures(): Promise<Record<string, string>> {
  const fixture = convexTest(schema, modules).withIdentity({
    subject: "fixture",
    issuer: "https://clerk.example",
    tokenIdentifier: "https://clerk.example|fixture",
  });
  auth.convex = fixture;
  const generate = async (
    conversationKey: string,
    requestId: string,
    title: string,
    lineage: { previousPageKey?: string; parentPageKey?: string; sourceCardKey?: string } = {},
  ) => {
    vi.setSystemTime(Date.now() + 60_000);
    await fixture.mutation(api.pages.claimGeneration, {
      requestId,
      fingerprint: requestId,
      conversationKey,
      ...lineage,
    });
    const blocksJSON = JSON.stringify([{ ...page[0], title }, ...page.slice(1)]);
    const hero = page[1] as { image: { query: string; kind: "photo"; aspect?: "landscape" } };
    const pageId = await fixture.mutation(api.pages.completeGeneration, {
      requestId,
      leaseGeneration: 1,
      prompt: `Tell me about ${title}`,
      title,
      blocks: blocksJSON,
      activities: JSON.stringify([activity]),
      sources: JSON.stringify(sources.items),
      coverImageQuery: hero.image.query,
      coverImageKind: "photo",
    });
    await fixture.mutation(api.pages.setCoverImageUrl, {
      pageId: pageId!,
      url: `https://images.example/${requestId}.jpg`,
    });
  };
  const act = async (body: Record<string, string>) =>
    expect(
      (
        await changeConversation(
          new Request("https://emblem.test/api/conversation", {
            method: "POST",
            body: JSON.stringify(body),
          }),
        )
      ).status,
    ).toBe(200);

  await generate("lisbon", "request-lisbon-1", "Lisbon");
  await generate("lisbon", "request-lisbon-2", "Alfama", { previousPageKey: "request-lisbon-1" });
  await generate("lisbon", "request-lisbon-3", "Tram 28", {
    parentPageKey: "request-lisbon-2",
    sourceCardKey: "card-1",
  });
  for (const key of ["kyoto", "oslo", "lima", "quito"]) await generate(key, `request-${key}`, key);
  vi.setSystemTime(Date.now() + 60_000);
  await act({ action: "pin", conversationKey: "lisbon" });
  await act({ action: "rename", conversationKey: "lisbon", title: "Our Lisbon trip" });
  await act({ action: "archive", conversationKey: "quito" });

  const first = JSON.parse(await get(listConversations, "/api/conversations?limit=2"));
  const historyFirst = JSON.parse(
    await get(readHistory, "/api/history?conversationKey=lisbon&limit=2"),
  );
  const fixtures = {
    "home.ndjson": await homeStream(),
    "conversations-first.json": json(first),
    "conversations-next.json": await get(
      listConversations,
      `/api/conversations?limit=2&cursor=${encodeURIComponent(first.nextCursor)}`,
    ).then((text) => json(JSON.parse(text))),
    "conversations-archived.json": json(
      JSON.parse(await get(listConversations, "/api/conversations?archived=true")),
    ),
    "history-first.json": json(historyFirst),
    "history-next.json": await get(
      readHistory,
      `/api/history?conversationKey=lisbon&limit=2&cursor=${encodeURIComponent(historyFirst.nextCursor)}`,
    ).then((text) => json(JSON.parse(text))),
  };
  auth.convex = null;
  return fixtures;
}

async function produce(): Promise<Record<string, string>> {
  deterministicClock();
  return {
    "blocks.json": json(blocks),
    ...(await generateStreams()),
    ...(await signedInFixtures()),
  };
}

const ndjson = (text: string) =>
  text
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line) as { type: string; blocks?: unknown[]; items?: unknown[] });

describe("contract fixtures", () => {
  it("are what the server produces today", async () => {
    const produced = await produce();
    if (process.env.CONTRACTS_WRITE === "1") {
      rmSync(FIXTURES, { recursive: true, force: true });
      mkdirSync(FIXTURES, { recursive: true });
      for (const [name, text] of Object.entries(produced)) {
        writeFileSync(new URL(name, FIXTURES), text);
      }
    }
    expect(readdirSync(FIXTURES).sort(), "run npm run contracts").toEqual(
      Object.keys(produced).sort(),
    );
    for (const [name, text] of Object.entries(produced)) {
      expect(readFileSync(new URL(name, FIXTURES), "utf8"), `${name}: run npm run contracts`).toBe(
        text,
      );
    }
  });

  it("hold only blocks the server's schema accepts", () => {
    const read = (name: string) => readFileSync(new URL(name, FIXTURES), "utf8");
    const stored = JSON.parse(read("blocks.json")) as unknown[];
    expect(new Set(stored.map((block) => blockSchema.parse(block).type))).toEqual(
      new Set(blockSchema.options.map((option) => option.shape.type.value)),
    );
    for (const name of readdirSync(FIXTURES).filter((file) => file.endsWith(".ndjson"))) {
      for (const event of ndjson(read(name))) {
        for (const block of event.type === "pageSnapshot" ? event.blocks! : []) {
          blockSchema.parse(block);
        }
      }
    }
    for (const name of ["generate-completed.ndjson", "generate-guest.ndjson", "home.ndjson"]) {
      expect(isRenderablePage(parseGenerationNDJSON(read(name)).blocks), name).toBe(true);
    }
    for (const name of ["history-first.json", "history-next.json"]) {
      for (const stored of JSON.parse(read(name)).pages) stored.blocks.forEach(blockSchema.parse);
    }
  });

  it("include every input kind a page can require", () => {
    const stored = JSON.parse(readFileSync(new URL("blocks.json", FIXTURES), "utf8")) as {
      type: string;
      items?: { input?: { kind?: string } }[];
    }[];
    const sampledKinds = new Set(
      stored.flatMap((block) =>
        block.type === "questionList" ? (block.items ?? []).map((item) => item.input?.kind) : [],
      ),
    );
    const finishKinds = pageFinishSchema.shape.requiredInput.unwrap().shape.kind.options;
    expect(finishKinds.filter((kind) => !sampledKinds.has(kind))).toEqual([]);
  });
});
