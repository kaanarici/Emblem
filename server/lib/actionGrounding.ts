import { automationIntentIsExplicit, calendarIntentIsExplicit } from "@/lib/requestIntent";
import type { PlannedAction, PlannedActionGrounding } from "./responsePlan";

type GroundingCorpus = {
  trustedText: string[];
  trustedTokens: string[];
  trustedRaw: string[];
  userText: string;
  userRaw: string[];
};

const semanticStopWords = new Set([
  "a",
  "an",
  "and",
  "are",
  "at",
  "be",
  "by",
  "for",
  "from",
  "how",
  "i",
  "in",
  "into",
  "is",
  "it",
  "me",
  "my",
  "of",
  "on",
  "or",
  "please",
  "should",
  "show",
  "that",
  "the",
  "this",
  "to",
  "when",
  "where",
  "which",
  "with",
  "you",
  "your",
]);
const actionPromptScaffolding = new Set([
  "create",
  "generate",
  "make",
  "prepare",
  "start",
  "summarize",
]);
const calendarQuestionScaffolding = new Set(["begin", "event", "start", "time"]);
const monthNames = [
  "january",
  "february",
  "march",
  "april",
  "may",
  "june",
  "july",
  "august",
  "september",
  "october",
  "november",
  "december",
] as const;
const weekdayTerms = [
  ["monday", "mon"],
  ["tuesday", "tue", "tues"],
  ["wednesday", "wed"],
  ["thursday", "thu", "thur", "thurs"],
  ["friday", "fri"],
  ["saturday", "sat"],
  ["sunday", "sun"],
] as const;

export function isPlannedActionGrounded(
  planned: Exclude<PlannedAction, { kind: "none" | "url" }>,
  grounding: PlannedActionGrounding,
  idempotencyKey?: string,
): boolean {
  const corpus = actionGroundingCorpus(grounding);
  switch (planned.kind) {
    case "prompt":
      return (
        promptIntentIsDisclosed(planned.prompt, planned.label, corpus.userText) &&
        textIsGrounded(planned.prompt, corpus, { disclosed: planned.label })
      );
    case "directions":
      return (
        textIsGrounded(planned.destination.name, corpus) &&
        textIsGrounded(planned.destination.locality, corpus) &&
        directionsModeIsGrounded(planned.destination.mode, corpus.userText)
      );
    case "automation":
      return (
        Boolean(idempotencyKey) &&
        automationIntentIsExplicit(corpus.userText) &&
        textIsGrounded(planned.title, corpus) &&
        promptIntentIsDisclosed(planned.prompt, planned.label, corpus.userText) &&
        textIsGrounded(planned.prompt, corpus, {
          disclosed: planned.title,
          ignored: actionPromptScaffolding,
        }) &&
        timeIsGrounded(planned.hour, planned.minute, corpus.userRaw) &&
        weekdaysAreGrounded(planned.weekdays, corpus.userText)
      );
    case "calendar":
      return (
        Boolean(idempotencyKey) &&
        calendarIntentIsExplicit(corpus.userText) &&
        textIsGrounded(planned.title, corpus) &&
        dateIsGrounded(planned.date, corpus) &&
        durationIsGrounded(planned.durationMinutes, corpus.trustedRaw) &&
        textIsGrounded(planned.timeAnswerKey, corpus, {
          ignored: calendarQuestionScaffolding,
          allowNoSemanticTerms: true,
        })
      );
  }
}

function actionGroundingCorpus(grounding: PlannedActionGrounding): GroundingCorpus {
  const userRaw = grounding.messages
    .filter(({ role }) => role === "user")
    .map(({ content }) => content);
  const trustedRaw = [...userRaw, ...(grounding.verifiedEvidence ?? [])].filter(
    (value) => value.trim().length > 0,
  );
  const trustedText = trustedRaw.map(normalizeGroundingText);
  return {
    trustedText,
    trustedTokens: trustedText.flatMap((value) => value.split(" ").filter(Boolean)),
    trustedRaw,
    userText: normalizeGroundingText(userRaw.join("\n")),
    userRaw,
  };
}

