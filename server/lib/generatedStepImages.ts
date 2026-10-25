import { createCipheriv, createDecipheriv, createHash, createHmac } from "node:crypto";
import { ConvexHttpClient } from "convex/browser";
import sharp from "sharp";

import { api } from "@/convex/_generated/api";
import type { Block } from "./schema";
import { ownerScopeInput } from "./signing";
import { hasExpectedMagicBytes, MAX_IMAGE_BYTES } from "./imageBytes";

const GENERATED_STEP_IMAGE_QUERY_PREFIX = "emblem-step-image.v1.";
const GENERATED_STEP_IMAGE_STYLE_VERSION = "instructional-3d-v4";

const GEMINI_IMAGE_MODEL = "gemini-3.1-flash-lite-image";
const GEMINI_IMAGE_ENDPOINT = `https://generativelanguage.googleapis.com/v1/models/${GEMINI_IMAGE_MODEL}:generateContent`;
const DEFAULT_GENERATION_DEADLINE_MS = 25_000;
const STORED_IMAGE_SIZE = 768;
const DEFAULT_VISUAL_CONTINUITY =
  "keep the same physical subject, tools, materials, proportions, camera position, and accumulated construction state across the sequence";
const PRIVATE_VISUAL_PATTERN =
  /(?:https?:\/\/|www\.|[\w.+-]+@[\w.-]+\.[a-z]{2,}|@\w{2,}|\+?\d[\d\s().-]{7,}\d|\b(?:api[ _-]?key|password|secret|access[ _-]?token)\b)/i;
const PERSONAL_REFERENCE_PATTERN = /\b(?:my|our|mine|ours)\b/i;
const HEX_KEY = /^[a-f0-9]{64}$/;
const inFlight = new Map<string, Promise<void>>();

type GeneratedStepDescriptor = {
  version: typeof GENERATED_STEP_IMAGE_STYLE_VERSION;
  cacheKey: string;
  ownerScopeHash: string;
  scene: string;
  continuity: string;
};

export type GeneratedStepImage = {
  bytes: Uint8Array;
  mimeType: "image/png" | "image/jpeg" | "image/webp";
};

type StoredGeneratedStepImage = {
  url: string;
  mimeType: GeneratedStepImage["mimeType"];
  byteLength: number;
};

export type GeneratedStepImageStore = {
  get(key: string, ownerScopeHash?: string): Promise<StoredGeneratedStepImage | null>;
  put(key: string, image: GeneratedStepImage, ownerScopeHash?: string): Promise<void>;
};

type PrepareGeneratedStepImagesOptions = {
  ownerScope: string;
  tokenSecret: string;
};

type ResolveGeneratedStepImageOptions = {
  tokenSecret?: string;
  apiKey?: string;
  store?: GeneratedStepImageStore;
  fetch?: typeof fetch;
  deadlineMs?: number;
  signal?: AbortSignal;
};

export function prepareGeneratedStepImages(
  blocks: readonly Block[],
  options: PrepareGeneratedStepImagesOptions,
): Block[] {
  const ownerScope = options.ownerScope.trim();
  const tokenSecret = options.tokenSecret.trim();
  if (!ownerScope) throw new Error("generated step images require an owner scope");
  if (!tokenSecret) throw new Error("generated step images require a token secret");

  const ownerScopeHash = sha256(ownerScopeInput(ownerScope));
  return blocks.map((block): Block => {
    if (block.type !== "stepCarousel") return block;
    const continuity =
      safeVisualPhrase(block.continuity) ??
      (block.continuity == null ? DEFAULT_VISUAL_CONTINUITY : null);
    if (!continuity) return block;

    return {
      ...block,
      steps: block.steps.map((step) => {
        if (step.icon?.image?.kind === "photo") return step;
        const authoredScene = step.imageScene == null ? null : safeVisualPhrase(step.imageScene);
        if (step.imageScene != null && !authoredScene) return step;
        const scene = literalStepScene(step.title, step.body, authoredScene);
        if (!scene) return step;
        const descriptor = descriptorFor(scene, continuity, ownerScopeHash);
        return {
          ...step,
          icon: {
            ...step.icon,
            sym: step.icon?.sym ?? step.sym,
            image: {
              query: sealDescriptor(descriptor, tokenSecret),
              kind: "generated" as const,
              aspect: "square" as const,
            },
          },
        };
      }),
    };
  });
}

