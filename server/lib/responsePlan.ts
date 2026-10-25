import { isUnsupportedFollowUpAction } from "@/lib/requestIntent";
import { z } from "zod";
import { isPlannedActionGrounded } from "./actionGrounding";
import { type Block } from "./schema";
import { httpURL, areaSpot, type Action, type AreaSpot } from "./blockPrimitives";
import { objectIconNoun } from "./objectIconNoun";
import { choiceIcons, withQuestionIcons } from "./questionIcons";
const MAX_REQUIRED_CHOICES = 5;
const MAX_FOLLOW_UPS = 3;
const MAX_CHOICE_LABEL_CHARS = 80;
const followUpIconIntent = z.enum([
  "explore",
  "compare",
  "details",
  "plan",
  "places",
  "sources",
  "schedule",
  "refine",
]);
type FollowUpIconIntent = z.infer<typeof followUpIconIntent>;
const followUpIcons: Record<FollowUpIconIntent, string> = {
  explore: "sparkles",
  compare: "arrow.left.arrow.right",
  details: "list.bullet.rectangle",
  plan: "checklist",
  places: "map.fill",
  sources: "doc.text.magnifyingglass",
  schedule: "calendar",
  refine: "slider.horizontal.3",
};
const followUpIconStandIns: Record<FollowUpIconIntent, readonly string[]> = {
  explore: ["compass", "telescope"],
  compare: ["balance scale", "measuring tape"],
  details: ["magnifying glass", "binoculars"],
  plan: ["clipboard", "hourglass"],
  places: ["map", "globe"],
  sources: ["open book", "magnifying glass"],
  schedule: ["calendar", "hourglass"],
  refine: ["toolbox", "wrench"],
};

function distinctFollowUpIconQueries(
  followUps: readonly { iconQuery: string; iconIntent: FollowUpIconIntent }[],
): (string | null)[] {
  const used = new Set<string>();
  const kept = followUps.map(({ iconQuery }) => {
    const noun = objectIconNoun(iconQuery);
    if (!noun || used.has(noun)) return null;
    used.add(noun);
    return iconQuery;
  });
  return followUps.map(({ iconIntent }, index) => {
    if (kept[index]) return kept[index];
    const standIn = followUpIconStandIns[iconIntent].find((query) => !used.has(query));
    if (standIn) used.add(standIn);
    return standIn ?? null;
  });
}

const concreteObjectIconQuery = z
  .string()
  .trim()
  .min(1)
  .max(48)
  .refine((query) => query.split(/\s+/).length <= 3, {
    message: "object icon query must be a concrete physical noun in 1-3 words",
  });
const plannedFollowUpSchema = z.object({
  label: z.string().trim().min(1).max(2_000),
  prompt: z
    .string()
    .trim()
    .min(1)
    .max(2_000)
    .describe(
      "The self-contained next USER request, including the subject: Explain MoMA admission discounts. Never an assistant offer such as Would you like or Are you interested.",
    ),
  iconQuery: concreteObjectIconQuery,
  iconIntent: followUpIconIntent,
});
const plannedActionSchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("none") }),
  z.object({
    kind: z.literal("prompt"),
    label: z.string().trim().min(1).max(24),
    prompt: z.string().trim().min(1).max(2_000),
  }),
  z.object({
    kind: z.literal("url"),
    label: z.string().trim().min(1).max(24),
    url: httpURL,
  }),
  z.object({
    kind: z.literal("directions"),
    label: z.string().trim().min(1).max(24),
    destination: z.object({
      name: z.string().trim().min(1),
      locality: z.string().trim().min(1),
      mode: z.enum(["driving", "walking", "transit"]),
    }),
  }),
  z.object({
    kind: z.literal("automation"),
    label: z.string().trim().min(1).max(24),
    title: z.string().trim().min(1).max(100),
    prompt: z.string().trim().min(1).max(2_000),
    hour: z.number().int().min(0).max(23),
    minute: z.number().int().min(0).max(59),
    weekdays: z.array(z.number().int().min(1).max(7)).max(7),
  }),
  z.object({
    kind: z.literal("calendar"),
    label: z.string().trim().min(1).max(24),
    title: z.string().trim().min(1).max(120),
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    durationMinutes: z.number().int().min(5).max(1_440),
    timeAnswerKey: z.string().trim().min(1).max(300),
  }),
]);
export type PlannedAction = z.infer<typeof plannedActionSchema>;
export type PlannedActionGrounding = {
  messages: ReadonlyArray<{ role: string; content: string }>;
  verifiedEvidence?: ReadonlyArray<string>;
};

