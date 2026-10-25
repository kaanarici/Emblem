import { z } from "zod";

function gregorianDate(value: string): Date | undefined {
  if (!/^(?!0000)\d{4}-\d{2}-\d{2}$/.test(value)) return;
  const date = new Date(`${value}T00:00:00.000Z`);
  if (!Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value) return date;
}

function validTimeZone(value: string): boolean {
  if (!/^[A-Za-z][A-Za-z0-9_+\-/]*$/.test(value)) return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value }).format(0);
    return true;
  } catch {
    return false;
  }
}

export type CalendarGenerationContext = {
  date: string;
  timeZone: string;
  mode: "daily" | "weekly" | "monthly";
};

function calendarGenerationPeriod(context: CalendarGenerationContext) {
  const start = gregorianDate(context.date);
  if (!start) throw new Error("invalid Calendar date");
  if (context.mode === "weekly") start.setUTCDate(start.getUTCDate() - start.getUTCDay());
  if (context.mode === "monthly") start.setUTCDate(1);
  const end = new Date(start);
  if (context.mode === "monthly") end.setUTCMonth(end.getUTCMonth() + 1);
  else end.setUTCDate(end.getUTCDate() + (context.mode === "weekly" ? 7 : 1));
  const localDate = (date: Date) => {
    const result = date.toISOString().slice(0, 10);
    if (!gregorianDate(result))
      throw new Error("Calendar period is outside the supported date range");
    return result;
  };
  return {
    startInclusive: localDate(start),
    endExclusive: localDate(end),
    timeZone: context.timeZone,
  };
}

export const calendarGenerationContextSchema = z
  .object({
    date: z.string().refine((value) => Boolean(gregorianDate(value)), "invalid Calendar date"),
    timeZone: z.string().min(1).max(100).refine(validTimeZone, "invalid Calendar time zone"),
    mode: z.enum(["daily", "weekly", "monthly"]),
  })
  .strict()
  .superRefine((context, refinement) => {
    if (!gregorianDate(context.date)) return;
    try {
      calendarGenerationPeriod(context);
    } catch {
      refinement.addIssue({ code: "custom", message: "invalid Calendar period" });
    }
  });

const calendarInputSchema = z
  .object({
    calendarContext: calendarGenerationContextSchema,
    timezone: z.string().optional(),
    parentPageKey: z.unknown().optional(),
    sourceCardKey: z.unknown().optional(),
    drillInPresentation: z.unknown().optional(),
    savedSelection: z.unknown().optional(),
  })
  .passthrough()
  .superRefine((input, refinement) => {
    if (
      input.parentPageKey !== undefined ||
      input.sourceCardKey !== undefined ||
      input.drillInPresentation !== undefined ||
      input.savedSelection !== undefined
    ) {
      refinement.addIssue({
        code: "custom",
        message: "Calendar selection cannot be a card drill-in or Saved selection",
      });
    }
    if (input.timezone !== undefined && input.timezone !== input.calendarContext.timeZone) {
      refinement.addIssue({
        code: "custom",
        message: "Calendar and request time zones must match",
      });
    }
  });

export function validateCalendarGenerationInput(value: unknown): unknown {
  if (
    value &&
    typeof value === "object" &&
    "calendarContext" in value &&
    (value as { calendarContext?: unknown }).calendarContext !== undefined
  ) {
    return calendarInputSchema.parse(value);
  }
  return value;
}

export function calendarGenerationInstruction(context: CalendarGenerationContext): string {
  const period = calendarGenerationPeriod(context);
  return (
    `\n\n[Calendar selection]\nRead my calendar for the ${context.mode} selection anchored on ${context.date}. ` +
    `The selected local period is ${period.startInclusive} inclusive to ${period.endExclusive} exclusive in ${period.timeZone}. ` +
    `Interpret these as local calendar-date boundaries, not UTC instants or fixed 24-hour durations. ` +
    `Use the permitted connected calendar read tool for this interval when available. ` +
    `Missing, denied, failed or incomplete calendar evidence is unknown, never an empty schedule. ` +
    `A bounded result is not proof of a complete month or all free time. ` +
    `Calendar pages carry no follow-up suggestions. When the read succeeds with no events, the whole page is one sentence in this form: "On **Thursday, October 22nd** you have no events scheduled." ` +
    `When the calendar cannot be read, the whole page is one short sentence saying the schedule for that day is unavailable right now, with the date in bold; no advice, alternatives or follow-ups.`
  );
}
