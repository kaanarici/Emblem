import { objectIconNoun } from "./objectIconNoun";
import type { Block } from "./schema";

type QuestionItem = Extract<Block, { type: "questionList" }>["items"][number];
type QuestionIcon = NonNullable<QuestionItem["icon"]>;

const DURATION_UNIT = /^(day|night|week|month)s?$/i;
const PEOPLE_UNIT =
  /^(people|person|persons|traveler|travelers|traveller|travellers|guest|guests|adult|adults|kid|kids|child|children|passenger|passengers)$/i;

function iconFor(query: string, sym: string): QuestionIcon {
  return { sym, image: { query, kind: "object" } };
}

function defaultQuestionIcon(input: QuestionItem["input"] | undefined): QuestionIcon {
  switch (input?.kind) {
    case "place":
      return iconFor("map pin", "mappin.and.ellipse");
    case "area":
      return iconFor("map", "map");
    case "date":
    case "dateRange":
      return iconFor("calendar", "calendar");
    case "time":
      return iconFor("alarm clock", "alarm");
    case "count": {
      const unit = input.unit?.trim() ?? "";
      if (DURATION_UNIT.test(unit)) return iconFor("calendar", "calendar");
      if (PEOPLE_UNIT.test(unit)) return iconFor("group of people", "person.2");
      return iconFor("abacus", "slider.horizontal.3");
    }
    case "text":
      return iconFor("pencil", "pencil");
    default:
      return iconFor("clipboard", "checklist");
  }
}

function hasIcon(icon: QuestionItem["icon"]): boolean {
  return Boolean(icon?.image?.query.trim() || icon?.sym?.trim() || icon?.emoji?.trim());
}

const CHOICE_STAND_INS = ["compass", "star", "light bulb", "puzzle piece", "gift box"];
const SYMBOL_PARTS = new Set(["fill", "circle", "square", "badge", "slash", "stack", "2", "3"]);

function usableIconQuery(query = ""): string | null {
  const trimmed = query.trim();
  const candidates = [
    trimmed,
    trimmed.split(/\s+(?:with|and|of|on|in|for|&)\s+/i)[0] ?? "",
    trimmed
      .split(".")
      .filter((part) => !SYMBOL_PARTS.has(part))
      .join(" "),
  ];
  return candidates.find((candidate) => objectIconNoun(candidate)) ?? null;
}

export function choiceIcons(
  options: readonly string[],
  icons: readonly (string | undefined)[] | undefined,
): string[] | undefined {
  const usable = options.map((_, index) => usableIconQuery(icons?.[index]));
  if (!usable.some(Boolean)) return undefined;
  const nouns = new Set(usable.map((query) => query && objectIconNoun(query)));
  const standIns = CHOICE_STAND_INS.filter((query) => !nouns.has(query));
  return usable.map((query) => query ?? standIns.shift() ?? "star");
}

function withChoiceIcons(item: QuestionItem): QuestionItem {
  const input = item.input;
  if (input?.kind !== "choice" || !input.options?.length) return item;
  const icons = choiceIcons(input.options, input.icons);
  return icons ? { ...item, input: { ...input, icons } } : item;
}

export function withQuestionIcons(block: Block): Block {
  if (block.type !== "questionList") return block;
  return {
    ...block,
    items: block.items.map((item) =>
      withChoiceIcons(
        hasIcon(item.icon) ? item : { ...item, icon: defaultQuestionIcon(item.input) },
      ),
    ),
  };
}
