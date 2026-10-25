import { exaSearch } from "./exa";
import { appleMusicSearchURL } from "./music";
import type { Block } from "./schema";

type Service = {
  domain: string;
  names: RegExp;
  label: string;
  search: (term: string) => string;
};

const withParam = (base: string, key: string) => (term: string) => {
  const url = new URL(base);
  url.searchParams.set(key, term);
  return url.toString();
};

const withPath = (base: string) => (term: string) => `${base}${encodeURIComponent(term)}`;

const SERVICES: Service[] = [
  {
    domain: "open.spotify.com",
    names: /\bspotify\b/,
    label: "Listen",
    search: withPath("https://open.spotify.com/search/"),
  },
  {
    domain: "music.apple.com",
    names: /\bapple music\b|\bitunes\b/,
    label: "Listen",
    search: appleMusicSearchURL,
  },
  {
    domain: "music.youtube.com",
    names: /\byoutube music\b/,
    label: "Listen",
    search: withParam("https://music.youtube.com/search", "q"),
  },
  {
    domain: "music.amazon.com",
    names: /\bamazon music\b/,
    label: "Listen",
    search: withPath("https://music.amazon.com/search/"),
  },
  {
    domain: "tidal.com",
    names: /\btidal\b/,
    label: "Listen",
    search: withParam("https://tidal.com/search", "q"),
  },
  {
    domain: "soundcloud.com",
    names: /\bsoundcloud\b/,
    label: "Listen",
    search: withParam("https://soundcloud.com/search", "q"),
  },
  {
    domain: "deezer.com",
    names: /\bdeezer\b/,
    label: "Listen",
    search: withPath("https://www.deezer.com/search/"),
  },
  {
    domain: "tv.apple.com",
    names: /\bapple tv\b/,
    label: "Watch",
    search: withParam("https://tv.apple.com/search", "term"),
  },
  {
    domain: "primevideo.com",
    names: /\bprime video\b|\bamazon prime\b/,
    label: "Watch",
    search: withParam("https://www.primevideo.com/search", "phrase"),
  },
  {
    domain: "netflix.com",
    names: /\bnetflix\b/,
    label: "Watch",
    search: withParam("https://www.netflix.com/search", "q"),
  },
  {
    domain: "hulu.com",
    names: /\bhulu\b/,
    label: "Watch",
    search: withParam("https://www.hulu.com/search", "q"),
  },
  {
    domain: "disneyplus.com",
    names: /\bdisney\s?\+|\bdisney plus\b/,
    label: "Watch",
    search: withParam("https://www.disneyplus.com/search", "q"),
  },
  {
    domain: "max.com",
    names: /\bhbo max\b|^max$/,
    label: "Watch",
    search: withParam("https://play.max.com/search", "q"),
  },
  {
    domain: "peacocktv.com",
    names: /\bpeacock\b/,
    label: "Watch",
    search: withParam("https://www.peacocktv.com/search", "q"),
  },
  {
    domain: "paramountplus.com",
    names: /\bparamount\s?\+|\bparamount plus\b/,
    label: "Watch",
    search: withParam("https://www.paramountplus.com/search/", "q"),
  },
  {
    domain: "youtube.com",
    names: /\byoutube\b/,
    label: "Watch",
    search: withParam("https://www.youtube.com/results", "search_query"),
  },
];

const LEADING_FILLER =
  /^(where (can i |to )?(watch|stream|listen to|listen|buy|find)|how to (watch|stream|listen to)|watch|stream|listen to|listen)\s+/i;

function hostOf(value: string | undefined): string {
  if (!value) return "";
  try {
    return new URL(value.includes("://") ? value : `https://${value}`).hostname
      .toLowerCase()
      .replace(/^www\./, "");
  } catch {
    return "";
  }
}

function serviceFor(title: string, site: string | undefined): Service | undefined {
  const host = hostOf(site);
  const name = title.toLowerCase();
  return (
    SERVICES.find((service) => service.names.test(name)) ??
    SERVICES.find((service) => host === service.domain || host.endsWith(`.${service.domain}`))
  );
}

function serviceLinkSubject(page: readonly Block[]): string | null {
  const title = page.find((block) => block.type === "titleBlock");
  if (title?.type === "titleBlock" && title.title.trim()) return title.title.trim();
  const meta = page.find((block) => block.type === "pageMeta");
  const heading = meta?.type === "pageMeta" ? (meta.title?.trim() ?? "") : "";
  const subject = heading.replace(LEADING_FILLER, "").trim();
  return subject || null;
}

async function directLink(service: Service, subject: string): Promise<string | null> {
  try {
    const results = await exaSearch(subject, false, {
      includeDomains: [service.domain],
      numResults: 3,
      timeoutMs: 2500,
    });
    const match = results.find(({ url }) => {
      const host = hostOf(url);
      const path = URL.canParse(url) ? new URL(url).pathname : "/";
      return (host === service.domain || host.endsWith(`.${service.domain}`)) && path.length > 1;
    });
    return match?.url ?? null;
  } catch {
    return null;
  }
}

export async function resolveServiceLinks(page: Block[]): Promise<Block[]> {
  const subject = serviceLinkSubject(page);
  if (!subject) return page;
  return Promise.all(
    page.map(async (block) => {
      if (block.type !== "mediaRowList") return block;
      const rows = await Promise.all(
        block.rows.map(async (row) => {
          if (row.action?.url) return row;
          const service = serviceFor(row.title, row.site);
          if (!service) return row;
          const url = (await directLink(service, subject)) ?? service.search(subject);
          return {
            ...row,
            site: row.site ?? service.domain,
            action: { label: service.label, url },
          };
        }),
      );
      return { ...block, rows };
    }),
  );
}