function plannedActionToAction(planned: PlannedAction, idempotencyKey?: string): Action | null {
  switch (planned.kind) {
    case "none":
      return null;
    case "prompt":
      return { label: planned.label, prompt: planned.prompt };
    case "url":
      return { label: planned.label, url: planned.url };
    case "directions":
      return {
        label: planned.label,
        native: "directions",
        destination: {
          ...planned.destination,
          query: [planned.destination.name, planned.destination.locality]
            .filter(Boolean)
            .join(", "),
        },
      };
    case "automation":
      return {
        label: planned.label,
        automation: {
          ...(idempotencyKey ? { idempotencyKey } : {}),
          title: planned.title,
          prompt: planned.prompt,
          hour: planned.hour,
          minute: planned.minute,
          ...(planned.weekdays.length ? { weekdays: planned.weekdays } : {}),
        },
      };
    case "calendar":
      if (!idempotencyKey) return null;
      return {
        label: planned.label,
        calendar: {
          idempotencyKey,
          title: planned.title,
          date: planned.date,
          durationMinutes: planned.durationMinutes,
          timeAnswerKey: planned.timeAnswerKey,
        },
      };
  }
}

export function verifiedPlannedAction(
  planned: PlannedAction,
  verifiedURLs: ReadonlySet<string>,
  idempotencyKey?: string,
  grounding?: PlannedActionGrounding,
): Action | null {
  const action = plannedActionToAction(planned, idempotencyKey);
  if (action?.url && !verifiedURLs.has(action.url)) return null;
  if (!action || planned.kind === "none" || planned.kind === "url") return action;
  if (
    planned.kind === "prompt" &&
    planned.label === "Continue" &&
    planned.prompt === "Continue with my selections."
  )
    return action;
  if (!grounding || !isPlannedActionGrounded(planned, grounding, idempotencyKey)) {
    return null;
  }
  return action;
}

export const pageFinishSchema = z.object({
  type: z.literal("pageFinish"),
  heading: z
    .string()
    .trim()
    .min(1)
    .max(60)
    .describe(
      "2-6 plain words in Emblem's calm voice naming the three follow-ups, never 'Next steps', 'What's next?' or 'What would you like to explore?'",
    ),
  followUps: z.array(plannedFollowUpSchema).max(MAX_FOLLOW_UPS),
  requiredInput: z
    .object({
      question: z.string().trim().max(300),
      kind: z
        .enum(["choice", "date", "dateRange", "time", "count", "place", "area", "text"])
        .describe(
          "native input matching the decision type: date/dateRange open a calendar picker, time a clock wheel, count a stepper, place a place search, area a map lens for a search region or starting point, text a keyboard; choice renders the options",
        ),
      unit: z
        .string()
        .max(30)
        .optional()
        .describe('count only: singular noun for the number, e.g. "cookie", "person", "day"'),
      value: z
        .number()
        .optional()
        .describe("count only: the current number from the conversation, e.g. the recipe's yield"),
      min: z.number().optional().describe("count only: floor"),
      max: z.number().optional().describe("count only: ceiling"),
      step: z.number().optional().describe("count only: increment per tap, e.g. 1, 50 for money"),
      options: z
        .array(z.string().min(1).max(MAX_CHOICE_LABEL_CHARS))
        .max(MAX_REQUIRED_CHOICES)
        .describe(
          "choice: 2-5 complete context-specific choices; count: 3-4 suggested numbers as digits including value, e.g. 12, 18, 24, 36; empty for every other kind",
        ),
      icons: z
        .array(z.string().max(60))
        .max(MAX_REQUIRED_CHOICES)
        .describe(
          "choice only: one concrete 3D object icon query per option in the same order, so the options render as picture cards; empty for quick reply phrases (what to do with an attachment), which render as chips",
        )
        .optional(),
      areas: z
        .array(areaSpot)
        .max(6)
        .optional()
        .describe("area only: 3-6 suggested areas for the request's city or region"),
      action: z
        .string()
        .max(24)
        .optional()
        .describe(
          'count only: 1-2 word dock button that redoes the page with the number, e.g. "Rescale", "Update", "Plan it"',
        ),
    })
    .optional()
    .describe(
      "Only when the answer cannot proceed without one required user decision; the question is the complete visible message. NEVER flatten a date, time, or count decision into invented choice strings; use the matching kind so the native picker renders",
    ),
  primaryAction: plannedActionSchema.optional(),
});
export type PageFinish = z.infer<typeof pageFinishSchema>;

