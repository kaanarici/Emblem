import { api } from "@/convex/_generated/api";
import type { RequestAuth } from "@/lib/auth";
import { logError } from "@/lib/log";
import {
  RATE_LIMIT_BATCH,
  RATE_LIMIT_LEASE_MS,
  signRateLimitGrant,
  type RateBudget,
} from "@/lib/rateLimitGrant";

type Context = Pick<RequestAuth, "convex" | "ownerKey">;
type Reservation = { count: number; leaseMs: number };
type Reserve = (
  budgets: readonly RateBudget[],
  context: Context,
  batch: number,
) => Promise<Reservation>;

export function createRateLimitGate(reserve: Reserve, clock = () => performance.now()) {
  const leases = new Map<string, { remaining: number; deadline: number }>();
  const pending = new Map<string, Promise<boolean>>();
  let generation = 0;
  return {
    clear() {
      generation += 1;
      leases.clear();
      pending.clear();
    },
    async allow(budgets: readonly RateBudget[], context: Context, batch = 1): Promise<boolean> {
      const key = JSON.stringify([context.ownerKey, budgets]);
      for (;;) {
        const lease = leases.get(key);
        if (lease && lease.deadline > clock() && lease.remaining > 0) {
          lease.remaining -= 1;
          leases.delete(key);
          leases.set(key, lease);
          return true;
        }
        const existing = pending.get(key);
        if (existing) {
          if (!(await existing)) return false;
          continue;
        }
        const started = clock();
        const currentGeneration = generation;
        const refill = reserve(budgets, context, batch)
          .then(({ count, leaseMs }) => {
            if (currentGeneration !== generation) return false;
            if (
              !Number.isInteger(count) ||
              count < 0 ||
              count > Math.min(batch, RATE_LIMIT_BATCH) ||
              !Number.isFinite(leaseMs) ||
              leaseMs < 0 ||
              leaseMs > RATE_LIMIT_LEASE_MS
            )
              throw new Error("invalid rate limit reservation");
            if (count === 0) return false;
            const deadline = started + leaseMs;
            if (count > 1 && deadline > clock()) {
              if (leases.size >= 5_000) {
                const oldest = leases.keys().next().value;
                if (oldest !== undefined) leases.delete(oldest);
              }
              leases.set(key, { remaining: count - 1, deadline });
            }
            return true;
          })
          .catch((error: unknown) => {
            logError("rate limit reservation failed", error);
            return false;
          });
        pending.set(key, refill);
        try {
          return await refill;
        } finally {
          if (pending.get(key) === refill) pending.delete(key);
        }
      }
    },
  };
}

let configuration = "";
const gate = createRateLimitGate(async (budgets, context, batch) => {
  const secret = process.env.RATE_LIMIT_SECRET?.trim();
  if (!context.convex || !secret || secret.length < 32)
    throw new Error("rate limit service unavailable");
  const grant = await signRateLimitGrant(secret, context.ownerKey, budgets, batch);
  return context.convex.mutation(api.rateLimits.reserve, grant);
});

export async function allowRequests(
  budgets: readonly RateBudget[],
  context: Context,
  batch = 1,
): Promise<boolean> {
  const secret = process.env.RATE_LIMIT_SECRET?.trim();
  if (!context.convex || !secret || secret.length < 32) return false;
  const current = `${process.env.NEXT_PUBLIC_CONVEX_URL ?? ""}\0${secret}`;
  if (current !== configuration) {
    gate.clear();
    configuration = current;
  }
  return gate.allow(budgets, context, batch);
}

export function clientKey(req: Request, ownerKey: string | null): string {
  if (ownerKey) return `user:${ownerKey}`;
  return `ip:${req.headers.get("x-real-ip")?.trim() || "unknown"}`;
}
