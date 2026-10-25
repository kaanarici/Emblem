import type { ImageAspect } from "@/lib/blockPrimitives";
import { MAX_IMAGE_BYTES } from "@/lib/imageBytes";
import { lookup } from "node:dns";
import { request as httpRequest, type IncomingMessage } from "node:http";
import { request as httpsRequest } from "node:https";
import { isIP, type LookupFunction } from "node:net";
import sharp from "sharp";

const CANDIDATE_PROBES = 6;
const PROBE_BATCHES = 3;
const PROBE_DEADLINE_MS = 6_000;
const IMAGE_FETCH_MS = 2_000;
const MIN_IMAGE_BYTES = 1_024;
export const USER_AGENT = "EmblemApp/1.0 (https://github.com/kaanarici/emblem)";

const NON_PHOTO_ASSET =
  /(?:^|[/_. -])(flag|coat[ _-]?of[ _-]?arms|logo|seal|emblem|icon|symbol|diagram|wordmark|map)(?:[/_. ?&-]|$)|\.svg(?:\.png)?(?:\?|$)/i;

export function isLikelyPhotographURL(url: string): boolean {
  try {
    return !NON_PHOTO_ASSET.test(decodeURIComponent(url));
  } catch {
    return !NON_PHOTO_ASSET.test(url);
  }
}

const IMAGE_EXT = /\.(jpe?g|png|webp|avif|gif|bmp)(\?|$)/i;
const DYNAMIC_IMAGE = /\/is\/image\/|[?&](fmt|format)=(png|jpe?g)(?:[-&]|$)/i;
const IMAGE_CDN =
  /^https:\/\/(?:images|plus)\.unsplash\.com\/|^https:\/\/assets\.lummi\.ai\/assets\//i;
const JUNK_IMAGE = /\.svg(\?|$)|favicon|sprite|(?:^|[^a-z])icons?(?:[^a-z]|$)|1x1/i;
const LOGO_URL = /(?:^|[^a-z])(?:logos?|lockup|wordmark|brandmark)(?:[^a-z]|$)/i;

export function isWebImageCandidate(url: string, kind: string): boolean {
  return (
    url.startsWith("https") &&
    (IMAGE_EXT.test(url) || DYNAMIC_IMAGE.test(url) || IMAGE_CDN.test(url)) &&
    !JUNK_IMAGE.test(url) &&
    (kind === "logo" || !LOGO_URL.test(url)) &&
    (kind !== "photo" || isLikelyPhotographURL(url))
  );
}

export type ImagePlacement = "card" | "hero";

export function minimumShortEdge(kind: string, placement: ImagePlacement): number {
  if (kind === "logo") return 128;
  return placement === "hero" ? 600 : 320;
}

const WATERMARKED_HOST =
  /(?:^|\.)(?:shutterstock\.com|alamy\.[a-z.]+|gettyimages\.[a-z.]+|istockphoto\.com|dreamstime\.com|123rf\.com|depositphotos\.com|stock\.adobe\.com|ftcdn\.net|bigstockphoto\.com|canstockphoto\.[a-z.]+|agefotostock\.com|superstock\.com|pond5\.com|vectorstock\.com|pinimg\.com|pinterest\.[a-z.]+|encrypted-tbn\d*\.gstatic\.com|mm\.bing\.net)$/i;

function isAllowedImageSource(url: string): boolean {
  try {
    const { hostname, pathname } = new URL(url);
    return !WATERMARKED_HOST.test(hostname) && !/watermark/i.test(pathname);
  } catch {
    return false;
  }
}

const WIKIMEDIA_THUMB =
  /^https:\/\/(?:upload|thumb)\.wikimedia\.org\/(wikipedia\/[^/]+)\/thumb\/([0-9a-f]\/[0-9a-f]{2}\/[^/]+\.(?:jpe?g|png|webp|gif))\/(\d+)px-[^/?]+(?:\?.*)?$/i;
const SIZE_SUFFIX = /-\d{2,4}x\d{2,4}(\.(?:jpe?g|png|webp))$/i;
const SIZE_PARAMS = ["w", "h", "width", "height", "resize", "fit", "size"];
const FULL_SIZE_PX = 1280;

