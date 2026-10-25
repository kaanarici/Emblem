import { describe, expect, it } from "vitest";
import { compositionEnvelopeSchema } from "../lib/composerSchema";
import { makeCerebrasStrictCompatible } from "../lib/provider";
import { makeOpenAIStrictCompatible } from "../lib/strictSchema";
import { pageFinishSchema } from "../lib/responsePlan";

type JsonNode = Record<string, any>;

const CEREBRAS_NAME_LIMIT = 5_000;
const CEREBRAS_RESERVE = 250;
const OPENAI_NAME_LIMIT = 120_000;
const OPENAI_PROPERTY_LIMIT = 5_000;
const OPENAI_ENUM_VALUE_LIMIT = 1_000;
const OPENAI_NESTING_LIMIT = 10;

function at(root: JsonNode, ref: string): JsonNode {
  return ref
    .slice(2)
    .split("/")
    .reduce((value: JsonNode, key: string) => value[key], root);
}

function nameBudget(root: JsonNode): number {
  const count = (node: unknown, references: string[]): number => {
    if (Array.isArray(node)) return node.reduce((sum, item) => sum + count(item, references), 0);
    if (!node || typeof node !== "object") return 0;
    const value = node as JsonNode;
    let size = [value.properties, value.$defs].reduce<number>(
      (sum, names) =>
        sum + (names && typeof names === "object" ? Object.keys(names).join("").length : 0),
      0,
    );
    if (Array.isArray(value.enum)) {
      size += value.enum.filter((item): item is string => typeof item === "string").join("").length;
    }
    if (typeof value.const === "string") size += value.const.length;
    for (const [key, child] of Object.entries(value)) {
      if (key !== "$ref") {
        size += count(child, references);
        continue;
      }
      if (typeof child !== "string" || !child.startsWith("#/"))
        throw new Error("invalid schema ref");
      if (references.includes(child)) throw new Error("recursive schema ref");
      size += count(at(root, child), [...references, child]);
    }
    return size;
  };
  return count(root, []) + "elements".length;
}

function strictShape(root: JsonNode) {
  let properties = 0;
  let enumValues = 0;
  let maxDepth = 0;
  const violations: string[] = [];
  const visit = (raw: JsonNode, depth: number, refs: string[]) => {
    if (!raw || typeof raw !== "object") return;
    if (typeof raw.$ref === "string") {
      if (refs.includes(raw.$ref)) return;
      return visit(at(root, raw.$ref), depth, [...refs, raw.$ref]);
    }
    if (Array.isArray(raw.enum)) enumValues += raw.enum.length;
    if (raw.oneOf) violations.push("oneOf");
    if (raw.properties) {
      const names = Object.keys(raw.properties);
      properties += names.length;
      maxDepth = Math.max(maxDepth, depth + 1);
      if (raw.additionalProperties !== false) violations.push("additionalProperties");
      if ([...(raw.required ?? [])].sort().join() !== [...names].sort().join())
        violations.push(`required:${names.join(",")}`);
      for (const child of Object.values(raw.properties)) visit(child as JsonNode, depth + 1, refs);
    }
    if (raw.items) visit(raw.items, depth, refs);
    for (const branch of raw.anyOf ?? []) visit(branch, depth, refs);
  };
  visit(root, 0, []);
  return { properties, enumValues, maxDepth, violations };
}

async function compositionWire(): Promise<JsonNode> {
  return structuredClone(
    await (compositionEnvelopeSchema(pageFinishSchema) as { jsonSchema: PromiseLike<unknown> })
      .jsonSchema,
  ) as JsonNode;
}

describe("strict composition schema provider limits", () => {
  it("stays well inside the Cerebras name limit", async () => {
    const wire = await compositionWire();
    makeCerebrasStrictCompatible(wire);
    expect(nameBudget(wire)).toBeLessThanOrEqual(CEREBRAS_NAME_LIMIT - CEREBRAS_RESERVE);
  });

  it("stays inside OpenAI's strict limits", async () => {
    const root = {
      type: "object",
      properties: { elements: { type: "array", items: await compositionWire() } },
    };
    makeOpenAIStrictCompatible(root);
    const shape = strictShape(root);
    expect(shape.violations).toEqual([]);
    expect(shape.properties).toBeLessThanOrEqual(OPENAI_PROPERTY_LIMIT);
    expect(shape.enumValues).toBeLessThanOrEqual(OPENAI_ENUM_VALUE_LIMIT);
    expect(shape.maxDepth).toBeLessThanOrEqual(OPENAI_NESTING_LIMIT);
    expect(nameBudget(root)).toBeLessThanOrEqual(OPENAI_NAME_LIMIT);
  });
});
