import { logError } from "@/lib/log";
import { z } from "zod";
import { jsonResponse, readJsonBody } from "@/lib/http";
import { generateText } from "ai";
import { getModel } from "@/lib/provider";
import { admitMetered, METERED_ROUTES } from "@/lib/meteredAccess";

export const maxDuration = 30;

const hintSchema = z.object({
  question: z.string().trim().min(1).max(4000),
  options: z.union([z.array(z.string().max(2000)).max(4), z.string().max(8000)]).optional(),
  answer: z.string().max(2000).optional(),
});

export async function POST(req: Request) {
  if (!(await admitMetered(req, METERED_ROUTES.hint))) {
    return jsonResponse({ error: "hint unavailable" }, 429);
  }
  const raw = await readJsonBody(req);
  if (raw instanceof Response) return raw;
  const parsed = hintSchema.safeParse(raw);
  if (!parsed.success) return jsonResponse({ error: "invalid hint request" }, 400);
  const { question, options, answer } = parsed.data;

  try {
    const { text } = await generateText({
      model: getModel(),
      abortSignal: AbortSignal.timeout(15000),
      prompt: `Quiz question: "${question}"
Options: ${Array.isArray(options) ? options.join(" | ") : (options ?? "")}
Correct answer (SECRET: never state it, quote it, or make it the only survivor): ${answer ?? "unknown"}
Write ONE short hint sentence (max 18 words) that nudges the student's thinking toward the right idea without giving the answer away. No prefixes, just the hint.`,
    });
    return jsonResponse({ hint: text.trim() });
  } catch (error) {
    logError("hint failed", error);
    return jsonResponse({ error: "hint unavailable" }, 502);
  }
}