export function fullSizeVariants(url: string): string[] {
  const wikimedia = WIKIMEDIA_THUMB.exec(url);
  if (wikimedia) {
    return Number(wikimedia[3]) < FULL_SIZE_PX
      ? [`https://upload.wikimedia.org/${wikimedia[1]}/${wikimedia[2]}`, url]
      : [url];
  }
  const youtube =
    /^(https:\/\/i\.ytimg\.com\/vi\/[^/]+\/)(?:default|mqdefault|hqdefault|sddefault)\.jpg$/.exec(
      url,
    );
  if (youtube) return [`${youtube[1]}maxresdefault.jpg`, url];
  const original = new URL(url);
  original.pathname = original.pathname.replace(SIZE_SUFFIX, "$1");
  const thumbnailParam = SIZE_PARAMS.some((name) => {
    const value = original.searchParams.get(name);
    return value !== null && Number.parseInt(value, 10) < FULL_SIZE_PX;
  });
  if (thumbnailParam) SIZE_PARAMS.forEach((name) => original.searchParams.delete(name));
  return original.href === new URL(url).href ? [url] : [original.href, url];
}

function privateAddress(address: string): boolean {
  if (isIP(address) === 6) {
    return !/^[23]/i.test(address) || /^2001:db8:/i.test(address);
  }
  if (isIP(address) !== 4) return true;
  const [a, b] = address.split(".").map(Number);
  return (
    a === 0 ||
    a === 10 ||
    a === 127 ||
    a >= 224 ||
    (a === 100 && b >= 64 && b <= 127) ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && (b === 0 || b === 168)) ||
    (a === 198 && (b === 18 || b === 19))
  );
}

const publicLookup: LookupFunction = (hostname, options, callback) => {
  lookup(hostname, { all: true }, (error, addresses) => {
    if (error) return callback(error, "");
    if (!addresses.length || addresses.some(({ address }) => privateAddress(address))) {
      return callback(new Error("private image destination"), "");
    }
    if (options.all) callback(null, addresses);
    else callback(null, addresses[0].address, addresses[0].family);
  });
};

async function fetchPublicImage(
  input: string,
  init?: Pick<RequestInit, "signal">,
): Promise<Response> {
  let url = new URL(input);
  for (let redirects = 0; redirects <= 3; redirects++) {
    const host = url.hostname.replace(/^\[|\]$/g, "").replace(/\.$/, "");
    if (
      !["http:", "https:"].includes(url.protocol) ||
      url.username ||
      url.password ||
      host === "localhost" ||
      /\.(localhost|local|internal)$/i.test(host) ||
      (isIP(host) && privateAddress(host))
    )
      throw new Error("private image destination");
    const response = await new Promise<IncomingMessage>((resolve, reject) => {
      const request = (url.protocol === "https:" ? httpsRequest : httpRequest)(
        url,
        {
          agent: false,
          lookup: publicLookup,
          signal: init?.signal ?? undefined,
          headers: { "Accept-Encoding": "identity", "User-Agent": USER_AGENT },
        },
        resolve,
      );
      request.on("error", reject);
      request.end();
    });
    const status = response.statusCode ?? 502;
    if ([301, 302, 303, 307, 308].includes(status) && response.headers.location) {
      response.destroy();
      url = new URL(response.headers.location, url);
      continue;
    }
    try {
      if (Number(response.headers["content-length"]) > MAX_IMAGE_BYTES)
        throw new Error("image too large");
      const chunks: Buffer[] = [];
      let size = 0;
      for await (const chunk of response) {
        const bytes = Buffer.from(chunk);
        size += bytes.byteLength;
        if (size > MAX_IMAGE_BYTES) throw new Error("image too large");
        chunks.push(bytes);
      }
      return new Response([204, 205, 304].includes(status) ? null : Buffer.concat(chunks), {
        status,
        headers: { "Content-Type": String(response.headers["content-type"] ?? "") },
      });
    } finally {
      response.destroy();
    }
  }
  throw new Error("too many image redirects");
}

type Verdict = { url: string | null; verified: boolean; tried: number };

function matchesAspect(width: number, height: number, aspect?: ImageAspect): boolean {
  if (!aspect || width <= 0 || height <= 0) return true;
  const ratio = width / height;
  if (aspect === "portrait") return ratio < 0.9;
  if (aspect === "landscape") return ratio > 1.2;
  return ratio >= 0.75 && ratio <= 1.33;
}

function fitsAspect(width: number, height: number, aspect?: ImageAspect): boolean {
  if (aspect !== "square" || width <= 0 || height <= 0) return matchesAspect(width, height, aspect);
  const ratio = width / height;
  return ratio >= 0.5 && ratio <= 2;
}

