import { jsonResponse } from "@/lib/http";
import { logError } from "@/lib/log";
import { api } from "@/convex/_generated/api";
import type { ConvexHttpClient } from "convex/browser";
import { authFailure, requestAuth } from "@/lib/auth";
import { disconnectAll } from "@/lib/connectors";

export const maxDuration = 240;
const PURGE_WAIT_MS = 30_000;
const PURGE_POLL_MS = 250;

export async function DELETE(req: Request) {
  const auth = await requestAuth(req);
  const failure = authFailure(auth);
  if (failure) return failure;
  if (!auth.authenticated || !auth.ownerKey) {
    return jsonResponse({ error: "sign in required" }, 401);
  }
  if (!auth.convex) {
    return jsonResponse({ error: "backend unavailable" }, 503);
  }

  let cleanupStatus = "not_requested";
  try {
    await auth.convex.mutation(api.accounts.beginErasure, {});
    const providerConfigured = Boolean(process.env.COMPOSIO_API_KEY);
    cleanupStatus = providerConfigured ? "uncertain" : "not_requested";
    await disconnectAll(auth.ownerKey);
    cleanupStatus = providerConfigured ? "unverified" : "not_requested";

    const purge = await auth.convex.mutation(api.accounts.purgeSelf, {});
    if (!purge.done && !(await waitForPurge(auth.convex))) {
      throw new Error("account purge is still running");
    }
    return jsonResponse({
      ok: true,
      localData: "deleted",
      cleanupStatus,
      providerCompletion: "unverified",
    });
  } catch (error) {
    logError("account purge failed", error);
    return jsonResponse(
      {
        error: "account data could not be deleted",
        code: "purge_failed",
        cleanupStatus,
        providerCompletion: "unverified",
        retryable: true,
      },
      502,
    );
  }
}

async function waitForPurge(convex: ConvexHttpClient): Promise<boolean> {
  const deadline = Date.now() + PURGE_WAIT_MS;
  while (Date.now() < deadline) {
    if ((await convex.query(api.accounts.purgeStatus, {})).done) return true;
    await new Promise((resolve) => setTimeout(resolve, PURGE_POLL_MS));
  }
  return (await convex.query(api.accounts.purgeStatus, {})).done;
}
