import { describe, expect, it } from "vitest";
import { createPageAssembly } from "../lib/pageAssembly";
import { finalizePagePlan } from "../lib/responsePlan";
import type { Block } from "../lib/schema";

describe("drill-in cover", () => {
  const lead: Block = { type: "titleBlock", id: "lead", title: "Sushi Saito" };
  const cover: Block = {
    type: "hero",
    id: "cover",
    image: { query: "Sushi Saito counter Akasaka Tokyo", kind: "photo", aspect: "landscape" },
    aspect: "wide",
  };

  it("keeps the drill-in's own cover ahead of its lead", () => {
    const { blocks } = finalizePagePlan(
      [
        lead,
        cover,
        { type: "text", id: "body", body: "Eight seats.", style: "body" },
        { ...cover, id: "second" },
      ],
      null,
      { articleLead: true, articleTitle: "Sushi Saito" },
    );
    expect(blocks.map((block) => block.id)).toEqual(["article-meta", "cover", "lead", "body"]);
  });

  it("shows no cover on a calendar event", () => {
    const page = createPageAssembly({
      persist: {
        prompt: "Dentist",
        requestId: "r",
        timezone: "UTC",
        calendarEvent: { title: "Dentist", timeRange: "9 AM", dayLabel: "Monday" },
      },
      articleLead: true,
      messages: [],
      weatherPayloads: [],
      sources: new Map(),
      researchNotesText: "",
      verifiedActionURLs: new Set(),
      hotelCatalogs: new Map(),
      hotelSummaries: new Map(),
      places: new Map(),
      hotelGalleryTarget: null,
    }).projectPage([cover, lead]);
    expect(page.some((block) => block.type === "hero")).toBe(false);
  });
});
