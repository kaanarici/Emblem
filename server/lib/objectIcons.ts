import { createHash } from "node:crypto";
import { createFal } from "@ai-sdk/fal";
import { generateImage } from "ai";
import sharp from "sharp";

import { objectIconNoun } from "./objectIconNoun";
import {
  generateGeminiImage,
  generatedStepImageStore,
  generatedStepImageURL,
  type GeneratedStepImage,
  type GeneratedStepImageStore,
} from "./generatedStepImages";

const OBJECT_ICON_VERSION = "object-icon-v3";

const ICON_SIZE = 256;
const WORK_SIZE = ICON_SIZE * 2;
const DEADLINE_MS = 25_000;
const inFlight = new Map<string, Promise<string | null>>();

const iconStyle = (noun: string) =>
  `A single 3D icon of ${noun}, matching a premium soft-3D emoji icon set. ` +
  "Slightly chunky, simplified toy-like proportions with generously rounded, softened edges, like a high-end 3D emoji, not a photoreal product render. " +
  "Matte clay-plastic surfaces with restrained realistic detail; subtle gloss only where the real material is metal, glass, or liquid. " +
  "Soft diffuse studio light from the upper left, gentle ambient occlusion baked into the object itself, warm muted natural palette, no outlines. " +
  "Three-quarter view seen slightly from above, one single object group centered, filling about 82 percent of the square frame. ";
const ICON_TAIL = "No text, no label, no logo, no watermark, no border.";

const GEMINI_ICON_PROMPT = (noun: string) =>
  iconStyle(noun) +
  "If the subject is a powder, granule, liquid, paste, or other shapeless substance, show a small recognizable amount of it in or spilling from one simple neutral container (small sack, bowl, spoon, or cracked shell) so the substance itself is clearly visible, never an unlabeled closed container alone. " +
  "Place the object on an exact solid pure magenta #FF00FF chroma-key background touching all four edges. The background must be one perfectly uniform color with no cast shadow, contact shadow, reflection, gradient, vignette, texture, floor line, lighting variation, or environment. " +
  "Keep #FF00FF and all close magenta, fuchsia, and hot-pink colors completely out of the object. Keep the complete object crisply separated from the background with generous clear padding and no cropping. " +
  ICON_TAIL;

const FAL_ICON_PROMPT = (noun: string) =>
  iconStyle(noun) +
  `Depict exactly "${noun}". When "${noun}" is a loose substance such as flour, sugar, ground spice or oil, show it in its typical simple package; never add bowls, spoons, plates or other props to a solid object. ` +
  "Place the object alone on a plain, flat, pure white background with no cast shadow, contact shadow, reflection, gradient, floor line or environment. " +
  "Keep the complete object crisply separated from the background with generous clear padding and no cropping. " +
  ICON_TAIL;

type GenerateOptions = { deadlineMs: number; signal?: AbortSignal; fetch?: typeof fetch };
type ObjectIconGenerator = {
  available: () => boolean;
  generate: (noun: string, options: GenerateOptions) => Promise<GeneratedStepImage>;
};

const falKey = () => (process.env.FAL_KEY ?? process.env.FAL_API_KEY)?.trim();

const generators: Record<"gemini" | "fal", ObjectIconGenerator> = {
  gemini: {
    available: () => Boolean(process.env.GEMINI_API_KEY?.trim()),
    generate: async (noun, options) =>
      removeMagentaBackground(
        await generateGeminiImage(GEMINI_ICON_PROMPT(noun), {
          ...options,
          apiKey: process.env.GEMINI_API_KEY!.trim(),
        }),
      ),
  },
  fal: {
    available: () => Boolean(falKey()),
    generate: async (noun, { deadlineMs, signal }) => {
      const abortSignal = signal
        ? AbortSignal.any([signal, AbortSignal.timeout(deadlineMs)])
        : AbortSignal.timeout(deadlineMs);
      const fal = createFal({ apiKey: falKey() });
      const { image } = await generateImage({
        model: fal.image("fal-ai/flux-2/flash"),
        prompt: FAL_ICON_PROMPT(noun),
        size: "512x512",
        providerOptions: {
          fal: { outputFormat: "png", syncMode: true, enablePromptExpansion: false },
        },
        maxRetries: 0,
        abortSignal,
      });
      const { image: cutout } = await generateImage({
        model: fal.image("fal-ai/birefnet/v2"),
        prompt: { images: [image.uint8Array] },
        providerOptions: { fal: { outputFormat: "png", syncMode: true } },
        maxRetries: 0,
        abortSignal,
      });
      const bytes = await sharp(Buffer.from(cutout.uint8Array))
        .resize(ICON_SIZE, ICON_SIZE, {
          fit: "contain",
          background: { r: 0, g: 0, b: 0, alpha: 0 },
        })
        .png()
        .toBuffer();
      return { bytes: new Uint8Array(bytes), mimeType: "image/png" };
    },
  },
};

