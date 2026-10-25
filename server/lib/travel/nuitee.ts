import { z } from "zod";

const id = z.union([z.string().min(1), z.number().int()]).transform(String);
const text = z.string().nullable().optional();
const score = z.number().min(0).max(10).nullable().optional();
const count = z.number().int().nonnegative().nullable().optional();
const apiBase = "https://api.liteapi.travel/v3.0";
const MAX_RESPONSE_BYTES = 8 * 1024 * 1024;
const photo = z.object({
  url: text,
  urlHd: text,
  hd_url: text,
  imageDescription: text,
  caption: text,
});
const room = z.object({
  id,
  roomName: text,
  roomTitle: text,
  markdownDescription: text,
  description: text,
  photos: z.array(photo).nullish(),
  maxAdults: count,
  maxChildren: count,
  maxOccupancy: count,
  roomSizeSquare: z.number().nonnegative().nullish(),
  roomSizeUnit: text,
  roomAmenities: z.array(z.object({ name: z.string() })).nullish(),
  bedRelation: text,
  bedTypes: z.array(z.object({ quantity: count, bedType: text, bedSize: text })).nullish(),
});
const hotel = z.object({
  id,
  name: z.string().trim().min(1),
  address: text,
  city: text,
  country: text,
  main_photo: text,
  starRating: z.number().min(0).max(5).nullish(),
  stars: z.number().min(0).max(5).nullish(),
  rating: score,
  reviewCount: count,
  hotelDescription: text,
  markdownDescription: text,
  hotelImportantInformation: text,
  hotelImages: z.array(photo).nullish(),
  hotelFacilities: z.array(z.string()).nullish(),
  rooms: z.array(room).nullish(),
  location: z
    .object({ latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180) })
    .nullish(),
  latitude: z.number().min(-90).max(90).nullish(),
  longitude: z.number().min(-180).max(180).nullish(),
  phone: text,
  email: text,
  website: text,
  checkinCheckoutTimes: z
    .object({
      checkin_start: text,
      checkin_end: text,
      checkout: text,
      instructions: z.union([z.string(), z.array(z.string())]).nullish(),
      special_instructions: text,
    })
    .nullish(),
  policies: z.array(z.object({ policy_type: text, name: text, description: text })).nullish(),
  sentiment_analysis: z
    .object({
      pros: z.array(z.string()).nullish(),
      cons: z.array(z.string()).nullish(),
      categories: z
        .array(z.object({ name: z.string(), rating: score, description: text }))
        .nullish(),
    })
    .nullish(),
  sentiment_updated_at: text,
});
const review = z.object({
  reviewId: id,
  averageScore: score,
  country: text,
  type: text,
  name: text,
  date: text,
  headline: text,
  language: text,
  pros: text,
  cons: text,
  source: text,
});
const date = z.iso.date();
const countryCode = z.string().regex(/^[A-Z]{2}$/);
const currency = z.string().regex(/^[A-Z]{3}$/);
const hotelId = z
  .string()
  .trim()
  .min(1)
  .max(100)
  .regex(/^[\w-]+$/);

export const hotelSearchInput = z.object({
  cityName: z.string().trim().min(1).max(150),
  countryCode,
  hotelName: z.string().trim().min(1).max(200).optional(),
  limit: z.number().int().min(1).max(8).default(6),
});
export const hotelDetailsInput = z.object({ hotelId });
export const hotelReviewsInput = z.object({
  hotelId,
  limit: z.number().int().min(1).max(20).default(10),
  offset: z.number().int().min(0).max(5000).default(0),
});
export const flightSearchInput = z
  .object({
    legs: z
      .array(
        z.object({
          origin: z.string().regex(/^[A-Z]{3}$/),
          destination: z.string().regex(/^[A-Z]{3}$/),
          date,
          direction: z.enum(["OUTBOUND", "INBOUND"]).optional(),
        }),
      )
      .min(1)
      .max(4),
    adults: z.number().int().min(1).max(8),
    children: z.number().int().min(0).max(6).default(0),
    infants: z.number().int().min(0).max(6).default(0),
    childrenAges: z.array(z.number().int().min(2).max(11)).max(6).optional(),
    infantAges: z.array(z.number().int().min(0).max(1)).max(6).optional(),
    currency,
    cabinClass: z.enum(["ECONOMY", "PREMIUM_ECONOMY", "BUSINESS", "FIRST"]).optional(),
  })
  .superRefine((input, ctx) => {
    const now = new Date();
    const today = now.toISOString().slice(0, 10);
    const lastDay = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 12, 0),
    ).getUTCDate();
    const latest = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 11, Math.min(now.getUTCDate(), lastDay)),
    )
      .toISOString()
      .slice(0, 10);
    input.legs.forEach((leg, index) => {
      if (leg.date < today || leg.date > latest)
        ctx.addIssue({
          code: "custom",
          message: "Flight dates must be today through eleven months ahead",
          path: ["legs", index, "date"],
        });
    });
    if (input.infants > input.adults)
      ctx.addIssue({
        code: "custom",
        message: "Infants cannot outnumber adults",
        path: ["infants"],
      });
    for (const [ages, expected] of [
      [input.childrenAges, input.children],
      [input.infantAges, input.infants],
    ] as const)
      if (ages && ages.length !== expected)
        ctx.addIssue({ code: "custom", message: "Passenger age count does not match" });
    for (let i = 0; i < input.legs.length; i++) {
      const leg = input.legs[i];
      if (leg.origin === leg.destination || (i > 0 && leg.date < input.legs[i - 1].date))
        ctx.addIssue({
          code: "custom",
          message: "Invalid itinerary order or route",
          path: ["legs", i],
        });
    }
  });

