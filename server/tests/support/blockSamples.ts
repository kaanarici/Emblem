import { action } from "../../lib/blockPrimitives";
import { blockSchema } from "../../lib/schema";

type Def = {
  type: string;
  shape?: Record<string, Node>;
  innerType?: Node;
  element?: Node;
  items?: Node[];
  options?: Node[];
  values?: unknown[];
  entries?: Record<string, string>;
  checks?: { _zod: { def: Record<string, unknown> } }[];
};
type Node = { _zod: { def: Def } };

const ACTION_DESTINATIONS = [
  { prompt: "Plan the next step" },
  { url: "https://example.com/booking" },
  { conversation: "conversation-1" },
  { openAutomation: "automation-1" },
  {
    native: "directions",
    destination: {
      name: "Ferry Building",
      locality: "San Francisco",
      query: "Ferry Building San Francisco",
      mode: "walking",
    },
  },
  {
    automation: {
      idempotencyKey: "request-1:automation",
      title: "Morning brief",
      prompt: "Brief me on my day",
      hour: 8,
      minute: 30,
      weekdays: [1, 2, 3, 4, 5],
    },
  },
  {
    calendar: {
      idempotencyKey: "request-1:calendar",
      title: "Dinner",
      date: "2026-10-25",
      durationMinutes: 90,
      timeAnswerKey: "What time works?",
    },
  },
];

const PATTERNS: Record<string, string> = {
  "^#[0-9A-Fa-f]{6}$": "#3366CC",
  "^\\d{4}-\\d{2}-\\d{2}$": "2026-10-25",
};

type Choose = (path: string, count: number) => number;
type Sampling = { choose: Choose; arrayLength: number; next: () => number; used: Set<string> };

function checks(def: Def): Record<string, unknown>[] {
  return (def.checks ?? []).map((check) => check._zod.def);
}

function isAction(node: Node): boolean {
  return node === (action as unknown as Node);
}

function choicePoints(node: Node, path: string, points: Map<string, number>, seen: Set<Node>) {
  if (seen.has(node)) return;
  const inner = new Set(seen).add(node);
  if (isAction(node)) {
    points.set(path, ACTION_DESTINATIONS.length);
    return;
  }
  const def = node._zod.def;
  if (def.entries) points.set(path, Object.keys(def.entries).length);
  def.options?.forEach((option, index) => choicePoints(option, `${path}|${index}`, points, inner));
  if (def.options) points.set(path, def.options.length);
  for (const [name, child] of Object.entries(def.shape ?? {})) {
    choicePoints(child, `${path}.${name}`, points, inner);
  }
  for (const child of [def.innerType, def.element]) {
    if (child) choicePoints(child, path, points, inner);
  }
  def.items?.forEach((item, index) => choicePoints(item, `${path}.${index}`, points, inner));
}

function sample(node: Node, path: string, key: string, sampling: Sampling): unknown {
  const pick = (count: number) => {
    const index = sampling.choose(path, count) % count;
    sampling.used.add(`${path}=${index}`);
    return index;
  };
  if (isAction(node)) {
    return {
      label: "Open",
      sym: "arrow.up.right",
      ...ACTION_DESTINATIONS[pick(ACTION_DESTINATIONS.length)],
    };
  }
  const def = node._zod.def;
  switch (def.type) {
    case "object":
      return Object.fromEntries(
        Object.entries(def.shape!).map(([name, child]) => [
          name,
          sample(child, `${path}.${name}`, name, sampling),
        ]),
      );
    case "optional":
      return sample(def.innerType!, path, key, sampling);
    case "union": {
      const index = pick(def.options!.length);
      return sample(def.options![index], `${path}|${index}`, key, sampling);
    }
    case "literal":
      return def.values![0];
    case "enum": {
      const values = Object.values(def.entries!);
      return values[pick(values.length)];
    }
    case "boolean":
      return true;
    case "number": {
      let value = 2;
      for (const check of checks(def)) {
        if (check.check === "greater_than") value = Number(check.value) + (check.inclusive ? 0 : 1);
      }
      for (const check of checks(def)) {
        if (check.check === "less_than") value = Math.min(value, Number(check.value));
      }
      return value;
    }
    case "string": {
      let value = `${key}-${sampling.next()}`;
      for (const check of checks(def)) {
        if (check.format === "url") value = `https://example.com/${value}`;
        if (check.format === "regex") {
          const replacement = PATTERNS[(check.pattern as RegExp).source];
          if (!replacement) throw new Error(`no sample for pattern at ${path}`);
          value = replacement;
        }
        if (check.check === "max_length") value = value.slice(0, Number(check.maximum));
        if (check.check === "min_length") value = value.padEnd(Number(check.minimum), "x");
      }
      return value;
    }
    case "tuple":
      return def.items!.map((item, index) => sample(item, `${path}.${index}`, key, sampling));
    case "array": {
      let length = sampling.arrayLength;
      for (const check of checks(def)) {
        if (check.check === "length_equals") length = Number(check.length);
        if (check.check === "min_length") length = Math.max(length, Number(check.minimum));
        if (check.check === "max_length") length = Math.min(length, Number(check.maximum));
      }
      return Array.from({ length }, () => sample(def.element!, path, key, sampling));
    }
  }
  throw new Error(`no sample for ${def.type} at ${path}`);
}

export function sampleBlocks(): Record<string, unknown>[] {
  let counter = 0;
  return blockSchema.options.flatMap((option) => {
    const node = option as unknown as Node;
    const type = option.shape.type.value;
    const points = new Map<string, number>();
    choicePoints(node, type, points, new Set());
    const covered = new Set<string>();
    const blocks: Record<string, unknown>[] = [];
    const add = (choose: Choose) => {
      for (const arrayLength of [2, 1]) {
        const used = new Set<string>();
        const block = sample(node, type, "block", {
          choose,
          arrayLength,
          next: () => ++counter,
          used,
        });
        if (!blockSchema.safeParse(block).success) continue;
        if (blocks.length > 0 && [...used].every((choice) => covered.has(choice))) return;
        used.forEach((choice) => covered.add(choice));
        blocks.push(block as Record<string, unknown>);
        return;
      }
    };
    const widest = Math.max(1, ...points.values());
    for (let variant = 0; variant < widest; variant++) add(() => variant);
    for (const [path, count] of points) {
      for (let index = 0; index < count; index++) {
        if (!covered.has(`${path}=${index}`)) add((at) => (at === path ? index : 0));
      }
    }
    const missing = [...points].flatMap(([path, count]) =>
      Array.from({ length: count }, (_, index) => `${path}=${index}`).filter(
        (choice) => !covered.has(choice),
      ),
    );
    if (missing.length > 0) throw new Error(`no valid ${type} sample covers ${missing.join(", ")}`);
    return blocks;
  });
}
