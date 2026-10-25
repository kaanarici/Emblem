import { describe, expect, it } from "vitest";
import { objectIconNoun } from "../lib/objectIconNoun";
import { finalizePagePlan, pageFinishSchema } from "../lib/responsePlan";
import type { Block } from "../lib/schema";

function choiceInputs(blocks: Block[]) {
  return blocks.flatMap((block) =>
    block.type === "questionList"
      ? block.items.flatMap((item) => (item.input?.kind === "choice" ? [item.input] : []))
      : [],
  );
}

function requiredChoice(options: string[], icons?: string[]) {
  const finish = pageFinishSchema.parse({
    type: "pageFinish",
    heading: "Pick one",
    followUps: [],
    requiredInput: { question: "What kind of trip?", kind: "choice", options, icons },
  });
  return choiceInputs(finalizePagePlan([{ type: "pageMeta", id: "meta" }], finish).blocks)[0];
}

describe("choice card icons", () => {
  it("gives every card a drawable object when the model sent unusable or missing ones", () => {
    const input = requiredChoice(
      ["Coastal scenic drive", "Food & drink", "Small towns", "Long stretches (5+ hours)"],
      ["ocean waves", "plate with fork and knife", "", "car.fill"],
    );
    expect(input?.icons).toEqual(["ocean waves", "plate", "compass", "car"]);
    expect(input?.icons?.every((query) => objectIconNoun(query))).toBe(true);
  });

  it("keeps each icon with its option when duplicate options are merged", () => {
    const input = requiredChoice(
      ["Beach", "Beach", "Mountains"],
      ["umbrella", "towel", "pine tree"],
    );
    expect(input?.options).toEqual(["Beach", "Mountains"]);
    expect(input?.icons).toEqual(["umbrella", "pine tree"]);
  });

  it("leaves quick reply phrases as chips", () => {
    expect(requiredChoice(["Describe it", "Edit it"])).toEqual({
      kind: "choice",
      options: ["Describe it", "Edit it"],
      look: "chips",
    });
  });

  it("fills the gaps in a model-written question grid", () => {
    const { blocks } = finalizePagePlan(
      [
        {
          type: "questionList",
          id: "questions",
          items: [
            {
              question: "Scenery",
              answer: "",
              input: {
                kind: "choice",
                options: ["Coast", "Historic towns and culture", "Desert"],
                icons: ["ocean waves", "clock showing 5 hours"],
              },
            },
          ],
        },
      ],
      null,
    );
    expect(choiceInputs(blocks)[0]?.icons).toEqual(["ocean waves", "compass", "star"]);
  });
});
