import { asRecord } from "./records";
import type { GenerationSource } from "./generationProtocol";

type PresentedResult = {
  result: unknown;
  sources?: GenerationSource[];
};

type GmailMessage = {
  display_url?: string;
  labelIds?: string[];
  messageId?: string;
  messageText?: string;
  messageTimestamp?: string;
  preview?: { body?: string; subject?: string };
  sender?: string;
  subject?: string;
  threadId?: string;
  to?: string;
};

function text(value: unknown, max: number): string | undefined {
  if (typeof value !== "string") return undefined;
  return value.replace(/\s+/g, " ").trim().slice(0, max) || undefined;
}

function gmailUrl(value: unknown): string | undefined {
  const candidate = text(value, 2_048);
  if (!candidate) return undefined;
  try {
    const url = new URL(candidate);
    if (url.protocol !== "https:" || url.hostname !== "mail.google.com") return undefined;
    if (url.username || url.password) return undefined;
    return url.toString();
  } catch {
    return undefined;
  }
}

function gmailMessage(value: unknown): GmailMessage | null {
  const message = asRecord(value);
  if (!message) return null;
  const preview = asRecord(message.preview);
  const previewBody = text(preview?.body, 320);
  const previewSubject = text(preview?.subject, 240);
  const sender = text(message.sender, 240);
  const subject = text(message.subject, 240);
  if (!previewBody && !previewSubject && !sender && !subject) return null;
  const labelIds = Array.isArray(message.labelIds)
    ? message.labelIds.flatMap((label) => text(label, 64) ?? []).slice(0, 10)
    : undefined;
  return {
    display_url: gmailUrl(message.display_url),
    ...(labelIds?.length ? { labelIds } : {}),
    messageId: text(message.messageId, 256),
    messageText: text(message.messageText, 1_200),
    messageTimestamp: text(message.messageTimestamp, 64),
    preview:
      previewBody || previewSubject
        ? {
            body: previewBody,
            subject: previewSubject,
          }
        : undefined,
    sender,
    subject,
    threadId: text(message.threadId, 256),
    to: text(message.to, 240),
  };
}

function gmailSources(messages: GmailMessage[], threadURL?: string): GenerationSource[] {
  const sources = messages.flatMap((message) => {
    if (!message.display_url) return [];
    const snippet =
      [message.sender, message.preview?.body ?? message.messageText]
        .filter(Boolean)
        .join(" · ")
        .slice(0, 500) || undefined;
    return [
      {
        id: message.display_url,
        title: message.subject ?? message.preview?.subject ?? "No subject",
        url: message.display_url,
        domain: "mail.google.com",
        ...(message.messageTimestamp ? { publishedAt: message.messageTimestamp } : {}),
        ...(snippet ? { snippet } : {}),
      } satisfies GenerationSource,
    ];
  });
  if (sources.length === 0 && threadURL) {
    const message = messages[0];
    const snippet =
      [message?.sender, message?.preview?.body ?? message?.messageText]
        .filter(Boolean)
        .join(" · ")
        .slice(0, 500) || undefined;
    sources.push({
      id: threadURL,
      title: message?.subject ?? message?.preview?.subject ?? "Gmail thread",
      url: threadURL,
      domain: "mail.google.com",
      ...(message?.messageTimestamp ? { publishedAt: message.messageTimestamp } : {}),
      ...(snippet ? { snippet } : {}),
    });
  }
  return Array.from(new Map(sources.map((source) => [source.id, source])).values()).slice(0, 12);
}

function presentGmailMessages(value: unknown): PresentedResult {
  const root = asRecord(value);
  const data = asRecord(root?.data);
  const messages = (Array.isArray(data?.messages) ? data.messages : [])
    .flatMap((message) => gmailMessage(message) ?? [])
    .slice(0, 12);
  const estimate =
    typeof data?.resultSizeEstimate === "number" && Number.isFinite(data.resultSizeEstimate)
      ? Math.max(0, Math.min(10_000, Math.floor(data.resultSizeEstimate)))
      : undefined;
  const result = {
    successful: root?.successful === true,
    data: {
      messages,
      ...(estimate === undefined ? {} : { resultSizeEstimate: estimate }),
      ...(text(data?.threadId, 256) ? { threadId: text(data?.threadId, 256) } : {}),
      ...(text(data?.historyId, 256) ? { historyId: text(data?.historyId, 256) } : {}),
      ...(gmailUrl(data?.display_url) ? { display_url: gmailUrl(data?.display_url) } : {}),
    },
  };
  if (root?.successful !== true || messages.length === 0) return { result };
  const sources = gmailSources(messages, gmailUrl(data?.display_url));
  return { result, ...(sources.length ? { sources } : {}) };
}

