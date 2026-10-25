import { isHotelPhotoQuery, resolveHotelPhotoQuery } from "./travel/hotelContent";
import { logEvent } from "./log";
import { logError } from "./log";
import { createHash, createHmac } from "node:crypto";
import { ConvexHttpClient } from "convex/browser";
import { api } from "@/convex/_generated/api";
import {
  isGeneratedStepImageQuery,
  resolveGeneratedStepImageQuery,
} from "@/lib/generatedStepImages";
import { fitsAspect, probeImageCandidates } from "@/lib/imageVerify";
import type { Block } from "@/lib/schema";
import type { ImageAspect } from "@/lib/blockPrimitives";

type Resolved = { url: string; source: string };

const RESOLUTION_DEADLINE_MS = 16_000;
const WARM_DEADLINE_MS = 2_500;
const L2_LOOKUP_MS = 350;
const STRUCTURED_FETCH_MS = 3_500;
const WIKIDATA_LOOKUP_MS = 2_500;
const EXA_FETCH_MS = 3_000;

function bestEffort<T>(
  signal: AbortSignal,
  operation: (signal: AbortSignal) => Promise<T>,
): Promise<T | null> {
  if (signal.aborted) return Promise.resolve(null);
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value: T | null) => {
      if (settled) return;
      settled = true;
      signal.removeEventListener("abort", onAbort);
      resolve(value);
    };
    const onAbort = () => finish(null);
    signal.addEventListener("abort", onAbort, { once: true });
    if (signal.aborted) return onAbort();
    void operation(signal).then(finish, () => finish(null));
  });
}

async function withinDeadline<T>(
  timeoutMs: number,
  operation: (signal: AbortSignal) => Promise<T>,
): Promise<T | null> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await bestEffort(controller.signal, operation);
  } finally {
    clearTimeout(timeout);
    controller.abort();
  }
}

function boundedSignal(parent: AbortSignal, timeoutMs: number): AbortSignal {
  return AbortSignal.any([parent, AbortSignal.timeout(timeoutMs)]);
}

async function providerJson<T>(
  url: string,
  init: RequestInit,
  parentSignal: AbortSignal,
  timeoutMs: number,
): Promise<T | null> {
  const signal = boundedSignal(parentSignal, timeoutMs);
  return await bestEffort(signal, async () => {
    const response = await fetch(url, { ...init, signal });
    if (!response.ok) return null;
    return (await response.json()) as T;
  });
}

let convexClient: ConvexHttpClient | null | undefined;
function getConvex(): ConvexHttpClient | null {
  if (convexClient === undefined) {
    const url = process.env.NEXT_PUBLIC_CONVEX_URL;
    convexClient = url ? new ConvexHttpClient(url) : null;
  }
  return convexClient;
}

async function l2Get(key: string): Promise<Resolved | null> {
  const convex = getConvex();
  if (!convex) return null;
  return await convex.query(api.imageCache.get, { key, now: Date.now() }).catch((error) => {
    logError("convex imageCache.get failed", error);
    return null;
  });
}

function imageCacheWriteGrant(secret: string, key: string, url: string, source: string): string {
  return createHmac("sha256", secret).update([key, url, source].join("\0")).digest("hex");
}

function l2Put(key: string, resolved: Resolved): void {
  const convex = getConvex();
  const secret = process.env.GENERATED_STEP_IMAGE_STORAGE_SECRET?.trim();
  if (!convex || !secret) return;
  const writeGrant = imageCacheWriteGrant(secret, key, resolved.url, resolved.source);
  void convex
    .action(api.imageCache.put, {
      key,
      url: resolved.url,
      source: resolved.source,
      writeGrant,
    })
    .catch((error) => logError("convex imageCache.put failed", error));
}

const l1 = new Map<string, Promise<string | null>>();
const L1_MAX = 500;

function l1Set(key: string, value: Promise<string | null>) {
  if (l1.size >= L1_MAX) l1.delete(l1.keys().next().value!);
  l1.set(key, value);
}

export function cacheKey(query: string, kind: string, aspect?: ImageAspect): string {
  const normalized = query.trim().toLowerCase().replace(/\s+/g, " ");
  const namespace = kind === "photo" ? "photo.v2" : kind;
  return boundedCacheKey(
    aspect ? `${namespace}:${aspect}:${normalized}` : `${namespace}:${normalized}`,
  );
}

function boundedCacheKey(key: string): string {
  return key.length <= 512 ? key : `image:v2:${createHash("sha256").update(key).digest("hex")}`;
}

