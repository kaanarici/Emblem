import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { RequestAuth } from "../lib/auth";
import type { RateBudget } from "../lib/rateLimitGrant";

const mocks = vi.hoisted(() => ({
  ownerKey: null as string | null,
  convex: null as RequestAuth["convex"],
  status: null as RequestAuth["status"] | null,
  requestAuth: vi.fn(),
  resolveImage: vi.fn(),
  resolveObject: vi.fn(),
  cachedObject: vi.fn(async (): Promise<string | null> => null),
  resolveGenerated: vi.fn(),
  allow:
    vi.fn<(budgets: readonly RateBudget[], auth: RequestAuth, batch: number) => Promise<boolean>>(),
}));
vi.mock("@/lib/auth", () => ({
  requestAuth: mocks.requestAuth,
}));
vi.mock("@/lib/rateLimit", async (original) => ({
  ...(await original<typeof import("../lib/rateLimit")>()),
  allowRequests: mocks.allow,
}));
vi.mock("@/lib/imageResolve", () => ({
  cachedImageURL: async () => null,
  resolveImageCached: mocks.resolveImage,
}));
vi.mock("@/lib/objectIcons", () => ({
  objectIconGenerationAvailable: () => true,
  resolveObjectIconQuery: mocks.resolveObject,
  cachedObjectIconURL: mocks.cachedObject,
}));
vi.mock("@/lib/generatedStepImages", () => ({
  isGeneratedStepImageQuery: (query: string) => query.startsWith("emblem-step-image.v1."),
  resolveGeneratedStepImageQuery: mocks.resolveGenerated,
}));
const actualRateLimit =
  await vi.importActual<typeof import("../lib/rateLimit")>("../lib/rateLimit");
const { verifyRateLimitGrant } = await import("../lib/rateLimitGrant");
const { hotelPhotoQuery } = await import("../lib/travel/hotelContent");
const { GET } = await import("../app/api/image/route");
const { admitMetered, METERED_ROUTES } = await import("../lib/meteredAccess");
const from = (ip: string) =>
  new Request("https://emblem.test/api", { headers: { "x-real-ip": ip } });

beforeEach(() => {
  mocks.ownerKey = null;
  mocks.convex = null;
  mocks.status = null;
  mocks.requestAuth.mockReset().mockImplementation(async () => ({
    convex: mocks.convex,
    authenticated: mocks.ownerKey !== null,
    ownerKey: mocks.ownerKey,
    status: mocks.status ?? (mocks.ownerKey ? "authenticated" : "guest"),
  }));
  mocks.allow.mockReset().mockResolvedValue(true);
});

describe("metered paid endpoints", () => {
  it("reserves the guest address and shared endpoint cap atomically", async () => {
    expect(await admitMetered(from("192.0.2.1"), METERED_ROUTES.hint)).toBe(true);
    expect(mocks.allow.mock.calls[0][0]).toEqual([
      { key: "hint:ip:192.0.2.1", ...METERED_ROUTES.hint.perCaller },
      { key: "hint:guests", ...METERED_ROUTES.hint.allGuests },
    ]);
    expect(mocks.allow.mock.calls[0][2]).toBe(1);
    mocks.allow.mockResolvedValue(false);
    expect(await admitMetered(from("192.0.2.1"), METERED_ROUTES.hint)).toBe(false);
  });

  it("uses only the signed-in owner's bucket and keeps endpoints separate", async () => {
    mocks.ownerKey = "issuer|alice";
    for (const route of Object.values(METERED_ROUTES)) {
      await admitMetered(from("192.0.2.1"), route);
      expect(mocks.allow.mock.lastCall?.[0]).toEqual([
        { key: `${route.name}:user:issuer|alice`, ...route.perCaller },
      ]);
    }
  });

  it("batches ordinary and catalog image permits only", async () => {
    for (const route of Object.values(METERED_ROUTES)) {
      await admitMetered(from("192.0.2.1"), route);
      expect(mocks.allow.mock.lastCall?.[2]).toBe(
        route.name === "image" || route.name === "catalogImage" ? 8 : 1,
      );
    }
  });
});

const SECRET = "catalog-media-synthetic-rate-limit-secret-only";
let fixtureRun = 0;
let query: string;
let counter: ReturnType<typeof vi.fn>;
let balances: Map<string, number>;
let claims: NonNullable<Awaited<ReturnType<typeof verifyRateLimitGrant>>>[];
const imageRequest = (value: string, kind: string | null = "photo", ip = "192.0.2.40") => {
  const url = new URL("https://emblem.test/api/image");
  url.searchParams.set("query", value);
  if (kind !== null) url.searchParams.set("kind", kind);
  return new Request(url, { headers: { "x-real-ip": ip } });
};

function expectedCatalogBudgets(owner: string | null, ip = "192.0.2.40") {
  return [
    {
      key: `catalogImage:${owner ? `user:${owner}` : `ip:${ip}`}`,
      capacity: 240,
      refillPerHour: 600,
    },
    ...(owner ? [] : [{ key: "catalogImage:guests", capacity: 3000, refillPerHour: 6000 }]),
  ];
}

