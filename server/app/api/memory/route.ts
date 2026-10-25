import { logError } from "@/lib/log";
import { JSON_BODY_LIMITS, jsonResponse, readJsonBody } from "@/lib/http";
import { z } from "zod";
import { authFailure, requestAuth } from "@/lib/auth";
import { api } from "@/convex/_generated/api";
import {
  MAX_MEMORY_CHARS,
  MAX_PROFILE_FIELD_CHARS,
  MAX_PROFILE_INSTRUCTION_CHARS,
} from "@/lib/memoryPolicy";

const field = z.string().trim().max(MAX_PROFILE_FIELD_CHARS).optional();
const actionSchema = z.discriminatedUnion("action", [
  z.object({
    action: z.literal("saveProfile"),
    profile: z.object({
      nickname: field,
      occupation: field,
      about: field,
      instructions: z.string().trim().max(MAX_PROFILE_INSTRUCTION_CHARS).optional(),
      memoryEnabled: z.boolean().optional(),
    }),
  }),
  z.object({
    action: z.literal("forget"),
    text: z.string().min(1).max(MAX_MEMORY_CHARS),
  }),
  z.object({ action: z.literal("clear") }),
]);

export async function GET(req: Request) {
  const auth = await requestAuth(req);
  const failure = authFailure(auth);
  if (failure) return failure;
  if (!auth.authenticated || !auth.convex) {
    return jsonResponse({ error: "sign in required" }, 401);
  }
  try {
    const [memories, profile] = await Promise.all([
      auth.convex.query(api.memories.list, {}),
      auth.convex.query(api.profiles.get, {}),
    ]);
    return jsonResponse({ memories, profile: profile ?? {} });
  } catch (error) {
    logError("memory fetch failed", error);
    return jsonResponse({ error: "memory unavailable" }, 503);
  }
}

export async function POST(req: Request) {
  const auth = await requestAuth(req);
  const failure = authFailure(auth);
  if (failure) return failure;
  if (!auth.authenticated || !auth.convex) {
    return jsonResponse({ error: "sign in required" }, 401);
  }

  const raw = await readJsonBody(req, JSON_BODY_LIMITS.action);
  if (raw instanceof Response) return raw;
  let body: z.infer<typeof actionSchema>;
  try {
    body = actionSchema.parse(raw);
  } catch {
    return jsonResponse({ error: "invalid request" }, 400);
  }

  try {
    switch (body.action) {
      case "saveProfile": {
        const profile = await auth.convex.mutation(api.profiles.save, {
          profile: body.profile,
        });
        return jsonResponse({ ok: true, profile: profile ?? {} });
      }
      case "forget": {
        const forgotten = await auth.convex.mutation(api.memories.forget, {
          text: body.text,
        });
        return jsonResponse({ ok: true, forgotten });
      }
      case "clear": {
        const deleted = await auth.convex.action(api.memories.clear, {});
        return jsonResponse({ ok: true, deleted });
      }
    }
  } catch (error) {
    logError("memory action failed", error);
    return jsonResponse({ error: "memory action failed" }, 503);
  }
}
