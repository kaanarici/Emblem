import { convexTest } from "convex-test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../convex/_generated/api";
import schema from "../convex/schema";

const modules = import.meta.glob("../convex/**/*.ts");
const DAY = 24 * 60 * 60_000;

afterEach(() => {
  vi.useRealTimers();
});

function setup() {
  vi.useFakeTimers();
  vi.setSystemTime(Date.UTC(2026, 8, 1));
  const t = convexTest(schema, modules);
  const alice = t.withIdentity({
    subject: "alice",
    issuer: "https://clerk.example",
    tokenIdentifier: "https://clerk.example|alice",
  });
  return { t, alice };
}

async function page(alice: ReturnType<typeof setup>["alice"], requestId: string, key: string) {
  await alice.mutation(api.pages.claimGeneration, {
    requestId,
    fingerprint: requestId,
    conversationKey: key,
  });
  await alice.mutation(api.pages.completeGeneration, {
    requestId,
    leaseGeneration: 1,
    prompt: "Brief me every morning",
    blocks: "[]",
  });
}

async function sweep(t: ReturnType<typeof setup>["t"]) {
  for (let phase = 0, more = true; more; phase++) {
    ({ more } = await t.mutation(internal.pages.purgeExpiredRuns, { phase }));
  }
}

async function runIds(t: ReturnType<typeof setup>["t"]) {
  return (await t.run((ctx) => ctx.db.query("generationRuns").take(100))).map(
    (run) => run.requestId,
  );
}

describe("generation run retention", () => {
  it("keeps a page's agent action working after the retention window, exactly once", async () => {
    const { t, alice } = setup();
    await page(alice, "kept", "morning");
    await page(alice, "deleted", "gone");
    await alice.mutation(api.pages.claimGeneration, {
      requestId: "failed",
      fingerprint: "failed",
      conversationKey: "morning",
    });
    await alice.mutation(api.pages.finishGeneration, {
      requestId: "failed",
      leaseGeneration: 1,
      status: "failed",
    });
    await alice.mutation(api.conversations.purge, { conversationKey: "gone" });
    const create = {
      prompt: "Brief me every morning",
      schedule: { hour: 8, minute: 0, timezone: "UTC" },
      conversationKey: "morning",
      requestId: "kept",
      sources: [],
    };

    vi.setSystemTime(Date.now() + 31 * DAY);
    await sweep(t);

    expect(await runIds(t)).toEqual(["kept"]);
    const created = await alice.mutation(api.automations.create, create);
    expect(await alice.mutation(api.automations.create, create)).toEqual(created);

    vi.setSystemTime(Date.now() + 31 * DAY);
    await sweep(t);
    expect(await alice.mutation(api.automations.create, create)).toEqual(created);
  });
});
