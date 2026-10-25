import type { GenerationActivity, GenerationSource } from "@/lib/generationProtocol";
import { harvestHTTPURLs, userSuppliedHTTPURLs } from "@/lib/actionGrounding";
import { weatherLocationKey, type WeatherPayload } from "@/lib/weather";

const MAX_WEATHER_PAYLOADS = 3;
const MAX_CITED_SOURCES = 12;
const PRIVATE_SOURCE_DOMAINS = new Set(["mail.google.com"]);

type DatedSource = Pick<GenerationSource, "title" | "url" | "snippet">;

export type GenerationEvidence = {
  readonly activities: Map<string, GenerationActivity>;
  readonly sources: Map<string, GenerationSource>;
  readonly citedSourceIDs: Set<string>;
  readonly verifiedActionURLs: Set<string>;
  readonly weatherPayloads: WeatherPayload[];
  readonly datedSources: DatedSource[];
  researchNotes: string;
};

export function createGenerationEvidence(
  messages: readonly { role: "user" | "assistant"; content: string }[],
): GenerationEvidence {
  return {
    activities: new Map(),
    sources: new Map(),
    citedSourceIDs: new Set(),
    verifiedActionURLs: userSuppliedHTTPURLs([...messages]),
    weatherPayloads: [],
    datedSources: [],
    researchNotes: "",
  };
}

export function addSources(evidence: GenerationEvidence, items: readonly GenerationSource[]): void {
  for (const item of items) {
    evidence.sources.set(item.id, item);
    evidence.citedSourceIDs.add(item.id);
    if (!PRIVATE_SOURCE_DOMAINS.has(item.domain)) evidence.verifiedActionURLs.add(item.url);
  }
}

export function addWeather(evidence: GenerationEvidence, weather: WeatherPayload): void {
  const locationKey = weatherLocationKey(weather);
  const existing = evidence.weatherPayloads.findIndex(
    (item) =>
      (locationKey ? weatherLocationKey(item) === locationKey : item === weather) &&
      item.focusDay === weather.focusDay,
  );
  if (existing >= 0) evidence.weatherPayloads[existing] = weather;
  else if (evidence.weatherPayloads.length < MAX_WEATHER_PAYLOADS)
    evidence.weatherPayloads.push(weather);
}

export function recordResearchNotes(evidence: GenerationEvidence, notes: string | null): void {
  if (notes) harvestHTTPURLs(notes, evidence.verifiedActionURLs);
  evidence.researchNotes = notes ?? "";
  for (const activity of evidence.activities.values()) {
    if (activity.status !== "started") continue;
    evidence.activities.set(activity.id, {
      ...activity,
      status: "failed",
      message: `${activity.title} did not finish`,
    });
  }
}

export function citedSources(evidence: GenerationEvidence): GenerationSource[] {
  return Array.from(evidence.citedSourceIDs)
    .flatMap((id) => evidence.sources.get(id) ?? [])
    .slice(0, MAX_CITED_SOURCES);
}
