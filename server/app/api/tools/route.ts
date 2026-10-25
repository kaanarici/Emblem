import { jsonResponse, readJsonBody } from "@/lib/http";
import { z } from "zod";
import { exaSearch } from "@/lib/exa";
import { searchMusic } from "@/lib/music";
import { admitMetered, METERED_ROUTES } from "@/lib/meteredAccess";

export const maxDuration = 15;

const input = z.object({
  tool: z.enum(["searchWeb", "searchMusic"]),
  query: z.string().trim().min(1).max(300),
});

const MAX_RESULTS = 4;
const MAX_SNIPPET_CHARS = 280;

export async function POST(req: Request) {
  if (!(await admitMetered(req, METERED_ROUTES.tools))) {
    return jsonResponse({ error: "rate_limited" }, 429);
  }
  const body = await readJsonBody(req);
  if (body instanceof Response) return body;
  const parsed = input.safeParse(body);
  if (!parsed.success) {
    return jsonResponse({ error: "invalid_request" }, 400);
  }

  if (parsed.data.tool === "searchMusic") {
    const tracks = await searchMusic(parsed.data.query, MAX_RESULTS);
    return jsonResponse({ tracks });
  }
  const results = (await exaSearch(parsed.data.query)).slice(0, MAX_RESULTS).map((result) => ({
    title: result.title.slice(0, 120),
    url: result.url,
    snippet: (result.highlights?.join(" ") || result.text || "").slice(0, MAX_SNIPPET_CHARS),
    favicon: result.favicon?.startsWith("https://") ? result.favicon : undefined,
    publishedAt: result.publishedDate,
  }));
  return jsonResponse({ results });
}
