import { NDJSON_HEADERS, ndjsonLine } from "./generationProtocol";

export const JSON_BODY_LIMITS = {
  action: 16 * 1024,
  automation: 32 * 1024,
  savesClassify: 96 * 1024,
  writing: 128 * 1024,
  writingSave: 256 * 1024,
  tts: 64 * 1024,
  generation: 64 * 1024 * 1024,
} as const;

export function jsonResponse(
  body: unknown,
  status = 200,
  headers: Record<string, string> = {},
): Response {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store", ...headers } });
}

export function pageLimit(value: string | null, fallback: number, max: number): number | null {
  if (value === null) return fallback;
  const limit = Number(value);
  return Number.isInteger(limit) && limit >= 1 && limit <= max ? limit : null;
}

const invalidJSONBody = () => jsonResponse({ error: "invalid JSON body" }, 400);
const tooLarge = () => jsonResponse({ error: "request_too_large" }, 413);

async function readBodyText(req: Request, maxBytes: number): Promise<string | Response> {
  if (Number(req.headers.get("content-length")) > maxBytes) {
    void req.body?.cancel().catch(() => {});
    return tooLarge();
  }
  const reader = req.body?.getReader();
  if (!reader) return invalidJSONBody();
  try {
    const decoder = new TextDecoder("utf-8", { fatal: true });
    let text = "";
    let size = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) {
        void reader.cancel().catch(() => {});
        return tooLarge();
      }
      text += decoder.decode(value, { stream: true });
    }
    return text + decoder.decode();
  } catch {
    return invalidJSONBody();
  } finally {
    reader.releaseLock();
  }
}

export async function readJsonBody(
  req: Request,
  maxBytes: number = JSON_BODY_LIMITS.action,
  validate: (value: unknown, text: string) => Response | null = () => null,
): Promise<unknown> {
  const text = await readBodyText(req, maxBytes);
  if (text instanceof Response) return text;
  try {
    const value: unknown = JSON.parse(text);
    return validate(value, text) ?? value;
  } catch {
    return invalidJSONBody();
  }
}

export function ndjsonResponse(
  produce: (emit: (event: object) => void) => Promise<void>,
  onError: (error: unknown) => void,
): Response {
  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const emit = (event: object) => controller.enqueue(encoder.encode(ndjsonLine(event)));
      try {
        await produce(emit);
      } catch (error) {
        onError(error);
        emit({ type: "error" });
      } finally {
        controller.close();
      }
    },
  });
  return new Response(stream, { headers: NDJSON_HEADERS });
}
