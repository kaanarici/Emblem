import { createFal } from "@ai-sdk/fal";
import { generateImage } from "ai";

import { hasExpectedMagicBytes, MAX_IMAGE_BYTES } from "./imageBytes";

export type ImageProvider = "fal" | "gemini";

export type GeneratedImage = {
  bytes: Uint8Array;
  mimeType: "image/png" | "image/jpeg" | "image/webp";
};

export type DrawOptions = { signal: AbortSignal; fetch?: typeof fetch };

type ImageStore = {
  get(key: string, ownerScopeHash?: string): Promise<{ url: string } | null>;
  put(key: string, image: GeneratedImage, ownerScopeHash?: string): Promise<void>;
};

export type GenerationJob = {
  key: string;
  ownerScopeHash?: string;
  store: ImageStore;
  admit: (key: string) => Promise<boolean>;
  draw: (provider: ImageProvider, options: DrawOptions) => Promise<GeneratedImage>;
  deadlineMs?: number;
  signal?: AbortSignal;
  fetch?: typeof fetch;
};

const GEMINI_IMAGE_MODEL = "gemini-3.1-flash-lite-image";
const GEMINI_IMAGE_ENDPOINT = `https://generativelanguage.googleapis.com/v1/models/${GEMINI_IMAGE_MODEL}:generateContent`;
const FAL_IMAGE_MODEL = "fal-ai/flux-2/flash";
const FAL_CUTOUT_MODEL = "fal-ai/birefnet/v2";
const DEFAULT_DEADLINE_MS = 25_000;
const inFlight = new Map<string, Promise<boolean>>();

const falKey = () => process.env.FAL_KEY?.trim();
const geminiKey = () => process.env.GEMINI_API_KEY?.trim();

export function imageProvider(): ImageProvider | null {
  const chosen = process.env.IMAGE_PROVIDER?.trim();
  const available = { fal: Boolean(falKey()), gemini: Boolean(geminiKey()) };
  if (chosen === "fal" || chosen === "gemini") return available[chosen] ? chosen : null;
  if (available.fal) return "fal";
  return available.gemini ? "gemini" : null;
}

export async function generateOnce(job: GenerationJob): Promise<boolean> {
  let pending = inFlight.get(job.key);
  if (!pending) {
    pending = (async () => {
      if (await job.store.get(job.key, job.ownerScopeHash)) return true;
      const provider = imageProvider();
      if (!provider || !(await job.admit(job.key))) return false;
      const deadline = AbortSignal.timeout(job.deadlineMs ?? DEFAULT_DEADLINE_MS);
      const signal = job.signal ? AbortSignal.any([job.signal, deadline]) : deadline;
      const image = await job.draw(provider, { signal, fetch: job.fetch });
      await job.store.put(job.key, image, job.ownerScopeHash);
      return true;
    })().catch(() => false);
    inFlight.set(job.key, pending);
  }
  try {
    return await pending;
  } finally {
    if (inFlight.get(job.key) === pending) inFlight.delete(job.key);
  }
}

export async function drawFal(
  prompt: string,
  size: `${number}x${number}`,
  options: DrawOptions,
): Promise<Uint8Array> {
  return falImage(FAL_IMAGE_MODEL, prompt, options, size, { enablePromptExpansion: false });
}

export async function cutoutFal(image: Uint8Array, options: DrawOptions): Promise<Uint8Array> {
  return falImage(FAL_CUTOUT_MODEL, { images: [image] }, options);
}

async function falImage(
  model: string,
  prompt: string | { images: Uint8Array[] },
  options: DrawOptions,
  size?: `${number}x${number}`,
  extra: Record<string, boolean> = {},
): Promise<Uint8Array> {
  const fal = createFal({ apiKey: falKey(), fetch: options.fetch });
  const { image } = await generateImage({
    model: fal.image(model),
    prompt,
    ...(size ? { size } : {}),
    providerOptions: { fal: { outputFormat: "png", syncMode: true, ...extra } },
    maxRetries: 0,
    abortSignal: options.signal,
  });
  return image.uint8Array;
}

export async function drawGemini(prompt: string, options: DrawOptions): Promise<GeneratedImage> {
  const response = await (options.fetch ?? fetch)(GEMINI_IMAGE_ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": geminiKey() ?? "",
    },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: {
        responseModalities: ["IMAGE"],
        imageConfig: { aspectRatio: "1:1", imageSize: "1K" },
      },
    }),
    signal: options.signal,
  });
  if (!response.ok) {
    throw new Error(`Gemini image generation failed (${response.status})`);
  }
  const image = inlineImage(await response.json());
  if (!image) throw new Error("Gemini image generation returned no image");
  return image;
}

export function isSupportedMimeType(value: unknown): value is GeneratedImage["mimeType"] {
  return value === "image/png" || value === "image/jpeg" || value === "image/webp";
}

function inlineImage(payload: unknown): GeneratedImage | null {
  if (!payload || typeof payload !== "object") return null;
  const candidates = (payload as { candidates?: unknown }).candidates;
  if (!Array.isArray(candidates)) return null;
  for (const candidate of candidates) {
    if (!candidate || typeof candidate !== "object") continue;
    const content = (candidate as { content?: unknown }).content;
    if (!content || typeof content !== "object") continue;
    const parts = (content as { parts?: unknown }).parts;
    if (!Array.isArray(parts)) continue;
    for (const part of parts) {
      if (!part || typeof part !== "object") continue;
      const inlineData =
        (part as { inlineData?: unknown }).inlineData ??
        (part as { inline_data?: unknown }).inline_data;
      if (!inlineData || typeof inlineData !== "object") continue;
      const mimeType =
        (inlineData as { mimeType?: unknown }).mimeType ??
        (inlineData as { mime_type?: unknown }).mime_type;
      const data = (inlineData as { data?: unknown }).data;
      if (!isSupportedMimeType(mimeType) || typeof data !== "string") continue;
      const compact = data.replace(/\s+/g, "");
      if (
        !compact ||
        compact.length > Math.ceil((MAX_IMAGE_BYTES * 4) / 3) + 4 ||
        !/^[A-Za-z0-9+/]*={0,2}$/.test(compact)
      ) {
        continue;
      }
      const bytes = new Uint8Array(Buffer.from(compact, "base64"));
      const image = { bytes, mimeType };
      if (
        bytes.byteLength > 0 &&
        bytes.byteLength <= MAX_IMAGE_BYTES &&
        hasExpectedMagicBytes(image.bytes, image.mimeType)
      ) {
        return image;
      }
    }
  }
  return null;
}
