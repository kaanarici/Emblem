type ExaResult = {
  title: string;
  url: string;
  favicon?: string;
  publishedDate?: string;
  text?: string;
  highlights?: string[];
};

export async function exaSearch(
  query: string,
  includeText = false,
  options: { includeDomains?: string[]; numResults?: number; timeoutMs?: number } = {},
): Promise<ExaResult[]> {
  const apiKey = process.env.EXA_API_KEY;
  if (!apiKey) return [];

  const res = await fetch("https://api.exa.ai/search", {
    method: "POST",
    headers: { "x-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      query,
      numResults: options.numResults ?? 5,
      type: "instant",
      ...(options.includeDomains ? { includeDomains: options.includeDomains } : {}),
      contents: { highlights: true, ...(includeText ? { text: { maxCharacters: 6_000 } } : {}) },
    }),
    signal: AbortSignal.timeout(options.timeoutMs ?? 5000),
  });
  if (!res.ok) {
    console.error(JSON.stringify({ event: "exa search failed", status: res.status }));
    return [];
  }
  const { results } = (await res.json()) as { results: ExaResult[] };
  return results ?? [];
}

export type PlaceRecord = {
  ref: string;
  name: string;
  lat: number;
  lng: number;
  address?: string;
  rating?: { score: number; count?: number };
  category?: string;
  website?: string;
  phone?: string;
};

type ExaPlaceEntity = {
  id?: string;
  type?: string;
  properties?: {
    name?: string | null;
    categories?: string[] | null;
    address?: Record<string, string | null> | null;
    location?: { latitude?: number; longitude?: number } | null;
    phoneNumbers?: string[] | null;
    websites?: string[] | null;
    rating?: { score?: number | null; count?: number | null } | null;
  };
};

function placeRecords(results: readonly { entities?: ExaPlaceEntity[] }[]): PlaceRecord[] {
  const seen = new Set<string>();
  return results.flatMap(({ entities }) =>
    (entities ?? []).flatMap((entity): PlaceRecord[] => {
      const ref = entity.id?.split("/").pop()?.trim();
      const p = entity.properties;
      const name = p?.name?.trim();
      const lat = p?.location?.latitude;
      const lng = p?.location?.longitude;
      if (
        entity.type !== "place" ||
        !ref ||
        !name ||
        seen.has(ref) ||
        typeof lat !== "number" ||
        typeof lng !== "number" ||
        Math.abs(lat) > 90 ||
        Math.abs(lng) > 180
      )
        return [];
      seen.add(ref);
      const address = [p?.address?.street, p?.address?.locality]
        .filter((part): part is string => Boolean(part?.trim()))
        .join(", ");
      const website = p?.websites?.find((url) => /^https:\/\//i.test(url));
      return [
        {
          ref,
          name,
          lat,
          lng,
          ...(address ? { address } : {}),
          ...(typeof p?.rating?.score === "number"
            ? {
                rating: {
                  score: p.rating.score,
                  ...(typeof p.rating.count === "number" ? { count: p.rating.count } : {}),
                },
              }
            : {}),
          ...(p?.categories?.[0] ? { category: p.categories[0].split(" > ").pop() } : {}),
          ...(website ? { website } : {}),
          ...(p?.phoneNumbers?.[0] ? { phone: p.phoneNumbers[0] } : {}),
        },
      ];
    }),
  );
}

export async function exaPlaces(
  kind: string,
  area: string,
  signal?: AbortSignal,
): Promise<PlaceRecord[]> {
  const apiKey = process.env.EXA_API_KEY;
  if (!apiKey) return [];
  const res = await fetch("https://api.exa.ai/search", {
    method: "POST",
    headers: { "x-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({ query: `${kind} near ${area}`, type: "auto", numResults: 5 }),
    signal: AbortSignal.any([...(signal ? [signal] : []), AbortSignal.timeout(8000)]),
  });
  if (!res.ok) {
    console.error(JSON.stringify({ event: "exa places failed", status: res.status }));
    return [];
  }
  const { results } = (await res.json()) as { results?: { entities?: ExaPlaceEntity[] }[] };
  return placeRecords(results ?? []).slice(0, 12);
}