type TravelProvenance = {
  provider: "nuitee";
  sandbox: true;
  fetchedAt: string;
  sourceId: string;
  sourceURL: string;
};
type TravelPhoto = { url: string; caption?: string };
export type HotelSummary = TravelProvenance & {
  id: string;
  name: string;
  address: string | null;
  city: string | null;
  country: string | null;
  starClassification: number | null;
  guestRating: { score: number; maximum: number | null; reviewCount: number | null } | null;
  imageURL: string | null;
  location: { latitude: number; longitude: number } | null;
};
export type HotelDetails = HotelSummary & {
  description: string | null;
  photos: TravelPhoto[];
  rooms: {
    id: string;
    name: string | null;
    description: string | null;
    photos: TravelPhoto[];
    maxAdults: number | null;
    maxChildren: number | null;
    maxOccupancy: number | null;
    size: { value: number; unit: string } | null;
    amenities: string[];
    bedRelation: string | null;
    beds: { quantity: number | null; type: string | null; size: string | null }[];
  }[];
  amenities: string[];
  contact: { phone: string | null; email: string | null; website: string | null };
  checkinCheckout: z.infer<typeof hotel>["checkinCheckoutTimes"];
  importantInformation: string | null;
  policies: { name: string | null; description: string | null }[];
  guestThemes: {
    pros: string[];
    cons: string[];
    categories: { name: string; score: number | null; maximum: 10; description: string | null }[];
    updatedAt: string | null;
  } | null;
};

export class TravelProviderError extends Error {
  constructor(
    readonly code:
      | "not_configured"
      | "sandbox_required"
      | "invalid_input"
      | "timeout"
      | "upstream_error"
      | "access_denied"
      | "invalid_response",
  ) {
    super(`Nuitee sandbox: ${code}`);
  }
}

function publicURL(value: string | null | undefined): string | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password && value.length <= 8192
      ? value
      : null;
  } catch {
    return null;
  }
}
function photos(items: z.infer<typeof photo>[] | null | undefined): TravelPhoto[] {
  const seen = new Set<string>();
  return (items ?? []).flatMap((item) => {
    const url = publicURL(item.urlHd) ?? publicURL(item.hd_url) ?? publicURL(item.url);
    if (!url || seen.has(url)) return [];
    seen.add(url);
    return [
      {
        url,
        ...((item.caption ?? item.imageDescription)
          ? { caption: item.caption ?? item.imageDescription! }
          : {}),
      },
    ];
  });
}
function provenance(kind: string, key: string, path: string): TravelProvenance {
  return {
    provider: "nuitee",
    sandbox: true,
    fetchedAt: new Date().toISOString(),
    sourceId: `nuitee:sandbox:${kind}:${key}`,
    sourceURL: `${apiBase}${path}`,
  };
}
function summary(raw: z.infer<typeof hotel>): HotelSummary {
  return {
    ...provenance("hotel", raw.id, `/data/hotel?hotelId=${encodeURIComponent(raw.id)}`),
    id: raw.id,
    name: raw.name,
    address: raw.address ?? null,
    city: raw.city ?? null,
    country: raw.country ?? null,
    starClassification: raw.starRating ?? raw.stars ?? null,
    guestRating:
      raw.rating == null
        ? null
        : { score: raw.rating, maximum: null, reviewCount: raw.reviewCount ?? null },
    imageURL: publicURL(raw.main_photo),
    location:
      raw.location ??
      (raw.latitude != null && raw.longitude != null
        ? { latitude: raw.latitude, longitude: raw.longitude }
        : null),
  };
}

