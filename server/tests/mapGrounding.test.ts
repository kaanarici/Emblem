import { describe, expect, it, vi } from "vitest";
import { createPageAssembly } from "../lib/pageAssembly";
import type { Block } from "../lib/schema";

const geocoder: Record<string, object[]> = {
  "Zion National Park": [
    {
      name: "Zion National Park",
      latitude: 37.3,
      longitude: -113.03,
      country_code: "US",
      admin1: "Utah",
    },
  ],
  Monterey: [
    {
      name: "Monterey",
      latitude: 38.41,
      longitude: -79.58,
      country_code: "US",
      admin1: "Virginia",
    },
    {
      name: "Monterey",
      latitude: 36.6,
      longitude: -121.89,
      country_code: "US",
      admin1: "California",
    },
  ],
  Springfield: [
    {
      name: "Springfield",
      latitude: 39.8,
      longitude: -89.64,
      country_code: "US",
      admin1: "Illinois",
    },
  ],
};

function assembly(researchNotesText = "") {
  return createPageAssembly({
    persist: { prompt: "Plan a road trip", requestId: "r", timezone: "UTC" },
    articleLead: false,
    messages: [],
    weatherPayloads: [],
    sources: new Map(),
    researchNotesText,
    verifiedActionURLs: new Set(),
    hotelCatalogs: new Map(),
    hotelSummaries: new Map(),
    places: new Map(),
    hotelGalleryTarget: null,
  });
}

function mapPage(places: { name: string; locality: string; ref?: string }[]): Block[] {
  return [
    {
      type: "map",
      id: "route-map",
      places: places.map((place) => ({
        ...place,
        searchQuery: `${place.name}, ${place.locality}`,
      })),
    },
  ];
}

async function groundedPlaces(page: Block[], researchNotesText?: string) {
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string) => {
      const name = new URL(url).searchParams.get("name") ?? "";
      return Response.json({ results: geocoder[name] });
    }),
  );
  const pageAssembly = assembly(researchNotesText);
  await pageAssembly.groundMapPlaces(page);
  const map = pageAssembly.projectPage(page).find((block) => block.type === "map");
  vi.unstubAllGlobals();
  return map?.type === "map" ? map.places.map(({ name, lat, lng }) => ({ name, lat, lng })) : [];
}

describe("map place grounding", () => {
  it("keeps real stops the research never named, at the geocoder's coordinates", async () => {
    const places = await groundedPlaces(
      mapPage([
        { name: "Zion National Park", locality: "Springdale, UT", ref: "zion" },
        { name: "Monterey", locality: "Monterey, CA" },
      ]),
      "A long research note about coastal drives that names neither stop at any point.",
    );
    expect(places).toEqual([
      { name: "Zion National Park", lat: 37.3, lng: -113.03 },
      { name: "Monterey", lat: 36.6, lng: -121.89 },
    ]);
  });

  it("drops places no evidence or geocoder can find in the stated area", async () => {
    const places = await groundedPlaces(
      mapPage([
        { name: "Sunset Cove Diner", locality: "Big Sur, CA" },
        { name: "Springfield", locality: "Springfield, MO" },
      ]),
      "A long research note about coastal drives that names neither stop at any point.",
    );
    expect(places).toEqual([]);
  });
});
