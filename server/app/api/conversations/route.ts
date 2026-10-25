import { jsonResponse, pageLimit } from "@/lib/http";
import { logError } from "@/lib/log";
import { api } from "@/convex/_generated/api";
import { authFailure, requestAuth } from "@/lib/auth";
import type { FunctionReturnType } from "convex/server";

type Conversation = FunctionReturnType<typeof api.conversations.list>["conversations"][number];
type List = "pinned" | "recent" | "archived";

const LISTS: readonly List[] = ["pinned", "recent", "archived"];
const PINNED_PAGE = 100;
const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 100;
const MAX_CURSOR = 4096;

function parseCursor(value: string | null): { list: List; cursor: string } | null | undefined {
  if (value === null) return null;
  const split = value.indexOf(":");
  const list = LISTS.find((name) => name === value.slice(0, split));
  const cursor = value.slice(split + 1);
  return list && cursor && value.length <= MAX_CURSOR ? { list, cursor } : undefined;
}

export async function GET(req: Request) {
  const params = new URL(req.url).searchParams;
  const limit = pageLimit(params.get("limit"), DEFAULT_LIMIT, MAX_LIMIT);
  if (limit === null) return jsonResponse({ error: "invalid limit", code: "invalid_limit" }, 400);
  const start = parseCursor(params.get("cursor"));
  if (start === undefined) {
    return jsonResponse({ error: "invalid cursor", code: "invalid_cursor" }, 400);
  }
  const auth = await requestAuth(req);
  const failure = authFailure(auth);
  if (failure) return failure;
  if (auth.status === "guest") {
    return jsonResponse({ pinned: [], conversations: [], nextCursor: null });
  }
  const { convex } = auth;
  if (!convex) return jsonResponse({ error: "backend unavailable" }, 503);

  const pinned: Conversation[] = [];
  const conversations: Conversation[] = [];
  let list: List = start?.list ?? (params.get("archived") === "true" ? "archived" : "pinned");
  let cursor = start?.cursor ?? null;
  try {
    while (true) {
      const page = await convex.query(api.conversations.list, {
        list,
        cursor,
        limit: list === "pinned" ? PINNED_PAGE : limit,
      });
      (list === "pinned" ? pinned : conversations).push(...page.conversations);
      if (page.nextCursor || list !== "pinned") {
        const nextCursor = page.nextCursor ? `${list}:${page.nextCursor}` : null;
        return jsonResponse({ pinned, conversations, nextCursor });
      }
      list = "recent";
      cursor = null;
    }
  } catch (error) {
    logError("conversations request failed", error);
    return jsonResponse(
      { error: "conversations unavailable", code: "conversations_unavailable" },
      500,
    );
  }
}
