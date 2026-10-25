import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { createNuiteeClient, type HotelDetails, type HotelSummary } from "./nuitee";
import type { Block } from "../schema";

export type HotelSelection = { hotelId: string; roomId?: string };
export const hotelResourceID = (ref: HotelSelection) =>
  `nuitee:sandbox:hotel:${ref.hotelId}${ref.roomId ? `:room:${ref.roomId}` : ""}`;
const prefix = "emblem-hotel.v1.";
const identifier = /^[\w-]{1,100}$/;
const imageRefPattern = /^hotel:([\w-]{1,100})(?::room:([\w-]{1,100}))?$/;
const photoID = (url: string) => createHash("sha256").update(url).digest("hex");
function assetSignature(payload: string): string | null {
  const key = process.env.NUITEE_SANDBOX_API_KEY?.trim();
  if (!key || !/^sand_[A-Za-z0-9_-]+$/.test(key)) return null;
  return createHmac("sha256", key)
    .update(`emblem-nuitee-public-photo-v1\0${payload}`)
    .digest("base64url");
}
const catalogs = new Map<string, { expires: number; value: Promise<HotelDetails> }>();

export function hotelPhotoQuery(ref: HotelSelection, url?: string): string {
  const payload = `${ref.hotelId}.${ref.roomId ?? "-"}.${url ? photoID(url) : "cover"}`;
  const signature = assetSignature(payload);
  if (!signature) throw new Error("Hotel media signing unavailable");
  return `${prefix}${payload}.${signature}`;
}

export function parseHotelPhotoQuery(query: string): (HotelSelection & { photo: string }) | null {
  if (!query.startsWith(prefix)) return null;
  const parts = query.slice(prefix.length).split(".");
  if (parts.length !== 4) return null;
  const [hotelId, room, photo, signature] = parts;
  if (!identifier.test(hotelId) || (room !== "-" && !identifier.test(room))) return null;
  if (photo !== "cover" && !/^[a-f0-9]{64}$/.test(photo)) return null;
  if (!/^[A-Za-z0-9_-]{43}$/.test(signature)) return null;
  const expectedSignature = assetSignature(`${hotelId}.${room}.${photo}`);
  if (!expectedSignature) return null;
  const supplied = Buffer.from(signature);
  const expected = Buffer.from(expectedSignature);
  if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) return null;
  return { hotelId, ...(room !== "-" ? { roomId: room } : {}), photo };
}

export function isHotelPhotoQuery(query: string): boolean {
  return query.startsWith(prefix) || imageRefPattern.test(query);
}

export function hotelCatalog(hotelId: string): Promise<HotelDetails> {
  const cached = catalogs.get(hotelId);
  if (cached && cached.expires > Date.now()) return cached.value;
  const value = createNuiteeClient().hotelDetails({ hotelId });
  if (catalogs.size >= 32) catalogs.delete(catalogs.keys().next().value!);
  catalogs.set(hotelId, { expires: Date.now() + 60_000, value });
  void value.catch(() => {
    if (catalogs.get(hotelId)?.value === value) catalogs.delete(hotelId);
  });
  return value;
}

export async function resolveHotelPhotoQuery(query: string): Promise<string | null> {
  const ref = parseHotelPhotoQuery(query);
  if (!ref) return null;
  try {
    const hotel = await hotelCatalog(ref.hotelId);
    const room = ref.roomId ? hotel.rooms.find(({ id }) => id === ref.roomId) : undefined;
    if (ref.roomId && !room) return null;
    const photos = room ? room.photos : hotel.photos;
    if (ref.photo === "cover") return photos[0]?.url ?? (room ? null : hotel.imageURL);
    if (!room && hotel.imageURL && photoID(hotel.imageURL) === ref.photo) return hotel.imageURL;
    return photos.find(({ url }) => photoID(url) === ref.photo)?.url ?? null;
  } catch {
    return null;
  }
}

