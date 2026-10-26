import { logError } from "@/lib/log";
import { z } from "zod";
import { jsonResponse, readJsonBody } from "@/lib/http";
import { api } from "@/convex/_generated/api";
import { authFailure, requestAuth } from "@/lib/auth";
import type { ConvexHttpClient } from "convex/browser";

const MUTATION_WAIT_MS = 30_000;
const MAX_PURGE_BATCHES = 100;
const MAX_KEYS = 100;
const PURGE_CONCURRENCY = 6;

const keySchema = z.string().trim().min(1).max(200);
const requestSchema = z.union([
  z.object({
    action: z.enum(["archive", "unarchive", "delete", "pin", "unpin"]),
    conversationKey: keySchema,
  }),
  z.object({
    action: z.literal("rename"),
    conversationKey: keySchema,
    title: z.string().trim().min(1).max(2000),
  }),
  z.object({
    action: z.enum(["archive", "unarchive", "delete"]),
    conversationKeys: z.array(keySchema).min(1).max(MAX_KEYS),
  }),
]);

export async function POST(req: Request) {
  const auth = await requestAuth(req);
  const failure = authFailure(auth);
  if (failure) return failure;
  if (!auth.authenticated) {
    return jsonResponse({ error: "sign in required" }, 401);
  }
  const { convex } = auth;
  if (!convex) return jsonResponse({ error: "backend unavailable" }, 503);
  const raw = await readJsonBody(req);
  if (raw instanceof Response) return raw;
  const parsed = requestSchema.safeParse(raw);
  if (!parsed.success) {
    return jsonResponse({ error: "valid action and conversationKey required" }, 400);
  }
  const body = parsed.data;
  const { action } = body;
  const bulk = "conversationKeys" in body;
  const keys = bulk ? [...new Set(body.conversationKeys)] : [body.conversationKey];
  if (action === "delete") return await purge(convex, keys);
  try {
    const found =
      body.action === "rename"
        ? await convex.mutation(api.conversations.rename, {
            conversationKey: keys[0],
            title: body.title,
          })
        : action === "pin" || action === "unpin"
          ? await convex.mutation(api.conversations.setPinned, {
              conversationKey: keys[0],
              pinned: action === "pin",
            })
          : await convex.mutation(api.conversations.setArchived, {
              conversationKeys: keys,
              archived: action === "archive",
            });
    if (bulk) return jsonResponse({ ok: true, action, count: Number(found) });
    return found
      ? jsonResponse({ ok: true, action })
      : jsonResponse({ error: "conversation not found" }, 404);
  } catch (error) {
    logError("conversation change failed", error);
    return jsonResponse(
      { error: "conversation change failed", code: "conversation_incomplete", retryable: true },
      503,
    );
  }
}

async function purge(convex: ConvexHttpClient, keys: string[]): Promise<Response> {
  const deadline = Date.now() + MUTATION_WAIT_MS;
  const queue = [...keys];
  let count = 0;
  const purgeNext = async (): Promise<void> => {
    for (let key = queue.shift(); key !== undefined; key = queue.shift()) {
      const conversationKey = key;
      for (let batch = 0; ; batch++) {
        if (batch === MAX_PURGE_BATCHES) throw new Error("conversation purge batch limit");
        const deleted = await beforeDeadline(
          () => convex.mutation(api.conversations.purge, { conversationKey }),
          deadline,
        );
        if (deleted === 0) break;
        count += deleted;
      }
    }
  };
  try {
    await Promise.all(Array.from({ length: Math.min(PURGE_CONCURRENCY, keys.length) }, purgeNext));
    return jsonResponse({ ok: true, action: "delete", count });
  } catch (error) {
    queue.length = 0;
    logError("conversation delete incomplete", error);
  }
  return jsonResponse(
    {
      ok: false,
      action: "delete",
      count,
      retryable: true,
      error: "conversation delete incomplete; retry the same request",
      code: "conversation_incomplete",
    },
    503,
    { "Retry-After": "1" },
  );
}

async function beforeDeadline<T>(work: () => Promise<T>, deadline: number): Promise<T> {
  const remaining = deadline - Date.now();
  if (remaining <= 0) throw new Error("conversation deadline exceeded");
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      work(),
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error("conversation deadline exceeded")), remaining);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}
