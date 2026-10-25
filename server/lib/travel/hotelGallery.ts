import { createHash } from "node:crypto";
import type { Block } from "../schema";
import { hotelPhotoQuery, parseHotelPhotoQuery, type HotelSelection } from "./hotelContent";
import type { HotelDetails } from "./nuitee";

export type HotelGalleryTarget = Readonly<HotelSelection>;

type GallerySnapshot = {
  photos: readonly string[];
  propertyPhotos: readonly string[];
  propertyImageURL: string | null;
  rooms: ReadonlyMap<string, readonly string[]>;
};

const snapshots = new WeakMap<HotelGalleryTarget, GallerySnapshot>();
const photoHash = (url: string) => createHash("sha256").update(url).digest("hex");

export function isPublicHotelGalleryRoot(input: {
  hasParentContext: boolean;
  hasPrivateContext: boolean;
  hasAttachments: boolean;
  hasCalendarContext: boolean;
  isDrillIn: boolean;
  isSavedSelection: boolean;
  isSingleUserTurn: boolean;
  allowsOnlyPublicResearch: boolean;
}): boolean {
  return (
    !input.hasParentContext &&
    !input.hasPrivateContext &&
    !input.hasAttachments &&
    !input.hasCalendarContext &&
    !input.isDrillIn &&
    !input.isSavedSelection &&
    input.isSingleUserTurn &&
    input.allowsOnlyPublicResearch
  );
}

export function createHotelGalleryTarget(
  catalogs: ReadonlyMap<string, HotelDetails>,
  selected: HotelSelection | undefined,
  publicRoot = false,
): HotelGalleryTarget | null {
  const hotelId =
    selected?.hotelId ??
    (publicRoot && catalogs.size === 1 ? catalogs.keys().next().value : undefined);
  if (!hotelId) return null;
  const hotel = catalogs.get(hotelId);
  if (!hotel || hotel.id !== hotelId) return null;
  const room =
    selected?.roomId == null ? undefined : hotel.rooms.find(({ id }) => id === selected.roomId);
  if (selected?.roomId != null && !room) return null;
  const photos = (room?.photos ?? hotel.photos).map(({ url }) => url);
  if (photos.length === 0) return null;
  const target = Object.freeze({
    hotelId,
    ...(room ? { roomId: room.id } : {}),
  });
  snapshots.set(target, {
    photos: Object.freeze(photos),
    propertyPhotos: Object.freeze(hotel.photos.map(({ url }) => url)),
    propertyImageURL: hotel.imageURL,
    rooms: new Map(
      hotel.rooms.map(({ id, photos }) => [id, Object.freeze(photos.map(({ url }) => url))]),
    ),
  });
  return target;
}

export function projectScopedHotelGalleries(
  blocks: Block[],
  target: HotelGalleryTarget | null,
): Block[] {
  if (!target) return blocks;
  const snapshot = snapshots.get(target);
  if (!snapshot) return blocks;
  return blocks.map((block) => {
    if (block.type !== "photoGrid" || block.images.length === 0) return block;
    const valid = block.images.every((image) => {
      if (image.kind !== "photo") return false;
      const ref = parseHotelPhotoQuery(image.query);
      if (!ref || ref.hotelId !== target.hotelId) return false;
      if (target.roomId != null && ref.roomId !== target.roomId) return false;
      const photos = ref.roomId == null ? snapshot.propertyPhotos : snapshot.rooms.get(ref.roomId);
      if (!photos) return false;
      if (ref.photo === "cover") {
        return photos.length > 0 || (ref.roomId == null && snapshot.propertyImageURL != null);
      }
      return (
        (ref.roomId == null &&
          snapshot.propertyImageURL != null &&
          photoHash(snapshot.propertyImageURL) === ref.photo) ||
        photos.some((url) => photoHash(url) === ref.photo)
      );
    });
    if (!valid) return block;
    return {
      ...block,
      presentation: "collection" as const,
      images: snapshot.photos.map((url) => ({
        kind: "photo" as const,
        query: hotelPhotoQuery(target, url),
      })),
    };
  });
}