export function prepareDraftStepImages(
  block: Block,
  options: PrepareGeneratedStepImagesOptions,
): Block {
  if (block.type !== "stepCarousel" || block.steps.length < 2) return block;
  const [prepared] = prepareGeneratedStepImages(
    [{ ...block, steps: block.steps.slice(0, -1) }],
    options,
  );
  if (prepared?.type !== "stepCarousel") return block;
  return { ...block, steps: [...prepared.steps, block.steps.at(-1)!] };
}

export function isGeneratedStepImageQuery(query: string): boolean {
  return query.startsWith(GENERATED_STEP_IMAGE_QUERY_PREFIX);
}

export function generatedStepImageURL(cacheKey: string): string {
  if (!HEX_KEY.test(cacheKey)) throw new Error("invalid generated image key");
  return `/api/generated-step-image?key=${cacheKey}`;
}

export async function resolveGeneratedStepImageQuery(
  query: string,
  options: ResolveGeneratedStepImageOptions = {},
): Promise<string | null> {
  if (!isGeneratedStepImageQuery(query)) return null;
  const tokenSecret = options.tokenSecret ?? generatedStepImageTokenSecret();
  const apiKey = options.apiKey ?? process.env.GEMINI_API_KEY;
  if (!tokenSecret || !apiKey) return null;
  if (
    !options.store &&
    (!process.env.NEXT_PUBLIC_CONVEX_URL || !process.env.GENERATED_STEP_IMAGE_STORAGE_SECRET)
  ) {
    return null;
  }

  const descriptor = openDescriptor(query, tokenSecret);
  if (!descriptor) return null;
  const store = options.store ?? generatedStepImageStore;
  if (await store.get(descriptor.cacheKey, descriptor.ownerScopeHash)) {
    return generatedStepImageURL(descriptor.cacheKey);
  }

  let pending = inFlight.get(descriptor.cacheKey);
  if (!pending) {
    pending = generateAndStore(descriptor, {
      apiKey,
      store,
      fetch: options.fetch ?? fetch,
      deadlineMs: options.deadlineMs ?? DEFAULT_GENERATION_DEADLINE_MS,
      signal: options.signal,
    });
    inFlight.set(descriptor.cacheKey, pending);
  }

  try {
    await pending;
    return generatedStepImageURL(descriptor.cacheKey);
  } catch {
    return null;
  } finally {
    if (inFlight.get(descriptor.cacheKey) === pending) {
      inFlight.delete(descriptor.cacheKey);
    }
  }
}

export async function readGeneratedStepImage(
  cacheKey: string,
  store: GeneratedStepImageStore = generatedStepImageStore,
): Promise<StoredGeneratedStepImage | null> {
  if (!HEX_KEY.test(cacheKey)) return null;
  return await store.get(cacheKey);
}

async function generateGeminiStepImage(
  scene: string,
  continuity: string,
  options: {
    apiKey: string;
    fetch?: typeof fetch;
    deadlineMs?: number;
    signal?: AbortSignal;
  },
): Promise<GeneratedStepImage> {
  return generateGeminiImage(styledPrompt(scene, continuity), options);
}

