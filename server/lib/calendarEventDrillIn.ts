import type { Block } from "./schema";

export type SelectedCalendarEvent = {
  title: string;
  timeRange: string;
  place?: string;
  dayLabel: string;
};

const EVENT_OBJECTS: [RegExp, string][] = [
  [/\b(flights?|fly|flying|airport|boarding|layover)\b/, "airplane"],
  [/\b(trains?|amtrak|rail)\b/, "train"],
  [/\b(trip|travel|vacation|holiday|hotel|check.?in|check.?out)\b/, "suitcase"],
  [/\b(birthday|bday)\b/, "birthday cake"],
  [/\b(party|celebration|wedding|anniversary)\b/, "balloon"],
  [/\b(dentist|dental|orthodontist)\b/, "tooth"],
  [/\b(doctor|dr|physio|therapy|therapist|checkup|clinic|vet)\b/, "stethoscope"],
  [/\b(due|deadline|submit|submission|assignment|homework|todo|to.?do|reminder)\b/, "to do list"],
  [
    /\b(exam|midterm|finals?|quiz|class|classes|lecture|seminar|course|lesson|tutorial|lab|school|university|college|campus|study|office hours|intro to|science|math|maths|history|biology|chemistry|physics|economics|econometrics|marketing|literature)\b/,
    "graduation",
  ],
  [/\b(gym|workout|lift|lifting|crossfit|pilates|hiit|strength)\b/, "dumbbell"],
  [/\b(run|running|jog|jogging|marathon|5k|10k)\b/, "running"],
  [/\b(yoga|meditation)\b/, "yoga"],
  [/\b(swim|swimming|pool)\b/, "swimming"],
  [/\b(breakfast|brunch|lunch|dinner|supper|meal|restaurant|reservation)\b/, "dining table"],
  [/\b(coffee|cafe|latte)\b/, "coffee"],
  [/\b(drinks|happy hour|bar|cocktails?)\b/, "cocktail"],
  [/\b(movie|film|cinema)\b/, "movie"],
  [/\b(concert|gig|show|theater|theatre|play)\b/, "ticket"],
  [/\b(zoom|google meet|ms teams|webex|facetime|video call)\b/, "webcam"],
  [/\b(call|phone|dial)\b/, "phone"],
  [/\b(interview)\b/, "handshake"],
  [/\b(presentation|demo|pitch|keynote|talk)\b/, "presentation"],
  [/\b(conference|summit|offsite|workshop)\b/, "conference"],
  [
    /\b(meeting|sync|standup|stand.?up|1:1|one.?on.?one|review|planning|retro|kickoff|catch.?up|huddle|team)\b/,
    "meeting",
  ],
];

function calendarEventObjectQuery(...texts: (string | undefined)[]): string {
  const text = texts
    .filter((value): value is string => Boolean(value))
    .join(" \n ")
    .toLocaleLowerCase("en-US");
  return EVENT_OBJECTS.find(([pattern]) => pattern.test(text))?.[1] ?? "calendar";
}

export function selectedCalendarEvent(
  blocksJSON: string,
  title: string | undefined,
): SelectedCalendarEvent | undefined {
  const wanted = title?.trim().toLocaleLowerCase("en-US");
  if (!wanted) return;
  let blocks: unknown;
  try {
    blocks = JSON.parse(blocksJSON);
  } catch {
    return;
  }
  if (!Array.isArray(blocks)) return;
  for (const block of blocks) {
    if (!block || typeof block !== "object" || block.type !== "eventCard") continue;
    const { dayLabel, events } = block as { dayLabel?: unknown; events?: unknown };
    if (typeof dayLabel !== "string" || !Array.isArray(events)) continue;
    for (const event of events) {
      if (!event || typeof event !== "object") continue;
      const { title: eventTitle, timeRange, place } = event as Record<string, unknown>;
      if (typeof eventTitle !== "string" || typeof timeRange !== "string") continue;
      if (eventTitle.trim().toLocaleLowerCase("en-US") !== wanted) continue;
      return {
        title: eventTitle,
        timeRange,
        ...(typeof place === "string" && place.trim() ? { place } : {}),
        dayLabel,
      };
    }
  }
}

export function withCalendarEventIcon(blocks: Block[], event: SelectedCalendarEvent): Block[] {
  let attached = false;
  return blocks.map((block) => {
    if (attached || block.type !== "titleBlock") return block;
    attached = true;
    const query = calendarEventObjectQuery(
      event.title,
      block.title,
      block.tags?.join(" "),
      event.place,
    );
    return { ...block, icon: { image: { query, kind: "object" } } };
  });
}
