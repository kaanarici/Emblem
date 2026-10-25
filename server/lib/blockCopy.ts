import { z } from "zod";
import { type Block } from "./schema";
import { icon, type Action } from "./blockPrimitives";
import { parseHotelPhotoQuery, hotelResourceID } from "./travel/hotelContent";

function procedureObjectQuery(step: { title: string; body: string; sym?: string }): string {
  const copy = `${step.title} ${step.body}`.toLocaleLowerCase();
  const semanticObjects: Array<[RegExp, string]> = [
    [/\b(?:preheat|oven)\b/, "oven"],
    [/\b(?:dry ingredients?|flour)\b/, "flour bag"],
    [/\b(?:wet ingredients?|whisk|mix)\b/, "mixing bowl"],
    [/\b(?:combine|fold)\b/, "spatula"],
    [/\b(?:chocolate|chips?)\b/, "chocolate chips"],
    [/\b(?:chill|refrigerat|freeze)\w*\b/, "refrigerator"],
    [/\b(?:scoop|portion|space)\w*\b/, "cookie scoop"],
    [/\bbak(?:e|ing)\b/, "baking tray"],
    [/\b(?:cool|rack)\w*\b/, "cooling rack"],
  ];
  return (
    semanticObjects.find(([pattern]) => pattern.test(copy))?.[1] ??
    step.sym?.replace(/[._-]+/g, " ") ??
    step.title
  );
}

