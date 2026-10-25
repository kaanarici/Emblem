import {
  isGeneratedStepImageQuery,
  resolveGeneratedStepImageQuery,
} from "@/lib/generatedStepImages";
import {
  cachedObjectIconURL,
  objectIconGenerationAvailable,
  resolveObjectIconQuery,
} from "@/lib/objectIcons";
import { cachedImageURL, resolveImageCached } from "@/lib/imageResolve";
import type { ImageAspect } from "@/lib/blockPrimitives";
import { requestAuth } from "@/lib/auth";
import { admitMetered, imageGenerationAdmission, METERED_ROUTES } from "@/lib/meteredAccess";
import { parseHotelPhotoQuery } from "@/lib/travel/hotelContent";

export const runtime = "nodejs";
export const maxDuration = 60;

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url);
  const query = searchParams.get("query")?.trim();
  const kind = searchParams.get("kind") ?? "photo";
  const rawAspect = searchParams.get("aspect");
  const aspect: ImageAspect | undefined =
    rawAspect === "square" || rawAspect === "portrait" || rawAspect === "landscape"
      ? rawAspect
      : undefined;
  const placement = searchParams.get("placement") === "hero" ? "hero" : "card";
  if (!query) return Response.json({ url: null }, { status: 400 });
  if (query.length > 4_096 || (searchParams.get("exclude")?.length ?? 0) > 4_096) {
    return Response.json({ error: "invalid_request" }, { status: 400 });
  }
  if (kind === "object") {
    const cached = await cachedObjectIconURL(query);
    if (cached) {
      return Response.json(
        { url: cached },
        { headers: { "Cache-Control": "public, max-age=86400" } },
      );
    }
    if (!objectIconGenerationAvailable()) {
      return Response.json({ url: null, unavailable: true }, { headers: cacheHeaders(null) });
    }
  }
  const exclude = searchParams.get("exclude")?.trim() || undefined;
  if (kind !== "object" && kind !== "generated" && !exclude && !isGeneratedStepImageQuery(query)) {
    const cached = await cachedImageURL(query, kind, aspect, placement);
    if (cached) return Response.json({ url: cached }, { headers: cacheHeaders(cached) });
  }
  const route =
    kind === "photo" && parseHotelPhotoQuery(query)
      ? METERED_ROUTES.catalogImage
      : METERED_ROUTES.image;
  const auth = await requestAuth(req);
  if (!(await admitMetered(req, route, auth))) {
    return Response.json(
      { error: "rate_limited" },
      {
        status: 429,
        headers: { "Cache-Control": "no-store" },
      },
    );
  }

  if (kind === "object") {
    const url = await resolveObjectIconQuery(query, { admit: imageGenerationAdmission(auth) });
    return Response.json(
      { url },
      {
        headers: url
          ? { "Cache-Control": "public, max-age=31536000, immutable" }
          : cacheHeaders(null),
      },
    );
  }

  if (kind === "generated" && isGeneratedStepImageQuery(query)) {
    const url = await resolveGeneratedStepImageQuery(query, {
      admit: imageGenerationAdmission(auth),
    });
    return Response.json(
      { url },
      {
        headers: url
          ? { "Cache-Control": "private, max-age=31536000, immutable" }
          : cacheHeaders(null),
      },
    );
  }
  if (kind === "generated" || isGeneratedStepImageQuery(query)) {
    return Response.json({ url: null }, { headers: cacheHeaders(null) });
  }

  const url = await resolveImageCached(query, kind, aspect, exclude, placement);
  return Response.json({ url }, { headers: cacheHeaders(url) });
}

function cacheHeaders(url: string | null): HeadersInit {
  return { "Cache-Control": url ? "public, max-age=86400" : "no-store" };
}