const flightOffer = z.object({
  offerId: z.string().min(1),
  expiration: z.string().nullish(),
  pricing: z.object({
    display: z.object({
      total: z.number().nonnegative(),
      currency,
      base: z.number().nonnegative().nullish(),
      taxes: z.number().nonnegative().nullish(),
      fees: z.number().nonnegative().nullish(),
    }),
  }),
  fare: z.object({ family: text, seatsRemaining: count }).nullish(),
  terms: z
    .object({
      changeable: z.boolean().nullish(),
      refundable: z.boolean().nullish(),
      summary: z.array(z.object({ level: text, message: z.string() })).nullish(),
    })
    .nullish(),
  provider: z.object({ code: text }).nullish(),
  baggage: z
    .object({
      hasCarryOnBag: z.boolean().nullish(),
      hasCheckedBag: z.boolean().nullish(),
      included: z
        .array(
          z.object({
            bagType: text,
            description: text,
            passengerType: text,
            pieces: count,
            weightKg: z.number().nonnegative().nullish(),
          }),
        )
        .nullish(),
    })
    .nullish(),
});
const flightJourney = z.object({
  journeyKey: z.string().min(1),
  offers: z.array(flightOffer),
  segments: z
    .array(
      z.object({
        segmentKey: z.string(),
        originCode: z.string(),
        destinationCode: z.string(),
        originName: text,
        destinationName: text,
        departureTime: z.string(),
        arrivalTime: z.string(),
        direction: text,
        stopCount: count,
        carrier: z
          .object({
            marketingCode: text,
            marketingName: text,
            operatingCode: text,
            operatingName: text,
          })
          .nullish(),
        flight: z.object({ marketingNumber: text, operatingNumber: text }).nullish(),
        duration: z.object({ minutes: z.number().nonnegative() }).nullish(),
        stops: z
          .array(
            z.object({
              airportCode: z.string(),
              airportName: text,
              arrivalTime: text,
              departureTime: text,
            }),
          )
          .nullish(),
      }),
    )
    .min(1),
  totalDuration: z.object({ minutes: z.number().nonnegative() }).nullish(),
});
type FlightJourney = z.infer<typeof flightJourney> & TravelProvenance;

export function nuiteeConfigured(): boolean {
  return Boolean(
    /^sand_[A-Za-z0-9_-]+$/.test(process.env.NUITEE_SANDBOX_API_KEY?.trim() ?? "") &&
    process.env.NUITEE_SANDBOX_BASE_URL?.trim().replace(/\/$/, "") === apiBase,
  );
}