export async function generateGeminiImage(
  prompt: string,
  options: {
    apiKey: string;
    fetch?: typeof fetch;
    deadlineMs?: number;
    signal?: AbortSignal;
  },
): Promise<GeneratedStepImage> {
  const deadline = AbortSignal.timeout(options.deadlineMs ?? DEFAULT_GENERATION_DEADLINE_MS);
  const signal = options.signal ? AbortSignal.any([options.signal, deadline]) : deadline;
  const response = await (options.fetch ?? fetch)(GEMINI_IMAGE_ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": options.apiKey,
    },
    body: JSON.stringify({
      contents: [
        {
          role: "user",
          parts: [{ text: prompt }],
        },
      ],
      generationConfig: {
        responseModalities: ["IMAGE"],
        imageConfig: {
          aspectRatio: "1:1",
          imageSize: "1K",
        },
      },
    }),
    signal,
  });
  if (!response.ok) {
    throw new Error(`Gemini image generation failed (${response.status})`);
  }

  const payload: unknown = await response.json();
  const image = inlineImage(payload);
  if (!image) throw new Error("Gemini image generation returned no image");
  return image;
}

export const generatedStepImageStore: GeneratedStepImageStore = {
  async get(key, ownerScopeHash) {
    if (!HEX_KEY.test(key)) return null;
    try {
      const client = generatedImageConvexClient();
      const secret = process.env.GENERATED_STEP_IMAGE_STORAGE_SECRET?.trim();
      if (!client || !secret) return null;
      const readGrant = createHmac("sha256", secret)
        .update(["read-generated-image-v1", key, ownerScopeHash ?? ""].join("\0"))
        .digest("hex");
      const stored = await client.query(api.generatedImages.get, {
        key,
        ...(ownerScopeHash === undefined ? {} : { ownerScopeHash }),
        readGrant,
      });
      if (
        !stored ||
        !isSupportedMimeType(stored.mimeType) ||
        !Number.isSafeInteger(stored.byteLength) ||
        stored.byteLength <= 0 ||
        stored.byteLength > MAX_IMAGE_BYTES ||
        !safeHTTPURL(stored.url)
      ) {
        return null;
      }
      return {
        url: stored.url,
        mimeType: stored.mimeType,
        byteLength: stored.byteLength,
      };
    } catch {
      return null;
    }
  },

  async put(key, image, ownerScopeHash = "shared") {
    if (!HEX_KEY.test(key)) throw new Error("invalid generated image key");
    if (
      !hasExpectedMagicBytes(image.bytes, image.mimeType) ||
      image.bytes.byteLength <= 0 ||
      image.bytes.byteLength > MAX_IMAGE_BYTES
    ) {
      throw new Error("invalid generated image bytes");
    }
    const client = generatedImageConvexClient();
    const storageSecret = process.env.GENERATED_STEP_IMAGE_STORAGE_SECRET?.trim();
    if (!client || !storageSecret) {
      throw new Error("generated image storage is not configured");
    }
    const data = Buffer.from(image.bytes).toString("base64");
    const digest = createHash("sha256").update(image.bytes).digest("hex");
    const writeGrant = createHmac("sha256", storageSecret)
      .update(
        storageGrantPayload(ownerScopeHash, key, image.mimeType, image.bytes.byteLength, digest),
      )
      .digest("hex");
    await client.action(api.generatedImages.store, {
      key,
      ownerScopeHash,
      mimeType: image.mimeType,
      byteLength: image.bytes.byteLength,
      digest,
      data,
      writeGrant,
    });
  },
};

export function generatedStepImageTokenSecret(): string | undefined {
  return process.env.GENERATED_STEP_IMAGE_TOKEN_SECRET?.trim() || undefined;
}

function safeVisualPhrase(value: string | undefined): string | null {
  if (value == null) return null;
  const normalized = value.trim().replace(/\s+/g, " ");
  if (normalized.length < 1 || normalized.length > 160) return null;
  if (/[\r\n\t\u0000-\u001f\u007f]/.test(value)) return null;
  if (PRIVATE_VISUAL_PATTERN.test(normalized) || PERSONAL_REFERENCE_PATTERN.test(normalized)) {
    return null;
  }
  return normalized.toLocaleLowerCase("en-US");
}

