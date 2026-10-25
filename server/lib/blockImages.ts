import type { ImageAspect } from "./blockPrimitives";

const COVER_KINDS = new Set(["photo", "poster", "still"]);
export type CoverImage = {
  query: string;
  kind: "photo" | "poster" | "still";
  aspect?: ImageAspect;
  url?: string;
};

function safeImageURL(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password ? url.href : undefined;
  } catch {
    return undefined;
  }
}

export function conversationCover(blocksJson: string): CoverImage | undefined {
  let found: CoverImage | undefined;
  try {
    const walk = (node: unknown): void => {
      if (found || !node || typeof node !== "object") return;
      const o = node as Record<string, unknown>;
      const nestedImage = o.image;
      if (nestedImage && typeof nestedImage === "object") {
        const image = nestedImage as Record<string, unknown>;
        if (
          typeof image.query === "string" &&
          typeof image.kind === "string" &&
          COVER_KINDS.has(image.kind)
        ) {
          found = {
            query: image.query,
            kind: image.kind as CoverImage["kind"],
            aspect:
              image.aspect === "square" ||
              image.aspect === "portrait" ||
              image.aspect === "landscape"
                ? image.aspect
                : undefined,
            url: safeImageURL(o.imageURL),
          };
          return;
        }
      }
      if (typeof o.query === "string" && typeof o.kind === "string" && COVER_KINDS.has(o.kind)) {
        found = {
          query: o.query,
          kind: o.kind as CoverImage["kind"],
          aspect:
            o.aspect === "square" || o.aspect === "portrait" || o.aspect === "landscape"
              ? o.aspect
              : undefined,
        };
        return;
      }
      for (const v of Object.values(o)) {
        if (Array.isArray(v)) v.forEach(walk);
        else if (v && typeof v === "object") walk(v);
        if (found) return;
      }
    };
    walk(JSON.parse(blocksJson));
  } catch {}
  return found;
}

export function storedConversationCover(row: {
  blocks: string;
  coverImageQuery?: string;
  coverImageKind?: CoverImage["kind"];
  coverImageAspect?: ImageAspect;
  coverImageUrl?: string;
}): { image?: CoverImage; imageURL?: string } {
  const storedURL = safeImageURL(row.coverImageUrl);
  const image = row.coverImageQuery
    ? {
        query: row.coverImageQuery,
        kind: row.coverImageKind ?? "photo",
        aspect: row.coverImageAspect,
      }
    : conversationCover(row.blocks);
  if (!image) return {};
  const imageURL = storedURL ?? image.url;
  const { url: _, ...spec } = image;
  return imageURL ? { image: spec, imageURL } : { image: spec };
}

export function firstTextBody(blocksJson: string): string | undefined {
  try {
    const blocks = JSON.parse(blocksJson) as {
      type?: string;
      body?: string;
    }[];
    if (!Array.isArray(blocks)) return undefined;
    const text = blocks.find(
      (b) => b?.type === "text" && typeof b.body === "string" && b.body.trim(),
    );
    return text?.body;
  } catch {
    return undefined;
  }
}
