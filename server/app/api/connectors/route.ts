import { logError } from "@/lib/log";
import { jsonResponse, readJsonBody } from "@/lib/http";
import { authFailure, requestAuth } from "@/lib/auth";
import type { RequestAuth } from "@/lib/auth";
import { api } from "@/convex/_generated/api";
import { admitMetered, METERED_ROUTES } from "@/lib/meteredAccess";
import { z } from "zod";
import {
  classifyConnectorFailure,
  connectorsEnabled,
  connectorStates,
  initiateConnection,
  disconnect,
} from "@/lib/connectors";

class AccountErasedError extends Error {}

async function assertActive(auth: RequestAuth) {
  if (!auth.convex) throw new Error("account status unavailable");
  if (await auth.convex.query(api.accounts.isErased, {})) throw new AccountErasedError();
}

function erasedResponse(error: unknown): Response | null {
  return error instanceof AccountErasedError
    ? jsonResponse({ error: "account erased", code: "account_erased" }, 403)
    : null;
}

export async function GET(req: Request) {
  const auth = await requestAuth(req);
  const failure = authFailure(auth);
  if (failure) return failure;
  const { authenticated, ownerKey } = auth;
  if (!authenticated || !ownerKey) {
    return jsonResponse({ error: "sign in required" }, 401);
  }
  if (!connectorsEnabled()) {
    return jsonResponse({ enabled: false, toolkits: [] });
  }
  if (!(await admitMetered(req, METERED_ROUTES.connectorsRead, auth))) {
    return jsonResponse({ error: "too many requests" }, 429);
  }
  try {
    await assertActive(auth);
    const force = new URL(req.url).searchParams.get("refresh") === "1";
    const toolkits = await connectorStates(ownerKey, force, req.signal);
    await assertActive(auth);
    return jsonResponse({ enabled: true, toolkits });
  } catch (error) {
    const erased = erasedResponse(error);
    if (erased) return erased;
    const failure = classifyConnectorFailure(error, true);
    logError("connectors list failed", error, { code: failure.code });
    return jsonResponse({ error: "connectors unavailable", code: failure.code }, 503);
  }
}

const mutation = z.object({
  action: z.enum(["connect", "disconnect"]),
  toolkit: z.string().trim().min(1).max(100),
  account: z.string().trim().min(1).max(200).optional(),
  another: z.boolean().optional(),
});

export async function POST(req: Request) {
  const auth = await requestAuth(req);
  const failure = authFailure(auth);
  if (failure) return failure;
  const { authenticated, ownerKey } = auth;
  if (!authenticated || !ownerKey) {
    return jsonResponse({ error: "sign in required" }, 401);
  }
  if (!connectorsEnabled()) {
    return jsonResponse(
      {
        error: "connectors not configured",
        cleanupStatus: "not_requested",
        providerCompletion: "unverified",
      },
      503,
    );
  }
  if (!(await admitMetered(req, METERED_ROUTES.connectors, auth))) {
    return jsonResponse({ error: "too many requests" }, 429);
  }

  const raw = await readJsonBody(req);
  if (raw instanceof Response) return raw;
  const parsed = mutation.safeParse(raw);
  if (!parsed.success) {
    return jsonResponse({ error: "invalid connector action" }, 400);
  }
  const body = parsed.data;

  try {
    if (body.action === "connect") {
      const result = await initiateConnection(
        ownerKey,
        body.toolkit,
        () => assertActive(auth),
        body.another === true,
      );
      return jsonResponse(
        "alreadyConnected" in result
          ? { ok: true, status: "connected" }
          : { ok: true, redirectUrl: result.redirectUrl },
      );
    }
    await disconnect(ownerKey, body.toolkit, body.account);
    return jsonResponse({
      ok: true,
      cleanupStatus: "unverified",
      providerCompletion: "unverified",
    });
  } catch (error) {
    const erased = erasedResponse(error);
    if (erased) return erased;
    const failure = classifyConnectorFailure(error, true);
    logError("connectors mutation failed", error, { code: failure.code });
    return jsonResponse(
      {
        error: "connector action failed",
        code: failure.code,
        ...(body.action === "disconnect"
          ? {
              cleanupStatus: "uncertain",
              providerCompletion: "unverified",
              retryable: true,
            }
          : {}),
      },
      503,
    );
  }
}
