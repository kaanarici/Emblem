import { convexTest } from "convex-test";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../convex/_generated/api";
import schema from "../convex/schema";
import { blockSchema } from "../lib/schema";
import { insertPage } from "./support/pages";

const modules = import.meta.glob("../convex/**/*.ts");
const owner = "https://clerk.example|alice";
const auth = vi.hoisted(() => ({ convex: null as unknown }));

vi.mock("@/lib/auth", () => ({
  requestAuth: async () => ({
    convex: auth.convex,
    authenticated: true,
    ownerKey: "https://clerk.example|alice",
    status: "authenticated",
  }),
  authFailure: () => null,
}));

const { GET: listConversations } = await import("../app/api/conversations/route");
const { GET: readHistory } = await import("../app/api/history/route");
const { POST: changeConversation } = await import("../app/api/conversation/route");

function setup(options: { transactionLimits?: boolean } = {}) {
  const t = convexTest({ schema, modules, ...options });
  const alice = t.withIdentity({
    subject: "alice",
    issuer: "https://clerk.example",
    tokenIdentifier: owner,
  });
  auth.convex = alice;
  return { t, alice };
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(1_000_000);
});

function pageBlocks(title: string, body: string, query = "harbor at dusk") {
  return JSON.stringify([
    { type: "pageMeta", id: "meta", title },
    { type: "hero", id: "hero", image: { query, kind: "photo" } },
    { type: "text", id: "intro", style: "intro", body },
    {
      type: "writing",
      id: "draft",
      drafts: [{ id: "one", label: "Draft", body: "First draft" }],
    },
  ]);
}

async function generate(
  alice: ReturnType<typeof setup>["alice"],
  conversationKey: string,
  requestId: string,
  title: string,
  options: { previousPageKey?: string; beforeComplete?: () => Promise<void> } = {},
) {
  vi.setSystemTime(Date.now() + 1_000);
  await alice.mutation(api.pages.claimGeneration, {
    requestId,
    fingerprint: requestId,
    conversationKey,
    ...(options.previousPageKey ? { previousPageKey: options.previousPageKey } : {}),
  });
  await options.beforeComplete?.();
  return await alice.mutation(api.pages.completeGeneration, {
    requestId,
    leaseGeneration: 1,
    prompt: `Prompt for ${title}`,
    title,
    blocks: pageBlocks(title, `${title} body`),
    coverImageQuery: "harbor at dusk",
    coverImageKind: "photo",
  });
}

async function conversations(query = "") {
  const response = await listConversations(
    new Request(`https://emblem.test/api/conversations${query}`),
  );
  expect(response.status).toBe(200);
  return (await response.json()) as {
    pinned: { key: string; title: string; archived: boolean; pinnedAt?: number }[];
    conversations: { key: string; title: string; archived: boolean; pinnedAt?: number }[];
    nextCursor: string | null;
  };
}

