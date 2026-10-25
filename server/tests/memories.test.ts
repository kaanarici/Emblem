import { convexTest } from "convex-test";
import { describe, expect, it } from "vitest";
import { api } from "../convex/_generated/api";
import schema from "../convex/schema";

const modules = import.meta.glob("../convex/**/*.ts");

function identity(subject: string) {
  return {
    subject,
    issuer: "https://clerk.example",
    tokenIdentifier: `https://clerk.example|${subject}`,
  };
}

function remember(t: ReturnType<typeof convexTest>, subject: string, text: string) {
  return t.run(async (ctx) => {
    await ctx.db.insert("memories", {
      ownerKey: identity(subject).tokenIdentifier,
      text,
      createdAt: Date.now(),
    });
  });
}

function claim(requestId: string, conversationKey: string) {
  return {
    requestId,
    fingerprint: `${requestId}-input`,
    conversationKey,
  };
}

describe("generation memory action receipts", () => {
  it("applies every distinct save and forget in one request and replays each without a second effect", async () => {
    const t = convexTest(schema, modules);
    const alice = t.withIdentity(identity("alice"));
    const saveClaim = claim("11111111-1111-4111-8111-111111111111", "save");
    await alice.mutation(api.pages.claimGeneration, saveClaim);
    const save = (text: string) =>
      alice.mutation(api.memories.applyGenerationAction, {
        requestId: saveClaim.requestId,
        leaseGeneration: 1,
        action: { kind: "save", text },
      });

    const firstSave = await save("User has a dog named Rex");
    expect(await save("User's wife is Sara")).toEqual({
      kind: "save",
      saved: "User's wife is Sara",
    });
    expect(await save("User has a dog named Rex")).toEqual(firstSave);
    expect((await alice.query(api.memories.list, {})).sort()).toEqual([
      "User has a dog named Rex",
      "User's wife is Sara",
    ]);

    await remember(t, "alice", "User prefers alpine train travel by day");
    await remember(t, "alice", "User prefers alpine train travel by night");
    const forgetClaim = claim("22222222-2222-4222-8222-222222222222", "forget");
    await alice.mutation(api.pages.claimGeneration, forgetClaim);
    const forget = (text: string) =>
      alice.mutation(api.memories.applyGenerationAction, {
        requestId: forgetClaim.requestId,
        leaseGeneration: 1,
        action: { kind: "forget", text },
      });
    const firstForget = await forget("Forget alpine train travel");
    expect(await forget("Forget alpine train travel")).toEqual(firstForget);
    expect(
      (await alice.query(api.memories.list, {})).filter((text) =>
        text.includes("alpine train travel"),
      ),
    ).toHaveLength(1);
    expect(await forget("Forget alpine train travel by day")).toMatchObject({
      kind: "forget",
      forgotten: expect.stringContaining("alpine train travel"),
    });
    expect(
      (await alice.query(api.memories.list, {})).filter((text) =>
        text.includes("alpine train travel"),
      ),
    ).toEqual([]);
  });

  it("rejects a stale lease after retry and replays the receipt to the winner", async () => {
    const t = convexTest(schema, modules);
    const alice = t.withIdentity(identity("alice"));
    await remember(t, "alice", "User prefers quiet train journeys");
    const generation = claim("33333333-3333-4333-8333-333333333333", "retry");
    await alice.mutation(api.pages.claimGeneration, generation);
    await alice.mutation(api.memories.applyGenerationAction, {
      requestId: generation.requestId,
      leaseGeneration: 1,
      action: { kind: "save", text: "User prefers window seats" },
    });
    await alice.mutation(api.pages.finishGeneration, {
      requestId: generation.requestId,
      leaseGeneration: 1,
      status: "failed",
      failure: JSON.stringify({ retryable: true }),
    });
    await expect(
      alice.mutation(api.pages.claimGeneration, {
        ...generation,
        retry: true,
      }),
    ).resolves.toEqual({ state: "claimed", leaseGeneration: 2 });

    await expect(
      alice.mutation(api.memories.applyGenerationAction, {
        requestId: generation.requestId,
        leaseGeneration: 1,
        action: { kind: "forget", text: "Forget quiet train journeys" },
      }),
    ).rejects.toThrow("generation memory action rejected");
    await expect(
      alice.mutation(api.memories.applyGenerationAction, {
        requestId: generation.requestId,
        leaseGeneration: 2,
        action: { kind: "save", text: "User prefers window seats" },
      }),
    ).resolves.toEqual({
      kind: "save",
      saved: "User prefers window seats",
    });
    expect(await alice.query(api.memories.list, {})).toEqual(
      expect.arrayContaining(["User prefers quiet train journeys", "User prefers window seats"]),
    );
  });

  it("scopes claims, receipts, and effects to the authenticated owner", async () => {
    const t = convexTest(schema, modules);
    const alice = t.withIdentity(identity("alice"));
    const bob = t.withIdentity(identity("bob"));
    const generation = claim("44444444-4444-4444-8444-444444444444", "shared");
    await alice.mutation(api.pages.claimGeneration, generation);

    await expect(
      bob.mutation(api.memories.applyGenerationAction, {
        requestId: generation.requestId,
        leaseGeneration: 1,
        action: { kind: "save", text: "User is Bob" },
      }),
    ).rejects.toThrow("generation memory action rejected");
    expect(await bob.query(api.memories.list, {})).toEqual([]);

    await alice.mutation(api.memories.applyGenerationAction, {
      requestId: generation.requestId,
      leaseGeneration: 1,
      action: { kind: "save", text: "User is Alice" },
    });
    await expect(bob.mutation(api.pages.claimGeneration, generation)).resolves.toEqual({
      state: "claimed",
      leaseGeneration: 1,
    });
    await bob.mutation(api.memories.applyGenerationAction, {
      requestId: generation.requestId,
      leaseGeneration: 1,
      action: { kind: "save", text: "User is Bob" },
    });

    expect(await alice.query(api.memories.list, {})).toEqual(["User is Alice"]);
    expect(await bob.query(api.memories.list, {})).toEqual(["User is Bob"]);
  });
});