function objectIconGenerator(): ObjectIconGenerator {
  const chosen = process.env.OBJECT_ICON_PROVIDER?.trim();
  if (chosen === "fal" || chosen === "gemini") return generators[chosen];
  return generators.fal.available() ? generators.fal : generators.gemini;
}

type ResolveObjectIconOptions = {
  store?: GeneratedStepImageStore;
  fetch?: typeof fetch;
  deadlineMs?: number;
  signal?: AbortSignal;
};

export function objectIconGenerationAvailable(): boolean {
  return Boolean(
    objectIconGenerator().available() &&
    process.env.NEXT_PUBLIC_CONVEX_URL &&
    process.env.GENERATED_STEP_IMAGE_STORAGE_SECRET,
  );
}

export async function cachedObjectIconURL(
  query: string,
  store?: GeneratedStepImageStore,
): Promise<string | null> {
  const noun = objectIconNoun(query);
  if (!noun) return null;
  if (!process.env.NEXT_PUBLIC_CONVEX_URL || !process.env.GENERATED_STEP_IMAGE_STORAGE_SECRET)
    return null;
  const cacheKey = createHash("sha256").update(`${OBJECT_ICON_VERSION}\0${noun}`).digest("hex");
  return (await (store ?? generatedStepImageStore).get(cacheKey))?.url ?? null;
}

export async function resolveObjectIconQuery(
  query: string,
  options: ResolveObjectIconOptions = {},
): Promise<string | null> {
  const noun = objectIconNoun(query);
  if (!noun) return null;
  if (
    !options.store &&
    (!process.env.NEXT_PUBLIC_CONVEX_URL || !process.env.GENERATED_STEP_IMAGE_STORAGE_SECRET)
  ) {
    return null;
  }

  const cacheKey = createHash("sha256").update(`${OBJECT_ICON_VERSION}\0${noun}`).digest("hex");
  const store = options.store ?? generatedStepImageStore;
  let pending = inFlight.get(cacheKey);
  if (!pending) {
    pending = (async () => {
      const cached = await store.get(cacheKey);
      if (cached) return cached.url;

      const generator = objectIconGenerator();
      if (!generator.available()) return null;
      const generated = await generator.generate(noun, {
        fetch: options.fetch,
        deadlineMs: options.deadlineMs ?? DEADLINE_MS,
        signal: options.signal,
      });
      await store.put(cacheKey, generated);
      try {
        const stored = await store.get(cacheKey);
        if (stored) return stored.url;
      } catch {}
      return generatedStepImageURL(cacheKey);
    })();
    inFlight.set(cacheKey, pending);
  }

  try {
    return await pending;
  } catch {
    return null;
  } finally {
    if (inFlight.get(cacheKey) === pending) inFlight.delete(cacheKey);
  }
}