export function createNuiteeClient() {
  const key = process.env.NUITEE_SANDBOX_API_KEY?.trim();
  const base = process.env.NUITEE_SANDBOX_BASE_URL?.trim();
  if (!key || !base) throw new TravelProviderError("not_configured");
  if (!/^sand_[A-Za-z0-9_-]+$/.test(key) || base.replace(/\/$/, "") !== apiBase)
    throw new TravelProviderError("sandbox_required");
  async function request<T>(
    path: string,
    schema: z.ZodType<T>,
    signal?: AbortSignal,
    body?: unknown,
  ): Promise<T> {
    try {
      const response = await fetch(`${apiBase}${path}`, {
        method: body === undefined ? "GET" : "POST",
        redirect: "error",
        headers: {
          "X-API-Key": key!,
          Accept: "application/json",
          ...(body === undefined ? {} : { "Content-Type": "application/json" }),
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        signal: AbortSignal.any([
          ...(signal ? [signal] : []),
          AbortSignal.timeout(path.startsWith("/flights/") ? 20000 : 12000),
        ]),
        cache: "no-store",
      });
      if (!response.ok)
        throw new TravelProviderError(
          response.status === 401 || response.status === 403 ? "access_denied" : "upstream_error",
        );
      if (!response.body) throw new TravelProviderError("invalid_response");
      const reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let size = 0;
      try {
        while (true) {
          const chunk = await reader.read();
          if (chunk.done) break;
          size += chunk.value.byteLength;
          if (size > MAX_RESPONSE_BYTES) throw new TravelProviderError("invalid_response");
          chunks.push(chunk.value);
        }
      } finally {
        await reader.cancel().catch(() => {});
      }
      const parsed = schema.safeParse(JSON.parse(Buffer.concat(chunks).toString("utf8")));
      if (!parsed.success) throw new TravelProviderError("invalid_response");
      return parsed.data;
    } catch (error) {
      if (error instanceof TravelProviderError) throw error;
      if (signal?.aborted) throw signal.reason;
      throw new TravelProviderError(
        error instanceof Error && ["AbortError", "TimeoutError"].includes(error.name)
          ? "timeout"
          : "invalid_response",
      );
    }
  }
  const parse = <T>(schema: z.ZodType<T>, input: unknown): T => {
    const result = schema.safeParse(input);
    if (!result.success) throw new TravelProviderError("invalid_input");
    return result.data;
  };
  return {
    async searchHotels(
      input: z.input<typeof hotelSearchInput>,
      signal?: AbortSignal,
    ): Promise<HotelSummary[]> {
      const args = parse(hotelSearchInput, input);
      const query = new URLSearchParams(
        Object.entries(args).map(([key, value]) => [key, String(value)]),
      );
      const response = await request(
        `/data/hotels?${query}`,
        z.object({ data: z.array(hotel) }),
        signal,
      );
      return response.data.slice(0, args.limit).map(summary);
    },
    async hotelDetails(
      input: z.input<typeof hotelDetailsInput>,
      signal?: AbortSignal,
    ): Promise<HotelDetails> {
      const { hotelId } = parse(hotelDetailsInput, input);
      const { data: raw } = await request(
        `/data/hotel?hotelId=${encodeURIComponent(hotelId)}`,
        z.object({ data: hotel }),
        signal,
      );
      if (raw.id !== hotelId) throw new TravelProviderError("invalid_response");
      return {
        ...summary(raw),
        description: raw.markdownDescription ?? raw.hotelDescription ?? null,
        photos: photos(raw.hotelImages),
        amenities: raw.hotelFacilities ?? [],
        rooms: (raw.rooms ?? []).map((room) => ({
          id: room.id,
          name: room.roomTitle ?? room.roomName ?? null,
          description: room.markdownDescription ?? room.description ?? null,
          photos: photos(room.photos),
          maxAdults: room.maxAdults ?? null,
          maxChildren: room.maxChildren ?? null,
          maxOccupancy: room.maxOccupancy ?? null,
          size:
            room.roomSizeSquare == null || !room.roomSizeUnit
              ? null
              : { value: room.roomSizeSquare, unit: room.roomSizeUnit },
          amenities: (room.roomAmenities ?? []).map(({ name }) => name),
          bedRelation: room.bedRelation ?? null,
          beds: (room.bedTypes ?? []).map((bed) => ({
            quantity: bed.quantity ?? null,
            type: bed.bedType ?? null,
            size: bed.bedSize ?? null,
          })),
        })),
        contact: {
          phone: raw.phone ?? null,
          email: raw.email ?? null,
          website: publicURL(raw.website),
        },
        checkinCheckout: raw.checkinCheckoutTimes ?? null,
        importantInformation: raw.hotelImportantInformation ?? null,
        policies: (raw.policies ?? []).map((item) => ({
          name: item.name ?? item.policy_type ?? null,
          description: item.description ?? null,
        })),
        guestThemes: raw.sentiment_analysis
          ? {
              pros: raw.sentiment_analysis.pros ?? [],
              cons: raw.sentiment_analysis.cons ?? [],
              categories: (raw.sentiment_analysis.categories ?? []).map((category) => ({
                name: category.name,
                score: category.rating ?? null,
                maximum: 10 as const,
                description: category.description ?? null,
              })),
              updatedAt: raw.sentiment_updated_at ?? null,
            }
          : null,
      };
    },
    async hotelReviews(input: z.input<typeof hotelReviewsInput>, signal?: AbortSignal) {
      const args = parse(hotelReviewsInput, input);
      const query = new URLSearchParams(
        Object.entries(args).map(([key, value]) => [key, String(value)]),
      );
      const response = await request(
        `/data/reviews?${query}`,
        z.object({ data: z.array(review), total: count }),
        signal,
      );
      return {
        ...provenance(
          "reviews",
          args.hotelId,
          `/data/reviews?hotelId=${encodeURIComponent(args.hotelId)}`,
        ),
        hotelId: args.hotelId,
        total: response.total ?? null,
        offset: args.offset,
        reviews: response.data.map((item) => ({ ...item, maximum: 10 as const })),
      };
    },
    async searchFlights(
      input: z.input<typeof flightSearchInput>,
      signal?: AbortSignal,
    ): Promise<FlightJourney[]> {
      const args = parse(flightSearchInput, input);
      const response = await request(
        "/flights/rates",
        z.object({ data: z.array(z.object({ journeys: z.array(flightJourney) })) }),
        signal,
        args,
      );
      return response.data
        .flatMap((batch) => batch.journeys)
        .slice(0, 12)
        .map((journey) => ({
          ...journey,
          ...provenance("flight", journey.journeyKey, "/flights/rates"),
        }));
    },
  };
}