function textIsGrounded(
  value: string,
  corpus: GroundingCorpus,
  options: {
    disclosed?: string;
    ignored?: ReadonlySet<string>;
    allowNoSemanticTerms?: boolean;
  } = {},
): boolean {
  const normalized = normalizeGroundingText(value);
  if (!normalized) return false;
  if (corpus.trustedText.some((text) => text.includes(normalized))) return true;

  const ignored = new Set([...semanticStopWords, ...(options.ignored ?? [])]);
  const terms = normalized.split(" ").filter((term) => term && !ignored.has(term));
  if (terms.length === 0) return options.allowNoSemanticTerms === true;
  const disclosed = normalizeGroundingText(options.disclosed ?? "")
    .split(" ")
    .filter(Boolean);
  const candidates = [...corpus.trustedTokens, ...disclosed];
  return terms.every((term) => candidates.some((candidate) => tokenCovers(candidate, term)));
}

function tokenCovers(candidate: string, term: string): boolean {
  if (candidate === term) return true;
  if (candidate.length < 4 || term.length < 4) return false;
  return candidate.startsWith(term) || term.startsWith(candidate);
}

function directionsModeIsGrounded(
  mode: "driving" | "walking" | "transit",
  userText: string,
): boolean {
  const requested = new Set<"driving" | "walking" | "transit">();
  if (/\b(drive|driving|car)\b/.test(userText)) requested.add("driving");
  if (/\b(walk|walking|foot|pedestrian)\b/.test(userText)) requested.add("walking");
  if (/\b(transit|public transport|bus|train|subway|metro)\b/.test(userText)) {
    requested.add("transit");
  }
  return requested.size === 0 ? mode === "driving" : requested.has(mode);
}

function promptIntentIsDisclosed(prompt: string, label: string, userText: string): boolean {
  const visibleTokens = new Set(
    normalizeGroundingText(`${label} ${userText}`).split(" ").filter(Boolean),
  );
  const intentTerms = normalizeGroundingText(prompt)
    .split(" ")
    .filter((term) => promptIntentTerms.has(term));
  return intentTerms.every((term) => visibleTokens.has(term));
}

const promptIntentTerms = new Set([
  "accept",
  "add",
  "approve",
  "archive",
  "book",
  "buy",
  "call",
  "cancel",
  "create",
  "decline",
  "delete",
  "email",
  "erase",
  "invite",
  "message",
  "move",
  "order",
  "pay",
  "post",
  "publish",
  "purchase",
  "remove",
  "rename",
  "reply",
  "reserve",
  "schedule",
  "send",
  "share",
  "submit",
  "transfer",
  "update",
]);

function weekdaysAreGrounded(weekdays: readonly number[], userText: string): boolean {
  if (weekdays.length === 0) {
    return /\b(daily|each day|every day|every morning|every afternoon|every evening|every night)\b/.test(
      userText,
    );
  }
  const unique = [...new Set(weekdays)].sort((left, right) => left - right);
  if (unique.join(",") === "1,2,3,4,5" && /\bweekdays?\b/.test(userText)) return true;
  if (unique.join(",") === "6,7" && /\bweekends?\b/.test(userText)) return true;
  return unique.every((day) =>
    weekdayTerms[day - 1].some((term) => new RegExp(`\\b${term}\\b`).test(userText)),
  );
}

