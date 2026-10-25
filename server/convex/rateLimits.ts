import { HOUR, RateLimiter } from "@convex-dev/rate-limiter";
import { v } from "convex/values";
import { RATE_LIMIT_LEASE_MS, verifyRateLimitGrant } from "../lib/rateLimitGrant";
import { components, internal } from "./_generated/api";
import { internalMutation, mutation } from "./_generated/server";
import { ownerKey } from "./ownership";

const limiter = new RateLimiter(components.rateLimiter);
const RECEIPT_RETENTION_MS = 30_000;
const receipt = v.object({ count: v.number(), leaseMs: v.number() });

export const reserve = mutation({
  args: { payload: v.string(), signature: v.string() },
  returns: receipt,
  handler: async (ctx, args) => {
    const secret = process.env.RATE_LIMIT_SECRET?.trim();
    if (!secret || secret.length < 32) throw new Error("rate limit service unavailable");
    const owner = await ownerKey(ctx);
    const claims = await verifyRateLimitGrant(secret, owner, args);
    if (!claims) throw new Error("invalid rate limit grant");
    const existing = await ctx.db
      .query("rateLimitReservations")
      .withIndex("by_nonce", (q) => q.eq("nonce", claims.nonce))
      .unique();
    if (existing) {
      if (existing.signature !== args.signature) throw new Error("rate limit grant conflict");
      return {
        count: existing.expiresAt > Date.now() ? existing.count : 0,
        leaseMs: Math.max(0, existing.expiresAt - Date.now()),
      };
    }
    const options = (budget: (typeof claims.budgets)[number], count: number) => ({
      key: budget.key,
      count,
      config: {
        kind: "token bucket" as const,
        capacity: budget.capacity,
        rate: budget.refillPerHour,
        period: HOUR,
      },
    });
    let count = Math.min(claims.batch, ...claims.budgets.map((budget) => budget.capacity));
    for (const attempt of new Set([count, 1])) {
      const allowed = await Promise.all(
        claims.budgets.map((budget) => limiter.check(ctx, "http", options(budget, attempt))),
      );
      if (allowed.every(({ ok }) => ok)) {
        count = attempt;
        break;
      }
      count = 0;
    }
    if (count > 0) {
      for (const budget of claims.budgets) {
        const result = await limiter.limit(ctx, "http", options(budget, count));
        if (!result.ok) throw new Error("rate limit reservation conflict");
      }
    }
    if (count > 0)
      await ctx.db.insert("rateLimitReservations", {
        nonce: claims.nonce,
        signature: args.signature,
        count,
        expiresAt: Date.now() + RATE_LIMIT_LEASE_MS,
      });
    return { count, leaseMs: RATE_LIMIT_LEASE_MS };
  },
});

export const purgeExpiredReservations = internalMutation({
  args: {},
  returns: v.number(),
  handler: async (ctx) => {
    const rows = await ctx.db
      .query("rateLimitReservations")
      .withIndex("by_expiresAt", (q) => q.lt("expiresAt", Date.now() - RECEIPT_RETENTION_MS))
      .take(100);
    for (const row of rows) await ctx.db.delete("rateLimitReservations", row._id);
    if (rows.length === 100)
      await ctx.scheduler.runAfter(0, internal.rateLimits.purgeExpiredReservations, {});
    return rows.length;
  },
});
