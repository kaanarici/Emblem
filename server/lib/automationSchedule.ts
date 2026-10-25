const DAY_MS = 86_400_000;
const MAX_TIMEZONE_LENGTH = 64;

type WallClock = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
};

export type ScheduleTime = {
  hour: number;
  minute: number;
};

export const MAX_DAILY_UPDATE_TIMES = 8;

export type BriefingTimes = {
  morning?: ScheduleTime;
  afternoon?: ScheduleTime;
  evening?: ScheduleTime;
};

export function briefingScheduleTimes(times: BriefingTimes): ScheduleTime[] {
  return [times.morning, times.afternoon, times.evening].filter(
    (time): time is ScheduleTime => time !== undefined,
  );
}

export function scheduleTimes(schedule: {
  updateTimes?: readonly ScheduleTime[];
  briefingTimes?: BriefingTimes;
  hour?: number;
  minute?: number;
}): readonly ScheduleTime[] {
  if (schedule.updateTimes) return schedule.updateTimes;
  if (schedule.briefingTimes) return briefingScheduleTimes(schedule.briefingTimes);
  return schedule.hour != null && schedule.minute != null
    ? [{ hour: schedule.hour, minute: schedule.minute }]
    : [];
}

export function validateBriefingTimes(briefingTimes: BriefingTimes, timezone: string): void {
  const times = briefingScheduleTimes(briefingTimes);
  if (times.length === 0) throw new Error("briefing time required");
  validateDailyUpdateTimes(times, timezone);
}

export function validateDailyUpdateTimes(times: readonly ScheduleTime[], timezone: string): void {
  if (times.length > MAX_DAILY_UPDATE_TIMES) {
    throw new Error("too many daily update times");
  }
  for (const time of times) {
    validateSchedule(time.hour, time.minute, undefined, timezone);
  }
  const minuteOfDay = times.map((time) => time.hour * 60 + time.minute);
  if (minuteOfDay.some((time, index) => index > 0 && time <= minuteOfDay[index - 1])) {
    throw new Error("briefing times must be ordered");
  }
}

function wallClock(ts: number, timeZone: string): WallClock {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(ts));
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? 0);
  return {
    year: get("year"),
    month: get("month"),
    day: get("day"),
    hour: get("hour") % 24,
    minute: get("minute"),
    second: get("second"),
  };
}

function zonedTimeToUtc(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  timeZone: string,
): number {
  const desired = Date.UTC(year, month - 1, day, hour, minute, 0);
  let ts = desired;
  for (let i = 0; i < 2; i++) {
    const w = wallClock(ts, timeZone);
    const observed = Date.UTC(w.year, w.month - 1, w.day, w.hour, w.minute, w.second);
    ts += desired - observed;
  }
  return ts;
}

function isoWeekday(year: number, month: number, day: number): number {
  const dow = new Date(Date.UTC(year, month - 1, day)).getUTCDay();
  return dow === 0 ? 7 : dow;
}

export function computeNextRunAt(
  hour: number,
  minute: number,
  weekdays: number[] | undefined,
  timezone: string,
  from: number = Date.now(),
): number {
  let best = Infinity;
  const seen = new Set<string>();
  for (let t = from; t <= from + 9 * DAY_MS; t += DAY_MS / 4) {
    const w = wallClock(t, timezone);
    const key = `${w.year}-${w.month}-${w.day}`;
    if (seen.has(key)) continue;
    seen.add(key);
    if (weekdays && weekdays.length > 0 && !weekdays.includes(isoWeekday(w.year, w.month, w.day))) {
      continue;
    }
    const candidate = zonedTimeToUtc(w.year, w.month, w.day, hour, minute, timezone);
    if (candidate > from && candidate < best) best = candidate;
  }
  if (!Number.isFinite(best)) {
    throw new Error(`could not compute next run in timezone ${timezone}`);
  }
  return best;
}

export function computeNextRunAtForTimes(
  times: readonly ScheduleTime[],
  weekdays: number[] | undefined,
  timezone: string,
  from: number = Date.now(),
): number {
  if (times.length === 0) throw new Error("schedule requires a time");
  return Math.min(
    ...times.map((time) => computeNextRunAt(time.hour, time.minute, weekdays, timezone, from)),
  );
}

export function validateSchedule(
  hour: number,
  minute: number,
  weekdays: number[] | undefined,
  timezone: string,
): void {
  if (!Number.isInteger(hour) || hour < 0 || hour > 23) {
    throw new Error("hour must be an integer 0-23");
  }
  if (!Number.isInteger(minute) || minute < 0 || minute > 59) {
    throw new Error("minute must be an integer 0-59");
  }
  if (weekdays) {
    if (weekdays.some((d) => !Number.isInteger(d) || d < 1 || d > 7)) {
      throw new Error("weekdays must be integers 1 (Monday) - 7 (Sunday)");
    }
  }
  if (timezone.length > MAX_TIMEZONE_LENGTH) throw new Error("invalid timezone");
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: timezone });
  } catch {
    throw new Error(`invalid timezone: ${timezone}`);
  }
}
