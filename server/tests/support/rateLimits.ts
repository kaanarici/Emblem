import rateLimiterTest from "@convex-dev/rate-limiter/test";
import { convexTest } from "convex-test";
import { beforeEach, vi } from "vitest";
import { api } from "../../convex/_generated/api";
import schema from "../../convex/schema";
import { signRateLimitGrant } from "../../lib/rateLimitGrant";

const modules = import.meta.glob("../../convex/**/*.ts");
const SECRET = "route-fixture-rate-limit-secret-only";

export function rateLimitFixture(actual: typeof import("../../lib/rateLimit")) {
  const setup = () => {
    const t = convexTest(schema, modules);
    rateLimiterTest.register(t);
    return actual.createRateLimitGate(
      async (budgets, context, batch) => {
        const caller = context.ownerKey ? t.withIdentity({ tokenIdentifier: context.ownerKey }) : t;
        return caller.mutation(
          api.rateLimits.reserve,
          await signRateLimitGrant(SECRET, context.ownerKey, budgets, batch),
        );
      },
      () => 0,
    );
  };
  let gate = setup();
  beforeEach(() => {
    vi.stubEnv("RATE_LIMIT_SECRET", SECRET);
    gate = setup();
  });
  return {
    ...actual,
    allowRequests: (...args: Parameters<typeof actual.allowRequests>) => gate.allow(...args),
  };
}
