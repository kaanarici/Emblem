import { readGeneratedStepImage } from "@/lib/generatedStepImages";

export const runtime = "nodejs";

export async function GET(req: Request) {
  const key = new URL(req.url).searchParams.get("key")?.trim();
  if (!key) {
    return new Response(null, {
      status: 400,
      headers: { "Cache-Control": "no-store" },
    });
  }

  const image = await readGeneratedStepImage(key);
  if (!image) {
    return new Response(null, {
      status: 404,
      headers: { "Cache-Control": "no-store" },
    });
  }

  try {
    const upstream = await fetch(image.url, {
      signal: AbortSignal.timeout(5_000),
    });
    if (!upstream.ok || !upstream.body) throw new Error("stored image unavailable");
    return new Response(upstream.body, {
      headers: {
        "Cache-Control": "public, max-age=31536000, immutable",
        "Content-Length": String(image.byteLength),
        "Content-Type": image.mimeType,
        "X-Content-Type-Options": "nosniff",
      },
    });
  } catch {
    return new Response(null, {
      status: 502,
      headers: { "Cache-Control": "no-store" },
    });
  }
}