export function isPageFinish(value: Block | PageFinish): value is PageFinish {
  return value.type === "pageFinish";
}

export function verifyRowLinks(block: Block, verifiedURLs: ReadonlySet<string>): Block {
  if (block.type === "titleBlock") {
    if (!block.actions) return block;
    return {
      ...block,
      actions: block.actions.flatMap((action) =>
        action.url && action.label && verifiedURLs.has(action.url)
          ? [{ label: action.label, url: action.url }]
          : [],
      ),
    };
  }
  if (block.type !== "mediaRowList") return block;
  return {
    ...block,
    rows: block.rows.map((row) => {
      const url = row.action?.url;
      if (url && row.action?.label && verifiedURLs.has(url)) {
        return { ...row, action: { label: row.action.label, url } };
      }
      return { ...row, action: undefined };
    }),
  };
}

export function attachVerifiedTitleLink(
  blocks: Block[],
  primaryAction: Action | null,
  verifiedURLs: ReadonlySet<string>,
): Block[] {
  if (!primaryAction?.url || !verifiedURLs.has(primaryAction.url)) return blocks;
  const index = blocks.findIndex((block) => block.type === "titleBlock");
  if (index < 0) return blocks;
  const title = blocks[index];
  if (title.type === "titleBlock" && title.actions?.length) return blocks;
  const link = { label: primaryAction.label, url: primaryAction.url };
  return blocks.map((block, position) =>
    position === index && block.type === "titleBlock" ? { ...block, actions: [link] } : block,
  );
}

export function finalizePagePlan(
  blocks: Block[],
  finish: PageFinish | null,
  mode?: {
    articleLead?: boolean;
    requiredInputOnly?: boolean;
    articleTitle?: string;
    explanationIntent?: boolean;
  },
): {
  blocks: Block[];
  needsInput: boolean;
  hasEditableInputs?: boolean;
  inputAction?: Action;
} {
  const question = finish?.requiredInput?.question.trim().slice(0, 300) ?? "";
  const choices = new Map<string, string | undefined>();
  (finish?.requiredInput?.options ?? []).forEach((option, index) => {
    const label = option.trim().slice(0, MAX_CHOICE_LABEL_CHARS);
    if (label && !choices.has(label)) choices.set(label, finish?.requiredInput?.icons?.[index]);
  });
  const options = [...choices.keys()].slice(0, MAX_REQUIRED_CHOICES);
  const inputKind = finish?.requiredInput?.kind ?? "choice";
  const icons = choiceIcons(
    options,
    options.map((option) => choices.get(option)),
  );
  const needsInput = question.length > 0 && (inputKind !== "choice" || options.length >= 2);
  const areas = inputKind === "area" ? areaSpots(finish?.requiredInput?.areas) : [];

  let page: Block[] = blocks
    .filter((block) =>
      needsInput && mode?.requiredInputOnly
        ? block.type === "pageMeta" || block.type === "runStamp"
        : block.type !== "chipRow",
    )
    .map(withQuestionIcons);
  if (!mode?.explanationIntent) {
    page = page.filter((block) => block.type !== "diagram");
  }
  if (mode?.articleLead) {
    const modelMeta = page.find((block) => block.type === "pageMeta");
    const leadBlock = page.find((block) => block.type === "titleBlock");
    const cover = page.find((block) => block.type === "hero");
    page = page.filter(
      (block) =>
        block.type !== "pageMeta" &&
        block.type !== "hero" &&
        (block.type !== "titleBlock" || block === leadBlock) &&
        !(block.type === "text" && block.style === "intro"),
    );
    if (cover) page.unshift(cover);
    const articleTitle = mode.articleTitle?.trim();
    page.unshift(
      modelMeta
        ? { ...modelMeta, ...(articleTitle ? { title: articleTitle } : {}) }
        : {
            type: "pageMeta",
            id: uniqueBlockID("article-meta", page),
            ...(articleTitle ? { title: articleTitle } : {}),
          },
    );
  }

  if (needsInput) {
    page.push({
      type: "questionList",
      id: uniqueBlockID("required-question", page),
      items: [
        {
          question,
          answer: "Not set",
          input:
            inputKind === "choice"
              ? icons
                ? { kind: "choice", options, icons }
                : { kind: "choice", options, look: "chips" as const }
              : inputKind === "count" && finish?.requiredInput
                ? countInput(finish.requiredInput, options)
                : inputKind === "area" && areas.length > 0
                  ? { kind: inputKind, areas }
                  : { kind: inputKind },
        },
      ],
    });
    const label = finish?.requiredInput?.action?.trim();
    return {
      blocks: page,
      needsInput,
      ...(inputKind === "count" && label ? { inputAction: { label, prompt: label } } : {}),
    };
  }

  const hasEditableInputs = page.some(
    (block) => block.type === "questionList" && block.items.some((item) => item.input != null),
  );
  const followUps = hasEditableInputs
    ? []
    : (finish?.followUps ?? []).filter(
        ({ label, prompt }) => !isUnsupportedFollowUpAction(label, prompt),
      );
  if (followUps.length > 0) {
    const iconQueries = distinctFollowUpIconQueries(followUps);
    page.push({
      type: "chipRow",
      id: uniqueBlockID("planned-choices", page),
      role: "followUp",
      title: finish!.heading,
      chips: followUps.map(({ label, prompt, iconIntent }, index) => {
        const query = iconQueries[index];
        return {
          label,
          prompt,
          icon: {
            ...(query ? { image: { query, kind: "object" as const } } : {}),
            sym: followUpIcons[iconIntent],
          },
        };
      }),
    });
  }

  if (finish?.primaryAction?.kind === "directions" && !page.some(({ type }) => type === "route")) {
    finish.primaryAction = { kind: "none" };
  }
  return {
    blocks: page,
    needsInput,
    ...(hasEditableInputs ? { hasEditableInputs: true } : {}),
  };
}