function timeIsGrounded(hour: number, minute: number, values: readonly string[]): boolean {
  for (const value of values) {
    const text = value.toLocaleLowerCase();
    if (hour === 12 && minute === 0 && /\bnoon\b/.test(text)) return true;
    if (hour === 0 && minute === 0 && /\bmidnight\b/.test(text)) return true;
    const matches = text.matchAll(
      /\b(at\s+)?(\d{1,2})(?:([:.])(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?\b/g,
    );
    for (const match of matches) {
      if (!match[1] && !match[3] && !match[5]) continue;
      let candidateHour = Number(match[2]);
      const candidateMinute = match[4] ? Number(match[4]) : 0;
      const meridiem = match[5]?.replaceAll(".", "");
      if (candidateHour > 23 || candidateMinute > 59) continue;
      if (meridiem) {
        if (candidateHour < 1 || candidateHour > 12) continue;
        candidateHour %= 12;
        if (meridiem === "pm") candidateHour += 12;
      }
      if (candidateHour === hour && candidateMinute === minute) return true;
    }
  }
  return false;
}

function dateIsGrounded(date: string, corpus: GroundingCorpus): boolean {
  const [yearText, monthText, dayText] = date.split("-");
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  const monthName = monthNames[month - 1];
  if (!monthName || !Number.isInteger(day) || !Number.isInteger(year)) return false;
  const variants = [
    normalizeGroundingText(date),
    `${monthName} ${day} ${year}`,
    `${monthName} ${day}`,
    `${day} ${monthName} ${year}`,
    `${day} ${monthName}`,
  ];
  if (corpus.trustedText.some((text) => variants.some((variant) => text.includes(variant)))) {
    return true;
  }

  const userText = normalizeGroundingText(corpus.userRaw.join("\n"));
  const offset = /\btomorrow\b/.test(userText) ? 1 : /\btoday\b/.test(userText) ? 0 : null;
  if (offset == null) return false;
  const reference = referenceDate(corpus.trustedText);
  if (!reference) return false;
  reference.setUTCDate(reference.getUTCDate() + offset);
  return (
    reference.getUTCFullYear() === year &&
    reference.getUTCMonth() + 1 === month &&
    reference.getUTCDate() === day
  );
}

function referenceDate(values: readonly string[]): Date | null {
  for (const value of values) {
    for (let month = 0; month < monthNames.length; month += 1) {
      const match = value.match(new RegExp(`\\b${monthNames[month]} (\\d{1,2}) (\\d{4})\\b`));
      if (!match) continue;
      const date = new Date(Date.UTC(Number(match[2]), month, Number(match[1])));
      if (!Number.isNaN(date.valueOf())) return date;
    }
  }
  return null;
}

function durationIsGrounded(minutes: number, values: readonly string[]): boolean {
  const text = values.join("\n").toLocaleLowerCase();
  if (minutes === 1_440 && /\ball[ -]?day\b/.test(text)) return true;
  if (new RegExp(`\\b${minutes}\\s*(?:minutes?|mins?)\\b`).test(text)) return true;
  if (minutes === 30 && /\bhalf (?:an? )?hour\b/.test(text)) return true;
  if (minutes === 60 && /\b(?:an|one) hour\b/.test(text)) return true;
  if (minutes % 60 === 0) {
    const hours = minutes / 60;
    if (new RegExp(`\\b${hours}\\s*(?:hours?|hrs?)\\b`).test(text)) return true;
  }
  if (minutes % 30 === 0) {
    const hours = minutes / 60;
    const value = String(hours).replace(".", "\\.");
    if (new RegExp(`\\b${value}\\s*(?:hours?|hrs?)\\b`).test(text)) return true;
  }
  return false;
}

function normalizeGroundingText(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLocaleLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .replace(/\s+/g, " ");
}

export function harvestHTTPURLs(text: string, into: Set<string>): void {
  for (const candidate of text.match(/https?:\/\/[^\s<>"']+/gi) ?? []) {
    const trimmed = candidate.replace(/[),.;!?]+$/g, "");
    try {
      const url = new URL(trimmed);
      if (url.protocol !== "http:" && url.protocol !== "https:") continue;
      if (url.hostname === "mail.google.com") continue;
      into.add(trimmed);
    } catch {}
  }
}

export function userSuppliedHTTPURLs(
  messages: ReadonlyArray<{ role: string; content: string }>,
): Set<string> {
  const urls = new Set<string>();
  for (const message of messages) {
    if (message.role === "user") harvestHTTPURLs(message.content, urls);
  }
  return urls;
}
