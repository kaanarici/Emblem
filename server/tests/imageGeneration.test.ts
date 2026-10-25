import sharp from "sharp";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("convex/browser", () => ({
  ConvexHttpClient: class {
    query = async () => null;
    action = async () => ({});
  },
}));

const { prepareGeneratedStepImages, resolveGeneratedStepImageQuery } =
  await import("../lib/generatedStepImages");
const { resolveObjectIconQuery } = await import("../lib/objectIcons");
const { warmImage } = await import("../lib/imageResolve");

const png = await sharp({
  create: { width: 16, height: 16, channels: 4, background: { r: 200, g: 120, b: 40, alpha: 1 } },
})
  .png()
  .toBuffer();
const FLUX = "fal.run/fal-ai/flux-2/flash";
const CUTOUT = "fal.run/fal-ai/birefnet/v2";
const GEMINI =
  "generativelanguage.googleapis.com/v1/models/gemini-3.1-flash-lite-image:generateContent";
const allow = async () => true;
const deny = async () => false;

function memoryStore() {
  const images = new Set<string>();
  return {
    get: async (key: string) =>
      images.has(key)
        ? { url: `https://cdn.test/${key}`, mimeType: "image/png" as const, byteLength: 1 }
        : null,
    put: async (key: string) => {
      images.add(key);
    },
  };
}

function providers() {
  const paid: string[] = [];
  const fetch = async (input: string | URL | Request) => {
    const url = input instanceof Request ? input.url : String(input);
    if (url.startsWith("data:")) return new Response(png);
    paid.push(`${new URL(url).host}${new URL(url).pathname}`);
    if (url.startsWith("https://fal.run/"))
      return Response.json({
        images: [{ url: `data:image/png;base64,${png.toString("base64")}` }],
      });
    return Response.json({
      candidates: [
        {
          content: {
            parts: [{ inlineData: { mimeType: "image/png", data: png.toString("base64") } }],
          },
        },
      ],
    });
  };
  return { paid, fetch: fetch as typeof globalThis.fetch };
}

function stepQuery(title = "Whisk butter") {
  const [block] = prepareGeneratedStepImages(
    [
      {
        type: "stepCarousel",
        id: "steps",
        steps: [{ title, body: "Whisk butter with sugar until glossy." }],
      },
    ],
    { ownerScope: "https://images-test.invalid|alice", tokenSecret: "test-token-secret" },
  );
  if (block?.type !== "stepCarousel") throw new Error("step carousel required");
  return block.steps[0]!.icon!.image!.query;
}

beforeEach(() => {
  vi.stubEnv("NEXT_PUBLIC_CONVEX_URL", "https://local-test.convex.cloud");
  vi.stubEnv("GENERATED_STEP_IMAGE_STORAGE_SECRET", "test-storage-secret");
  vi.stubEnv("GENERATED_STEP_IMAGE_TOKEN_SECRET", "test-token-secret");
  vi.stubEnv("GEMINI_API_KEY", "synthetic-only");
  vi.stubEnv("FAL_KEY", "synthetic-only");
  vi.stubEnv("IMAGE_PROVIDER", "");
  vi.stubEnv("OBJECT_ICON_PROVIDER", "");
  vi.stubGlobal("fetch", async () => {
    throw new Error("tests never reach the network");
  });
});
afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe("paid image generation", () => {
  it("draws step images and icons with fal when FAL_KEY is set and with Gemini only without it", async () => {
    const fal = providers();
    const url = await resolveGeneratedStepImageQuery(stepQuery(), {
      store: memoryStore(),
      fetch: fal.fetch,
      admit: allow,
    });
    expect(url).toMatch(/^\/api\/generated-step-image\?key=[a-f0-9]{64}$/);
    expect(
      await resolveObjectIconQuery("kettle", {
        store: memoryStore(),
        fetch: fal.fetch,
        admit: allow,
      }),
    ).toMatch(/^https:\/\/cdn\.test\//);
    expect(fal.paid).toEqual([FLUX, FLUX, CUTOUT]);

    vi.stubEnv("FAL_KEY", "");
    const gemini = providers();
    await resolveGeneratedStepImageQuery(stepQuery("Fold in flour"), {
      store: memoryStore(),
      fetch: gemini.fetch,
      admit: allow,
    });
    expect(gemini.paid).toEqual([GEMINI]);
  });

  it("draws one icon for a noun across case, spacing, plurals and concurrent requests", async () => {
    vi.stubEnv("FAL_KEY", "");
    const store = memoryStore();
    const fal = providers();
    const resolve = (query: string) =>
      resolveObjectIconQuery(query, { store, fetch: fal.fetch, admit: allow });
    const [egg, eggs] = await Promise.all([resolve("egg"), resolve(" Eggs ")]);
    expect(egg).not.toBeNull();
    expect(eggs).toBe(egg);
    await resolve("EGG");
    await resolve("glass");
    await resolve("glasses");
    expect(fal.paid).toEqual([GEMINI, GEMINI, GEMINI]);
  });

  it("past the daily ceiling serves cached images and skips new ones without a paid call", async () => {
    vi.stubEnv("FAL_KEY", "");
    const store = memoryStore();
    const fal = providers();
    const kettle = await resolveObjectIconQuery("kettle", {
      store,
      fetch: fal.fetch,
      admit: allow,
    });
    fal.paid.length = 0;
    expect(await resolveObjectIconQuery("kettle", { store, fetch: fal.fetch, admit: deny })).toBe(
      kettle,
    );
    expect(await resolveObjectIconQuery("teapot", { store, fetch: fal.fetch, admit: deny })).toBe(
      null,
    );
    expect(
      await resolveGeneratedStepImageQuery(stepQuery(), { store, fetch: fal.fetch, admit: deny }),
    ).toBeNull();
    expect(fal.paid).toEqual([]);
  });

  it("leaves step image generation to the client's request instead of warming it while streaming", async () => {
    const network = providers();
    vi.stubGlobal("fetch", network.fetch);
    warmImage(stepQuery(), "generated");
    await new Promise((resolve) => setImmediate(resolve));
    expect(network.paid).toEqual([]);
  });
});
