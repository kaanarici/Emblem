import { constantTimeEqual, hmacHex } from "./signing";
import { z } from "zod";

export const RATE_LIMIT_LEASE_MS = 1_000;
const RATE_LIMIT_GRANT_MS = 10_000;
export const RATE_LIMIT_BATCH = 8;

export type RateLimit = { capacity: number; refillPerHour: number };
export type RateBudget = RateLimit & { key: string };

const digest = z.string().regex(/^[0-9a-f]{64}$/);
const grantSchema = z.strictObject({
  nonce: z.uuid(),
  owner: digest,
  expiresAt: z.number().int().positive(),
  batch: z.number().int().min(1).max(RATE_LIMIT_BATCH),
  budgets: z
    .array(
      z.strictObject({
        key: digest,
        capacity: z.number().int().min(1).max(1_000_000),
        refillPerHour: z.number().min(0).max(1_000_000),
      }),
    )
    .min(1)
    .max(2),
});

export async function signRateLimitGrant(
  secret: string,
  owner: string | null,
  budgets: readonly RateBudget[],
  batch: number,
): Promise<{ payload: string; signature: string }> {
  const claims = grantSchema.parse({
    nonce: crypto.randomUUID(),
    owner: await hmacHex(secret, `rate-limit-owner-v1\0${owner ?? "guest"}`),
    expiresAt: Date.now() + RATE_LIMIT_GRANT_MS,
    batch,
    budgets: await Promise.all(
      budgets.map(async ({ key, ...limit }) => ({
        ...limit,
        key: await hmacHex(
          secret,
          `rate-limit-budget-v1\0${key}\0${limit.capacity}:${limit.refillPerHour}`,
        ),
      })),
    ),
  });
  const payload = JSON.stringify(claims);
  return { payload, signature: await hmacHex(secret, `rate-limit-reservation-v1\0${payload}`) };
}

export async function verifyRateLimitGrant(
  secret: string,
  owner: string | null,
  grant: { payload: string; signature: string },
) {
  if (grant.payload.length > 2_048 || !digest.safeParse(grant.signature).success) return null;
  const expected = await hmacHex(secret, `rate-limit-reservation-v1\0${grant.payload}`);
  if (!constantTimeEqual(expected, grant.signature)) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(grant.payload);
  } catch {
    return null;
  }
  const result = grantSchema.safeParse(parsed);
  if (!result.success) return null;
  const claims = result.data;
  const now = Date.now();
  if (claims.expiresAt <= now || claims.expiresAt > now + RATE_LIMIT_GRANT_MS + 5_000) return null;
  const expectedOwner = await hmacHex(secret, `rate-limit-owner-v1\0${owner ?? "guest"}`);
  if (!constantTimeEqual(expectedOwner, claims.owner)) return null;
  if (new Set(claims.budgets.map(({ key }) => key)).size !== claims.budgets.length) return null;
  return claims;
}
