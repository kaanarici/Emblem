import sharp from "sharp";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  fullSizeVariants,
  minimumShortEdge,
  probeImageCandidates,
  USER_AGENT,
} from "../lib/imageVerify";
import { resolveImageCached, resolvePageArtwork } from "../lib/imageResolve";

const network = vi.hoisted(() => ({
  images: new Map<string, Buffer>(),
  requests: [] as { url: string; headers: Record<string, string> }[],
}));

vi.mock("node:https", async () => {
  const { Readable } = await import("node:stream");
  return {
    request: (
      url: URL,
      options: { headers: Record<string, string> },
      respond: (message: unknown) => void,
    ) => ({
      on() {
        return this;
      },
      end() {
        network.requests.push({ url: url.href, headers: options.headers });
        const body = network.images.get(url.href);
        respond(
          Object.assign(Readable.from(body ? [body] : []), {
            statusCode: body ? 200 : 404,
            headers: { "content-type": body ? "image/jpeg" : "text/html" },
          }),
        );
      },
    }),
  };
});

async function photo(width: number, height: number): Promise<Buffer> {
  const pixels = Buffer.alloc(width * height * 3);
  for (let i = 0; i < width * height; i++) {
    pixels[i * 3] = ((i % width) * 255) / width;
    pixels[i * 3 + 1] = (Math.floor(i / width) * 255) / height;
    pixels[i * 3 + 2] = Math.imul(i + 1, 2654435761) >>> 24;
  }
  return sharp(pixels, { raw: { width, height, channels: 3 } })
    .jpeg()
    .toBuffer();
}

async function serve(images: Record<string, [number, number]>) {
  for (const [url, [width, height]] of Object.entries(images)) {
    network.images.set(url, await photo(width, height));
  }
}

const fetched = () => network.requests.map(({ url }) => url);

beforeEach(() => {
  network.images.clear();
  network.requests.length = 0;
});

describe("photo quality rules", () => {
  it("measures real pixels instead of trusting a size in the URL", async () => {
    await serve({
      "https://cdn.example.com/1280px-claims-large.jpg": [300, 300],
      "https://cdn.example.com/actual-large.jpg": [800, 600],
    });
    const verdict = await probeImageCandidates([
      "https://cdn.example.com/1280px-claims-large.jpg",
      "https://cdn.example.com/actual-large.jpg",
    ]);
    expect(verdict.url).toBe("https://cdn.example.com/actual-large.jpg");
  });

  it("asks more of a hero than of a card", async () => {
    await serve({ "https://cdn.example.com/medium.jpg": [500, 400] });
    const candidates = ["https://cdn.example.com/medium.jpg"];
    expect((await probeImageCandidates(candidates)).url).toBe(candidates[0]);
    const hero = await probeImageCandidates(candidates, {
      minEdge: minimumShortEdge("photo", "hero"),
    });
    expect(hero.url).toBeNull();
    expect(minimumShortEdge("logo", "hero")).toBeLessThan(minimumShortEdge("photo", "card"));
  });

  it("never fetches stock, watermark or thumbnail-service hosts", async () => {
    const blocked = [
      "https://image.shutterstock.com/image-photo/diner-600w-1.jpg",
      "https://c8.alamy.com/comp/ABC123/diner.jpg",
      "https://media.gettyimages.com/id/1/photo/diner.jpg",
      "https://media.istockphoto.com/id/1/photo/diner.jpg",
      "https://thumbs.dreamstime.com/b/diner-1.jpg",
      "https://previews.123rf.com/images/diner.jpg",
      "https://st.depositphotos.com/1/diner.jpg",
      "https://t3.ftcdn.net/jpg/01/diner.jpg",
      "https://stock.adobe.com/images/diner.jpg",
      "https://i.pinimg.com/236x/aa/bb/diner.jpg",
      "https://encrypted-tbn0.gstatic.com/images?q=tbn:diner.jpg",
      "https://tse1.mm.bing.net/th/id/diner.jpg",
      "https://cdn.example.com/watermarked/diner.jpg",
    ];
    await serve(Object.fromEntries(blocked.map((url) => [url, [1600, 1200]])));
    await serve({ "https://cdn.example.com/diner.jpg": [1600, 1200] });
    const verdict = await probeImageCandidates([...blocked, "https://cdn.example.com/diner.jpg"]);
    expect(verdict.url).toBe("https://cdn.example.com/diner.jpg");
    expect(fetched()).toEqual(["https://cdn.example.com/diner.jpg"]);
  });

  it("names the original-size variant before a thumbnail", () => {
    expect(
      fullSizeVariants(
        "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Diner.jpg/220px-Diner.jpg",
      ),
    ).toEqual([
      "https://upload.wikimedia.org/wikipedia/commons/a/ab/Diner.jpg",
      "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Diner.jpg/220px-Diner.jpg",
    ]);
    expect(
      fullSizeVariants(
        "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Diner.jpg/1280px-Diner.jpg",
      ),
    ).toHaveLength(1);
    expect(
      fullSizeVariants(
        "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Scan.tif/220px-Scan.tif.jpg",
      ),
    ).toHaveLength(1);
    expect(
      fullSizeVariants("https://blog.example.com/wp-content/uploads/diner-300x200.jpg"),
    ).toEqual([
      "https://blog.example.com/wp-content/uploads/diner.jpg",
      "https://blog.example.com/wp-content/uploads/diner-300x200.jpg",
    ]);
    expect(
      fullSizeVariants("https://cdn.example.com/diner.jpg?w=300&h=200&fit=crop&s=sig"),
    ).toEqual([
      "https://cdn.example.com/diner.jpg?s=sig",
      "https://cdn.example.com/diner.jpg?w=300&h=200&fit=crop&s=sig",
    ]);
    expect(fullSizeVariants("https://images.example.com/diner.jpg?w=2000")).toHaveLength(1);
    expect(fullSizeVariants("https://i.ytimg.com/vi/abc123/hqdefault.jpg")).toEqual([
      "https://i.ytimg.com/vi/abc123/maxresdefault.jpg",
      "https://i.ytimg.com/vi/abc123/hqdefault.jpg",
    ]);
  });

  it("prefers the original, then the thumbnail only when it is big enough", async () => {
    const thumb =
      "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Diner.jpg/640px-Diner.jpg";
    const original = "https://upload.wikimedia.org/wikipedia/commons/a/ab/Diner.jpg";
    await serve({ [thumb]: [640, 480], [original]: [2400, 1800] });
    expect((await probeImageCandidates([thumb])).url).toBe(original);

    network.images.delete(original);
    expect((await probeImageCandidates([thumb])).url).toBe(thumb);

    const tiny = "https://cdn.example.com/diner-150x150.jpg";
    await serve({ [tiny]: [150, 150] });
    expect((await probeImageCandidates([tiny])).url).toBeNull();
  });

  it("identifies itself so Wikimedia serves the image", async () => {
    await serve({ "https://upload.wikimedia.org/wikipedia/commons/a/ab/Diner.jpg": [800, 600] });
    await probeImageCandidates(["https://upload.wikimedia.org/wikipedia/commons/a/ab/Diner.jpg"]);
    expect(network.requests[0]?.headers["User-Agent"]).toBe(USER_AGENT);
  });
});

