import { convexTest } from "convex-test";
import { describe, expect, it } from "vitest";
import { api } from "../convex/_generated/api";
import schema from "../convex/schema";

const modules = import.meta.glob("../convex/**/*.ts");

function as(t: ReturnType<typeof convexTest>, subject: string) {
  return t.withIdentity({
    subject,
    issuer: "https://clerk.example",
    tokenIdentifier: `https://clerk.example|${subject}`,
  });
}

const blocks = JSON.stringify([
  { type: "pageMeta", id: "meta", title: "Tomorrow" },
  { type: "text", id: "intro", style: "intro", body: "Two priorities." },
]);

describe("owner isolation", () => {
  it("keeps equal conversation keys isolated by verified owner", async () => {
    const t = convexTest(schema, modules);
    const alice = as(t, "alice");
    const bob = as(t, "bob");
    for (const [owner, prompt] of [
      [alice, "Alice's page"],
      [bob, "Bob's page"],
    ] as const) {
      const requestId = crypto.randomUUID();
      await owner.mutation(api.pages.claimGeneration, {
        requestId,
        fingerprint: prompt,
        conversationKey: "same-client-key",
      });
      await owner.mutation(api.pages.completeGeneration, {
        requestId,
        leaseGeneration: 1,
        prompt,
        blocks,
      });
    }
    const read = async (owner: typeof alice) =>
      (
        await owner.query(api.conversations.history, {
          conversationKey: "same-client-key",
          cursor: null,
          limit: 50,
        })
      ).pages;

    expect((await read(alice)).map((page) => page.prompt)).toEqual(["Alice's page"]);
    expect((await read(bob)).map((page) => page.prompt)).toEqual(["Bob's page"]);

    await bob.mutation(api.conversations.purge, { conversationKey: "same-client-key" });
    expect(await read(bob)).toEqual([]);
    expect((await read(alice)).map((page) => page.prompt)).toEqual(["Alice's page"]);
  });

  it("claims one owner-scoped generation and atomically replays its page", async () => {
    const t = convexTest(schema, modules);
    const alice = as(t, "alice");
    const bob = as(t, "bob");
    const claim = {
      requestId: "11111111-1111-1111-1111-111111111111",
      fingerprint: "same-input",
      conversationKey: "conversation",
    };

    expect(await alice.mutation(api.pages.claimGeneration, claim)).toEqual({
      state: "claimed",
      leaseGeneration: 1,
    });
    expect(await alice.mutation(api.pages.claimGeneration, claim)).toMatchObject({
      state: "running",
    });
    expect(await bob.mutation(api.pages.claimGeneration, claim)).toEqual({
      state: "claimed",
      leaseGeneration: 1,
    });
    expect(
      await alice.mutation(api.pages.claimGeneration, { ...claim, fingerprint: "different-input" }),
    ).toEqual({ state: "conflict" });

    const complete = {
      requestId: claim.requestId,
      leaseGeneration: 1,
      prompt: "Plan tomorrow",
      title: "Tomorrow",
      blocks,
    };
    const pageId = await alice.mutation(api.pages.completeGeneration, complete);
    expect(await alice.mutation(api.pages.completeGeneration, complete)).toBe(pageId);
    expect(
      await alice.query(api.conversations.history, {
        conversationKey: claim.conversationKey,
        cursor: null,
        limit: 50,
      }),
    ).toMatchObject({ pages: [{ prompt: "Plan tomorrow", title: "Tomorrow" }], nextCursor: null });
    expect(
      await alice.mutation(api.pages.claimGeneration, { ...claim, retry: true }),
    ).toMatchObject({ state: "replay", status: "completed", blocks, persisted: true });

    await alice.mutation(api.conversations.purge, { conversationKey: claim.conversationKey });
    expect(await alice.mutation(api.pages.claimGeneration, claim)).toEqual({ state: "deleted" });
    expect(await alice.mutation(api.pages.completeGeneration, complete)).toBeNull();
    expect(await bob.mutation(api.pages.claimGeneration, claim)).toMatchObject({
      state: "running",
    });
  });
});