export function resolveImageCached(
  query: string,
  kind: string,
  aspect?: ImageAspect,
  exclude?: string,
): Promise<string | null> {
  if (isHotelPhotoQuery(query))
    return kind === "photo" ? resolveHotelPhotoQuery(query) : Promise.resolve(null);
  const base = cacheKey(query, kind, aspect);
  const key = boundedCacheKey(
    exclude ? `${base}!x:${createHash("sha256").update(exclude).digest("hex")}` : base,
  );
  const hit = l1.get(key);
  if (hit) return hit;
  const pending = withinDeadline(RESOLUTION_DEADLINE_MS, (signal) =>
    resolveThroughL2(key, query, kind, signal, aspect, exclude),
  );
  l1Set(key, pending);
  void pending.then((url) => {
    if (!url && l1.get(key) === pending) l1.delete(key);
  });
  return pending;
}

const PENDING = Symbol("pending");

export async function cachedImageURL(
  query: string,
  kind: string,
  aspect?: ImageAspect,
): Promise<string | null> {
  if (isHotelPhotoQuery(query)) return null;
  const key = cacheKey(query, kind, aspect);
  const hit = l1.get(key);
  if (hit) {
    const settled = await Promise.race([hit, Promise.resolve(PENDING)]);
    return settled === PENDING ? null : settled;
  }
  const cached = await withinDeadline(L2_LOOKUP_MS, () => l2Get(key));
  if (!cached) return null;
  l1Set(key, Promise.resolve(cached.url));
  return cached.url;
}

const CARD_ARTWORK_DEADLINE_MS = 1_500;
const HERO_ARTWORK_DEADLINE_MS = 2_500;

export function resolvePageArtwork(
  blocks: readonly Block[],
  resolve: typeof resolveImageCached = resolveImageCached,
): Promise<Block[]> {
  return Promise.all(
    blocks.map(async (block): Promise<Block> => {
      if (block.type === "hero") {
        const aspect: ImageAspect =
          block.image.kind === "poster" || block.aspect === "poster"
            ? "portrait"
            : block.aspect === "wide"
              ? "landscape"
              : "square";
        const image = { ...block.image, aspect };
        if (image.kind === "object") return { ...block, image };
        const imageURL = await withHarvestDeadline(
          resolve(image.query, image.kind, aspect),
          HERO_ARTWORK_DEADLINE_MS,
        );
        return imageURL ? { ...block, image, imageURL } : { ...block, image };
      }
      if (block.type === "cardCarousel") {
        const cards = await Promise.all(block.cards.map((card) => harvestArtwork(card, resolve)));
        return { ...block, cards };
      }
      if (block.type === "stepCarousel") {
        const steps = await Promise.all(
          block.steps.map((step) => harvestArtwork(step, resolve, "landscape")),
        );
        return { ...block, steps };
      }
      if (block.type === "spotList") {
        const spots = await Promise.all(
          block.spots.map((spot) => harvestArtwork(spot, resolve, "landscape")),
        );
        return { ...block, spots };
      }
      if (block.type === "sideBySide") {
        const entities = await Promise.all(
          block.entities.map((entity) => harvestArtwork(entity, resolve)),
        );
        return { ...block, entities: symmetricEntityArtwork(entities) };
      }
      if (block.type === "oneAgainstMany") {
        const contenders = symmetricEntityArtwork(
          await Promise.all(
            [block.anchor, ...block.challengers].map((contender) =>
              harvestArtwork(contender, resolve),
            ),
          ),
        );
        const [anchor, ...challengers] = contenders;
        return { ...block, anchor, challengers };
      }
      return block;
    }),
  );
}

async function harvestArtwork<
  T extends {
    image?: { query: string; kind: string; aspect?: ImageAspect };
    imageURL?: string;
  },
>(entity: T, resolve: typeof resolveImageCached, defaultAspect?: ImageAspect): Promise<T> {
  const image = entity.image;
  if (!image || entity.imageURL || image.kind === "object" || image.kind === "generated") {
    return entity;
  }
  const imageURL = await withHarvestDeadline(
    resolve(image.query, image.kind, image.aspect ?? defaultAspect),
    CARD_ARTWORK_DEADLINE_MS,
  );
  return imageURL ? { ...entity, imageURL } : entity;
}

