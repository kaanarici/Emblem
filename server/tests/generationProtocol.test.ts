import { describe, expect, it } from "vitest";
import {
  ndjsonLine,
  generationPageSnapshot,
  isRenderablePage,
  pageCompositionIssues,
  parseGenerationNDJSON,
} from "../lib/generationProtocol";

const blocks = [
  { type: "pageMeta", id: "meta", title: "Tomorrow" },
  { type: "text", id: "intro", style: "intro", body: "You have two meetings." },
];
const inference = {
  requestId: "run-1",
  profile: {
    research: {
      provider: "cerebras" as const,
      modelId: "gpt-oss-120b",
      credentialSource: "platform" as const,
      supportsImages: false,
    },
    compose: {
      provider: "xai" as const,
      modelId: "grok-4.5",
      credentialSource: "platform" as const,
      supportsImages: true,
    },
  },
  calls: [],
};

describe("generation terminal protocol", () => {
  it("parses stored verified blocks alongside distinct model blocks", () => {
    const persisted = [
      { type: "pageMeta", id: "meta", title: "Inbox" },
      {
        type: "mediaRowList",
        id: "verified-gmail-messages",
        rows: [{ title: "Real email" }],
      },
      { type: "mediaRowList", id: "availability", rows: [{ title: "3:00 PM" }] },
    ];
    const body = [
      { type: "pageSnapshot", id: "page-snapshot", revision: 1, blocks: persisted },
      {
        type: "terminal",
        id: "terminal",
        status: "completed",
        blockCount: persisted.length,
        persisted: true,
        revision: 1,
      },
    ]
      .map((event) => JSON.stringify(event))
      .join("\n");

    expect(parseGenerationNDJSON(body)).toMatchObject({
      blocks: persisted,
      terminal: { blockCount: 3, persisted: true },
    });
  });

  it("rejects incoherent ordering and duplicate block ids", () => {
    expect(
      pageCompositionIssues([
        { type: "text", id: "same", body: "Answer", style: "body" },
        { type: "pageMeta", id: "same" },
        { type: "chipRow", id: "chips", chips: [] },
        { type: "text", id: "tail", body: "Late", style: "body" },
      ]),
    ).toEqual(
      expect.arrayContaining([
        "pageMeta must be first",
        "block ids must be unique",
        "chipRow must be last",
      ]),
    );
  });

  it("accepts one renderable page followed by completed terminal state", () => {
    const text = [
      JSON.stringify({ type: "status", id: "s-0", text: "Searching your calendar…" }),
      JSON.stringify({ type: "pageSnapshot", id: "page-snapshot", revision: 1, blocks }),
      JSON.stringify({
        type: "activity",
        id: "calendar-0",
        source: "googlecalendar",
        category: "personal",
        title: "Google Calendar",
        status: "succeeded",
        message: "Checked your calendar",
      }),
      JSON.stringify({
        type: "sources",
        id: "sources",
        items: [
          {
            id: "https://example.com/story",
            title: "A grounded result",
            url: "https://example.com/story",
            domain: "example.com",
          },
        ],
      }),
      JSON.stringify({
        type: "metric",
        id: "generation-timing",
        route: "model",
        stages: { total: 420 },
        percentiles: { total: { p50: 400, p90: 420, p95: 420 } },
        sampleSize: 2,
      }),
      JSON.stringify({ type: "inference", id: "inference", summary: inference }),
      JSON.stringify({
        type: "terminal",
        id: "terminal",
        status: "completed",
        blockCount: blocks.length,
        persisted: true,
        revision: 1,
      }),
    ].join("\n");

    expect(parseGenerationNDJSON(text)).toMatchObject({ blocks, inference });
  });

  it("replaces provisional content with the latest authoritative snapshot", () => {
    const provisional = [blocks[0], { ...blocks[1], body: "Draft answer." }];
    const authoritative = [
      blocks[0],
      blocks[1],
      { type: "text", id: "detail", style: "body", body: "Final detail." },
    ];
    const text = [
      JSON.stringify(generationPageSnapshot(1, provisional)),
      JSON.stringify(generationPageSnapshot(2, authoritative)),
      JSON.stringify({
        type: "terminal",
        id: "terminal",
        status: "completed",
        blockCount: authoritative.length,
        revision: 2,
        persisted: true,
      }),
    ].join("\n");

    expect(parseGenerationNDJSON(text)).toMatchObject({
      blocks: authoritative,
      terminal: { revision: 2, blockCount: authoritative.length },
    });
  });

  it.each([
    [
      "a stale snapshot revision",
      [
        JSON.stringify(generationPageSnapshot(2, blocks)),
        JSON.stringify(generationPageSnapshot(2, blocks)),
        JSON.stringify({
          type: "terminal",
          id: "terminal",
          status: "completed",
          blockCount: blocks.length,
          revision: 2,
        }),
      ].join("\n"),
    ],
    [
      "a mismatched terminal revision",
      [
        JSON.stringify(generationPageSnapshot(1, blocks)),
        JSON.stringify({
          type: "terminal",
          id: "terminal",
          status: "completed",
          blockCount: blocks.length,
          revision: 2,
        }),
      ].join("\n"),
    ],
    [
      "mixed snapshots and legacy blocks",
      [
        JSON.stringify(generationPageSnapshot(1, blocks)),
        JSON.stringify(blocks[1]),
        JSON.stringify({
          type: "terminal",
          id: "terminal",
          status: "completed",
          blockCount: blocks.length,
          revision: 1,
        }),
      ].join("\n"),
    ],
  ])("rejects %s", (_label, text) => {
    expect(() => parseGenerationNDJSON(text)).toThrow();
  });

  it.each([
    [
      "activity before content",
      [
        JSON.stringify({
          type: "activity",
          id: "a",
          source: "web",
          category: "web",
          title: "Web",
          status: "succeeded",
          message: "Used web",
        }),
        ...blocks.map((block) => JSON.stringify(block)),
        JSON.stringify({
          type: "terminal",
          id: "terminal",
          status: "completed",
          blockCount: blocks.length,
        }),
      ].join("\n"),
    ],
    [
      "sources before content",
      [
        JSON.stringify({ type: "sources", id: "sources", items: [] }),
        ...blocks.map((block) => JSON.stringify(block)),
        JSON.stringify({
          type: "terminal",
          id: "terminal",
          status: "completed",
          blockCount: blocks.length,
        }),
      ].join("\n"),
    ],
    [
      "block after trailer",
      [
        JSON.stringify(blocks[0]),
        JSON.stringify({ type: "sources", id: "sources", items: [] }),
        JSON.stringify(blocks[1]),
        JSON.stringify({
          type: "terminal",
          id: "terminal",
          status: "completed",
          blockCount: blocks.length,
        }),
      ].join("\n"),
    ],
    [
      "duplicate sources trailer",
      [
        ...blocks.map((block) => JSON.stringify(block)),
        JSON.stringify({ type: "sources", id: "sources", items: [] }),
        JSON.stringify({ type: "sources", id: "sources", items: [] }),
        JSON.stringify({
          type: "terminal",
          id: "terminal",
          status: "completed",
          blockCount: blocks.length,
        }),
      ].join("\n"),
    ],
    [
      "event after terminal",
      [
        ...blocks.map((block) => JSON.stringify(block)),
        JSON.stringify({
          type: "terminal",
          id: "terminal",
          status: "completed",
          blockCount: blocks.length,
        }),
        JSON.stringify({ type: "sources", id: "sources", items: [] }),
      ].join("\n"),
    ],
  ])("rejects %s", (_label, text) => {
    expect(() => parseGenerationNDJSON(text)).toThrow();
  });

  it.each([
    ["missing terminal", blocks.map((block) => JSON.stringify(block)).join("\n")],
    [
      "failed terminal",
      [
        ...blocks.map((block) => JSON.stringify(block)),
        JSON.stringify({
          type: "error",
          id: "generation-error",
          code: "provider_auth",
          message: "No model",
          retryable: false,
        }),
        JSON.stringify({
          type: "terminal",
          id: "terminal",
          status: "failed",
          blockCount: blocks.length,
        }),
      ].join("\n"),
    ],
    [
      "count mismatch",
      [
        ...blocks.map((block) => JSON.stringify(block)),
        JSON.stringify({ type: "terminal", id: "terminal", status: "completed", blockCount: 99 }),
      ].join("\n"),
    ],
  ])("rejects %s", (_label, text) => {
    expect(() => parseGenerationNDJSON(text)).toThrow();
  });

  it("requires metadata and actual content", () => {
    expect(isRenderablePage([])).toBe(false);
    expect(isRenderablePage([blocks[0]])).toBe(false);
    expect(isRenderablePage(blocks)).toBe(true);
  });
});

it("preserves Unicode separators inside model text without creating native line breaks", () => {
  const page = [blocks[0], { ...blocks[1], body: "First\u2028second\u2029third\u0085fourth" }];
  const wire = [
    { type: "pageSnapshot", id: "page-snapshot", revision: 1, blocks: page },
    { type: "terminal", id: "terminal", status: "completed", blockCount: 2, revision: 1 },
  ]
    .map(ndjsonLine)
    .join("");
  expect(wire).not.toMatch(/[\u0085\u2028\u2029]/);
  expect(wire.trim().split(/[\n\u0085\u2028\u2029]/)).toHaveLength(2);
  expect(parseGenerationNDJSON(wire).blocks).toEqual(page);
});

it("does not mistake navigation and section scaffolding for a useful answer", () => {
  expect(
    pageCompositionIssues([
      { type: "pageMeta", id: "meta" },
      { type: "sectionHeader", id: "section", title: "Places" },
      { type: "titleBlock", id: "title", title: "Suggestions" },
      { type: "chipRow", id: "next", chips: [{ label: "Try again", prompt: "Try again" }] },
    ]),
  ).toContain("page needs useful content");
});