function hotelCard(summary: HotelSummary) {
  const classification =
    summary.starClassification == null ? null : `${summary.starClassification}-star hotel`;
  const guestScore = summary.guestRating
    ? `Guest score ${summary.guestRating.score}${summary.guestRating.reviewCount == null ? "" : ` (${summary.guestRating.reviewCount.toLocaleString("en-US")} reviews)`}`
    : null;
  return {
    title: summary.name,
    image: {
      kind: "photo" as const,
      query: hotelPhotoQuery({ hotelId: summary.id }),
    },
    meta: [classification, summary.city, guestScore].filter(Boolean).join(" · "),
    prompt: `Show me ${summary.name}, its rooms, photos, amenities, guest reviews, and things to know.`,
  };
}

export function selectedHotelFromBlocks(
  blocksJSON: string,
  sourceCardKey: string | undefined,
): HotelSelection | undefined {
  if (!sourceCardKey) return;
  let blocks: unknown;
  try {
    blocks = JSON.parse(blocksJSON);
  } catch {
    return;
  }
  if (!Array.isArray(blocks)) return;
  for (const block of blocks) {
    if (
      block?.type !== "cardCarousel" ||
      typeof block.id !== "string" ||
      !Array.isArray(block.cards)
    )
      continue;
    for (const card of block.cards) {
      if (typeof card?.title !== "string" || card.conversation != null || card.automation != null)
        continue;
      const id =
        typeof card.resourceID === "string"
          ? `resource:${card.resourceID}`
          : typeof card.prompt === "string"
            ? `prompt:${card.prompt}`
            : `card:${card.title}:${card.caption ?? ""}`;
      const key = createHash("sha256").update(`${block.id}\x1f${id}`).digest("hex");
      if (key !== sourceCardKey || typeof card.image?.query !== "string") continue;
      const ref = parseHotelPhotoQuery(card.image.query);
      if (ref && (card.resourceID == null || card.resourceID === hotelResourceID(ref)))
        return { hotelId: ref.hotelId, ...(ref.roomId ? { roomId: ref.roomId } : {}) };
    }
  }
}

export function retainedHotelContextFromBlocks(blocksJSON: string): HotelSelection | undefined {
  let blocks: unknown;
  try {
    blocks = JSON.parse(blocksJSON);
  } catch {
    return;
  }
  if (!Array.isArray(blocks)) return;
  const properties = new Set<string>();
  for (const block of blocks) {
    const images =
      block?.type === "photoGrid" && Array.isArray(block.images)
        ? block.images
        : block?.type === "cardCarousel" && Array.isArray(block.cards)
          ? block.cards.map((card: { image?: unknown }) => card?.image)
          : block?.type === "hero"
            ? [block.image]
            : [];
    for (const image of images) {
      const ref = typeof image?.query === "string" ? parseHotelPhotoQuery(image.query) : null;
      if (ref) properties.add(ref.hotelId);
    }
  }
  return properties.size === 1 ? { hotelId: [...properties][0] } : undefined;
}

export function hotelBrowseRoomsAction(hotel: Pick<HotelSummary, "name">) {
  return { label: "Book", prompt: `Show me the room options at ${hotel.name}.` };
}

const COMPOSER_ROOMS = 8;
const clip = (value: string | null | undefined, max: number): string | undefined => {
  const text = value?.replace(/\s+/g, " ").trim();
  if (!text) return undefined;
  return text.length > max ? `${text.slice(0, max - 1).trimEnd()}…` : text;
};
const firstItems = (items: readonly string[], count: number, max: number) =>
  items.flatMap((item) => clip(item, max) ?? []).slice(0, count);

function hotelImageRef(ref: HotelSelection): string {
  return `hotel:${ref.hotelId}${ref.roomId ? `:room:${ref.roomId}` : ""}`;
}

function parseHotelImageRef(query: string): HotelSelection | null {
  const match = imageRefPattern.exec(query);
  if (!match) return null;
  return { hotelId: match[1]!, ...(match[2] ? { roomId: match[2] } : {}) };
}

