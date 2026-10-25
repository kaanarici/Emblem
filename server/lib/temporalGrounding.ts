import type { Block } from "./schema";
import type { GenerationSource } from "./generationProtocol";

const months =
  "Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?";
const monthNumbers = [
  "jan",
  "feb",
  "mar",
  "apr",
  "may",
  "jun",
  "jul",
  "aug",
  "sep",
  "oct",
  "nov",
  "dec",
];
const currentWords = /\b(?:current(?:ly)?|today|right now|on view|on display)\b/i;
const nonCurrentWords = /\b(?:upcoming|future|past|previous|archived|coming soon|opening soon)\b/i;
const futureNotice = new RegExp(
  `\\b(?:upcoming|not yet|will open|will be on view|opening soon|has not opened|hasn['’]t opened|opens?\\s+(?:on\\s+)?(?:${months}|\\d))\\b`,
  "i",
);
const normalize = (text: string) =>
  text
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
type Range = { start?: string; end?: string };
type SourceEvidence = Pick<GenerationSource, "title" | "snippet" | "url">;
type ItemEvidence = SourceEvidence & { notCurrent?: boolean };
type DatedSource = Range & { title: string; entity: string; url: string };

function date(year: number, month: number, day: number): string | undefined {
  const value = new Date(Date.UTC(year, month, day));
  return value.getUTCFullYear() === year &&
    value.getUTCMonth() === month &&
    value.getUTCDate() === day
    ? value.toISOString().slice(0, 10)
    : undefined;
}

function ranges(text: string): Range[] {
  const result: Range[] = [];
  const pattern = new RegExp(
    `\\b(${months})\\.?\\s+(\\d{1,2})(?:,?\\s+(\\d{4}))?\\s*[–—-]\\s*(?:(${months})\\.?\\s+)?(\\d{1,2})(?:,?\\s+(\\d{4}))?\\b`,
    "gi",
  );
  for (const match of text.matchAll(pattern)) {
    if (!match[3] && !match[6]) continue;
    const firstMonth = monthNumbers.indexOf(match[1].slice(0, 3).toLowerCase());
    const lastMonth = match[4]
      ? monthNumbers.indexOf(match[4].slice(0, 3).toLowerCase())
      : firstMonth;
    const firstYear = Number(match[3] ?? Number(match[6]) - Number(firstMonth > lastMonth));
    const lastYear = Number(match[6] ?? firstYear + Number(lastMonth < firstMonth));
    const start = date(firstYear, firstMonth, Number(match[2]));
    const end = date(lastYear, lastMonth, Number(match[5]));
    if (start && end && start <= end) result.push({ start, end });
  }
  const endpoints = new RegExp(
    `\\b(through|until|ends?|opens?|starts?|begins?)\\s+(${months})\\.?\\s+(\\d{1,2}),?\\s+(\\d{4})\\b`,
    "gi",
  );
  for (const match of text.matchAll(endpoints)) {
    const value = date(
      Number(match[4]),
      monthNumbers.indexOf(match[2].slice(0, 3).toLowerCase()),
      Number(match[3]),
    );
    if (value)
      result.push(/^(through|until|end)/i.test(match[1]) ? { end: value } : { start: value });
  }
  return result;
}

function evidenceItems(sources: readonly SourceEvidence[]): ItemEvidence[] {
  return sources.flatMap((source) => {
    if (typeof source.title !== "string" || typeof source.snippet !== "string") return [];
    const items: ItemEvidence[] = [{ ...source, snippet: source.snippet.slice(0, 700) }];
    let section: boolean | undefined;
    let title = "";
    let lines: string[] = [];
    const finish = () => {
      if (title && section !== undefined)
        items.push({
          title,
          url: source.url,
          snippet: [title, ...lines].join("\n"),
          notCurrent: !section,
        });
      title = "";
      lines = [];
    };
    for (const line of source.snippet.split("\n")) {
      if (/^#{1,6}\s/.test(line)) {
        finish();
        section = currentWords.test(line) ? true : nonCurrentWords.test(line) ? false : undefined;
      } else if (/^[-*]\s/.test(line)) {
        finish();
        title = line.replace(/^[-*]\s+/, "").trim();
      } else if (title) lines.push(line);
    }
    finish();
    return items;
  });
}

function explicitDates(text: string) {
  const pattern = new RegExp(`\\b(${months})\\.?\\s+(\\d{1,2})(?:,?\\s+(\\d{4}))?\\b`, "gi");
  return [...text.matchAll(pattern)].flatMap((match) => {
    const month = monthNumbers.indexOf(match[1].slice(0, 3).toLowerCase());
    const day = Number(match[2]);
    if (match[3] && !date(Number(match[3]), month, day)) return [];
    return [{ month, day, year: match[3] ? Number(match[3]) : undefined }];
  });
}