function symmetricEntityArtwork<T extends { image?: unknown; imageURL?: string }>(
  entities: T[],
): T[] {
  const wanted = entities.filter((entity) => entity.image != null);
  if (wanted.length === 0) return entities;
  if (wanted.every((entity) => entity.imageURL != null)) return entities;
  return entities.map(({ image: _image, imageURL: _imageURL, ...rest }) => rest as T);
}

function withHarvestDeadline(
  pending: Promise<string | null>,
  deadlineMs: number,
): Promise<string | null> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  return Promise.race([
    pending,
    new Promise<null>((expire) => {
      timer = setTimeout(() => expire(null), deadlineMs);
    }),
  ]).finally(() => clearTimeout(timer));
}

const warming = new Set<string>();
export function warmImage(query: string, kind: string, aspect?: ImageAspect): void {
  if (kind === "object") return;
  if (kind === "generated" && isGeneratedStepImageQuery(query)) {
    void resolveGeneratedStepImageQuery(query);
    return;
  }
  if (kind === "generated" || isGeneratedStepImageQuery(query)) return;
  const key = cacheKey(query, kind, aspect);
  if (l1.has(key) || warming.has(key)) return;
  warming.add(key);
  void withinDeadline(WARM_DEADLINE_MS, async (signal) => {
    const cached = await bestEffort(boundedSignal(signal, L2_LOOKUP_MS), () => l2Get(key));
    if (cached || signal.aborted) return cached;
    const resolved = await resolveStructured(query, kind, signal, aspect);
    if (resolved) l2Put(key, resolved);
    return resolved;
  })
    .then((resolved) => {
      if (!resolved) return;
      logEvent("info", "image warmed", { kind, source: resolved.source });
      l1Set(key, Promise.resolve(resolved.url));
    })
    .catch(() => {})
    .finally(() => warming.delete(key));
}

export function imageSpecsIn(
  node: unknown,
): { query: string; kind: string; aspect?: ImageAspect }[] {
  const out: { query: string; kind: string; aspect?: ImageAspect }[] = [];
  const walk = (n: unknown): void => {
    if (!n || typeof n !== "object") return;
    const o = n as Record<string, unknown>;
    if (
      typeof o.query === "string" &&
      typeof o.kind === "string" &&
      ["poster", "still", "logo", "photo", "generated"].includes(o.kind)
    ) {
      const aspect =
        o.aspect === "square" || o.aspect === "portrait" || o.aspect === "landscape"
          ? o.aspect
          : undefined;
      out.push({ query: o.query, kind: o.kind, aspect });
      return;
    }
    for (const v of Object.values(o)) {
      if (Array.isArray(v)) v.forEach(walk);
      else if (v && typeof v === "object") walk(v);
    }
  };
  walk(node);
  return out;
}

async function resolveThroughL2(
  key: string,
  query: string,
  kind: string,
  signal: AbortSignal,
  aspect?: ImageAspect,
  exclude?: string,
): Promise<string | null> {
  const cached = await bestEffort(boundedSignal(signal, L2_LOOKUP_MS), () => l2Get(key));
  if (cached && cached.url !== exclude) {
    logEvent("info", "image resolved", { kind, source: `l2:${cached.source}` });
    return cached.url;
  }
  if (signal.aborted) return null;
  const resolved = await resolveImage(query, kind, signal, aspect, exclude);
  if (resolved) l2Put(key, resolved);
  return resolved?.url ?? null;
}

async function resolveImage(
  query: string,
  kind: string,
  signal: AbortSignal,
  aspect?: ImageAspect,
  exclude?: string,
): Promise<Resolved | null> {
  const structured = await resolveStructured(query, kind, signal, aspect);
  if (structured && structured.url !== exclude) {
    logEvent("info", "image resolved", { kind, source: structured.source });
    return structured;
  }
  return fallbackPhoto(query, aspect, signal, kind, exclude);
}

async function resolveStructured(
  query: string,
  kind: string,
  signal: AbortSignal,
  aspect?: ImageAspect,
): Promise<Resolved | null> {
  const entityQuery =
    kind === "poster" || kind === "still" || kind === "logo" ? mediaEntityQuery(query) : query;
  const photo = structuredPhoto(entityQuery, aspect, signal).catch(() => null);
  if (kind === "poster" || kind === "still" || kind === "logo") {
    const canUseITunes =
      !aspect || aspect === "square" || (kind === "poster" && aspect === "portrait");
    const media = [
      process.env.TMDB_API_KEY ? tmdb(entityQuery, kind, aspect, signal) : Promise.resolve(null),
      kind === "poster" && aspect !== "landscape"
        ? omdbPoster(entityQuery, signal)
        : Promise.resolve(null),
      canUseITunes ? itunesMedia(entityQuery, signal) : Promise.resolve(null),
      kind === "poster" && aspect !== "landscape"
        ? tvMazePoster(entityQuery, signal)
        : Promise.resolve(null),
    ].map((pending) => pending.catch(() => null));
    for (const pending of media) {
      const art = await pending;
      if (art) return art;
    }
    return await photo;
  }
  return photo;
}

