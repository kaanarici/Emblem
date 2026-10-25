import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();
crons.interval("recover background wakeup", { minutes: 5 }, internal.background.initialize, {});
crons.interval(
  "purge rate limit reservations",
  { minutes: 5 },
  internal.rateLimits.purgeExpiredReservations,
  {},
);
crons.daily(
  "purge expired image cache",
  { hourUTC: 4, minuteUTC: 0 },
  internal.imageCache.purgeExpired,
  {},
);
crons.daily(
  "purge expired generation runs",
  { hourUTC: 4, minuteUTC: 30 },
  internal.pages.purgeExpiredRuns,
  {},
);
export default crons;
