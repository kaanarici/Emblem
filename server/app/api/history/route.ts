import { jsonResponse, pageLimit } from "@/lib/http";
import { logError } from "@/lib/log";
import { api } from "@/convex/_generated/api";
import { authFailure, requestAuth } from "@/lib/auth";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;
const MAX_CURSOR = 4096;

export async function GET(req: Request) {
  const params = new URL(req.url).searchParams;
  const conversationKey = params.get("conversationKey")?.trim();
  if (!conversationKey) return jsonResponse({ error: "conversationKey required" }, 400);
  const limit = pageLimit(params.get("limit"), DEFAULT_LIMIT, MAX_LIMIT);
  if (limit === null) return jsonResponse({ error: "invalid limit", code: "invalid_limit" }, 400);
  const cursor = params.get("cursor");
  if (cursor !== null && (!cursor || cursor.length > MAX_CURSOR)) {
    return jsonResponse({ error: "invalid cursor", code: "invalid_cursor" }, 400);
  }
  const auth = await requestAuth(req);
  const failure = authFailure(auth);
  if (failure) return failure;
  if (auth.status === "guest") return jsonResponse({ pages: [], nextCursor: null });
  const { convex } = auth;
  if (!convex) return jsonResponse({ error: "backend unavailable" }, 503);

  try {
    const history = await convex.query(api.conversations.history, {
      conversationKey,
      cursor,
      limit,
    });
    const pages = history.pages.map((row) => ({
      pageKey: row.pageKey,
      previousPageKey: row.previousPageKey,
      parentPageKey: row.parentPageKey,
      sourceCardKey: row.sourceCardKey,
      prompt: row.prompt,
      title: row.title,
      blocks: storedArray(row.blocks),
      activities: row.activities ? storedArray(row.activities) : [],
      sources: row.sources ? storedArray(row.sources) : [],
    }));
    return jsonResponse({ pages, nextCursor: history.nextCursor });
  } catch (error) {
    logError("history query failed", error);
    return jsonResponse({ error: "history unavailable", code: "history_unavailable" }, 500);
  }
}

function storedArray(json: string): unknown[] {
  try {
    const parsed = JSON.parse(json);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}