function literalStepScene(
  title: string,
  body: string,
  authoredScene: string | null,
): string | null {
  const instruction = [title, body]
    .map((value) => value.trim())
    .filter(Boolean)
    .join(". ");
  if (PRIVATE_VISUAL_PATTERN.test(instruction) || PERSONAL_REFERENCE_PATTERN.test(instruction)) {
    return null;
  }
  const combined = [instruction, authoredScene ? `Visible details: ${authoredScene}` : ""]
    .filter(Boolean)
    .join(". ")
    .replace(/\s+/g, " ")
    .trim();
  const clipped =
    combined.length <= 160
      ? combined
      : combined
          .slice(0, 160)
          .replace(/\s+\S*$/, "")
          .replace(/[.,;:!?-]+$/, "");
  return safeVisualPhrase(clipped);
}

function descriptorFor(
  scene: string,
  continuity: string,
  ownerScopeHash: string,
): GeneratedStepDescriptor {
  const cacheKey = sha256(
    [GENERATED_STEP_IMAGE_STYLE_VERSION, ownerScopeHash, continuity, scene].join("\0"),
  );
  return {
    version: GENERATED_STEP_IMAGE_STYLE_VERSION,
    cacheKey,
    ownerScopeHash,
    scene,
    continuity,
  };
}

function sealDescriptor(descriptor: GeneratedStepDescriptor, tokenSecret: string): string {
  const plaintext = Buffer.from(JSON.stringify(descriptor));
  const { encryptionKey, nonceKey } = sealingKeys(tokenSecret);
  const iv = createHmac("sha256", nonceKey).update(plaintext).digest().subarray(0, 12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey, iv);
  cipher.setAAD(Buffer.from(GENERATED_STEP_IMAGE_QUERY_PREFIX));
  const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const envelope = Buffer.concat([iv, encrypted, cipher.getAuthTag()]);
  return GENERATED_STEP_IMAGE_QUERY_PREFIX + envelope.toString("base64url");
}

function openDescriptor(query: string, tokenSecret: string): GeneratedStepDescriptor | null {
  try {
    const encoded = query.slice(GENERATED_STEP_IMAGE_QUERY_PREFIX.length);
    if (!encoded || !/^[A-Za-z0-9_-]+$/.test(encoded)) return null;
    const envelope = Buffer.from(encoded, "base64url");
    if (envelope.byteLength < 29 || envelope.byteLength > 2_048) return null;
    const iv = envelope.subarray(0, 12);
    const tag = envelope.subarray(envelope.byteLength - 16);
    const encrypted = envelope.subarray(12, envelope.byteLength - 16);
    const { encryptionKey } = sealingKeys(tokenSecret);
    const decipher = createDecipheriv("aes-256-gcm", encryptionKey, iv);
    decipher.setAAD(Buffer.from(GENERATED_STEP_IMAGE_QUERY_PREFIX));
    decipher.setAuthTag(tag);
    const plaintext = Buffer.concat([decipher.update(encrypted), decipher.final()]);
    const value: unknown = JSON.parse(plaintext.toString("utf8"));
    if (!value || typeof value !== "object") return null;
    const candidate = value as Partial<GeneratedStepDescriptor>;
    if (
      candidate.version !== GENERATED_STEP_IMAGE_STYLE_VERSION ||
      typeof candidate.cacheKey !== "string" ||
      typeof candidate.ownerScopeHash !== "string" ||
      typeof candidate.scene !== "string" ||
      typeof candidate.continuity !== "string" ||
      !HEX_KEY.test(candidate.cacheKey) ||
      !HEX_KEY.test(candidate.ownerScopeHash)
    ) {
      return null;
    }
    const scene = safeVisualPhrase(candidate.scene);
    const continuity = safeVisualPhrase(candidate.continuity);
    if (!scene || !continuity) return null;
    const verified = descriptorFor(scene, continuity, candidate.ownerScopeHash);
    return verified.cacheKey === candidate.cacheKey ? verified : null;
  } catch {
    return null;
  }
}

