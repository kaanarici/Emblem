import { jsonResponse } from "@/lib/http";
import { logEvent } from "./log";
import { ConvexHttpClient } from "convex/browser";
import { verifyToken } from "@clerk/backend";

const CONVEX_AUDIENCE = "convex";

const loggedMissingConfig = new Set<string>();

const verifiedTokens = new Map<
  string,
  { ownerKey: string; verifiedAt: number; expiresAt: number }
>();
let verificationKey: string | undefined;
const VERIFICATION_CACHE_MS = 1_000;
const VERIFICATION_CACHE_SIZE = 1024;

type AuthStatus = "authenticated" | "guest" | "invalid" | "unavailable";

export type RequestAuth = {
  convex: ConvexHttpClient | null;
  authenticated: boolean;
  ownerKey: string | null;
  status: AuthStatus;
};

function bearer(req: Request): { present: boolean; token: string | null } {
  const header = req.headers.get("authorization");
  if (header === null) return { present: false, token: null };
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  return { present: true, token: match ? match[1].trim() : null };
}

export async function requestAuth(req: Request): Promise<RequestAuth> {
  const url = process.env.NEXT_PUBLIC_CONVEX_URL;
  if (!url) {
    logMissingConfig("auth: NEXT_PUBLIC_CONVEX_URL is not configured");
    return {
      convex: null,
      authenticated: false,
      ownerKey: null,
      status: "unavailable",
    };
  }

  const convex = new ConvexHttpClient(url, {
    logger: false,
    fetch: (input, init) => {
      const existing = init?.signal ?? (input instanceof Request ? input.signal : null);
      const deadline = AbortSignal.timeout(15_000);
      return fetch(input, {
        ...init,
        signal: existing ? AbortSignal.any([existing, deadline]) : deadline,
      });
    },
  });
  const authorization = bearer(req);
  if (!authorization.present) {
    return { convex, authenticated: false, ownerKey: null, status: "guest" };
  }
  if (!authorization.token) {
    return { convex, authenticated: false, ownerKey: null, status: "invalid" };
  }

  const jwtKey = process.env.CLERK_JWT_KEY?.replace(/\\n/g, "\n").trim();
  const secretKey = process.env.CLERK_SECRET_KEY;
  if (!jwtKey && !secretKey) {
    logMissingConfig("auth: Clerk verification key is not configured");
    return {
      convex: null,
      authenticated: false,
      ownerKey: null,
      status: "unavailable",
    };
  }
  if (verificationKey !== undefined && verificationKey !== jwtKey) {
    verifiedTokens.clear();
    return { convex: null, authenticated: false, ownerKey: null, status: "unavailable" };
  }
  verificationKey = jwtKey;
  const now = Date.now();
  const cached = jwtKey ? verifiedTokens.get(authorization.token) : undefined;
  if (cached && now >= cached.verifiedAt && now < cached.expiresAt) {
    convex.setAuth(authorization.token);
    return { convex, authenticated: true, ownerKey: cached.ownerKey, status: "authenticated" };
  }
  verifiedTokens.delete(authorization.token);
  try {
    const claims = await verifyToken(authorization.token, {
      ...(jwtKey ? { jwtKey } : { secretKey }),
      audience: CONVEX_AUDIENCE,
    });
    const hasConvexAudience =
      claims.aud === CONVEX_AUDIENCE ||
      (Array.isArray(claims.aud) &&
        claims.aud.every((audience) => typeof audience === "string") &&
        claims.aud.includes(CONVEX_AUDIENCE));
    const ownerKey =
      hasConvexAudience &&
      typeof claims.iss === "string" &&
      claims.iss.length > 0 &&
      typeof claims.sub === "string" &&
      claims.sub.length > 0
        ? `${claims.iss}|${claims.sub}`
        : null;
    if (!ownerKey) {
      return { convex, authenticated: false, ownerKey: null, status: "invalid" };
    }
    const verifiedAt = Date.now();
    if (
      jwtKey &&
      typeof claims.exp === "number" &&
      Number.isFinite(claims.exp) &&
      typeof claims.iat === "number" &&
      Number.isFinite(claims.iat) &&
      (claims.nbf === undefined ||
        (typeof claims.nbf === "number" && Number.isFinite(claims.nbf))) &&
      claims.iat * 1_000 <= verifiedAt &&
      (claims.nbf ?? 0) * 1_000 <= verifiedAt &&
      claims.exp * 1_000 > verifiedAt
    ) {
      if (verifiedTokens.size >= VERIFICATION_CACHE_SIZE) {
        verifiedTokens.delete(verifiedTokens.keys().next().value!);
      }
      verifiedTokens.set(authorization.token, {
        ownerKey,
        verifiedAt,
        expiresAt: Math.min(claims.exp * 1_000, verifiedAt + VERIFICATION_CACHE_MS),
      });
    }
    convex.setAuth(authorization.token);
    return { convex, authenticated: true, ownerKey, status: "authenticated" };
  } catch {
    logEvent("warn", "auth: rejected bearer token");
    return { convex, authenticated: false, ownerKey: null, status: "invalid" };
  }
}

function logMissingConfig(message: string): void {
  if (loggedMissingConfig.has(message)) return;
  loggedMissingConfig.add(message);
  logEvent("error", message);
}

export function authFailure(auth: RequestAuth): Response | null {
  if (auth.status === "invalid") {
    return jsonResponse({ error: "authentication expired or invalid", code: "invalid_auth" }, 401);
  }
  if (auth.status === "unavailable") {
    return jsonResponse(
      { error: "authentication backend unavailable", code: "auth_unavailable" },
      503,
    );
  }
  return null;
}