function stubProviders(wikiLead: string, exaImages: string[]) {
  vi.stubEnv("EXA_API_KEY", "test-key");
  vi.stubEnv("NEXT_PUBLIC_CONVEX_URL", "");
  const calls: string[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: string | URL | Request) => {
      const url = String(input);
      calls.push(url);
      if (url.includes("wikipedia.org/w/api.php")) {
        return Response.json({
          query: {
            pages: { "1": { thumbnail: { source: wikiLead, width: 1280, height: 960 } } },
          },
        });
      }
      if (url.includes("wikidata.org")) return Response.json({ search: [] });
      if (url.startsWith("https://api.exa.ai/")) {
        return Response.json({ results: exaImages.map((image) => ({ image })) });
      }
      return new Response(null, { status: 404 });
    }),
  );
  return calls;
}

describe("photo resolution", () => {
  it("skips a lead photo that is smaller than Wikipedia declares and a stock result", async () => {
    const lead = "https://upload.wikimedia.org/wikipedia/en/a/ab/Small_Diner.jpg";
    await serve({
      [lead]: [300, 300],
      "https://www.example.com/photos/diner-dining-room.jpg": [1600, 1000],
    });
    stubProviders(lead, [
      "https://image.shutterstock.com/image-photo/diner-dining-room-600w.jpg",
      "https://www.example.com/photos/diner-dining-room.jpg",
    ]);
    expect(await resolveImageCached("Quality Diner Austin", "photo", "landscape")).toBe(
      "https://www.example.com/photos/diner-dining-room.jpg",
    );
    expect(fetched().some((url) => url.includes("shutterstock"))).toBe(false);
  });

  it("returns no photo rather than a bad one", async () => {
    const lead = "https://upload.wikimedia.org/wikipedia/en/a/ab/Tiny_Cafe.jpg";
    await serve({ [lead]: [200, 200], "https://www.example.com/photos/tiny-cafe.jpg": [240, 180] });
    stubProviders(lead, [
      "https://www.example.com/photos/tiny-cafe.jpg",
      "https://i.pinimg.com/736x/aa/bb/tiny-cafe.jpg",
    ]);
    expect(await resolveImageCached("Tiny Cafe Lisbon", "photo", "landscape")).toBeNull();
  });

  it("gives a hero only a photo big enough for a hero", async () => {
    const lead = "https://upload.wikimedia.org/wikipedia/en/a/ab/Medium_Bistro.jpg";
    await serve({ [lead]: [500, 400] });
    stubProviders(lead, []);
    const page = await resolvePageArtwork([
      {
        type: "hero",
        id: "hero",
        image: { query: "Medium Bistro Porto", kind: "photo" },
        aspect: "square",
      },
      {
        type: "cardCarousel",
        id: "cards",
        cards: [
          {
            title: "Medium Bistro",
            image: { query: "Medium Bistro Porto", kind: "photo", aspect: "square" },
          },
        ],
      },
    ]);
    const [hero, cards] = page;
    expect(hero.type === "hero" && hero.imageURL).toBeFalsy();
    expect(cards.type === "cardCarousel" && cards.cards[0].imageURL).toBe(lead);
  });
});