function countInput(
  input: NonNullable<PageFinish["requiredInput"]>,
  options: readonly string[],
): {
  kind: "count";
  unit?: string;
  value?: number;
  min: number;
  max: number;
  step: number;
  options?: string[];
} {
  const finite = (value: number | undefined) =>
    value !== undefined && Number.isFinite(value) ? value : undefined;
  const suggestions = [
    ...new Set(
      options
        .map((option) => Number(option.replace(/[^\d.]/g, "")))
        .filter((value) => Number.isFinite(value) && value > 0),
    ),
  ].sort((a, b) => a - b);
  const step = Math.max(1, Math.round(finite(input.step) ?? 1));
  const value = finite(input.value) ?? suggestions[0];
  const min = Math.max(0, finite(input.min) ?? Math.min(step, value ?? step));
  const top = Math.max(value ?? 0, ...suggestions);
  const max = Math.max(min + step, finite(input.max) ?? (top > 0 ? top * 10 : 99));
  const clamp = (n: number) => Math.min(max, Math.max(min, n));
  const unit = input.unit?.trim();
  const picks = suggestions.filter((n) => n >= min && n <= max).map(String);
  return {
    kind: "count",
    ...(unit ? { unit } : {}),
    ...(value !== undefined ? { value: clamp(value) } : {}),
    min,
    max,
    step,
    ...(picks.length >= 2 ? { options: picks } : {}),
  };
}

function areaSpots(spots: readonly AreaSpot[] | undefined): AreaSpot[] {
  const seen = new Set<string>();
  return (spots ?? [])
    .flatMap((spot) => {
      const label = spot.label.trim();
      const key = label.toLowerCase();
      if (
        !label ||
        seen.has(key) ||
        !(Math.abs(spot.lat) <= 90 && Math.abs(spot.lng) <= 180) ||
        !Number.isFinite(spot.km)
      )
        return [];
      seen.add(key);
      return [
        {
          label,
          sym: spot.sym.trim() || "mappin",
          icon: spot.icon.trim(),
          lat: spot.lat,
          lng: spot.lng,
          km: Math.min(400, Math.max(0.5, spot.km)),
        },
      ];
    })
    .slice(0, 6);
}

function uniqueBlockID(base: string, blocks: readonly Block[]): string {
  const ids = new Set(blocks.map(({ id }) => id));
  if (!ids.has(base)) return base;
  let suffix = 2;
  while (ids.has(`${base}-${suffix}`)) suffix += 1;
  return `${base}-${suffix}`;
}
