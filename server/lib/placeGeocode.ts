import type { PlaceRecord } from "./exa";

const US_STATES = new Map(
  "AL Alabama|AK Alaska|AZ Arizona|AR Arkansas|CA California|CO Colorado|CT Connecticut|DE Delaware|DC District of Columbia|FL Florida|GA Georgia|HI Hawaii|ID Idaho|IL Illinois|IN Indiana|IA Iowa|KS Kansas|KY Kentucky|LA Louisiana|ME Maine|MD Maryland|MA Massachusetts|MI Michigan|MN Minnesota|MS Mississippi|MO Missouri|MT Montana|NE Nebraska|NV Nevada|NH New Hampshire|NJ New Jersey|NM New Mexico|NY New York|NC North Carolina|ND North Dakota|OH Ohio|OK Oklahoma|OR Oregon|PA Pennsylvania|RI Rhode Island|SC South Carolina|SD South Dakota|TN Tennessee|TX Texas|UT Utah|VT Vermont|VA Virginia|WA Washington|WV West Virginia|WI Wisconsin|WY Wyoming"
    .split("|")
    .map((entry) => [entry.slice(3).toLowerCase(), entry.slice(0, 2).toLowerCase()]),
);

type GeocodeResult = {
  name?: string;
  latitude?: number;
  longitude?: number;
  country?: string;
  country_code?: string;
  admin1?: string;
  admin2?: string;
  admin3?: string;
};

const words = (value: string) =>
  value
    .normalize("NFKC")
    .toLocaleLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();

export async function geocodePlace(
  name: string,
  locality: string,
): Promise<Omit<PlaceRecord, "ref"> | null> {
  const place = words(name);
  const area = ` ${words(locality)} `;
  if (place.length < 3) return null;
  try {
    const res = await fetch(
      `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(name)}&count=10`,
      { signal: AbortSignal.timeout(3000) },
    );
    if (!res.ok) return null;
    const { results } = (await res.json()) as { results?: GeocodeResult[] };
    const hit = results?.find((result) => {
      const found = words(result.name ?? "");
      const regions = [result.admin1, result.admin2, result.admin3, result.country]
        .filter((region): region is string => Boolean(region))
        .map(words);
      const state =
        result.country_code === "US" ? US_STATES.get(words(result.admin1 ?? "")) : undefined;
      const codes = [result.country_code?.toLowerCase(), state];
      return (
        typeof result.latitude === "number" &&
        typeof result.longitude === "number" &&
        (found === place || found.startsWith(`${place} `) || place.startsWith(`${found} `)) &&
        [...regions, ...codes].some((region) => region && area.includes(` ${region} `))
      );
    });
    return hit?.latitude !== undefined && hit.longitude !== undefined
      ? { name: hit.name ?? name, lat: hit.latitude, lng: hit.longitude }
      : null;
  } catch {
    return null;
  }
}