const GRAPHIC_DOMINANT_SHARE = 0.4;
const PHOTO_MIN_COLORS = 120;

async function looksLikeGraphic(image: Buffer): Promise<boolean> {
  const { data } = await sharp(image)
    .flatten({ background: "#ffffff" })
    .resize(64, 64, { fit: "inside" })
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const counts = new Map<number, number>();
  for (let i = 0; i + 2 < data.length; i += 3) {
    const bucket = ((data[i] >> 3) << 10) | ((data[i + 1] >> 3) << 5) | (data[i + 2] >> 3);
    counts.set(bucket, (counts.get(bucket) ?? 0) + 1);
  }
  const dominant = Math.max(...counts.values()) / (data.length / 3);
  return dominant >= GRAPHIC_DOMINANT_SHARE || counts.size < PHOTO_MIN_COLORS;
}

export async function probeImageCandidates(
  candidates: string[],
  options: {
    aspect?: ImageAspect;
    photo?: boolean;
    minEdge?: number;
    signal?: AbortSignal;
    fetchImage?: typeof fetchPublicImage;
  } = {},
): Promise<Verdict> {
  const {
    aspect,
    photo = false,
    minEdge = minimumShortEdge("photo", "card"),
    signal: parentSignal,
    fetchImage = fetchPublicImage,
  } = options;
  const seen = new Set<string>();
  const unique = candidates
    .filter((u) => u && isAllowedImageSource(u))
    .flatMap(fullSizeVariants)
    .filter((u) => isAllowedImageSource(u) && !seen.has(u) && seen.add(u));
  if (unique.length === 0) return { url: null, verified: false, tried: 0 };

  const timeout = AbortSignal.timeout(PROBE_DEADLINE_MS);
  const completed = new AbortController();
  const signal = AbortSignal.any([
    completed.signal,
    timeout,
    ...(parentSignal ? [parentSignal] : []),
  ]);

  let tried = 0;
  let croppable: string | null = null;
  let usable: string | null = null;
  try {
    for (
      let start = 0;
      start < Math.min(unique.length, CANDIDATE_PROBES * PROBE_BATCHES) && !signal.aborted;
      start += CANDIDATE_PROBES
    ) {
      const eligible = unique.slice(start, start + CANDIDATE_PROBES);
      const probes = eligible.map(async (url) => {
        const result = await probeCandidate(url, signal, fetchImage, photo, minEdge);
        if (result !== null) tried++;
        return result;
      });
      for (const [index, probe] of probes.entries()) {
        const size = await probe;
        if (!size) continue;
        if (matchesAspect(size.width, size.height, aspect)) {
          return { url: eligible[index], verified: true, tried };
        }
        if (!croppable && fitsAspect(size.width, size.height, aspect)) croppable = eligible[index];
        usable ??= eligible[index];
      }
      if (croppable) return { url: croppable, verified: true, tried };
    }
    return { url: usable, verified: false, tried };
  } finally {
    completed.abort();
  }
}

async function probeCandidate(
  url: string,
  parentSignal: AbortSignal,
  fetchImage: typeof fetchPublicImage,
  photo: boolean,
  minEdge: number,
): Promise<{ width: number; height: number } | false | null> {
  try {
    const signal = AbortSignal.any([parentSignal, AbortSignal.timeout(IMAGE_FETCH_MS)]);
    const response = await fetchImage(url, { signal });
    if (!response.ok) return false;
    const rawType = response.headers.get("content-type")?.split(";", 1)[0].toLowerCase();
    if (!rawType?.startsWith("image/") || rawType === "image/svg+xml") return false;
    const declared = Number(response.headers.get("content-length") ?? 0);
    if (declared > MAX_IMAGE_BYTES) return false;
    const bytes = await response.arrayBuffer();
    if (bytes.byteLength < MIN_IMAGE_BYTES || bytes.byteLength > MAX_IMAGE_BYTES) return false;
    const image = Buffer.from(bytes);
    const metadata = await sharp(image).metadata();
    if (!["jpeg", "png", "webp", "avif", "gif", "heif", "tiff"].includes(metadata.format)) {
      return false;
    }
    if (Math.min(metadata.width, metadata.height) < minEdge) return false;
    if (photo && (await looksLikeGraphic(image))) return false;
    return metadata.autoOrient;
  } catch {
    return null;
  }
}