export function expandHotelImageRefs<T>(
  value: T,
  hotels: ReadonlyMap<string, HotelSummary>,
  details: ReadonlyMap<string, HotelDetails>,
): T {
  if (Array.isArray(value))
    return value.map((item) => expandHotelImageRefs(item, hotels, details)) as T;
  if (!value || typeof value !== "object") return value;
  const entries = Object.entries(value).map(([key, item]) => {
    if (key !== "query" || typeof item !== "string")
      return [key, expandHotelImageRefs(item, hotels, details)];
    const ref = parseHotelImageRef(item);
    if (!ref) return [key, item];
    const known = ref.roomId
      ? details.get(ref.hotelId)?.rooms.some(({ id }) => id === ref.roomId)
      : hotels.has(ref.hotelId) || details.has(ref.hotelId);
    return [key, known ? hotelPhotoQuery(ref) : item];
  });
  return Object.fromEntries(entries) as T;
}

export function hotelComposerCard(summary: HotelSummary) {
  const { title, meta } = hotelCard(summary);
  return {
    hotelId: summary.id,
    title,
    image: { kind: "photo" as const, query: hotelImageRef({ hotelId: summary.id }) },
    meta,
    ...(summary.address ? { address: summary.address } : {}),
  };
}

function composerRooms(hotel: HotelDetails) {
  const seen = new Set<string>();
  const distinct = hotel.rooms.filter((room) => {
    const key = (room.name ?? room.id).toLocaleLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  return {
    roomCount: distinct.length,
    rooms: [...distinct]
      .sort((a, b) => Number(b.photos.length > 0) - Number(a.photos.length > 0))
      .slice(0, COMPOSER_ROOMS)
      .map((item) => ({
        title: item.name ?? "Room",
        caption: clip(item.description, 140),
        image: {
          kind: "photo",
          query: hotelImageRef({ hotelId: hotel.id, roomId: item.id }),
        },
        meta: [
          item.size ? `${item.size.value} ${item.size.unit}` : null,
          item.maxOccupancy == null ? null : `Up to ${item.maxOccupancy} guests`,
        ]
          .filter(Boolean)
          .join(" · "),
      })),
  };
}

export function hotelComposerContent(hotel: HotelDetails, roomId?: string) {
  const room = roomId ? hotel.rooms.find(({ id }) => id === roomId) : undefined;
  if (roomId && !room) throw new Error("Hotel room does not belong to this property");
  const times = hotel.checkinCheckout;
  const instructions = times?.instructions;
  return {
    provider: "Nuitée",
    environment: "sandbox",
    hotel: hotelComposerCard(hotel),
    description: clip(room?.description ?? hotel.description, 900),
    room: room
      ? {
          name: room.name,
          beds: room.beds,
          bedRelation: room.bedRelation,
          amenities: firstItems(room.amenities, 16, 60),
          size: room.size,
          maxOccupancy: room.maxOccupancy,
        }
      : undefined,
    gallery: {
      loadedCount: (room?.photos ?? hotel.photos).length,
      image: {
        kind: "photo",
        query: hotelImageRef({ hotelId: hotel.id, ...(room ? { roomId: room.id } : {}) }),
      },
    },
    ...(room ? {} : composerRooms(hotel)),
    amenities: firstItems(hotel.amenities, 24, 60),
    checkinCheckout: times
      ? {
          checkinStart: times.checkin_start ?? undefined,
          checkinEnd: times.checkin_end ?? undefined,
          checkout: times.checkout ?? undefined,
          instructions: clip(
            Array.isArray(instructions) ? instructions.join(" ") : instructions,
            300,
          ),
        }
      : null,
    policies: hotel.policies.slice(0, 5).map(({ name, description }) => ({
      name,
      description: clip(description, 160),
    })),
    importantInformation: clip(hotel.importantInformation, 500),
    contact: hotel.contact,
    location: hotel.location,
    guestRating: hotel.guestRating,
    guestThemes: hotel.guestThemes && {
      pros: firstItems(hotel.guestThemes.pros, 4, 100),
      cons: firstItems(hotel.guestThemes.cons, 4, 100),
      categories: hotel.guestThemes.categories.slice(0, 6).map((category) => ({
        name: category.name,
        score: category.score,
        maximum: category.maximum,
        description: clip(category.description, 80),
      })),
    },
    browseRoomsAction: hotelBrowseRoomsAction(hotel),
    constraints:
      "Catalog information only; no live availability, room price or reservation. Book browses room options. Preserve class stars, guest score and review count separately. Use image queries exactly as supplied (short hotel: references); the server expands them to verified photos, and a photoGrid with the gallery image shows the full gallery. Do not invent artwork or quotes. Use cardCarousel grid for compact room comparisons or rail for detailed room rows. Reuse reviewSummary for guest themes and aggregate guest ratings; quote only supplied attributable reviews, and keep classification stars separate.",
  };
}

export function hotelReviewsComposerContent(
  reviews: Awaited<ReturnType<ReturnType<typeof createNuiteeClient>["hotelReviews"]>>,
) {
  return {
    provider: "Nuitée",
    environment: "sandbox",
    hotelId: reviews.hotelId,
    total: reviews.total,
    reviews: reviews.reviews.map((review) => ({
      reviewer: review.name ?? undefined,
      country: review.country ?? undefined,
      type: review.type ?? undefined,
      date: review.date ?? undefined,
      score: review.averageScore ?? undefined,
      maximum: review.maximum,
      headline: clip(review.headline, 160),
      pros: clip(review.pros, 320),
      cons: clip(review.cons, 320),
      source: review.source ?? undefined,
    })),
  };
}

export function attachHotelCardResources(
  blocks: Block[],
  hotels: ReadonlyMap<string, HotelSummary>,
  details: ReadonlyMap<string, HotelDetails>,
): Block[] {
  const projected = blocks.map((block) => {
    if (block.type !== "cardCarousel") return block;
    const verified: HotelSelection[] = [];
    const cards = block.cards.map((card) => {
      const ref = card.image ? parseHotelPhotoQuery(card.image.query) : null;
      if (!ref) return card;
      const hotel = hotels.get(ref.hotelId) ?? details.get(ref.hotelId);
      const room = ref.roomId
        ? details.get(ref.hotelId)?.rooms.find(({ id }) => id === ref.roomId)
        : undefined;
      if (!hotel || (ref.roomId && !room)) return card;
      if (card.conversation == null && card.automation == null) verified.push(ref);
      return {
        ...card,
        resourceID: hotelResourceID(ref),
        saveCategory: "hotels-vacation-rentals" as const,
        title: room ? (room.name ?? "Room") : hotel.name,
        ...(room ? {} : { meta: hotelCard(hotel).meta }),
      };
    });
    const unhinted = {
      ...block,
      cards,
      ...(block.presentation === "hotelRail" ||
      block.presentation === "hotelList" ||
      block.presentation === "roomGrid" ||
      block.presentation === "roomList"
        ? { presentation: "standard" as const }
        : {}),
    };
    if (block.id === "ideas" || cards.length === 0 || verified.length !== cards.length)
      return unhinted;
    if (verified.every((ref) => ref.roomId == null)) {
      return { ...unhinted, presentation: "hotelRail" as const, layout: "rail" as const };
    }
    if (verified.every((ref) => ref.roomId != null && ref.hotelId === verified[0].hotelId)) {
      return block.layout === "grid"
        ? { ...unhinted, presentation: "roomGrid" as const, layout: "grid" as const }
        : { ...unhinted, presentation: "roomList" as const, layout: "rail" as const };
    }
    return unhinted;
  });
  const hotelCarousels = projected.filter(
    (block) => block.type === "cardCarousel" && block.presentation === "hotelRail",
  );
  if (hotelCarousels.length !== 1) return projected;
  return projected.map((block) =>
    block === hotelCarousels[0] && block.type === "cardCarousel"
      ? { ...block, presentation: "hotelList" as const }
      : block,
  );
}