function mediaEntityQuery(query: string): string {
  const entity = query
    .replace(/\b(?:netflix|apple\s+tv\+?|hbo|max|hulu|disney\+?|prime\s+video)\b/gi, " ")
    .replace(/\b(?:tv|television)\s+(?:series|show)\s+poster\b/gi, " ")
    .replace(/\b(?:movie|film)\s+poster\b/gi, " ")
    .replace(/\b(?:official\s+)?(?:poster|key\s+art|cover\s+art)\b/gi, " ")
    .replace(
      /\b(?:cast\s+silhouette|ensemble\s+cast|cast\s+portrait|character\s+ensemble|promotional\s+(?:image|art)|series\s+artwork)\b/gi,
      " ",
    )
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\s+series$/i, "");
  return entity || query;
}

async function structuredPhoto(
  query: string,
  aspect: ImageAspect | undefined,
  signal: AbortSignal,
): Promise<Resolved | null> {
  const exact = wikipediaExact(query, aspect, signal).catch(() => null);
  const p18 = wikidataP18(query, signal).catch(() => null);
  const lead = await exact;
  if (lead) return { url: lead, source: "wikipedia" };
  const image = await p18;
  if (image) return { url: image, source: "wikidata" };
  return null;
}

async function fallbackPhoto(
  query: string,
  aspect: ImageAspect | undefined,
  signal: AbortSignal,
  kind: string,
  exclude?: string,
): Promise<Resolved | null> {
  const [fuzzy, wikidata, exa] = await Promise.all([
    wikipediaFuzzy(query, aspect, signal),
    aspect ? wikidataP18(query, signal) : null,
    exaImages(query, kind, signal),
  ]);
  const candidates = [...fuzzy, ...(wikidata ? [wikidata] : []), ...exa].filter(
    (candidate) => candidate !== exclude,
  );
  const { url, verified, tried } = await probeImageCandidates(candidates, {
    aspect,
    photo: kind === "photo",
    signal,
  });
  logEvent("info", "image resolved by web search", {
    kind,
    candidates: candidates.length,
    tried,
    verified,
    found: url !== null,
  });
  return url ? { url, source: "web-verified" } : null;
}

const WIKI_HEADERS = { "User-Agent": "EmblemApp/1.0 (https://github.com/kaanarici/emblem)" };

async function wikiJson<T>(url: string, signal: AbortSignal): Promise<T | null> {
  return providerJson<T>(url, { headers: WIKI_HEADERS }, signal, STRUCTURED_FETCH_MS);
}

type PageImages = {
  query?: {
    pages?: Record<string, { thumbnail?: { source?: string; width?: number; height?: number } }>;
  };
};

function firstThumbnail(data: PageImages | null, aspect?: ImageAspect): string | null {
  for (const p of Object.values(data?.query?.pages ?? {})) {
    const src = p.thumbnail?.source;
    if (
      src?.startsWith("https") &&
      isLikelyPhotographURL(src) &&
      fitsAspect(p.thumbnail?.width ?? 0, p.thumbnail?.height ?? 0, aspect)
    ) {
      return src;
    }
  }
  return null;
}

const NON_PHOTO_ASSET =
  /(?:^|[/_. -])(flag|coat[ _-]?of[ _-]?arms|logo|seal|emblem|icon|symbol|diagram|wordmark|map)(?:[/_. ?&-]|$)|\.svg(?:\.png)?(?:\?|$)/i;

function isLikelyPhotographURL(url: string): boolean {
  try {
    return !NON_PHOTO_ASSET.test(decodeURIComponent(url));
  } catch {
    return !NON_PHOTO_ASSET.test(url);
  }
}

const WIKI_BASE =
  "https://en.wikipedia.org/w/api.php?action=query&prop=pageimages&format=json&pithumbsize=800&redirects=1";

