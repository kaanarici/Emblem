import { logError } from "@/lib/log";
import type { ConvexHttpClient } from "convex/browser";
import type { FunctionReturnType } from "convex/server";
import { api } from "@/convex/_generated/api";
import type { Block } from "@/lib/schema";
import type { Action } from "@/lib/blockPrimitives";
import { authFailure, requestAuth } from "@/lib/auth";
import { jsonResponse, readJsonBody } from "@/lib/http";
import { z } from "zod";
import {
  generationPageSnapshot,
  generationTerminal,
  ndjsonLine,
  NDJSON_HEADERS,
} from "@/lib/generationProtocol";

export const maxDuration = 15;

const requestSchema = z.object({
  name: z.string().max(200).optional(),
  timezone: z.string().max(100).optional(),
  nextEventTitle: z.string().max(2_000).optional(),
  nextEventStart: z.union([z.string().max(40), z.number()]).optional(),
});

export async function POST(req: Request) {
  const auth = await requestAuth(req);
  const failure = authFailure(auth);
  if (failure) return failure;
  const raw = await readJsonBody(req);
  if (raw instanceof Response) return raw;
  const parsed = requestSchema.safeParse(raw);
  if (!parsed.success) return jsonResponse({ error: "invalid home request" }, 400);
  const name = parsed.data.name?.trim() || "";
  const timezone = parsed.data.timezone?.trim() || undefined;
  const nextEvent = homeEvent(parsed.data.nextEventTitle, parsed.data.nextEventStart);
  const convex = auth.authenticated ? auth.convex : null;
  let body: string;
  try {
    const blocks = [
      { type: "pageMeta", id: "meta", title: "Home" },
      greetingBlock(name, timezone, nextEvent),
      ...dailyUpdateBlocks(await homeDailyUpdate(convex), auth.authenticated),
      ...newIdeaBlocks(timezone),
    ];
    body =
      ndjsonLine(generationPageSnapshot(1, blocks)) +
      ndjsonLine(generationTerminal("completed", blocks.length, { revision: 1 }));
  } catch (error) {
    logError("home refresh failed", error);
    body = ndjsonLine(generationTerminal("failed", 1));
  }
  return new Response(body, { headers: NDJSON_HEADERS });
}

type HomeEvent = { title: string; start: Date };

function homeEvent(title?: string, start?: string | number): HomeEvent | null {
  const cleanTitle = title?.trim().replace(/\s+/g, " ");
  const timestamp = Number(start);
  const now = Date.now();
  if (!cleanTitle || cleanTitle.length > 160 || !Number.isFinite(timestamp)) return null;
  const startDate = new Date(timestamp * 1_000);
  if (startDate.getTime() <= now || startDate.getTime() > now + 36 * 60 * 60_000) return null;
  return { title: cleanTitle, start: startDate };
}

function greetingBlock(name: string, timezone?: string, nextEvent?: HomeEvent | null): Block {
  let hour = new Date().getHours();
  if (timezone) {
    try {
      hour = Number(
        new Intl.DateTimeFormat("en-US", {
          timeZone: timezone,
          hour: "numeric",
          hourCycle: "h23",
        }).format(new Date()),
      );
    } catch {}
  }
  const greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";
  const next = nextEvent ? nextEventLine(nextEvent, timezone) : "What can I look into for you?";
  return {
    type: "text",
    id: "greeting",
    body: `${name ? `${greeting}, **${name}**.` : `${greeting}.`}\n${next}`,
    style: "intro",
  } satisfies Block;
}

function nextEventLine(event: HomeEvent, timezone?: string): string {
  const options = timezone ? { timeZone: timezone } : {};
  const day = new Intl.DateTimeFormat("en-US", {
    ...options,
    weekday: "long",
  }).format(event.start);
  const time = new Intl.DateTimeFormat("en-US", {
    ...options,
    hour: "numeric",
    minute: "2-digit",
  }).format(event.start);
  const daysAway = localDayIndex(event.start, timezone) - localDayIndex(new Date(), timezone);
  const eventHour = Number(
    new Intl.DateTimeFormat("en-US", {
      ...options,
      hour: "numeric",
      hourCycle: "h23",
    }).format(event.start),
  );
  const when =
    daysAway === 0
      ? `${eventHour >= 17 ? "tonight" : "today"} at **${time}**`
      : daysAway === 1
        ? `tomorrow at **${time}**`
        : `${day} at **${time}**`;
  return `Your 📅 **${inlineMarkdown(event.title)}** is ${when}.`;
}