function sealingKeys(tokenSecret: string): {
  encryptionKey: Buffer;
  nonceKey: Buffer;
} {
  const material = createHash("sha512")
    .update("emblem-generated-step-image-token-v1\0")
    .update(tokenSecret)
    .digest();
  return {
    encryptionKey: material.subarray(0, 32),
    nonceKey: material.subarray(32),
  };
}

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function styledPrompt(scene: string, continuity: string): string {
  return [
    "A square editorial 3D instructional illustration with softly rounded forms and clean realistic materials.",
    "Depict a real working scene at real-world scale. Keep every hand, tool, ingredient, building part, and object in believable relative proportion.",
    "Use a clean warm-ivory environment or seamless background, with the subject filling the frame at a useful close or medium instructional view.",
    `Exact procedure to depict: ${scene}.`,
    `Sequence continuity: ${continuity}.`,
    "Show the exact physical working state after earlier steps and the visible change this action makes.",
    "Include a hand only when a hand must actively hold or manipulate the named tool, ingredient, or part to demonstrate this exact action. Otherwise show no hand.",
    "For food, show every named ingredient in its usable state inside the actual bowl, pan, or tray at this stage and place the required utensil in contact with the mixture. Eggs must be cracked with visible yolk or white where appropriate; never put whole shell-on eggs into batter. Remove shells, wrappers, lids, and packaging unless the step explicitly handles them.",
    "For construction, show full-scale structural parts attached to the real structure at this stage. A fastener must physically pass through the named parts, the tool must engage that fastener correctly, and joints and alignment must be mechanically plausible.",
    "Never replace the procedure with a symbol, icon, badge, metaphor, mood, theme, diagram, decorative arrangement, tabletop model, clipboard, or magnifying glass unless the instruction explicitly requires that object.",
    "High-key diffuse studio light, subtle natural shadow, restrained warm palette, consistent three-quarter camera, one action only.",
    "No text, no logo, no watermark, no border, no clutter.",
  ].join(" ");
}

async function generateAndStore(
  descriptor: GeneratedStepDescriptor,
  options: {
    apiKey: string;
    store: GeneratedStepImageStore;
    fetch: typeof fetch;
    deadlineMs: number;
    signal?: AbortSignal;
  },
): Promise<void> {
  const image = await generateGeminiStepImage(descriptor.scene, descriptor.continuity, options);
  await options.store.put(
    descriptor.cacheKey,
    await compactStepImage(image),
    descriptor.ownerScopeHash,
  );
}

async function compactStepImage(image: GeneratedStepImage): Promise<GeneratedStepImage> {
  try {
    const bytes = await sharp(Buffer.from(image.bytes))
      .resize(STORED_IMAGE_SIZE, STORED_IMAGE_SIZE, { fit: "inside", withoutEnlargement: true })
      .jpeg({ quality: 82, mozjpeg: true })
      .toBuffer();
    return bytes.byteLength < image.bytes.byteLength
      ? { bytes: new Uint8Array(bytes), mimeType: "image/jpeg" }
      : image;
  } catch {
    return image;
  }
}

function inlineImage(payload: unknown): GeneratedStepImage | null {
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

function isSupportedMimeType(value: unknown): value is GeneratedStepImage["mimeType"] {
  return value === "image/png" || value === "image/jpeg" || value === "image/webp";
}

function generatedImageConvexClient(): ConvexHttpClient | null {
  const convexURL = process.env.NEXT_PUBLIC_CONVEX_URL?.trim();
  return convexURL ? new ConvexHttpClient(convexURL) : null;
}

function storageGrantPayload(
  ownerScopeHash: string,
  key: string,
  mimeType: GeneratedStepImage["mimeType"],
  byteLength: number,
  digest: string,
): string {
  return [
    "write-generated-image-v2",
    ownerScopeHash,
    key,
    mimeType,
    String(byteLength),
    digest,
  ].join("\0");
}

function safeHTTPURL(value: string): boolean {
  try {
    const url = new URL(value);
    return (
      (url.protocol === "https:" || url.protocol === "http:") && !url.username && !url.password
    );
  } catch {
    return false;
  }
}