async function act(body: Record<string, unknown>) {
  const response = await changeConversation(
    new Request("https://emblem.test/api/conversation", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  );
  return { status: response.status, body: await response.json() };
}

async function seed(t: ReturnType<typeof setup>["t"], count: number, prefix = "c") {
  await t.run(async (ctx) => {
    for (let i = 0; i < count; i++) {
      await insertPage(ctx, {
        userTokenIdentifier: owner,
        conversationKey: `${prefix}-${i}`,
        pageKey: `${prefix}-${i}-page`,
        requestedAt: 10_000 + i,
        prompt: `Conversation ${i}`,
        blocks: "[]",
      });
    }
  });
}

describe("conversation metadata", () => {
  it("keeps a pin and a custom title through follow-ups, artwork and draft edits", async () => {
    const { alice } = setup();
    const first = await generate(alice, "trip", "request-1", "Lisbon");
    expect((await act({ action: "pin", conversationKey: "trip" })).status).toBe(200);
    expect(
      (await act({ action: "rename", conversationKey: "trip", title: "Our trip" })).status,
    ).toBe(200);

    const second = await generate(alice, "trip", "request-2", "Lisbon food", {
      previousPageKey: "request-1",
    });
    await alice.mutation(api.pages.setCoverImageUrl, {
      pageId: second!,
      url: "https://images.example/harbor.jpg",
    });
    await alice.mutation(api.pages.setCoverImageUrl, {
      pageId: first!,
      url: "https://images.example/old.jpg",
    });
    expect(
      await alice.mutation(api.pages.updateWritingDraft, {
        conversationKey: "trip",
        pageKey: "request-2",
        blockID: "draft",
        draftID: "one",
        previousBody: "First draft",
        body: "Second draft",
      }),
    ).toBe("saved");

    const list = await conversations();
    expect(list.conversations).toEqual([]);
    expect(list.pinned).toEqual([
      expect.objectContaining({
        key: "trip",
        title: "Our trip",
        archived: false,
        pinnedAt: expect.any(Number),
        preview: "Lisbon food body",
        imageURL: "https://images.example/harbor.jpg",
      }),
    ]);
  });

  it("keeps an archived conversation archived when a new page lands", async () => {
    const { alice } = setup();
    await generate(alice, "old", "request-1", "Old plan");
    expect((await act({ action: "archive", conversationKey: "old" })).status).toBe(200);
    await generate(alice, "old", "request-2", "Old plan again", { previousPageKey: "request-1" });

    expect((await conversations()).conversations).toEqual([]);
    expect((await conversations("?archived=true")).conversations).toEqual([
      expect.objectContaining({ key: "old", title: "Old plan again", archived: true }),
    ]);
  });

  it("keeps a rename made while a generation is still running", async () => {
    const { alice } = setup();
    await generate(alice, "trip", "request-1", "Lisbon");
    await generate(alice, "trip", "request-2", "Lisbon food", {
      previousPageKey: "request-1",
      beforeComplete: async () => {
        expect(
          (await act({ action: "rename", conversationKey: "trip", title: "Our trip" })).body,
        ).toEqual({ ok: true, action: "rename" });
      },
    });
    await generate(alice, "trip", "request-3", "Lisbon bars", { previousPageKey: "request-2" });

    expect((await conversations()).conversations).toEqual([
      expect.objectContaining({ key: "trip", title: "Our trip" }),
    ]);
  });

  it("saves a page whose cover query or artwork URL is long", async () => {
    const { alice } = setup();
    const query = `Profile of ${"a very long article card title ".repeat(9)}`.slice(0, 300);
    const url = `https://images.example/${"x".repeat(3_000)}.jpg`;
    await alice.mutation(api.pages.claimGeneration, {
      requestId: "long-cover",
      fingerprint: "long-cover",
      conversationKey: "article",
    });
    expect(
      await alice.mutation(api.pages.completeGeneration, {
        requestId: "long-cover",
        leaseGeneration: 1,
        prompt: "Tell me more",
        title: "Article",
        blocks: pageBlocks("Article", "Long cover", query),
        coverImageQuery: query,
        coverImageKind: "photo",
        coverImageUrl: url,
      }),
    ).not.toBeNull();
    expect((await conversations()).conversations).toEqual([
      expect.objectContaining({ key: "article", image: { query, kind: "photo" } }),
    ]);
  });

  it("reports a missing conversation instead of pretending to change it", async () => {
    setup();
    for (const action of ["pin", "archive"]) {
      expect((await act({ action, conversationKey: "missing" })).status).toBe(404);
    }
    expect(
      (await act({ action: "rename", conversationKey: "missing", title: "Name" })).status,
    ).toBe(404);
  });
});

describe("conversation list", () => {
  it("reaches every conversation, with old pins first, across cursors", async () => {
    const { t } = setup();
    await seed(t, 130);
    for (const key of ["c-2", "c-0", "c-1"]) {
      vi.setSystemTime(Date.now() + 1_000);
      expect((await act({ action: "pin", conversationKey: key })).status).toBe(200);
    }

    const first = await conversations("?limit=50");
    expect(first.pinned.map((item) => item.key)).toEqual(["c-1", "c-0", "c-2"]);
    const unpinned = [...first.conversations];
    let cursor = first.nextCursor;
    let pages = 1;
    while (cursor) {
      const next = await conversations(`?limit=50&cursor=${encodeURIComponent(cursor)}`);
      expect(next.pinned).toEqual([]);
      unpinned.push(...next.conversations);
      cursor = next.nextCursor;
      pages += 1;
    }

    expect(pages).toBe(3);
    const expected = Array.from({ length: 127 }, (_, i) => `c-${129 - i}`);
    expect(unpinned.map((item) => item.key)).toEqual(expected);
  });

  it("continues pins before unpinned conversations past one page of pins", async () => {
    const { t } = setup();
    await seed(t, 105, "pinned");
    await seed(t, 3, "plain");
    for (let i = 0; i < 105; i++) {
      vi.setSystemTime(Date.now() + 1_000);
      await act({ action: "pin", conversationKey: `pinned-${i}` });
    }

    const first = await conversations("?limit=2");
    expect(first.pinned).toHaveLength(100);
    expect(first.conversations).toEqual([]);
    const second = await conversations(`?limit=2&cursor=${encodeURIComponent(first.nextCursor!)}`);
    expect(second.pinned.map((item) => item.key)).toEqual([
      "pinned-4",
      "pinned-3",
      "pinned-2",
      "pinned-1",
      "pinned-0",
    ]);
    expect(second.conversations.map((item) => item.key)).toEqual(["plain-2", "plain-1"]);
    const third = await conversations(`?limit=2&cursor=${encodeURIComponent(second.nextCursor!)}`);
    expect(third).toMatchObject({ pinned: [], nextCursor: null });
    expect(third.conversations.map((item) => item.key)).toEqual(["plain-0"]);
  });

  it("rejects a cursor it did not issue", async () => {
    setup();
    for (const query of ["?cursor=elsewhere:abc", "?cursor=pinned:", "?limit=0", "?limit=101"]) {
      const response = await listConversations(
        new Request(`https://emblem.test/api/conversations${query}`),
      );
      expect(response.status).toBe(400);
    }
  });
});

describe("conversation history", () => {
  it("reaches every page of a long conversation, oldest first within each response", async () => {
    const { t } = setup();
    await t.run(async (ctx) => {
      for (let i = 0; i < 45; i++) {
        await insertPage(ctx, {
          userTokenIdentifier: owner,
          conversationKey: "long",
          pageKey: `page-${i}`,
          ...(i > 0 ? { previousPageKey: `page-${i - 1}` } : {}),
          requestedAt: 50_000 - (45 - i) * 10,
          prompt: `Turn ${i}`,
          blocks: "[]",
        });
      }
    });

    let restored: string[] = [];
    let cursor: string | null = null;
    let responses = 0;
    do {
      const query: string = cursor ? `&cursor=${encodeURIComponent(cursor)}` : "";
      const response = await readHistory(
        new Request(`https://emblem.test/api/history?conversationKey=long&limit=20${query}`),
      );
      const body = (await response.json()) as {
        pages: { pageKey: string }[];
        nextCursor: string | null;
      };
      restored = [...body.pages.map((page) => page.pageKey), ...restored];
      cursor = body.nextCursor;
      responses += 1;
    } while (cursor);

    expect(responses).toBe(3);
    expect(restored).toEqual(Array.from({ length: 45 }, (_, i) => `page-${i}`));
  });
});

describe("conversation delete", () => {
  it("deletes a conversation of large pages within transaction limits", async () => {
    const { t, alice } = setup({ transactionLimits: true });
    const blocks = JSON.stringify([
      blockSchema.parse({ type: "text", id: "large", style: "body", body: "x".repeat(150_000) }),
    ]);
    for (let batch = 0; batch < 6; batch++) {
      await t.run(async (ctx) => {
        for (let i = 0; i < 20; i++) {
          await insertPage(ctx, {
            userTokenIdentifier: owner,
            conversationKey: "large",
            pageKey: `page-${batch}-${i}`,
            requestedAt: batch * 100 + i,
            prompt: "Large page",
            blocks,
          });
        }
      });
    }

    expect(await act({ action: "delete", conversationKey: "large" })).toMatchObject({
      status: 200,
      body: { ok: true, action: "delete" },
    });
    expect(
      await alice.query(api.conversations.history, {
        conversationKey: "large",
        cursor: null,
        limit: 50,
      }),
    ).toEqual({ pages: [], nextCursor: null });
    expect((await conversations()).conversations).toEqual([]);
  });
});
