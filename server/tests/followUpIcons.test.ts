import { describe, expect, it } from "vitest";
import { objectIconNoun } from "../lib/objectIconNoun";
import { finalizePagePlan, pageFinishSchema } from "../lib/responsePlan";

function followUpIcons(followUps: { iconQuery: string; iconIntent: string }[]) {
  const finish = pageFinishSchema.parse({
    type: "pageFinish",
    heading: "Where next",
    followUps: followUps.map((icon, index) => ({
      label: `Next ${index}`,
      prompt: `Do the next thing ${index}`,
      ...icon,
    })),
  });
  const { blocks } = finalizePagePlan(
    [{ type: "text", id: "intro", body: "Hello.", style: "intro" }],
    finish,
  );
  const row = blocks.find((block) => block.type === "chipRow");
  if (row?.type !== "chipRow") throw new Error("no follow-up row");
  return row.chips.map((chip) => chip.icon?.image?.query ?? null);
}

describe("follow-up icon nouns", () => {
  it("keeps distinct nouns the model chose", () => {
    expect(
      followUpIcons([
        { iconQuery: "Watering can", iconIntent: "explore" },
        { iconQuery: "leaf", iconIntent: "explore" },
        { iconQuery: "sun hat", iconIntent: "plan" },
      ]),
    ).toEqual(["Watering can", "leaf", "sun hat"]);
  });

  it("gives repeated and unusable nouns distinct stand-ins", () => {
    const queries = followUpIcons([
      { iconQuery: "map", iconIntent: "places" },
      { iconQuery: "Map", iconIntent: "places" },
      { iconQuery: "fork.knife", iconIntent: "places" },
    ]);
    expect(queries).toEqual(["map", "globe", null]);
    const nouns = queries.filter((query) => query !== null).map(objectIconNoun);
    expect(new Set(nouns).size).toBe(nouns.length);
  });
});
