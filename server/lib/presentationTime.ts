const MACHINE_UTC_TIMESTAMP = /\b(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z)\b/g;

const IANA_TIME_ZONE =
  /\s*(?:[·•|,—–-]\s*)?\(?\b(?:Africa|America|Antarctica|Asia|Atlantic|Australia|Europe|Indian|Pacific|Etc)\/[A-Za-z_]+(?:\/[A-Za-z_]+)?\b\)?/g;

const visibleTextKeys = new Set([
  "answer",
  "body",
  "caption",
  "dayLabel",
  "detail",
  "label",
  "meta",
  "metaLine",
  "name",
  "question",
  "subtitle",
  "summary",
  "text",
  "time",
  "timeRange",
  "title",
  "value",
]);

export function localizeVisibleMachineTimes<T>(value: T, timezone: string): T {
  return transform(value, timezone) as T;
}

export function formatLocalRunTime(timestamp: number, timezone: string): string {
  return formatDate(new Date(timestamp), timezone);
}

function transform(value: unknown, timezone: string, key?: string): unknown {
  if (typeof value === "string") {
    return key && visibleTextKeys.has(key) ? visibleText(value, timezone) : value;
  }
  if (Array.isArray(value)) {
    return value.map((item) => transform(item, timezone));
  }
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.entries(value).map(([childKey, childValue]) => [
      childKey,
      transform(childValue, timezone, childKey),
    ]),
  );
}

function withoutTimeZoneIDs(text: string): string {
  if (!text.includes("/")) return text;
  const scrubbed = text
    .replace(IANA_TIME_ZONE, "")
    .replace(/^\s*[·•|,—–-]\s*/, "")
    .trim();
  if (scrubbed) return scrubbed;
  const id = /[A-Za-z]+\/[A-Za-z_]+(?:\/[A-Za-z_]+)?/.exec(text)?.[0];
  return id ? friendlyTimeZone(id) : text;
}

function friendlyTimeZone(id: string): string {
  const fallback = `${id.split("/").at(-1)!.replaceAll("_", " ")} time`;
  try {
    const name = new Intl.DateTimeFormat("en-US", { timeZone: id, timeZoneName: "longGeneric" })
      .formatToParts(0)
      .find((part) => part.type === "timeZoneName")?.value;
    return name && !name.includes("/") ? name : fallback;
  } catch {
    return fallback;
  }
}

function visibleText(value: string, timezone: string): string {
  return withoutTimeZoneIDs(
    value.replace(MACHINE_UTC_TIMESTAMP, (timestamp) => formatDate(new Date(timestamp), timezone)),
  );
}

function formatDate(date: Date, timezone: string): string {
  if (Number.isNaN(date.getTime())) return "";
  try {
    return new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
    }).format(date);
  } catch {
    return new Intl.DateTimeFormat("en-US", {
      timeZone: "UTC",
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
    }).format(date);
  }
}
