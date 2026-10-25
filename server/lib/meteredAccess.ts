import { requestAuth, type RequestAuth } from "@/lib/auth";
import { allowRequests, clientKey } from "@/lib/rateLimit";
import { RATE_LIMIT_BATCH, type RateLimit } from "@/lib/rateLimitGrant";

type MeteredRoute = {
  name: string;
  perCaller: RateLimit;
  perGuest?: RateLimit;
  allGuests?: RateLimit;
  reservationBatch?: number;
};

export const METERED_ROUTES = {
  generate: {
    name: "generate",
    perCaller: { capacity: 120, refillPerHour: 240 },
    perGuest: { capacity: 8, refillPerHour: 4 },
    allGuests: { capacity: 300, refillPerHour: 600 },
  },
  writing: {
    name: "writing",
    perCaller: { capacity: 30, refillPerHour: 60 },
    allGuests: { capacity: 300, refillPerHour: 600 },
  },
  savesClassify: {
    name: "saves-classify",
    perCaller: { capacity: 30, refillPerHour: 30 },
    perGuest: { capacity: 10, refillPerHour: 10 },
    allGuests: { capacity: 100, refillPerHour: 100 },
  },
  connectors: {
    name: "connectors",
    perCaller: { capacity: 15, refillPerHour: 30 },
  },
  connectorsRead: {
    name: "connectors-read",
    perCaller: { capacity: 60, refillPerHour: 120 },
  },
  hint: {
    name: "hint",
    perCaller: { capacity: 30, refillPerHour: 30 },
    allGuests: { capacity: 300, refillPerHour: 600 },
  },
  questionOptions: {
    name: "questionOptions",
    perCaller: { capacity: 60, refillPerHour: 120 },
    allGuests: { capacity: 600, refillPerHour: 1200 },
  },
  tts: {
    name: "tts",
    perCaller: { capacity: 60, refillPerHour: 60 },
    allGuests: { capacity: 300, refillPerHour: 600 },
  },
  tools: {
    name: "tools",
    perCaller: { capacity: 60, refillPerHour: 60 },
    allGuests: { capacity: 600, refillPerHour: 1200 },
  },
  image: {
    name: "image",
    perCaller: { capacity: 300, refillPerHour: 3600 },
    perGuest: { capacity: 120, refillPerHour: 3600 },
    allGuests: { capacity: 3000, refillPerHour: 6000 },
    reservationBatch: RATE_LIMIT_BATCH,
  },
  catalogImage: {
    name: "catalogImage",
    perCaller: { capacity: 240, refillPerHour: 600 },
    allGuests: { capacity: 3000, refillPerHour: 6000 },
    reservationBatch: RATE_LIMIT_BATCH,
  },
} satisfies Record<string, MeteredRoute>;

export async function admitMetered(
  req: Request,
  route: MeteredRoute,
  auth?: Pick<RequestAuth, "authenticated" | "convex" | "ownerKey">,
): Promise<boolean> {
  auth ??= await requestAuth(req);
  const ownerKey = auth.authenticated ? auth.ownerKey : null;
  const perCaller = ownerKey === null ? (route.perGuest ?? route.perCaller) : route.perCaller;
  const budgets = [{ key: `${route.name}:${clientKey(req, ownerKey)}`, ...perCaller }];
  if (ownerKey === null && route.allGuests)
    budgets.push({ key: `${route.name}:guests`, ...route.allGuests });
  return allowRequests(budgets, auth, route.reservationBatch ?? 1);
}
