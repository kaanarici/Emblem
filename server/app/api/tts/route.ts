import WebSocket from "ws";
import { logError } from "@/lib/log";
import { admitMetered, METERED_ROUTES } from "@/lib/meteredAccess";
import { readJsonBody, JSON_BODY_LIMITS } from "@/lib/http";
import { z } from "zod";

export const maxDuration = 60;

const PCM_QUERY = "voice_id=ara&language=auto&codec=pcm&sample_rate=24000";

export async function POST(req: Request) {
  if (!(await admitMetered(req, METERED_ROUTES.tts))) {
    return new Response(null, { status: 503 });
  }
  const raw = await readJsonBody(req, JSON_BODY_LIMITS.tts);
  if (raw instanceof Response) return raw;
  const parsed = z
    .object({ text: z.string().refine((text) => Boolean(text.trim())) })
    .safeParse(raw);
  if (!parsed.success) return new Response(null, { status: 400 });
  if (!process.env.XAI_API_KEY) return new Response(null, { status: 503 });

  return pcmStream(parsed.data.text.slice(0, 15000), req.signal);
}

function pcmStream(text: string, signal: AbortSignal): Response {
  let cancel = () => {};
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      const ws = new WebSocket(`wss://api.x.ai/v1/tts?${PCM_QUERY}`, {
        headers: { Authorization: `Bearer ${process.env.XAI_API_KEY}` },
      });
      let closed = false;
      const finish = (error?: string, cancelled = false) => {
        if (closed) return;
        closed = true;
        clearTimeout(watchdog);
        signal.removeEventListener("abort", abort);
        if (!cancelled) {
          if (error) {
            logError("tts ws failed", error);
            controller.error(new Error(error));
          } else {
            controller.close();
          }
        }
        if (cancelled || error) ws.terminate();
        else ws.close();
      };
      let watchdog: ReturnType<typeof setTimeout> | undefined = setTimeout(
        () => finish("no audio within 10s"),
        10_000,
      );
      const abort = () => finish("request aborted");
      cancel = () => finish(undefined, true);

      ws.on("open", () => {
        if (closed) return;
        ws.send(JSON.stringify({ type: "text.delta", delta: text }));
        ws.send(JSON.stringify({ type: "text.done" }));
      });
      ws.on("message", (data) => {
        if (closed) return;
        try {
          const m = JSON.parse(data.toString());
          const b64 = m.audio ?? m.delta ?? m.data;
          if (typeof b64 === "string" && b64.length > 0) {
            clearTimeout(watchdog);
            watchdog = undefined;
            controller.enqueue(new Uint8Array(Buffer.from(b64, "base64")));
          }
          if ((m.type ?? "").includes("done")) finish();
        } catch {
          finish("unreadable tts frame");
        }
      });
      ws.on("error", (error) => finish(String(error)));
      ws.on("close", () => finish());
      signal.addEventListener("abort", abort, { once: true });
      if (signal.aborted) abort();
    },
    cancel() {
      cancel();
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "audio/pcm",
      "X-Sample-Rate": "24000",
      "Cache-Control": "no-store",
      "Content-Encoding": "identity",
    },
  });
}