function outside(range: Range, today: string): boolean {
  return Boolean((range.start && range.start > today) || (range.end && range.end < today));
}

function visibleText(value: unknown): string {
  if (!value || typeof value !== "object") return "";
  return Object.entries(value)
    .flatMap(([key, child]) => {
      if (
        [
          "title",
          "label",
          "name",
          "value",
          "body",
          "text",
          "summary",
          "caption",
          "subtitle",
          "detail",
        ].includes(key) &&
        typeof child === "string"
      )
        return child;
      return [];
    })
    .join(" ");
}

export function requestsDatedListing(request: string): boolean {
  return (
    /\b(?:exhibitions?|on view|on display)\b/i.test(request) &&
    /\b(?:current(?:ly)?|today|tonight|now|upcoming|on view|on display|this (?:week|month|year))\b/i.test(
      request,
    )
  );
}

export function temporalGrounding(
  request: string,
  sources: readonly SourceEvidence[],
  timezone: string,
  now = new Date(),
) {
  let today: string;
  try {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      calendar: "gregory",
      numberingSystem: "latn",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(now);
    today = ["year", "month", "day"]
      .map((type) => parts.find((part) => part.type === type)!.value)
      .join("-");
  } catch {
    today = now.toISOString().slice(0, 10);
  }
  const explicitCurrent = /\b(?:current(?:ly)?|on view|on display|right now)\b/i.test(request);
  const futureOnly =
    (nonCurrentWords.test(request) || /\bafter today\b/i.test(request)) && !explicitCurrent;
  const active =
    requestsDatedListing(request) &&
    currentWords.test(request) &&
    !futureOnly &&
    !/\b(?:yesterday|tomorrow|as of|on\s+\d{4}-|(?:19|20)\d{2})\b/i.test(request);
  const items = active ? evidenceItems(sources) : [];
  const dated: DatedSource[] = items.flatMap((source) => {
    const entity = normalize(source.title.split(/[|:]/, 1)[0]);
    if (entity.length < 4 || !normalize(source.snippet ?? "").includes(entity)) return [];
    const outsideDates = ranges(source.snippet ?? "").filter((range) => outside(range, today));
    return (source.notCurrent && outsideDates.length === 0 ? [{}] : outsideDates).map((range) => ({
      ...range,
      title: source.title,
      entity,
      url: source.url,
    }));
  });
  return {
    context: items.some((item) => item.notCurrent || explicitDates(item.snippet ?? "").length > 0)
      ? `\n\n[Date checks for ${today} (${timezone})] Copy each item's published dates exactly. Do not invent start dates when only an end date was retrieved. These retrieved items are NOT current; omit them from current items or separate them explicitly:\n${JSON.stringify(dated)}`
      : "",
    issues(blocks: readonly Block[]): string[] {
      if (!active) return [];
      let current = !nonCurrentWords.test(request);
      const issues = new Set<string>();
      for (const block of blocks) {
        const heading = "title" in block && typeof block.title === "string" ? block.title : "";
        if (block.type === "sectionHeader" || block.type === "pageMeta") {
          if (currentWords.test(heading)) current = true;
          else if (nonCurrentWords.test(heading)) current = false;
        }
        const scope = currentWords.test(heading)
          ? true
          : nonCurrentWords.test(heading)
            ? false
            : current;
        if (!scope || ["chipRow", "hero"].includes(block.type)) continue;
        if (
          (block.type === "pageMeta" || block.type === "sectionHeader") &&
          !currentWords.test(heading)
        )
          continue;
        const entries = [
          block,
          ...Object.values(block).flatMap((value) => (Array.isArray(value) ? value : [])),
        ];
        for (const entry of entries) {
          const text = visibleText(entry);
          if (!text) continue;
          if (block.type === "text" && futureNotice.test(text) && !currentWords.test(text))
            continue;
          const normalized = ` ${normalize(text)} `;
          const conflict = dated.find(({ entity }) => normalized.includes(` ${entity} `));
          const matching = items.filter((item) => {
            const entity = normalize(item.title.split(/[|:]/, 1)[0]);
            return entity.length >= 4 && normalized.includes(` ${entity} `);
          });
          const published = matching.flatMap((item) => explicitDates(item.snippet ?? ""));
          const unsupported = explicitDates(text).some(
            (value) =>
              value.year &&
              published.length > 0 &&
              !published.some(
                (known) =>
                  known.month === value.month &&
                  known.day === value.day &&
                  (known.year === undefined || known.year === value.year),
              ),
          );
          if (unsupported)
            issues.add(
              "Current item contains a date absent from its retrieved evidence. Copy the published date label; do not invent a missing start or end date.",
            );
          if (conflict || ranges(text).some((range) => outside(range, today))) {
            issues.add(
              `Current item falls outside ${today}. Omit it from current items or put it in an explicitly upcoming/past section.`,
            );
          }
        }
      }
      return [...issues];
    },
  };
}
