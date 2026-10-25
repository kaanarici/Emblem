import {
  attachHotelCardResources,
  expandHotelImageRefs,
  hotelBrowseRoomsAction,
} from "./travel/hotelContent";
import type { HotelSelection } from "./travel/hotelContent";
import { projectScopedHotelGalleries, type HotelGalleryTarget } from "./travel/hotelGallery";
import type { HotelDetails, HotelSummary } from "./travel/nuitee";
import type { PlaceRecord } from "./exa";
import { geocodePlace } from "./placeGeocode";
import { logEvent } from "@/lib/log";
import { requestsExplanation } from "@/lib/requestIntent";
import { pageCompositionIssues, type GenerationSource } from "@/lib/generationProtocol";
import { localizeVisibleMachineTimes } from "@/lib/presentationTime";
import { asksQuestions } from "@/lib/generationPreview";
import {
  attachVerifiedTitleLink,
  finalizePagePlan,
  verifiedPlannedAction,
  verifyRowLinks,
  type PageFinish,
} from "@/lib/responsePlan";
import { blockSchema, type Block } from "@/lib/schema";
import { type Action } from "@/lib/blockPrimitives";
import { canonicalizePlannedBlock, scrubBlockCopy } from "@/lib/blockCopy";
import { temporalGrounding } from "@/lib/temporalGrounding";
import { type WeatherPayload } from "@/lib/weather";
import { type SelectedCalendarEvent, withCalendarEventIcon } from "@/lib/calendarEventDrillIn";
import { withVerifiedWeather } from "@/lib/weatherComposition";
import { z } from "zod";

type MapPlace = Extract<Block, { type: "map" }>["places"][number];

type PageAssemblyContext = {
  persist: {
    prompt: string;
    requestId: string;
    timezone: string;
    articleTitle?: string;
    articleNeedsCover?: boolean;
    calendarEvent?: SelectedCalendarEvent;
  };
  articleLead: boolean;
  requiredInputOnly?: boolean;
  homeControl?: boolean;
  messages: { role: "user" | "assistant"; content: string }[];
  weatherPayloads: WeatherPayload[];
  sources: ReadonlyMap<string, GenerationSource>;
  researchNotesText: string;
  verifiedActionURLs: Set<string>;
  hotelCatalogs: ReadonlyMap<string, HotelDetails>;
  hotelSummaries: ReadonlyMap<string, HotelSummary>;
  places: ReadonlyMap<string, PlaceRecord>;
  hotelSelection?: HotelSelection;
  hotelGalleryTarget: HotelGalleryTarget | null;
};