function presentGmailThreads(value: unknown): PresentedResult {
  const root = asRecord(value);
  const data = asRecord(root?.data);
  const threads = (Array.isArray(data?.threads) ? data.threads : [])
    .flatMap((value) => {
      const thread = asRecord(value);
      const id = text(thread?.id, 256);
      if (!id) return [];
      return [
        {
          id,
          ...(text(thread?.snippet, 500) ? { snippet: text(thread?.snippet, 500) } : {}),
          ...(text(thread?.historyId, 256) ? { historyId: text(thread?.historyId, 256) } : {}),
        },
      ];
    })
    .slice(0, 20);
  const estimate =
    typeof data?.resultSizeEstimate === "number" && Number.isFinite(data.resultSizeEstimate)
      ? Math.max(0, Math.min(10_000, Math.floor(data.resultSizeEstimate)))
      : undefined;
  return {
    result: {
      successful: root?.successful === true,
      data: {
        threads,
        ...(text(data?.nextPageToken, 500)
          ? { nextPageToken: text(data?.nextPageToken, 500) }
          : {}),
        ...(estimate === undefined ? {} : { resultSizeEstimate: estimate }),
      },
    },
  };
}

const MAX_CALENDAR_ITEMS = 50;
const MAX_CALENDAR_DEPTH = 6;

function defined<T extends Record<string, unknown>>(value: T): Partial<T> {
  return Object.fromEntries(Object.entries(value).filter(([, field]) => field !== undefined)) as T;
}

function calendarTime(value: unknown) {
  const time = asRecord(value);
  const dateTime = text(time?.dateTime, 64);
  const date = text(time?.date, 32);
  if (!dateTime && !date) return undefined;
  return defined({ dateTime, date, timeZone: text(time?.timeZone, 64) });
}

function calendarPerson(value: unknown): string | undefined {
  const person = asRecord(value);
  const name = text(person?.displayName, 120);
  const email = text(person?.email, 240);
  if (!name && !email) return undefined;
  return [
    name && email ? `${name} <${email}>` : (name ?? email),
    text(person?.responseStatus, 32),
    person?.self === true ? "you" : undefined,
  ]
    .filter(Boolean)
    .join(", ");
}

function calendarLink(value: unknown): string | undefined {
  const candidate = text(value, 2_048);
  if (!candidate) return undefined;
  try {
    const url = new URL(candidate);
    return url.protocol === "https:" && url.hostname.endsWith("google.com") && !url.username
      ? url.toString()
      : undefined;
  } catch {
    return undefined;
  }
}

function calendarEvent(record: Record<string, unknown>) {
  const start = calendarTime(record.start);
  const end = calendarTime(record.end);
  const summary = text(record.summary, 240);
  if ((!start && !end) || (!summary && !text(record.id, 256))) return null;
  const attendees = Array.isArray(record.attendees)
    ? record.attendees.flatMap((attendee) => calendarPerson(attendee) ?? []).slice(0, 10)
    : [];
  return defined({
    id: text(record.id, 256),
    summary,
    status: text(record.status, 32),
    start,
    end,
    location: text(record.location, 240),
    description: text(record.description, 500),
    organizer: calendarPerson(record.organizer),
    attendees: attendees.length ? attendees : undefined,
    htmlLink: calendarLink(record.htmlLink),
  });
}

function collectCalendar(
  value: unknown,
  found: { events: unknown[]; busy: unknown[] },
  depth = 0,
): void {
  if (depth > MAX_CALENDAR_DEPTH) return;
  if (Array.isArray(value)) {
    value.forEach((item) => collectCalendar(item, found, depth + 1));
    return;
  }
  const record = asRecord(value);
  if (!record) return;
  const event = calendarEvent(record);
  if (event) {
    if (found.events.length < MAX_CALENDAR_ITEMS) found.events.push(event);
    return;
  }
  for (const [key, child] of Object.entries(record)) {
    if (key === "busy" && Array.isArray(child)) {
      for (const interval of child) {
        const busy = asRecord(interval);
        const start = text(busy?.start, 64);
        const end = text(busy?.end, 64);
        if (start && end && found.busy.length < MAX_CALENDAR_ITEMS) found.busy.push({ start, end });
      }
    } else {
      collectCalendar(child, found, depth + 1);
    }
  }
}

