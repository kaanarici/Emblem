import rateLimiterTest from "@convex-dev/rate-limiter/test";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../convex/_generated/api";
import { fenceOwnerWrites } from "../convex/ownership";
import schema from "../convex/schema";
import type { RequestAuth } from "../lib/auth";
import { imageGenerationAdmission } from "../lib/meteredAccess";
import { createRateLimitGate } from "../lib/rateLimit";
import { signRateLimitGrant, type RateBudget } from "../lib/rateLimitGrant";

const modules = import.meta.glob("../convex/**/*.ts");
const SECRET = "local-test-rate-limit-signing-secret-only";
const identity = (name: string) => ({
  subject: name,
  issuer: "https://limiter.test",
  tokenIdentifier: `https://limiter.test|${name}`,
});
function setup() {
  const t = convexTest(schema, modules);
  rateLimiterTest.register(t);
  return t;
}
const budget = (key: string, capacity: number, refillPerHour = 0) => ({
  key,
  capacity,
  refillPerHour,
});

beforeEach(() => {
  vi.stubEnv("RATE_LIMIT_SECRET", SECRET);
});
afterEach(() => {
  vi.unstubAllEnvs();
  vi.useRealTimers();
});

describe("durable server-authorized admission", () => {
  it("rejects forged, tampered, expired and cross-owner grants without consuming victim credits", async () => {
    const t = setup();
    const alice = t.withIdentity(identity("alice"));
    const bob = t.withIdentity(identity("bob"));
    const grant = await signRateLimitGrant(
      SECRET,
      identity("alice").tokenIdentifier,
      [budget("alice", 1)],
      1,
    );
    for (const caller of [t, bob])
      await expect(caller.mutation(api.rateLimits.reserve, grant)).rejects.toThrow(
        "invalid rate limit grant",
      );
    await expect(
      alice.mutation(api.rateLimits.reserve, { ...grant, signature: "0".repeat(64) }),
    ).rejects.toThrow("invalid rate limit grant");
    await expect(
      alice.mutation(api.rateLimits.reserve, {
        ...grant,
        payload: grant.payload.replace('"batch":1', '"batch":8'),
      }),
    ).rejects.toThrow("invalid rate limit grant");
    expect(await alice.mutation(api.rateLimits.reserve, grant)).toEqual({
      count: 1,
      leaseMs: 1000,
    });
    const expired = await signRateLimitGrant(SECRET, null, [budget("expired", 1)], 1);
    vi.useFakeTimers();
    vi.advanceTimersByTime(10_001);
    await expect(t.mutation(api.rateLimits.reserve, expired)).rejects.toThrow(
      "invalid rate limit grant",
    );
    expect(await t.run((ctx) => ctx.db.query("rateLimitReservations").collect())).toHaveLength(1);
    expect(grant.payload).not.toContain(identity("alice").tokenIdentifier);
    expect(grant.payload).not.toContain(SECRET);
  });

  it("keeps debits across new gate instances and makes grant retries idempotent", async () => {
    const t = setup();
    const budgets = [budget("generation:ip:192.0.2.1", 2)];
    const grant = await signRateLimitGrant(SECRET, null, budgets, 1);
    expect((await t.mutation(api.rateLimits.reserve, grant)).count).toBe(1);
    expect((await t.mutation(api.rateLimits.reserve, grant)).count).toBe(1);
    const reserve = async (limits: readonly RateBudget[]) =>
      t.mutation(api.rateLimits.reserve, await signRateLimitGrant(SECRET, null, limits, 1));
    expect(
      await createRateLimitGate(reserve).allow(budgets, { convex: null, ownerKey: null }),
    ).toBe(true);
    expect(
      await createRateLimitGate(reserve).allow(budgets, { convex: null, ownerKey: null }),
    ).toBe(false);
    vi.useFakeTimers();
    vi.advanceTimersByTime(1001);
    expect((await t.mutation(api.rateLimits.reserve, grant)).count).toBe(0);
  });

  it("atomically shares the guest cap without charging another address on refusal", async () => {
    const t = setup();
    const reserve = async (ip: string, shared: string, capacity: number) =>
      t.mutation(
        api.rateLimits.reserve,
        await signRateLimitGrant(SECRET, null, [budget(ip, 2), budget(shared, capacity)], 1),
      );
    expect((await reserve("address-a", "guest-hint", 1)).count).toBe(1);
    expect((await reserve("address-b", "guest-hint", 1)).count).toBe(0);
    expect((await reserve("address-b", "guest-tools", 3)).count).toBe(1);
    expect((await reserve("address-b", "guest-tools", 3)).count).toBe(1);
    expect((await reserve("address-b", "guest-tools", 3)).count).toBe(0);
  });

  it("precharges image batches across servers and falls back to one when fewer than eight remain", async () => {
    const t = setup();
    const limits = [budget("image:guest", 10)];
    const reserve = vi.fn(
      async (budgets: readonly RateBudget[], _context: unknown, batch: number) =>
        t.mutation(api.rateLimits.reserve, await signRateLimitGrant(SECRET, null, budgets, batch)),
    );
    const first = createRateLimitGate(reserve);
    const second = createRateLimitGate(reserve);
    const context = { convex: null, ownerKey: null };
    expect(await first.allow(limits, context, 8)).toBe(true);
    expect(await second.allow(limits, context, 8)).toBe(true);
    expect(await second.allow(limits, context, 8)).toBe(true);
    expect(await second.allow(limits, context, 8)).toBe(false);
    for (let i = 0; i < 7; i++) expect(await first.allow(limits, context, 8)).toBe(true);
    expect(await first.allow(limits, context, 8)).toBe(false);
    expect(reserve).toHaveBeenCalledTimes(5);
  });

  it("admits the request a slow reservation was charged for, without reusing the expired batch", async () => {
    let now = 0;
    const reserve = vi.fn(async () => {
      now += 1_500;
      return { count: 8, leaseMs: 1_000 };
    });
    const gate = createRateLimitGate(reserve, () => now);
    const context = { convex: null, ownerKey: null };
    expect(await gate.allow([budget("image:guest", 10)], context, 8)).toBe(true);
    expect(await gate.allow([budget("image:guest", 10)], context, 8)).toBe(true);
    expect(reserve).toHaveBeenCalledTimes(2);
  });

  it("keeps owners and endpoints independent and refills only from the shared clock", async () => {
    vi.useFakeTimers();
    const t = setup();
    const reserve = async (owner: string | null, key: string, capacity: number, rate: number) => {
      const client = owner ? t.withIdentity(identity(owner)) : t;
      return client.mutation(
        api.rateLimits.reserve,
        await signRateLimitGrant(
          SECRET,
          owner ? identity(owner).tokenIdentifier : null,
          [budget(key, capacity, rate)],
          1,
        ),
      );
    };
    for (let i = 0; i < 8; i++) expect((await reserve(null, "generate:guest", 8, 4)).count).toBe(1);
    expect((await reserve(null, "generate:guest", 8, 4)).count).toBe(0);
    vi.advanceTimersByTime(120_000);
    expect((await reserve(null, "tools:guest", 60, 60)).count).toBe(1);
    expect((await reserve(null, "generate:guest", 8, 4)).count).toBe(0);
    vi.advanceTimersByTime(780_001);
    expect((await reserve(null, "generate:guest", 8, 4)).count).toBe(1);
    expect((await reserve("alice", "generate:alice", 1, 0)).count).toBe(1);
    expect((await reserve("alice", "generate:alice", 1, 0)).count).toBe(0);
    expect((await reserve("bob", "generate:bob", 1, 0)).count).toBe(1);
  });

  it("does not create durable receipts for repeated denials", async () => {
    const t = setup();
    const budgets = [budget("exhausted", 1)];
    const reserve = async () =>
      t.mutation(api.rateLimits.reserve, await signRateLimitGrant(SECRET, null, budgets, 1));
    expect((await reserve()).count).toBe(1);
    for (let i = 0; i < 25; i++) expect((await reserve()).count).toBe(0);
    expect(await t.run((ctx) => ctx.db.query("rateLimitReservations").collect())).toHaveLength(1);
  });

  it("refuses erased owners and missing server configuration, and bounds receipt cleanup", async () => {
    const t = setup();
    await t.run((ctx) => fenceOwnerWrites(ctx, identity("alice").tokenIdentifier));
    const grant = await signRateLimitGrant(
      SECRET,
      identity("alice").tokenIdentifier,
      [budget("alice", 1)],
      1,
    );
    await expect(
      t.withIdentity(identity("alice")).mutation(api.rateLimits.reserve, grant),
    ).rejects.toThrow("account erased");
    vi.stubEnv("RATE_LIMIT_SECRET", "");
    await expect(t.mutation(api.rateLimits.reserve, grant)).rejects.toThrow(
      "rate limit service unavailable",
    );
    await t.run(async (ctx) => {
      for (let i = 0; i < 101; i++)
        await ctx.db.insert("rateLimitReservations", {
          nonce: `expired-${i}`,
          signature: "opaque",
          count: 1,
          expiresAt: Date.now() - 31_000,
        });
      await ctx.db.insert("rateLimitReservations", {
        nonce: "live",
        signature: "opaque",
        count: 1,
        expiresAt: Date.now() + 1000,
      });
    });
    vi.useFakeTimers();
    expect(await t.mutation(internal.rateLimits.purgeExpiredReservations, {})).toBe(100);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(
      (await t.run((ctx) => ctx.db.query("rateLimitReservations").collect())).map(
        (row) => row.nonce,
      ),
    ).toEqual(["live"]);
  });

  it("attempts each image once an hour across servers and stops paid images at the daily ceiling", async () => {
    const t = setup();
    const convex = {
      mutation: (
        reference: typeof api.rateLimits.reserve,
        grant: { payload: string; signature: string },
      ) => t.mutation(reference, grant),
    } as unknown as RequestAuth["convex"];
    const admit = imageGenerationAdmission({ convex, ownerKey: null });
    vi.stubEnv("IMAGE_GENERATIONS_PER_DAY", "3");
    expect(await admit("a".repeat(64))).toBe(true);
    expect(await admit("a".repeat(64))).toBe(false);
    expect(await admit("b".repeat(64))).toBe(true);
    expect(await admit("c".repeat(64))).toBe(true);
    expect(await admit("d".repeat(64))).toBe(false);
    vi.stubEnv("IMAGE_GENERATIONS_PER_DAY", "0");
    expect(await admit("e".repeat(64))).toBe(false);
  });
});