async function removeMagentaBackground(image: GeneratedStepImage): Promise<GeneratedStepImage> {
  const { data, info } = await sharp(Buffer.from(image.bytes))
    .resize(WORK_SIZE, WORK_SIZE, { fit: "cover" })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const { width, height } = info;
  for (let index = 0; index < width * height; index++) {
    const offset = index * 4;
    const red = data[offset]!;
    const green = data[offset + 1]!;
    const blue = data[offset + 2]!;
    const magentaDominance = Math.min(red, blue) - green;
    if (red > 235 && blue > 235 && green < 55) {
      data[offset] = 0;
      data[offset + 1] = 0;
      data[offset + 2] = 0;
      data[offset + 3] = 0;
      continue;
    }
    if (magentaDominance <= 120 || red <= 170 || blue <= 170) continue;

    const alpha = Math.max(
      0,
      Math.min(255, Math.round(255 * (1 - (magentaDominance - 120) / 100))),
    );
    const neutral = Math.max(green, Math.floor(Math.min(red, blue) / 2));
    data[offset] = Math.min(red, neutral + 28);
    data[offset + 2] = Math.min(blue, neutral + 18);
    data[offset + 3] = alpha;
  }

  const resized = await sharp(data, {
    raw: { width, height, channels: 4 },
  })
    .resize(ICON_SIZE, ICON_SIZE, { kernel: "lanczos3" })
    .raw()
    .toBuffer({ resolveWithObject: true });
  despillMagentaEdges(resized.data);
  removeFaintResidue(resized.data, resized.info.width, resized.info.height);

  const bytes = await sharp(resized.data, {
    raw: {
      width: resized.info.width,
      height: resized.info.height,
      channels: 4,
    },
  })
    .png()
    .toBuffer();
  return { bytes: new Uint8Array(bytes), mimeType: "image/png" };
}

function despillMagentaEdges(data: Buffer): void {
  for (let offset = 0; offset < data.length; offset += 4) {
    const red = data[offset]!;
    const green = data[offset + 1]!;
    const blue = data[offset + 2]!;
    let alpha = data[offset + 3]!;
    if (alpha === 0) {
      data[offset] = 0;
      data[offset + 1] = 0;
      data[offset + 2] = 0;
      continue;
    }

    const spill = Math.min(red, blue) - green;
    if (spill <= 12 || red < 45 || blue < 45) continue;
    data[offset] = Math.max(0, red - spill);
    data[offset + 2] = Math.max(0, blue - spill);
    if (spill >= 160) alpha = 0;
    else if (spill > 24) {
      alpha = Math.round(alpha * Math.max(0.15, 1 - (spill - 24) / 170));
    }
    if (alpha <= 1) {
      data[offset] = 0;
      data[offset + 1] = 0;
      data[offset + 2] = 0;
      data[offset + 3] = 0;
    } else {
      data[offset + 3] = alpha;
    }
  }
}

function removeFaintResidue(data: Buffer, width: number, height: number): number {
  if (data.length !== width * height * 4) return 0;
  let cleared = 0;
  const alpha = (pixel: number) => data[pixel * 4 + 3]!;
  const clear = (pixel: number) => {
    if (alpha(pixel) > 0) cleared++;
    data.fill(0, pixel * 4, pixel * 4 + 4);
  };
  for (let pixel = 0; pixel < width * height; pixel++) if (alpha(pixel) <= 8) clear(pixel);

  const visited = new Uint8Array(width * height);
  for (let seed = 0; seed < width * height; seed++) {
    if (visited[seed] || alpha(seed) === 0) continue;
    const component = [seed];
    visited[seed] = 1;
    let maxAlpha = 0;
    for (let cursor = 0; cursor < component.length; cursor++) {
      const pixel = component[cursor]!;
      maxAlpha = Math.max(maxAlpha, alpha(pixel));
      const x = pixel % width;
      const y = Math.floor(pixel / width);
      for (let yy = Math.max(0, y - 1); yy <= Math.min(height - 1, y + 1); yy++) {
        for (let xx = Math.max(0, x - 1); xx <= Math.min(width - 1, x + 1); xx++) {
          const neighbor = yy * width + xx;
          if (!visited[neighbor] && alpha(neighbor) > 0) {
            visited[neighbor] = 1;
            component.push(neighbor);
          }
        }
      }
    }
    if (maxAlpha < 64) for (const pixel of component) clear(pixel);
  }

  for (let y = height - 1; y >= Math.max(0, height - 40); y--) {
    let covered = 0;
    for (let x = 0; x < width; x++) if (alpha(y * width + x) > 0) covered++;
    if (covered <= width * 0.6) break;
    for (let x = 0; x < width; x++) if (alpha(y * width + x) < 64) clear(y * width + x);
  }
  return cleared;
}
