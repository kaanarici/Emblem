import { Output, streamText } from "ai";
import { logError } from "@/lib/log";
import { admitMetered, METERED_ROUTES } from "@/lib/meteredAccess";
import { getModel } from "@/lib/provider";
import { jsonResponse, ndjsonResponse, readJsonBody } from "@/lib/http";
import {
  QUESTION_OPTIONS_SYSTEM,
  questionOptionsOutputSchema,
  questionOptionsPrompt,
  questionOptionsRequestSchema,
  visibleOptions,
} from "@/lib/questionOptions";

export const maxDuration = 30;

export async function POST(req: Request) {
  if (!(await admitMetered(req, METERED_ROUTES.questionOptions))) {
    return jsonResponse({ error: "options unavailable" }, 429);
  }
  const raw = await readJsonBody(req);
  if (raw instanceof Response) return raw;
  const parsed = questionOptionsRequestSchema.safeParse(raw);
  if (!parsed.success) {
    return jsonResponse({ error: "invalid options request" }, 400);
  }
  const result = streamText({
    model: getModel(),
    output: Output.object({ schema: questionOptionsOutputSchema }),
    maxRetries: 0,
    maxOutputTokens: 800,
    abortSignal: AbortSignal.any([req.signal, AbortSignal.timeout(20000)]),
    system: QUESTION_OPTIONS_SYSTEM,
    prompt: questionOptionsPrompt(parsed.data),
  });
  return ndjsonResponse(
    async (emit) => {
      let last = "";
      for await (const partial of result.partialOutputStream) {
        const options = visibleOptions(partial);
        const encoded = JSON.stringify(options);
        if (options.length && encoded !== last) {
          last = encoded;
          emit({ type: "options", options });
        }
      }
      const options = visibleOptions(await result.output);
      if (options.length < 2) throw new Error("too few options");
      emit({ type: "complete", options });
    },
    (error) => logError("question options failed", error),
  );
}
