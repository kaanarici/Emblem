import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../convex/_generated/api";
import type { MutationCtx } from "../convex/_generated/server";
import schema from "../convex/schema";
import { ownerScopeHash } from "../convex/ownership";
import { claimAutomationRun } from "../convex/automationRuns";
import { insertPage } from "./support/pages";
import { blockSchema } from "../lib/schema";

const modules = import.meta.glob("../convex/**/*.ts");
const identity = (subject: string) => ({
  subject,
  issuer: "https://accounts-test.invalid",
  tokenIdentifier: `https://accounts-test.invalid|${subject}`,
});
const aliceIdentity = identity("alice");
const bobIdentity = identity("bob");

async function seedOwner(ctx: MutationCtx, owner: string) {
  const user = await ctx.db.insert("users", { tokenIdentifier: owner });
  const page = await insertPage(ctx, {
    userTokenIdentifier: owner,
    conversationKey: "shared-key",
    pageKey: "page",
    prompt: "private",
    blocks: "[]",
  });
  const generation = await ctx.db.insert("generationRuns", {
    userTokenIdentifier: owner,
    requestId: "request",
    fingerprint: "input",
    conversationKey: "shared-key",
    status: "completed",
    leaseGeneration: 1,
    leaseExpiresAt: 0,
    tombstoned: false,
    pageId: page,
  });
  const receipt = await ctx.db.insert("generationActions", {
    userTokenIdentifier: owner,
    requestId: "request",
    actionKey: "memory",
    fingerprint: "input",
    result: "saved",
  });
  const memory = await ctx.db.insert("memories", {
    ownerKey: owner,
    text: "private",
    createdAt: 0,
  });
  const profile = await ctx.db.insert("profiles", {
    ownerKey: owner,
    about: "private",
    updatedAt: 0,
  });
  const automation = await ctx.db.insert("automations", {
    userTokenIdentifier: owner,
    title: "private",
    prompt: "private",
    enabled: false,
  });
  const run = await ctx.db.insert("automationRuns", {
    userTokenIdentifier: owner,
    automationId: automation,
    status: "completed",
    startedAt: 0,
  });
  const budget = await ctx.db.insert("automationDispatchBudgets", {
    ownerKey: owner,
    tokens: 1,
    updatedAt: 0,
  });
  return [user, page, generation, receipt, memory, profile, automation, run, budget];
}

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