function inlineMarkdown(value: string): string {
  return value.replace(/([\\`*_{}[\]()<>#+\-.!|])/g, "\\$1");
}

const NEW_IDEA_SETS = [
  [
    {
      title: "Explain how a heat pump works",
      prompt:
        "Explain how a heat pump works, step by step, with what it costs to run compared with a furnace.",
      iconQuery: "heat pump",
      sym: "thermometer.medium",
    },
    {
      title: "Compare running shoes for flat feet",
      prompt:
        "Compare a few well-reviewed running shoes for flat feet by support, cushioning, fit and price.",
      iconQuery: "running shoe",
      sym: "shoe",
    },
    {
      title: "Plan a picnic for Saturday afternoon",
      prompt:
        "Plan a picnic for Saturday afternoon near me with a good spot, the weather, and what to pack.",
      iconQuery: "picnic basket",
      sym: "basket",
    },
    {
      title: "Cook a weeknight curry in 30 minutes",
      prompt:
        "Give me a weeknight curry I can cook in 30 minutes with exact ingredients and clear steps.",
      iconQuery: "curry bowl",
      sym: "fork.knife",
    },
    {
      title: "Find a quiet park for a long walk",
      prompt:
        "Find a few quiet parks near me for a long walk and show them on a map with what makes each one nice.",
      iconQuery: "park bench",
      sym: "tree",
    },
  ],
  [
    {
      title: "Learn the basics of film photography",
      prompt:
        "Teach me the basics of film photography: cameras, film stock, exposure, and a first roll to try.",
      iconQuery: "film camera",
      sym: "camera",
    },
    {
      title: "Pick a houseplant for a dim room",
      prompt:
        "Help me pick a houseplant that does well in low light and show how to care for each option.",
      iconQuery: "potted plant",
      sym: "leaf",
    },
    {
      title: "Map out a museum day in my city",
      prompt:
        "Map out a museum day in my city with the best order to visit, timing, and a lunch stop in between.",
      iconQuery: "museum building",
      sym: "building.columns",
    },
    {
      title: "Make a simple sourdough schedule",
      prompt:
        "Make a simple sourdough schedule that fits a workday, with each step and when to do it.",
      iconQuery: "bread loaf",
      sym: "fork.knife",
    },
    {
      title: "Compare e-readers for travel",
      prompt: "Compare the best e-readers for travel by weight, battery, screen and price.",
      iconQuery: "e-reader",
      sym: "book",
    },
  ],
  [
    {
      title: "See what's in tonight's night sky",
      prompt:
        "Show me what I can see in tonight's night sky from where I am, and the best time to look.",
      iconQuery: "telescope",
      sym: "moon.stars",
    },
    {
      title: "Plan a bike ride with a coffee stop",
      prompt:
        "Plan a relaxed bike ride near me with a good coffee stop halfway and the route on a map.",
      iconQuery: "bicycle",
      sym: "bicycle",
    },
    {
      title: "Learn one chess opening properly",
      prompt:
        "Teach me one beginner chess opening, the main ideas behind it, and the traps to avoid.",
      iconQuery: "chess knight",
      sym: "trophy",
    },
    {
      title: "Quiz me on world capitals",
      prompt: "Quiz me on world capitals, starting easy and getting harder as I go.",
      iconQuery: "globe",
      sym: "globe",
    },
    {
      title: "Make a Sunday reset checklist",
      prompt: "Make a calm Sunday reset checklist for the home and the week ahead.",
      iconQuery: "laundry basket",
      sym: "checklist",
    },
  ],
] as const;

function newIdeaBlocks(timezone?: string): Block[] {
  const ideas = NEW_IDEA_SETS[localDayIndex(new Date(), timezone) % NEW_IDEA_SETS.length]!;
  return [
    { type: "sectionHeader", id: "ideas-h", title: "Things to ask" } satisfies Block,
    {
      type: "cardCarousel",
      id: "ideas",
      cards: ideas.map((idea) => ({
        title: idea.title,
        prompt: idea.prompt,
        icon: {
          image: { query: idea.iconQuery, kind: "object" },
          sym: idea.sym,
        },
      })),
    } satisfies Block,
  ];
}

function localDayIndex(date: Date, timezone?: string): number {
  if (!timezone) return Math.floor(date.getTime() / 86_400_000);
  try {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      year: "numeric",
      month: "numeric",
      day: "numeric",
    }).formatToParts(date);
    const value = (type: Intl.DateTimeFormatPartTypes) =>
      Number(parts.find((part) => part.type === type)?.value);
    return Math.floor(Date.UTC(value("year"), value("month") - 1, value("day")) / 86_400_000);
  } catch {
    return Math.floor(date.getTime() / 86_400_000);
  }
}

type HomeDailyUpdate = FunctionReturnType<typeof api.automations.homeUpdate>;

async function homeDailyUpdate(convex: ConvexHttpClient | null): Promise<HomeDailyUpdate | null> {
  if (!convex) return null;
  try {
    return await convex.query(api.automations.homeUpdate, {});
  } catch (error) {
    logError("home daily update query failed", error);
    return null;
  }
}

const GET_BRIEF: Action = {
  label: "Get brief",
  prompt:
    "Prepare my daily brief now. Use today's calendar and relevant email when connected, synthesize what needs me, and make the answer visual and actionable.",
};

function dailyUpdateBlocks(update: HomeDailyUpdate | null, authenticated: boolean): Block[] {
  if (!authenticated) return [];
  let title: string;
  let subtitle: string;
  let action: Action | undefined;
  if (!update) {
    title = "Start with a daily brief";
    subtitle = "Your calendar and important email, on one page.";
    action = GET_BRIEF;
  } else if (!update.latestRun || update.latestRun.status !== "completed") {
    const running = update.latestRun?.status === "running";
    title = running ? "Your brief is on the way" : "Get a fresh daily brief";
    subtitle = running
      ? "Emblem is checking your calendar and email."
      : "Today’s schedule and important email, on one page.";
    action = running ? undefined : GET_BRIEF;
  } else {
    const copy = updateCopy(excerpt(update.latestRun.summary) ?? "The latest update is ready.");
    title = copy.title;
    subtitle = copy.detail ?? "Your latest daily brief is ready.";
    action = { label: "Open", openAutomation: update.id };
  }
  return [
    { type: "sectionHeader", id: "daily-update-h", title: "Today" } satisfies Block,
    {
      type: "mediaRowList",
      id: "daily-update",
      rows: [
        {
          icon: {
            image: { query: "morning newspaper", kind: "object" },
            sym: "sun.max.fill",
          },
          title,
          subtitle,
          ...(action ? { action } : {}),
        },
      ],
    } satisfies Block,
  ];
}

function updateCopy(summary: string): { title: string; detail?: string } {
  for (const delimiter of [";", ": ", ". "]) {
    const index = summary.indexOf(delimiter);
    if (index >= 20 && index <= 72) {
      const detail = summary.slice(index + delimiter.length).trim();
      return {
        title: summary.slice(0, index).trim(),
        detail: detail ? detail[0]!.toUpperCase() + detail.slice(1) : undefined,
      };
    }
  }
  if (summary.length <= 72) return { title: summary.replace(/[.;:]$/, "") };
  const prefix = summary.slice(0, 72);
  const boundary = prefix.lastIndexOf(" ");
  const cut = boundary > 40 ? boundary : 71;
  return {
    title: `${prefix.slice(0, cut).trimEnd()}…`,
    detail: summary.slice(cut).trim() || undefined,
  };
}

function excerpt(value: string | null | undefined): string | null {
  const text = value?.trim();
  if (!text) return null;
  return text.length <= 180 ? text : `${text.slice(0, 179).trimEnd()}…`;
}