describe("signed catalog image route and actual batched admission", () => {
  beforeEach(() => {
    vi.stubEnv("NUITEE_SANDBOX_API_KEY", "sand_synthetic_catalog_media");
    vi.stubEnv("RATE_LIMIT_SECRET", SECRET);
    vi.stubEnv("NEXT_PUBLIC_CONVEX_URL", `https://catalog-media-${++fixtureRun}.convex.test`);
    vi.stubGlobal(
      "fetch",
      vi.fn(() => {
        throw new Error("No network in catalog-media tests");
      }),
    );
    vi.spyOn(performance, "now").mockReturnValue(0);
    query = hotelPhotoQuery({ hotelId: "public-catalog-hotel" });
    balances = new Map();
    claims = [];
    counter = vi.fn(async (_function: unknown, grant: { payload: string; signature: string }) => {
      const signed = await verifyRateLimitGrant(SECRET, mocks.ownerKey, grant);
      if (!signed) throw new Error("Invalid synthetic transport grant");
      claims.push(signed);
      const remaining = Math.min(
        ...signed.budgets.map((budget) => balances.get(budget.key) ?? budget.capacity),
      );
      const count = remaining >= signed.batch ? signed.batch : remaining >= 1 ? 1 : 0;
      for (const budget of signed.budgets) {
        balances.set(budget.key, (balances.get(budget.key) ?? budget.capacity) - count);
      }
      return { count, leaseMs: 1000 };
    });
    mocks.convex = { mutation: counter } as unknown as NonNullable<RequestAuth["convex"]>;
    mocks.allow.mockImplementation(actualRateLimit.allowRequests);
    mocks.resolveImage.mockReset().mockResolvedValue("https://images.example/public-catalog.jpg");
    mocks.resolveObject.mockReset().mockResolvedValue(null);
    mocks.resolveGenerated.mockReset().mockResolvedValue(null);
  });
  afterEach(() => {
    expect(globalThis.fetch).not.toHaveBeenCalled();
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
    vi.restoreAllMocks();
  });

  it("classifies only a MAC-valid photo before admission and retains resolver arguments/cache policy", async () => {
    mocks.ownerKey = "issuer|catalog-owner";
    const req = imageRequest(query);
    const url = new URL(req.url);
    url.searchParams.set("aspect", "portrait");
    url.searchParams.set("exclude", "https://images.example/previous.jpg");
    const request = new Request(url, { headers: req.headers });
    const response = await GET(request);
    expect(response.status).toBe(200);
    expect(mocks.requestAuth).toHaveBeenCalledExactlyOnceWith(request);
    expect(mocks.allow.mock.calls[0]).toEqual([
      expectedCatalogBudgets(mocks.ownerKey),
      {
        convex: mocks.convex,
        authenticated: true,
        ownerKey: mocks.ownerKey,
        status: "authenticated",
      },
      8,
    ]);
    expect(mocks.resolveImage).toHaveBeenCalledWith(
      query,
      "photo",
      "portrait",
      "https://images.example/previous.jpg",
      "card",
    );
    expect(response.headers.get("cache-control")).toBe("public, max-age=86400");
    expect(counter).toHaveBeenCalledTimes(1);
    expect(claims[0]).toMatchObject({ batch: 8, budgets: [{ capacity: 240, refillPerHour: 600 }] });
  });

  it("uses the existing default photo kind and same guest IP plus shared-guest grant", async () => {
    expect((await GET(imageRequest(query, null))).status).toBe(200);
    expect(mocks.allow.mock.calls[0][0]).toEqual(expectedCatalogBudgets(null));
    expect(
      claims[0].budgets.map(({ capacity, refillPerHour }) => ({ capacity, refillPerHour })),
    ).toEqual([
      { capacity: 240, refillPerHour: 600 },
      { capacity: 3000, refillPerHour: 6000 },
    ]);
  });

  it.each(["forged MAC", "unsigned", "ordinary", "object", "poster", "generated"])(
    "keeps %s on the unchanged ordinary budget",
    async (kind) => {
      const variants = {
        "forged MAC": {
          query: query.replace("public-catalog-hotel", "forged-hotel"),
          kind: "photo",
        },
        unsigned: { query: query.slice(0, query.lastIndexOf(".")), kind: "photo" },
        ordinary: { query: "Public hotel exterior", kind: "photo" },
        object: { query, kind: "object" },
        poster: { query, kind: "poster" },
        generated: { query, kind: "generated" },
      };
      const value = variants[kind as keyof typeof variants];
      await GET(imageRequest(value.query, value.kind));
      expect(mocks.allow.mock.calls[0][0]).toEqual([
        { key: "image:ip:192.0.2.40", capacity: 120, refillPerHour: 3600 },
        { key: "image:guests", capacity: 3000, refillPerHour: 6000 },
      ]);
      expect(mocks.allow.mock.calls[0][2]).toBe(8);
    },
  );

  it("does not admit a signed token after its signing configuration disappears", async () => {
    vi.stubEnv("NUITEE_SANDBOX_API_KEY", "");
    await GET(imageRequest(query));
    expect(mocks.allow.mock.calls[0][0][0]).toEqual({
      key: "image:ip:192.0.2.40",
      capacity: 120,
      refillPerHour: 3600,
    });
  });

  it.each(["owner", "guest"])(
    "exhausts the %s at 240 permits with thirty batched reservations, then denies before resolver",
    async (caller) => {
      mocks.ownerKey = caller === "owner" ? "issuer|bounded-owner" : null;
      for (let index = 0; index < 240; index++)
        expect((await GET(imageRequest(query))).status).toBe(200);
      expect(counter).toHaveBeenCalledTimes(30);
      expect(claims.every((grant) => grant.batch === 8)).toBe(true);
      const denied = await GET(imageRequest(query));
      expect(denied.status).toBe(429);
      expect(denied.headers.get("cache-control")).toBe("no-store");
      await expect(denied.json()).resolves.toEqual({ error: "rate_limited" });
      expect(mocks.resolveImage).toHaveBeenCalledTimes(240);
      expect(counter).toHaveBeenCalledTimes(31);
      expect(mocks.requestAuth).toHaveBeenCalledTimes(241);
    },
  );

  it("serves an already generated object icon without spending any budget", async () => {
    mocks.cachedObject.mockResolvedValueOnce("https://cdn.example/icon.png");
    const response = await GET(imageRequest("Public object", "object"));
    await expect(response.json()).resolves.toEqual({ url: "https://cdn.example/icon.png" });
    expect(mocks.allow).not.toHaveBeenCalled();
    expect(mocks.resolveObject).not.toHaveBeenCalled();
  });

  it("does not broaden ordinary image/object limits when the catalog bucket is available", async () => {
    for (let index = 0; index < 120; index++)
      expect((await GET(imageRequest("Public object", "object"))).status).toBe(200);
    expect((await GET(imageRequest("Public object", "object"))).status).toBe(429);
    expect(mocks.resolveObject).toHaveBeenCalledTimes(120);
    expect((await GET(imageRequest(query))).status).toBe(200);
    expect(mocks.allow.mock.lastCall?.[0]).toEqual(expectedCatalogBudgets(null));
  });

  it("atomically exhausts the shared 3000 guest permits across independent IPs without a blanket exemption", async () => {
    for (let address = 0; address < 12; address++) {
      for (let index = 0; index < 240; index++)
        expect((await GET(imageRequest(query, "photo", `192.0.2.${address + 1}`))).status).toBe(
          200,
        );
    }
    for (let index = 0; index < 120; index++)
      expect((await GET(imageRequest(query, "photo", "192.0.2.90"))).status).toBe(200);
    expect(counter).toHaveBeenCalledTimes(375);
    expect((await GET(imageRequest(query, "photo", "192.0.2.91"))).status).toBe(429);
    expect(mocks.resolveImage).toHaveBeenCalledTimes(3000);
    expect(mocks.allow.mock.lastCall?.[0]).toEqual(expectedCatalogBudgets(null, "192.0.2.91"));
    mocks.ownerKey = "issuer|independent-owner";
    expect((await GET(imageRequest(query, "photo", "192.0.2.91"))).status).toBe(200);
    expect(mocks.allow.mock.lastCall?.[0]).toEqual(expectedCatalogBudgets(mocks.ownerKey));
  });

  it("retains unavailable-auth denial before any resolver even for a valid catalog signature", async () => {
    mocks.convex = null;
    mocks.status = "unavailable";
    const denied = await GET(imageRequest(query));
    expect(denied.status).toBe(429);
    expect(mocks.requestAuth).toHaveBeenCalledTimes(1);
    expect(counter).not.toHaveBeenCalled();
    expect(mocks.resolveImage).not.toHaveBeenCalled();
  });

  it("retains failed-grant denial before any resolver without falling back to an ordinary permit", async () => {
    counter.mockResolvedValue({ count: 0, leaseMs: 1000 });
    expect((await GET(imageRequest(query))).status).toBe(429);
    expect(counter).toHaveBeenCalledTimes(1);
    expect(mocks.allow).toHaveBeenCalledTimes(1);
    expect(mocks.resolveImage).not.toHaveBeenCalled();
  });

  it("still forwards valid nonmember tokens to the resolver and preserves null/no-store", async () => {
    query = hotelPhotoQuery(
      { hotelId: "public-catalog-hotel", roomId: "nonmember-room" },
      "https://images.example/nonmember.jpg",
    );
    mocks.resolveImage.mockResolvedValue(null);
    const response = await GET(imageRequest(query));
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ url: null });
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(mocks.resolveImage).toHaveBeenCalledExactlyOnceWith(
      query,
      "photo",
      undefined,
      undefined,
      "card",
    );
    expect(mocks.allow.mock.calls[0][0]).toEqual(expectedCatalogBudgets(null));
  });
});