function presentCalendar(value: unknown): PresentedResult {
  const root = asRecord(value);
  const found = { events: [] as unknown[], busy: [] as unknown[] };
  collectCalendar(root?.data, found);
  return {
    result: {
      successful: root?.successful === true,
      data: {
        ...(found.events.length > 0 || found.busy.length === 0 ? { events: found.events } : {}),
        ...(found.busy.length > 0 ? { busy: found.busy } : {}),
      },
    },
  };
}

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const INSTANT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$/i;
const MAX_EVENT_ATTENDEES = 12;

export type CalendarEventRow = {
  id: string;
  iCalUID: string | null;
  title: string;
  start: string;
  end: string;
  allDay: boolean;
  location: string | null;
  calendar: string | null;
  color: string | null;
  url: string | null;
  attendees: string[];
};

function hexColor(value: unknown): string | null {
  return typeof value === "string" && /^#[0-9a-f]{6}$/i.test(value) ? value : null;
}

function eventInstant(value: unknown): string | undefined {
  const candidate = text(value, 64);
  if (!candidate || !INSTANT.test(candidate)) return undefined;
  const time = Date.parse(candidate);
  return Number.isNaN(time) ? undefined : new Date(time).toISOString().replace(/\.\d{3}Z$/, "Z");
}

function eventSpan(record: Record<string, unknown>) {
  const start = asRecord(record.start);
  const end = asRecord(record.end);
  const startDate = text(start?.date, 32);
  const endDate = text(end?.date, 32);
  if (startDate && endDate && DATE.test(startDate) && DATE.test(endDate)) {
    return { start: startDate, end: endDate, allDay: true };
  }
  const startAt = eventInstant(start?.dateTime);
  const endAt = eventInstant(end?.dateTime);
  return startAt && endAt ? { start: startAt, end: endAt, allDay: false } : null;
}

function calendarEventRow(
  value: unknown,
  calendar: string | null,
  calendarColor: string | null,
): CalendarEventRow | null {
  const record = asRecord(value);
  const id = text(record?.id, 256);
  const span = record && eventSpan(record);
  if (!record || !id || !span || record.status === "cancelled") return null;
  const attendees = Array.isArray(record.attendees)
    ? record.attendees.flatMap((attendee) => {
        const person = asRecord(attendee);
        return text(person?.displayName, 80) ?? text(person?.email, 80) ?? [];
      })
    : [];
  return {
    id,
    iCalUID: text(record.iCalUID, 512) ?? null,
    title: text(record.summary, 200) ?? "(No title)",
    ...span,
    location: text(record.location, 200) ?? null,
    calendar,
    color: hexColor(record.backgroundColor) ?? calendarColor,
    url: calendarLink(record.htmlLink) ?? null,
    attendees: attendees.slice(0, MAX_EVENT_ATTENDEES),
  };
}

export function presentCalendarEvents(value: unknown): {
  calendar: string | null;
  events: CalendarEventRow[];
  nextPageToken?: string;
} {
  const data = asRecord(asRecord(value)?.data);
  const calendar = text(data?.summary, 200) ?? null;
  const calendarColor = hexColor(data?.backgroundColor);
  const items = Array.isArray(data?.items) ? data.items : [];
  return {
    calendar,
    events: items.flatMap((item) => calendarEventRow(item, calendar, calendarColor) ?? []),
    ...(typeof data?.nextPageToken === "string" && data.nextPageToken
      ? { nextPageToken: data.nextPageToken }
      : {}),
  };
}

export function presentConnectorResult(toolName: string, value: unknown): PresentedResult {
  if (toolName === "GMAIL_FETCH_EMAILS" || toolName === "GMAIL_FETCH_MESSAGE_BY_THREAD_ID") {
    return presentGmailMessages(value);
  }
  if (toolName === "GMAIL_LIST_THREADS") return presentGmailThreads(value);
  if (toolName.startsWith("GOOGLECALENDAR_")) return presentCalendar(value);
  return { result: null };
}