export function createPageAssembly({
  persist,
  homeControl = false,
  articleLead,
  requiredInputOnly = false,
  messages,
  weatherPayloads,
  sources,
  researchNotesText,
  verifiedActionURLs,
  hotelCatalogs,
  hotelSummaries,
  places,
  hotelSelection,
  hotelGalleryTarget,
}: PageAssemblyContext) {
  const normalizeEvidence = (value: string): string =>
    value
      .normalize("NFKC")
      .toLocaleLowerCase()
      .replace(/[^\p{L}\p{N}]+/gu, " ")
      .trim();
  const geocoded = new Map<string, Omit<PlaceRecord, "ref"> | null>();
  const lookups = new Map<string, Promise<void>>();
  return { finalizePage, projectPage, groundMapPlaces, canonicalComposerBlock };

  function mapGrounding() {
    const evidence = normalizeEvidence(
      [
        ...Array.from(sources.values()).flatMap(({ title, snippet }) =>
          snippet ? [title, snippet] : [title],
        ),
        researchNotesText,
      ].join("\n"),
    );
    const records = new Map<string, Omit<PlaceRecord, "ref">>(places);
    for (const hotel of [...hotelSummaries.values(), ...hotelCatalogs.values()]) {
      if (!hotel.location) continue;
      records.set(hotel.id, {
        name: hotel.name,
        lat: hotel.location.latitude,
        lng: hotel.location.longitude,
        ...(hotel.address ? { address: hotel.address } : {}),
      });
    }
    const recordsByName = new Map(
      [...records.values()].map((record) => [normalizeEvidence(record.name), record]),
    );
    return { evidence, records, recordsByName };
  }

  function placeRecord(
    place: MapPlace,
    { evidence, records, recordsByName }: ReturnType<typeof mapGrounding>,
  ): Omit<PlaceRecord, "ref"> | "evidence" | null | undefined {
    const record = place.ref
      ? records.get(place.ref)
      : recordsByName.get(normalizeEvidence(place.name));
    if (record) return record;
    if (
      !place.ref &&
      records.size === 0 &&
      (evidence.length <= 40 ||
        evidence.includes(normalizeEvidence(place.name)) ||
        evidence.includes(normalizeEvidence(place.searchQuery)))
    ) {
      return "evidence";
    }
    const key = normalizeEvidence(`${place.name} ${place.locality}`);
    if (!lookups.has(key)) {
      lookups.set(
        key,
        geocodePlace(place.name, place.locality).then((hit) => {
          geocoded.set(key, hit);
        }),
      );
    }
    return geocoded.get(key);
  }

  async function groundMapPlaces(page: Block[]) {
    const grounding = mapGrounding();
    for (const block of page) {
      if (block.type === "map") block.places.forEach((place) => placeRecord(place, grounding));
    }
    await Promise.all(lookups.values());
  }

  function finalizePage(
    page: Block[],
    finish: PageFinish | null,
    dateGrounding: ReturnType<typeof temporalGrounding>,
  ) {
    const finalized = finalizePagePlan(
      withVerifiedWeather(page, weatherPayloads, persist.prompt),
      finish,
      {
        articleLead,
        requiredInputOnly,
        articleTitle: persist.articleTitle,
        explanationIntent: requestsExplanation(persist.prompt),
      },
    );

    const hotel = hotelSelection ? hotelCatalogs.get(hotelSelection.hotelId) : undefined;
    const browse =
      hotel &&
      (!hotelSelection?.roomId || hotel.rooms.some(({ id }) => id === hotelSelection.roomId))
        ? hotelBrowseRoomsAction(hotel)
        : null;
    const planned = finish?.primaryAction;
    const catalogBrowse =
      browse &&
      planned?.kind === "prompt" &&
      planned.label === browse.label &&
      planned.prompt === browse.prompt
        ? browse
        : null;
    const proposedAction: Action | null = finalized.needsInput
      ? (finalized.inputAction ?? null)
      : finalized.hasEditableInputs
        ? { label: "Continue", prompt: "Continue" }
        : finish?.primaryAction && finish.primaryAction.kind !== "none"
          ? (catalogBrowse ??
            verifiedPlannedAction(finish.primaryAction, verifiedActionURLs, persist.requestId, {
              messages,
              verifiedEvidence: Array.from(sources.values()).flatMap(({ title, snippet }) =>
                snippet ? [title, snippet] : [title],
              ),
            }))
          : null;
    const finalPage: z.infer<typeof blockSchema>[] = attachVerifiedTitleLink(
      finalized.blocks.map((block) =>
        canonicalizePlannedBlock(
          block.type === "pageMeta"
            ? {
                ...block,
                ask: asksQuestions(finalized.blocks) || undefined,
                ...(proposedAction ? { dockAction: proposedAction } : { dockAction: undefined }),
              }
            : block,
          proposedAction,
        ),
      ),
      proposedAction,
      verifiedActionURLs,
    );
    const issues = [...pageCompositionIssues(finalPage), ...dateGrounding.issues(finalPage)];
    if (page.some((block) => block.type === "weather") && weatherPayloads.length === 0) {
      issues.push("weather block requires a successful weather tool result");
    }
    if (
      !finalized.needsInput &&
      weatherPayloads.length > 0 &&
      !finalPage.some((block) => block.type === "weather")
    ) {
      issues.push("successful weather lookup requires the native weather block");
    }
    return { blocks: finalPage, issues: [...new Set(issues)] };
  }

  function projectPage(page: Block[]) {
    let finalPage = localizeVisibleMachineTimes(
      homeControl ? page : page.filter((block) => block.type !== "homeControl"),
      persist.timezone,
    );

    const grounding = mapGrounding();
    const mode = requestedRouteMode(persist.prompt);
    finalPage = finalPage.flatMap((block): typeof finalPage => {
      if (block.type === "route" && mode) return [{ ...block, mode }];
      if (block.type !== "map") return [block];
      let pending = false;
      const kept = block.places.flatMap((mapPlace) => {
        const { ref: _ref, lat: _lat, lng: _lng, address: _a, ...place } = mapPlace;
        const record = placeRecord(mapPlace, grounding);
        if (record === "evidence") return [place];
        if (record === undefined) pending = true;
        if (!record) return [];
        return [
          {
            ...place,
            lat: record.lat,
            lng: record.lng,
            ...(record.address ? { address: record.address } : {}),
            ...(record.rating
              ? {
                  rating:
                    record.rating.score.toFixed(1) +
                    (record.rating.count
                      ? ` (${record.rating.count.toLocaleString("en-US")})`
                      : ""),
                }
              : {}),
          },
        ];
      });
      if (kept.length === 0) {
        if (!pending) {
          logEvent("warn", "map dropped: no evidence-grounded places", {
            requested: block.places.length,
          });
        }
        return [];
      }
      if (kept.length < block.places.length && !pending) {
        logEvent("warn", "map places pruned", { pruned: block.places.length - kept.length });
      }
      return [{ ...block, places: kept }];
    });
    const coverTitle = persist.articleTitle?.trim();
    if (
      persist.articleNeedsCover &&
      coverTitle &&
      !finalPage.some((block) => block.type === "hero")
    ) {
      const metaIndex = finalPage.findIndex((block) => block.type === "pageMeta");
      finalPage.splice(metaIndex + 1, 0, {
        type: "hero",
        id: "article-cover",
        image: { query: coverTitle, kind: "photo", aspect: "landscape" },
        aspect: "wide",
      });
    }
    if (persist.calendarEvent) finalPage = withCalendarEventIcon(finalPage, persist.calendarEvent);
    const hotel = hotelSelection ? hotelCatalogs.get(hotelSelection.hotelId) : undefined;
    if (
      hotel &&
      (!hotelSelection?.roomId || hotel.rooms.some(({ id }) => id === hotelSelection.roomId))
    ) {
      finalPage = finalPage.map((block) =>
        block.type === "pageMeta"
          ? {
              ...block,
              savePresentation: {
                categoryKey: "hotels-vacation-rentals",
                categoryTitle: "Hotels & vacation rentals",
              },
            }
          : block,
      );
    }
    return attachHotelCardResources(
      projectScopedHotelGalleries(finalPage, hotelGalleryTarget),
      hotelSummaries,
      hotelCatalogs,
    );
  }

  function canonicalComposerBlock(block: z.infer<typeof blockSchema>): z.infer<typeof blockSchema> {
    block = expandHotelImageRefs(block, hotelSummaries, hotelCatalogs);
    const weather =
      block.type === "weather"
        ? (weatherPayloads.find((payload) => {
            const payloadLocation = normalizeEvidence(payload.location);
            const blockLocation = normalizeEvidence(block.location);
            return (
              payloadLocation === blockLocation ||
              payloadLocation.includes(blockLocation) ||
              blockLocation.includes(payloadLocation)
            );
          }) ?? (weatherPayloads.length === 1 ? weatherPayloads[0] : undefined))
        : undefined;
    if (block.type === "weather" && weatherPayloads.length > 0 && !weather) {
      throw new Error("weather block does not match a successful weather tool result");
    }
    const groundedBlock = block.type === "weather" && weather ? { ...block, ...weather } : block;
    const actionCanonicalBlock =
      groundedBlock.type === "pageMeta"
        ? { ...groundedBlock, dockAction: undefined }
        : verifyRowLinks(groundedBlock, verifiedActionURLs);
    return canonicalizePlannedBlock(scrubBlockCopy(actionCanonicalBlock), null);
  }
}

function requestedRouteMode(prompt: string): "driving" | "walking" | "transit" | undefined {
  const text = prompt.toLocaleLowerCase();
  if (/\b(walk|walking|walkable|on foot)\b/.test(text)) return "walking";
  if (/\b(transit|public transport|bus|train|subway|metro)\b/.test(text)) return "transit";
  if (/\b(drive|driving|by car)\b/.test(text)) return "driving";
  return undefined;
}