async function wikipediaExact(
  query: string,
  aspect: ImageAspect | undefined,
  signal: AbortSignal,
): Promise<string | null> {
  return firstThumbnail(
    await wikiJson<PageImages>(`${WIKI_BASE}&titles=${encodeURIComponent(query)}`, signal),
    aspect,
  );
}

async function wikipediaFuzzy(
  query: string,
  aspect: ImageAspect | undefined,
  signal: AbortSignal,
): Promise<string[]> {
  const url = firstThumbnail(
    await wikiJson<PageImages>(
      `${WIKI_BASE}&generator=search&gsrsearch=${encodeURIComponent(query)}&gsrlimit=1`,
      signal,
    ),
    aspect,
  );
  return url ? [url] : [];
}

async function wikidataP18(query: string, parentSignal: AbortSignal): Promise<string | null> {
  const signal = boundedSignal(parentSignal, WIKIDATA_LOOKUP_MS);
  const search = await wikiJson<{
    search?: { id: string; label?: string; aliases?: string[]; match?: { text?: string } }[];
  }>(
    `https://www.wikidata.org/w/api.php?action=wbsearchentities&search=${encodeURIComponent(query)}&language=en&type=item&limit=1&format=json`,
    signal,
  );
  const hit = search?.search?.[0];
  if (!hit) return null;
  const q = query.trim().toLowerCase();
  const matched = [hit.label, hit.match?.text, ...(hit.aliases ?? [])]
    .filter((s): s is string => typeof s === "string")
    .some((s) => s.trim().toLowerCase() === q);
  if (!matched) return null;

  const claims = await wikiJson<{
    claims?: { P18?: { mainsnak?: { datavalue?: { value?: unknown } } }[] };
  }>(
    `https://www.wikidata.org/w/api.php?action=wbgetclaims&entity=${hit.id}&property=P18&format=json`,
    signal,
  );
  const file = claims?.claims?.P18?.[0]?.mainsnak?.datavalue?.value;
  if (typeof file !== "string") return null;
  const url = `https://commons.wikimedia.org/wiki/Special:FilePath/${encodeURIComponent(file)}?width=800`;
  return isLikelyPhotographURL(url) ? url : null;
}

async function exaImages(query: string, kind: string, signal: AbortSignal): Promise<string[]> {
  const first = await exaImagesOnce(query, kind, signal);
  if (first.length > 0 || signal.aborted) return first;
  return exaImagesOnce(query, kind, signal);
}

async function exaImagesOnce(query: string, kind: string, signal: AbortSignal): Promise<string[]> {
  const apiKey = process.env.EXA_API_KEY;
  if (!apiKey) return [];
  const data = await providerJson<{
    results?: { image?: string; extras?: { imageLinks?: string[] } }[];
  }>(
    "https://api.exa.ai/search",
    {
      method: "POST",
      headers: { "x-api-key": apiKey, "Content-Type": "application/json" },
      body: JSON.stringify({
        query:
          kind === "poster"
            ? `${query} official poster`
            : kind === "still"
              ? `${query} official TV still`
              : kind === "logo"
                ? `${query} official logo`
                : `${query} photograph`,
        numResults: 8,
        type: "auto",
        moderation: true,
        contents: { extras: { imageLinks: 5 } },
      }),
    },
    signal,
    EXA_FETCH_MS,
  );
  if (!data) return [];
  const { results } = data;
  const perResult = (results ?? []).map((r) => [
    ...(r.image ? [r.image] : []),
    ...(r.extras?.imageLinks ?? []),
  ]);
  const width = Math.max(0, ...perResult.map((c) => c.length));
  const out: string[] = [];
  for (let col = 0; col < width; col++) {
    for (const c of perResult) if (c[col]) out.push(c[col]);
  }
  return out.filter(
    (u) =>
      isUsableImage(u) &&
      (kind === "logo" || !LOGO_URL.test(u)) &&
      (kind !== "photo" || isLikelyPhotographURL(u)),
  );
}

const IMAGE_EXT = /\.(jpe?g|png|webp|avif|gif|bmp)(\?|$)/i;
const DYNAMIC_IMAGE = /\/is\/image\/|[?&](fmt|format)=(png|jpe?g)(?:[-&]|$)/i;
const IMAGE_CDN =
  /^https:\/\/(?:images|plus)\.unsplash\.com\/|^https:\/\/assets\.lummi\.ai\/assets\//i;
