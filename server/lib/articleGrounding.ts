import type { GenerationSource } from "./generationProtocol";

export function articleGroundingFrom(blocksJSON: string, focusTitle?: string): string | undefined {
  let blocks: unknown[];
  try {
    blocks = JSON.parse(blocksJSON) as unknown[];
  } catch {
    return undefined;
  }
  const lines: string[] = [];
  const push = (value: unknown) => {
    if (typeof value === "string" && value.trim()) lines.push(value.trim());
  };
  for (const raw of blocks) {
    if (!raw || typeof raw !== "object") continue;
    const block = raw as Record<string, unknown>;
    push(block.body);
    push(block.summary);
    for (const key of ["cards", "rows", "items", "facts", "spots", "features", "events"]) {
      const entries = block[key];
      if (!Array.isArray(entries)) continue;
      for (const entry of entries) {
        if (!entry || typeof entry !== "object") continue;
        const item = entry as Record<string, unknown>;
        const title =
          typeof item.title === "string"
            ? item.title
            : typeof item.label === "string"
              ? item.label
              : "";
        const detail =
          typeof item.caption === "string"
            ? item.caption
            : typeof item.subtitle === "string"
              ? item.subtitle
              : typeof item.value === "string"
                ? item.value
                : key === "events"
                  ? [block.dayLabel, item.timeRange, item.place]
                      .filter((part) => typeof part === "string" && part.trim())
                      .join(" · ")
                  : "";
        const line = [title, detail].filter(Boolean).join(": ");
        if (!line) continue;
        if (focusTitle && title.toLowerCase() === focusTitle.toLowerCase()) {
          lines.unshift(`SELECTED: ${line}`);
        } else {
          lines.push(line);
        }
      }
    }
  }
  const text = lines.join("\n").slice(0, 2_600);
  return text.trim() ? text : undefined;
}

export function storedGenerationSources(
  sourcesJSON: string | undefined | null,
): GenerationSource[] {
  if (!sourcesJSON) return [];
  try {
    const parsed = JSON.parse(sourcesJSON) as unknown[];
    return parsed.filter((item): item is GenerationSource =>
      Boolean(
        item &&
        typeof item === "object" &&
        typeof (item as GenerationSource).id === "string" &&
        typeof (item as GenerationSource).url === "string",
      ),
    );
  } catch {
    return [];
  }
}
