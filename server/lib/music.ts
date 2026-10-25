import type { Block } from "./schema";

type MusicBlock = Extract<Block, { type: "music" }>;
type MusicTrack = MusicBlock["tracks"][number];

const SEARCH_URL = "https://itunes.apple.com/search";
const TIMEOUT_MS = 3000;

const resultSchema = (
  value: unknown,
): value is {
  trackName: string;
  artistName: string;
  collectionName?: string;
  artworkUrl100?: string;
  previewUrl?: string;
  trackViewUrl?: string;
} => {
  if (!value || typeof value !== "object") return false;
  const record = value as Record<string, unknown>;
  return typeof record.trackName === "string" && typeof record.artistName === "string";
};

function https(value: string | undefined): string | undefined {
  if (!value) return undefined;
  try {
    const url = new URL(value);
    return url.protocol === "https:" ? url.toString() : undefined;
  } catch {
    return undefined;
  }
}

function comparable(value: string): string {
  return value
    .normalize("NFKD")
    .toLocaleLowerCase()
    .replace(/\(.*?\)|\[.*?\]/g, "")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

export async function searchMusic(term: string, limit = 1): Promise<MusicTrack[]> {
  const url = new URL(SEARCH_URL);
  url.searchParams.set("term", term.slice(0, 200));
  url.searchParams.set("entity", "song");
  url.searchParams.set("limit", String(Math.min(Math.max(limit, 1), 10)));
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS) });
    if (!response.ok) return [];
    const body = (await response.json()) as { results?: unknown[] };
    return (body.results ?? []).filter(resultSchema).map((result) => ({
      name: result.trackName,
      artist: result.artistName,
      album: result.collectionName,
      art: https(result.artworkUrl100?.replace(/\/\d+x\d+bb\./, "/600x600bb.")),
      preview: https(result.previewUrl),
      url: https(result.trackViewUrl),
    }));
  } catch {
    return [];
  }
}

export function appleMusicSearchURL(term: string): string {
  const url = new URL("https://music.apple.com/us/search");
  url.searchParams.set("term", term.slice(0, 200));
  return url.toString();
}

async function resolveMusicTrack(track: MusicTrack): Promise<MusicTrack> {
  const candidates = await searchMusic(`${track.name} ${track.artist}`, 10);
  const name = comparable(track.name);
  const artist = comparable(track.artist);
  return (
    candidates.find((candidate) => {
      const candidateArtist = comparable(candidate.artist);
      return (
        comparable(candidate.name).startsWith(name) &&
        (candidateArtist.includes(artist) || artist.includes(candidateArtist))
      );
    }) ?? {
      name: track.name,
      artist: track.artist,
      url: appleMusicSearchURL(`${track.name} ${track.artist}`),
    }
  );
}

export async function resolvePageMusic(page: Block[]): Promise<Block[]> {
  if (!page.some((block) => block.type === "music")) return page;
  return await Promise.all(
    page.map(async (block) =>
      block.type === "music"
        ? { ...block, tracks: await Promise.all(block.tracks.map(resolveMusicTrack)) }
        : block,
    ),
  );
}