function scrubCopy(value: string): string {
  return value
    .replace(/`+/g, "")
    .replace(/([.!?)\u201d"'])[\s,;:\-\u2010-\u2015]+$/u, "$1")
    .trimEnd();
}

type OptionalIcon = { icon?: z.infer<typeof icon> };

function hasCompleteIconSet(items: readonly OptionalIcon[]): boolean {
  return (
    items.length > 0 &&
    items.every(({ icon: value }) =>
      Boolean(value?.sym?.trim() || value?.emoji?.trim() || value?.image?.query.trim()),
    )
  );
}

function domainizeProvenance(value: string): string {
  return value
    .replace(/https?:\/\/[^\s)"']+/gi, (raw) => {
      try {
        return new URL(raw).hostname.replace(/^www\./, "");
      } catch {
        return "";
      }
    })
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 40);
}

export function scrubBlockCopy(block: Block): Block {
  switch (block.type) {
    case "text":
      return { ...block, body: scrubCopy(block.body) };
    case "stepCarousel":
      return {
        ...block,
        steps: block.steps.map((step) => ({
          ...step,
          title: scrubCopy(step.title),
          body: scrubCopy(step.body),
          ...(step.meta == null ? {} : { meta: scrubCopy(step.meta) }),
        })),
      };
    case "cardCarousel":
      return {
        ...block,
        cards: block.cards.map((card) => ({
          ...card,
          title: scrubCopy(card.title),
          ...(card.caption == null ? {} : { caption: scrubCopy(card.caption) }),
          ...(card.meta == null ? {} : { meta: scrubCopy(card.meta) }),
          ...(card.strap == null ? {} : { strap: scrubCopy(card.strap) }),
          ...(card.tag == null ? {} : { tag: scrubCopy(card.tag).slice(0, 24) }),
        })),
      };
    case "ratingRow":
      return { ...block, text: domainizeProvenance(scrubCopy(block.text)) };
    case "statRow":
      return {
        ...block,
        stats: block.stats.map((stat) => ({
          ...stat,
          label: domainizeProvenance(stat.label),
        })),
      };
    case "reviewSummary":
      return {
        ...block,
        ...(block.sources == null
          ? {}
          : {
              sources: block.sources
                .filter((source) => /\d/.test(source.score))
                .map((source) => ({
                  ...source,
                  score: source.score.slice(0, 8),
                  source: domainizeProvenance(source.source),
                })),
            }),
        themes: block.themes.map((theme) => ({
          ...theme,
          ...(theme.attribution == null
            ? {}
            : {
                attribution: domainizeProvenance(theme.attribution),
              }),
        })),
      };
    case "featureList": {
      const everyIcon = hasCompleteIconSet(block.items);
      return {
        ...block,
        items: block.items.map((item) => ({
          ...item,
          ...(everyIcon ? {} : { icon: undefined }),
          title: scrubCopy(item.title),
          ...(item.caption == null ? {} : { caption: scrubCopy(item.caption) }),
        })),
      };
    }
    case "mediaRowList": {
      const everyIcon = hasCompleteIconSet(block.rows);
      return {
        ...block,
        rows: block.rows.map((row) => ({
          ...row,
          ...(everyIcon ? {} : { icon: undefined }),
        })),
      };
    }
    case "factList": {
      const everyIcon = hasCompleteIconSet(block.facts);
      return {
        ...block,
        facts: block.facts.map((fact) => ({
          ...fact,
          ...(everyIcon ? {} : { icon: undefined }),
        })),
      };
    }
    case "listBlock": {
      const everyIcon = hasCompleteIconSet(block.items);
      return {
        ...block,
        items: block.items.map((item) => ({
          ...item,
          ...(everyIcon ? {} : { icon: undefined }),
          text: scrubCopy(item.text),
        })),
      };
    }
    default:
      return block;
  }
}

function dedupeByText<T>(items: readonly T[], key: (item: T) => string): T[] {
  const seen = new Set<string>();
  return items.filter((item) => {
    const k = key(item).normalize("NFKC").trim().toLocaleLowerCase();
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}

function dedupeCollectionEntries(block: Block): Block {
  switch (block.type) {
    case "cardCarousel": {
      const seenCards = new Set<string>();
      return {
        ...block,
        cards: block.cards.filter((card) => {
          const ref = card.image ? parseHotelPhotoQuery(card.image.query) : null;
          const key = ref
            ? `catalog:${hotelResourceID(ref)}`
            : `text:${`${card.title}\u{1F}${card.caption ?? ""}`.normalize("NFKC").trim().toLocaleLowerCase()}`;
          if (seenCards.has(key)) return false;
          seenCards.add(key);
          return true;
        }),
      };
    }
    case "itemGrid":
      return {
        ...block,
        items: dedupeByText(block.items, (item) => `${item.title}\u{1F}${item.caption ?? ""}`),
      };
    case "mediaRowList":
      return {
        ...block,
        rows: dedupeByText(block.rows, (row) => `${row.title}\u{1F}${row.subtitle ?? ""}`),
      };
    case "spotList":
      return {
        ...block,
        spots: dedupeByText(block.spots, (spot) => `${spot.name}\u{1F}${spot.caption ?? ""}`),
      };
    case "featureList":
      return {
        ...block,
        items: dedupeByText(block.items, (item) => `${item.title}\u{1F}${item.caption ?? ""}`),
      };
    default:
      return block;
  }
}

export function canonicalizePlannedBlock(block: Block, primaryAction?: Action | null): Block {
  block = dedupeCollectionEntries(block);
  if (block.type === "timeAsk" && primaryAction?.calendar) {
    return { ...block, question: primaryAction.calendar.timeAnswerKey };
  }
  if (block.type === "itemGrid") {
    return {
      ...block,
      items: block.items.map((item) => ({
        ...item,
        icon: {
          ...item.icon,
          image:
            item.icon?.image?.kind === "object"
              ? item.icon.image
              : { query: item.title, kind: "object" as const },
        },
      })),
    };
  }
  if (block.type === "stepCarousel") {
    return {
      ...block,
      steps: block.steps.map((step) => ({
        ...step,
        icon: {
          ...step.icon,
          sym: step.icon?.sym ?? step.sym,
          image:
            step.icon?.image?.kind === "object"
              ? step.icon.image
              : {
                  query: procedureObjectQuery({
                    title: step.title,
                    body: step.body,
                    sym: step.icon?.sym ?? step.sym,
                  }),
                  kind: "object" as const,
                },
        },
      })),
    };
  }
  if (block.type === "map") {
    return {
      ...block,
      places: block.places.map((place) => ({
        ...place,
        searchQuery: `${place.name}, ${place.locality}`,
      })),
    };
  }
  if (block.type === "route") {
    const plannedDestination =
      primaryAction?.native === "directions" ? primaryAction.destination : undefined;
    return {
      ...block,
      destination: {
        name: plannedDestination?.name ?? block.destination.name,
        locality: plannedDestination?.locality ?? block.destination.locality,
        searchQuery:
          plannedDestination?.query ?? `${block.destination.name}, ${block.destination.locality}`,
      },
      mode: plannedDestination?.mode ?? block.mode,
    };
  }
  return block;
}