describe("account erasure", () => {
  it("drains legal large pages under real transaction byte limits while preserving fences and another owner", async () => {
    const t = convexTest({ schema, modules, transactionLimits: true });
    const alice = t.withIdentity(aliceIdentity);
    const blocks = JSON.stringify([
      blockSchema.parse({ type: "text", id: "large", style: "body", body: "x".repeat(400 * 1024) }),
    ]);
    const ids = [];
    for (let batch = 0; batch < 6; batch++) {
      ids.push(
        ...(await t.run(async (ctx) => {
          const batchIds = [];
          for (let i = 0; i < 8; i++)
            batchIds.push(
              await ctx.db.insert("pages", {
                userTokenIdentifier: aliceIdentity.tokenIdentifier,
                conversationKey: "large",
                pageKey: `page-${batch * 8 + i}`,
                prompt: "Legal large page",
                blocks,
              }),
            );
          return batchIds;
        })),
      );
    }
    const fixture = await t.run(async (ctx) => ({
      user: await ctx.db.insert("users", { tokenIdentifier: aliceIdentity.tokenIdentifier }),
      memory: await ctx.db.insert("memories", {
        ownerKey: aliceIdentity.tokenIdentifier,
        text: "Wait for the next table",
        createdAt: 0,
      }),
      other: await ctx.db.insert("pages", {
        userTokenIdentifier: bobIdentity.tokenIdentifier,
        conversationKey: "large",
        pageKey: "page-0",
        prompt: "Another owner",
        blocks,
      }),
    }));
    const measured = await alice.mutation(async (ctx) => {
      const result = await ctx.runMutation(api.accounts.purgeSelf, {});
      const metrics = await ctx.meta.getTransactionMetrics();
      return { result, bytesRead: metrics.bytesRead.used };
    });
    const first = measured.result;
    expect(measured.bytesRead).toBeLessThan(8 * 1024 * 1024);
    expect(first.done).toBe(false);
    expect(first.deleted).toBeGreaterThan(0);
    expect(first.deleted).toBeLessThan(ids.length);
    const remaining = await Promise.all(
      ids.map((id) => t.run(async (ctx) => (await ctx.db.get(id)) !== null)),
    );
    expect(remaining.filter((present) => !present)).toHaveLength(first.deleted);
    expect(await t.run((ctx) => ctx.db.get(fixture.memory))).not.toBeNull();
    expect(await t.run((ctx) => ctx.db.get(fixture.user))).not.toBeNull();
    expect(await alice.query(api.accounts.isErased, {})).toBe(true);
    expect(await alice.query(api.accounts.purgeStatus, {})).toEqual({ done: false });
    await expect(
      alice.mutation(api.profiles.save, { profile: { about: "Late write" } }),
    ).rejects.toThrow("account erased");
    await t.finishAllScheduledFunctions(() => vi.advanceTimersByTime(0));
    expect(await alice.query(api.accounts.purgeStatus, {})).toEqual({ done: true });
    expect(await t.run((ctx) => ctx.db.get(fixture.user))).toBeNull();
    expect(await t.run((ctx) => ctx.db.get(fixture.memory))).toBeNull();
    for (const id of ids) expect(await t.run((ctx) => ctx.db.get(id))).toBeNull();
    expect(await t.run((ctx) => ctx.db.get(fixture.other))).toMatchObject({
      blocks,
      userTokenIdentifier: bobIdentity.tokenIdentifier,
    });
    expect(await alice.mutation(api.accounts.purgeSelf, {})).toEqual({ done: true, deleted: 0 });
  });

  it("drains image blobs in bounded batches and hides remaining images as soon as erasure starts", async () => {
    const t = convexTest(schema, modules);
    const alice = t.withIdentity(aliceIdentity);
    const scope = await ownerScopeHash(aliceIdentity.tokenIdentifier);
    const fixture = await t.run(async (ctx) => {
      const user = await ctx.db.insert("users", { tokenIdentifier: aliceIdentity.tokenIdentifier });
      const blobs = [];
      for (let i = 0; i < 81; i++) {
        const storageId = await ctx.storage.store(new Blob(["synthetic"]));
        blobs.push(storageId);
        await ctx.db.insert("generatedImages", {
          key: i.toString(16).padStart(64, "0"),
          ownerScopeHash: scope,
          storageId,
          mimeType: "image/png",
          byteLength: 9,
          createdAt: 0,
        });
      }
      return { user, blobs };
    });
    expect(await alice.mutation(api.accounts.purgeSelf, {})).toEqual({ done: false, deleted: 80 });
    expect(await alice.query(api.accounts.purgeStatus, {})).toEqual({ done: false });
    await expect(alice.mutation(api.users.ensure, {})).rejects.toThrow("account erased");
    await expect(
      alice.mutation(api.profiles.save, { profile: { about: "late during drain" } }),
    ).rejects.toThrow("account erased");
    await expect(
      alice.mutation(api.pages.claimGeneration, {
        requestId: "during-drain",
        fingerprint: "synthetic",
        conversationKey: "during-drain",
      }),
    ).rejects.toThrow("account erased");
    expect(await t.run((ctx) => ctx.db.get(fixture.user))).not.toBeNull();
    expect(await t.run((ctx) => ctx.db.system.query("_storage").collect())).toHaveLength(1);
    await expect(
      t.query(internal.generatedImages.getInternal, {
        key: "50".padStart(64, "0"),
        ownerScopeHash: scope,
      }),
    ).rejects.toThrow("owner erased");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await alice.query(api.accounts.purgeStatus, {})).toEqual({ done: true });
    expect(await t.run((ctx) => ctx.db.get(fixture.user))).toBeNull();
    expect(await t.run((ctx) => ctx.db.system.query("_storage").collect())).toEqual([]);
  });

  it("rejects guests for both deletion and status", async () => {
    const t = convexTest(schema, modules);
    await expect(t.mutation(api.accounts.beginErasure, {})).rejects.toThrow(
      "authentication required",
    );
    await expect(t.mutation(api.accounts.purgeSelf, {})).rejects.toThrow("authentication required");
    await expect(t.query(api.accounts.purgeStatus, {})).rejects.toThrow("authentication required");
  });

  it("honors existing hash fences without a user row and preserves true guest behavior", async () => {
    const t = convexTest(schema, modules);
    const alice = t.withIdentity(aliceIdentity);
    await t.run(async (ctx) =>
      ctx.db.insert("ownerErasures", {
        ownerScopeHash: await ownerScopeHash(aliceIdentity.tokenIdentifier),
      }),
    );
    await expect(alice.mutation(api.users.ensure, {})).rejects.toThrow("account erased");
    await expect(alice.mutation(api.profiles.save, { profile: { about: "late" } })).rejects.toThrow(
      "account erased",
    );
    await expect(
      alice.mutation(api.pages.claimGeneration, {
        requestId: "legacy-fence",
        fingerprint: "synthetic",
        conversationKey: "legacy-fence",
      }),
    ).rejects.toThrow("account erased");
    expect(await t.mutation(api.users.ensure, {})).toBeNull();
    expect(await t.mutation(api.profiles.save, { profile: { about: "guest" } })).toBeNull();
    await expect(
      t.mutation(api.pages.claimGeneration, {
        requestId: "guest",
        fingerprint: "synthetic",
        conversationKey: "guest",
      }),
    ).rejects.toThrow("authentication required");
    expect(await alice.query(api.accounts.purgeStatus, {})).toEqual({ done: true });
    expect(await alice.mutation(api.accounts.purgeSelf, {})).toEqual({ done: true, deleted: 0 });
  });

  it("erases every private owner table, preserves another owner, and retries safely", async () => {
    const t = convexTest(schema, modules);
    const alice = t.withIdentity(aliceIdentity);
    const bob = t.withIdentity(bobIdentity);
    const fixture = await t.run(async (ctx) => ({
      alice: await seedOwner(ctx, aliceIdentity.tokenIdentifier),
      bob: await seedOwner(ctx, bobIdentity.tokenIdentifier),
      cache: await ctx.db.insert("imageCache", {
        key: "shared",
        url: "https://example.invalid/image",
        source: "shared",
        createdAt: 0,
      }),
    }));
    expect(await alice.query(api.accounts.purgeStatus, {})).toEqual({ done: false });
    let batch = await alice.mutation(api.accounts.purgeSelf, {});
    expect(batch).toEqual({ done: false, deleted: 1 });
    let deleted = batch.deleted;
    for (let i = 0; i < 12 && !batch.done; i++) {
      expect(await t.run((ctx) => ctx.db.get(fixture.alice[0]))).not.toBeNull();
      batch = await alice.mutation(api.accounts.purgeSelf, {});
      deleted += batch.deleted;
    }
    expect(batch.done).toBe(true);
    expect(deleted).toBe(10);
    expect(
      await t.run(async (ctx) => Promise.all(fixture.alice.map((id) => ctx.db.get(id)))),
    ).toEqual(fixture.alice.map(() => null));
    expect(
      await t.run(async (ctx) => Promise.all(fixture.bob.map((id) => ctx.db.get(id)))),
    ).toEqual(fixture.bob.map((id) => expect.objectContaining({ _id: id })));
    expect(await t.run((ctx) => ctx.db.get(fixture.cache))).not.toBeNull();
    expect(await bob.query(api.accounts.purgeStatus, {})).toEqual({ done: false });
    expect(await alice.query(api.accounts.purgeStatus, {})).toEqual({ done: true });
    expect(await alice.mutation(api.accounts.purgeSelf, {})).toEqual({ done: true, deleted: 0 });
  });

  it("bounds each batch, keeps the user until all tables drain, and continues beyond two batches", async () => {
    const t = convexTest(schema, modules);
    const alice = t.withIdentity(aliceIdentity);
    const fixture = await t.run(async (ctx) => {
      const user = await ctx.db.insert("users", { tokenIdentifier: aliceIdentity.tokenIdentifier });
      for (let i = 0; i < 81; i++) {
        await insertPage(ctx, {
          userTokenIdentifier: aliceIdentity.tokenIdentifier,
          conversationKey: `page-${i}`,
          pageKey: `page-${i}`,
          prompt: "private",
          blocks: "[]",
        });
      }
      for (let i = 0; i < 161; i++) {
        await ctx.db.insert("memories", {
          ownerKey: aliceIdentity.tokenIdentifier,
          text: `private ${i}`,
          createdAt: i,
        });
      }
      return user;
    });
    expect(await alice.mutation(api.accounts.purgeSelf, {})).toEqual({ done: false, deleted: 80 });
    expect(await t.run((ctx) => ctx.db.get(fixture))).not.toBeNull();
    const remaining = await t.run(
      async (ctx) =>
        (await ctx.db.query("pages").take(300)).length +
        (await ctx.db.query("memories").take(300)).length,
    );
    expect(remaining).toBe(162);
    expect(await alice.query(api.accounts.purgeStatus, {})).toEqual({ done: false });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await alice.query(api.accounts.purgeStatus, {})).toEqual({ done: true });
    expect(await t.run((ctx) => ctx.db.get(fixture))).toBeNull();
    expect(await t.run((ctx) => ctx.db.query("memories").take(1))).toEqual([]);
    expect(await t.run((ctx) => ctx.db.query("conversationSummaries").take(1))).toEqual([]);
    expect(await alice.mutation(api.accounts.purgeSelf, {})).toEqual({ done: true, deleted: 0 });
  });

  it("fences deleted interactive and background run callbacks", async () => {
    const t = convexTest(schema, modules);
    const alice = t.withIdentity(aliceIdentity);
    const claim = await alice.mutation(api.pages.claimGeneration, {
      requestId: "late",
      fingerprint: "late",
      conversationKey: "late",
    });
    expect(claim.state).toBe("claimed");
    if (claim.state !== "claimed") throw new Error("claim required");
    const { id } = await alice.mutation(api.automations.create, {
      prompt: "Synthetic only",
      schedule: { hour: 9, minute: 0, timezone: "UTC" },
      sources: [],
    });
    const { runId } = await alice.mutation(api.automations.dispatch, {
      id,
      requestId: "late-background",
    });
    const started = await t.mutation(internal.automations.startRun, { runId });
    expect(started).not.toBeNull();
    expect(await alice.mutation(api.accounts.purgeSelf, {})).toMatchObject({ done: false });
    await expect(
      alice.mutation(api.pages.completeGeneration, {
        requestId: "late",
        leaseGeneration: claim.leaseGeneration,
        prompt: "late",
        blocks: "[]",
      }),
    ).rejects.toThrow("account erased");
    await expect(
      alice.mutation(api.pages.finishGeneration, {
        requestId: "late",
        leaseGeneration: claim.leaseGeneration,
        status: "cancelled",
      }),
    ).rejects.toThrow("account erased");
    expect(await t.mutation(internal.automations.startRun, { runId })).toBeNull();
    await t.mutation(internal.automationDispatch.completeRun, {
      runId,
      leaseGeneration: started!.leaseGeneration,
      blocks: "[]",
    });
    await t.mutation(internal.automationDispatch.failRun, {
      runId,
      leaseGeneration: started!.leaseGeneration,
      message: "late",
    });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await alice.query(api.accounts.purgeStatus, {})).toEqual({ done: true });
    expect(await t.run((ctx) => ctx.db.query("pages").take(1))).toEqual([]);
    expect(await t.run((ctx) => ctx.db.get(runId))).toBeNull();
  });

  it("fences every public creation path before drain and after completion while another owner can write", async () => {
    const t = convexTest(schema, modules);
    const alice = t.withIdentity({
      ...aliceIdentity,
      name: "Private name",
      email: "alice@example.invalid",
    });
    const bob = t.withIdentity(bobIdentity);
    const writes = (client: typeof alice) => [
      () => client.mutation(api.users.ensure, {}),
      () => client.mutation(api.profiles.save, { profile: { about: "Late private profile" } }),
      () =>
        client.mutation(api.pages.claimGeneration, {
          requestId: "fresh",
          conversationKey: "fresh",
          fingerprint: "fresh",
          retry: true,
        }),
      () =>
        client.mutation(api.pages.cancelGeneration, {
          requestId: "preclaim",
          conversationKey: "preclaim",
        }),
      () =>
        client.mutation(api.automations.create, {
          prompt: "Synthetic only",
          schedule: { hour: 9, minute: 0, timezone: "UTC" },
          sources: [],
        }),
      () => client.mutation(api.automations.syncDailyBrief, {}),
    ];
    await alice.mutation(api.users.ensure, {});
    await alice.mutation(api.profiles.save, { profile: { about: "Original private profile" } });
    const before = await t.run(async (ctx) => ({
      users: await ctx.db.query("users").collect(),
      profiles: await ctx.db.query("profiles").collect(),
    }));
    const delayedWrites = writes(alice);
    expect(await alice.mutation(api.accounts.beginErasure, {})).toBeNull();
    expect(await alice.mutation(api.accounts.beginErasure, {})).toBeNull();
    for (const write of delayedWrites) await expect(write()).rejects.toThrow("account erased");
    expect(
      await t.run(async (ctx) => ({
        users: await ctx.db.query("users").collect(),
        profiles: await ctx.db.query("profiles").collect(),
      })),
    ).toEqual(before);
    expect(await alice.query(api.accounts.purgeStatus, {})).toEqual({ done: false });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await alice.query(api.accounts.purgeStatus, {})).toEqual({ done: true });
    for (const write of delayedWrites) await expect(write()).rejects.toThrow("account erased");
    for (const write of writes(bob)) await write();
    expect(await alice.query(api.accounts.purgeStatus, {})).toEqual({ done: true });
    expect(await alice.mutation(api.accounts.purgeSelf, {})).toEqual({ done: true, deleted: 0 });
    expect(await bob.query(api.accounts.purgeStatus, {})).toEqual({ done: false });
    const fences = await t.run((ctx) => ctx.db.query("ownerErasures").collect());
    expect(fences).toHaveLength(1);
    expect(fences[0]).toEqual({
      _id: expect.any(String),
      _creationTime: expect.any(Number),
      ownerScopeHash: await ownerScopeHash(aliceIdentity.tokenIdentifier),
    });
    await bob.mutation(api.accounts.purgeSelf, {});
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  it("blocks background claims, starts and completions as soon as erasure starts", async () => {
    const t = convexTest(schema, modules);
    const alice = t.withIdentity(aliceIdentity);
    const { id } = await alice.mutation(api.automations.create, {
      prompt: "Synthetic",
      schedule: { hour: 9, minute: 0, timezone: "UTC" },
      sources: [],
    });
    const { runId } = await alice.mutation(api.automations.dispatch, { id, requestId: "started" });
    const started = await t.mutation(internal.automations.startRun, { runId });
    expect(started).not.toBeNull();
    const before = await t.run((ctx) => ctx.db.get(runId));
    await alice.mutation(api.accounts.beginErasure, {});
    await t.mutation(internal.automationDispatch.completeRun, {
      runId,
      leaseGeneration: started!.leaseGeneration,
      blocks: "private late result",
    });
    await t.mutation(internal.automationDispatch.failRun, {
      runId,
      leaseGeneration: started!.leaseGeneration,
      message: "private late failure",
    });
    expect(await t.run((ctx) => ctx.db.get(runId))).toEqual(before);
    expect(
      await t.run(async (ctx) =>
        claimAutomationRun(ctx, (await ctx.db.get(id))!, {
          trigger: "schedule",
          occurrenceKey: "late-scheduled",
          throwIfBusy: false,
        }),
      ),
    ).toBeNull();
    await t.run((ctx) => ctx.db.patch(runId, { status: "queued" }));
    expect(await t.mutation(internal.automations.startRun, { runId })).toBeNull();
    await alice.mutation(api.accounts.purgeSelf, {});
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await alice.query(api.accounts.purgeStatus, {})).toEqual({ done: true });
  });
});
