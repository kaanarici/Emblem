import { authFailure, requestAuth } from "@/lib/auth";
import { admitMetered, METERED_ROUTES } from "@/lib/meteredAccess";
import { JSON_BODY_LIMITS, jsonResponse, readJsonBody } from "@/lib/http";
import { classifySaves, saveClassificationRequestSchema } from "@/lib/saveClassification";

export const maxDuration = 30;
const failure = (code: string, status: number) => jsonResponse({ error: code, code }, status);

export async function POST(req: Request) {
  let auth;
  try {
    auth = await requestAuth(req);
  } catch {
    return failure("auth_unavailable", 503);
  }
  const rejected = authFailure(auth);
  if (rejected) return rejected;
  const guest = auth.status === "guest" && !auth.authenticated && auth.ownerKey === null;
  if (!guest && (auth.status !== "authenticated" || !auth.authenticated || !auth.ownerKey))
    return failure("authentication_required", 401);
  if (!auth.convex) return failure("auth_unavailable", 503);
  const raw = await readJsonBody(req, JSON_BODY_LIMITS.savesClassify);
  if (raw instanceof Response) return raw;
  const parsed = saveClassificationRequestSchema.safeParse(raw);
  if (!parsed.success) return failure("invalid_request", 400);
  if (!(await admitMetered(req, METERED_ROUTES.savesClassify, auth))) {
    return failure("rate_limited", 429);
  }
  try {
    req.signal.throwIfAborted();
    const result = await classifySaves(parsed.data, req.signal);
    return jsonResponse(result);
  } catch {
    return failure("classification_unavailable", 502);
  }
}