const JUNK_IMAGE = /\.svg(\?|$)|favicon|sprite|(?:^|[^a-z])icons?(?:[^a-z]|$)|1x1/i;
const LOGO_URL = /(?:^|[^a-z])(?:logos?|lockup|wordmark|brandmark)(?:[^a-z]|$)/i;
function isUsableImage(u: string): boolean {
  return (
    u.startsWith("https") &&
    (IMAGE_EXT.test(u) || DYNAMIC_IMAGE.test(u) || IMAGE_CDN.test(u)) &&
    !JUNK_IMAGE.test(u)
  );
}

async function tmdb(
  query: string,
  kind: string,
  aspect: ImageAspect | undefined,
  signal: AbortSignal,
): Promise<Resolved | null> {
  type Hit = {
    poster_path?: string;
    backdrop_path?: string;
    release_date?: string;
    first_air_date?: string;
  };
  const lookupSignal = boundedSignal(signal, STRUCTURED_FETCH_MS);
  const search = (title: string) =>
    providerJson<{ results?: Hit[] }>(
      `https://api.themoviedb.org/3/search/multi?query=${encodeURIComponent(title)}&include_adult=false`,
      { headers: { Authorization: `Bearer ${process.env.TMDB_API_KEY}` } },
      lookupSignal,
      STRUCTURED_FETCH_MS,
    );
  const data = await search(query);
  let hit = data?.results?.[0];
  const dated = /^(.*\S)\s+\(?((?:18|19|20)\d{2})\)?$/.exec(query);
  if (data?.results?.length === 0 && dated) {
    hit = (await search(dated[1]))?.results?.find((item) =>
      (item.release_date ?? item.first_air_date)?.startsWith(`${dated[2]}-`),
    );
  }
  if (!hit) return null;
  const path = tmdbPath(hit, kind, aspect);
  return path ? { url: `https://image.tmdb.org/t/p/w780${path}`, source: "tmdb" } : null;
}

function tmdbPath(
  hit: { poster_path?: string; backdrop_path?: string },
  kind: string,
  aspect?: ImageAspect,
): string | null {
  if (aspect === "landscape") return hit.backdrop_path ?? null;
  if (aspect === "portrait") return hit.poster_path ?? null;
  if (aspect === "square") return null;
  return kind === "still"
    ? (hit.backdrop_path ?? hit.poster_path ?? null)
    : (hit.poster_path ?? hit.backdrop_path ?? null);
}

async function itunesMedia(query: string, signal: AbortSignal): Promise<Resolved | null> {
  const results = ["tvShow", "movie"]
    .map(async (media) => {
      const data = await providerJson<{ results?: { artworkUrl100?: string }[] }>(
        `https://itunes.apple.com/search?term=${encodeURIComponent(query)}&limit=1&media=${media}&entity=${media === "movie" ? "movie" : "tvSeason"}`,
        {},
        signal,
        STRUCTURED_FETCH_MS,
      );
      const artwork = data?.results?.[0]?.artworkUrl100;
      return artwork ? { url: artwork.replace("100x100bb", "600x600bb"), source: "itunes" } : null;
    })
    .map((pending) => pending.catch(() => null));
  for (const pending of results) {
    const art = await pending;
    if (art) return art;
  }
  return null;
}

async function omdbPoster(query: string, signal: AbortSignal): Promise<Resolved | null> {
  const apiKey = process.env.OMDB_API_KEY;
  if (!apiKey) return null;
  const data = await providerJson<{ Poster?: string }>(
    `https://www.omdbapi.com/?t=${encodeURIComponent(query)}&apikey=${apiKey}`,
    {},
    signal,
    STRUCTURED_FETCH_MS,
  );
  const poster = data?.Poster;
  if (!poster || poster === "N/A" || !poster.startsWith("https")) return null;
  return { url: poster.replace("_SX300", "_SX780"), source: "omdb" };
}

async function tvMazePoster(query: string, signal: AbortSignal): Promise<Resolved | null> {
  const title = query
    .replace(/\b(?:netflix|apple\s+tv\+?|hbo|max|hulu|disney\+?|prime\s+video)\b/gi, " ")
    .replace(/\blive[- ]action\b/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
  const data = await providerJson<
    {
      show?: { image?: { original?: string; medium?: string } };
    }[]
  >(
    `https://api.tvmaze.com/search/shows?q=${encodeURIComponent(title || query)}`,
    {},
    signal,
    STRUCTURED_FETCH_MS,
  );
  const image = data?.[0]?.show?.image;
  const url = image?.original ?? image?.medium;
  return url ? { url, source: "tvmaze" } : null;
}
