import { writingDraftsSchema } from "./writing";
import { savedCategorySchema } from "./saveCategory";
import { z } from "zod";
import { httpURL, hexColor, imageSpec, icon, action, weatherCondition } from "./blockPrimitives";
import { areaSpot } from "./blockPrimitives";

const id = z.string().describe("unique kebab-case id");

export const centerpieceBlockTypes = [
  "writing",
  "quiz",
  "flashcards",
  "chart",
  "diagram",
  "whatIf",
  "text",
  "hero",
  "titleBlock",
  "cardCarousel",
  "featureList",
  "quote",
  "ratingRow",
  "mediaRowList",

  "spotList",
  "factList",
  "statRow",
  "itemGrid",
  "stepCarousel",
  "listBlock",
  "comparisonTable",
  "timeline",
  "sideBySide",
  "oneAgainstMany",
  "reviewSummary",
  "timeAsk",
  "eventCard",
  "questionList",
  "map",
  "route",
  "photoGrid",
  "music",
  "reminders",
  "contact",
  "homeControl",
] as const;
const block = <T extends string, S extends z.ZodRawShape>(type: T, shape: S, desc: string) =>
  z.object({ type: z.literal(type), id, ...shape }).describe(desc);

export const blockSchema = z.discriminatedUnion("type", [
  block(
    "writing",
    {
      title: z.string().optional().describe("short section heading, e.g. Post draft"),
      drafts: writingDraftsSchema.describe(
        "1-3 complete, genuinely different drafts; each has a stable id, a short tone label, optional SF Symbol sym, and the full copy-ready body",
      ),
    },
    "Editable writing carousel for messages, posts, emails, letters and other authored copy. The client supplies copy, share, full-screen editing and in-place tone rewrites. Use instead of text/cardCarousel for actual drafts.",
  ),
  block(
    "quiz",
    {
      title: z.string().optional(),
      questions: z
        .array(
          z
            .object({
              question: z.string(),
              options: z.array(z.string()).min(2).max(4).describe("2-4 plausible choices"),
              correctIndex: z.number().int().min(0).describe("0-based index of the right option"),
              why: z.string().optional().describe("one-line explanation, revealed after grading"),
            })
            .superRefine((question, context) => {
              if (question.correctIndex >= question.options.length) {
                context.addIssue({
                  code: "custom",
                  message: "correctIndex must reference an option",
                  path: ["correctIndex"],
                });
              }
            }),
        )
        .min(1),
    },
    "Interactive quiz (trivia, study, test-me). THE ONLY quiz mechanism; never assemble quizzes from questionList or choice inputs. Client grades on device; nothing is pre-selected or revealed.",
  ),
  block(
    "flashcards",
    {
      title: z.string().optional(),
      cards: z
        .array(
          z.object({
            front: z.string().describe("prompt side: a term or short question"),
            back: z.string().describe("answer side: one short paragraph max"),
          }),
        )
        .min(1)
        .describe("4-8 cards"),
    },
    "Tap-to-flip study deck, swiped horizontally. Memorize/drill intents only (vocab, terms, formulas): quiz TESTS, flashcards DRILL. Never fake a deck with cardCarousel.",
  ),
  block(
    "chart",
    {
      kind: z
        .enum(["bar", "line", "pie", "area"])
        .describe("bar = compare, line/area = trend over time, pie = parts of a whole"),
      title: z.string().optional().describe("short chart title"),
      unit: z.string().optional().describe('value unit ("$", "%", "°C", "km")'),
      colors: z
        .array(hexColor)
        .min(1)
        .max(8)
        .optional()
        .describe("optional series/slice palette in order; omit for the native neutral palette"),
      series: z
        .array(
          z.object({
            name: z.string().optional().describe("series name, required with 2+ series"),
            points: z
              .array(z.object({ label: z.string(), value: z.number() }))
              .min(1)
              .max(500),
          }),
        )
        .min(1)
        .max(8)
        .describe("series of labeled points; pie uses only the first series"),
    },
    "Native animated chart: THE block whenever numbers compare or trend (prices, stats, forecasts, budgets). Real numbers only, never invented.",
  ).superRefine((chart, context) => {
    chart.series.forEach((series, seriesIndex) => {
      const labels = new Set<string>();
      series.points.forEach((point, pointIndex) => {
        if (labels.has(point.label)) {
          context.addIssue({
            code: "custom",
            message: "chart labels must be unique within a series",
            path: ["series", seriesIndex, "points", pointIndex, "label"],
          });
        }
        labels.add(point.label);
      });
    });
    if (chart.kind !== "pie") return;
    if (chart.series.length !== 1) {
      context.addIssue({
        code: "custom",
        message: "pie charts require exactly one series",
        path: ["series"],
      });
    }
    const values = chart.series[0]?.points.map((point) => point.value) ?? [];
    if (values.some((value) => value < 0)) {
      context.addIssue({
        code: "custom",
        message: "pie chart values cannot be negative",
        path: ["series", 0, "points"],
      });
    }
    if (values.reduce((sum, value) => sum + value, 0) <= 0) {
      context.addIssue({
        code: "custom",
        message: "pie chart values must have a positive total",
        path: ["series", 0, "points"],
      });
    }
  }),
  block(
    "diagram",
    {
      title: z.string().optional(),
      nodes: z
        .array(
          z.object({
            id: z.string().describe("short unique key"),
            label: z.string().describe("2-3 words max"),
            icon: icon.optional(),
          }),
        )
        .min(2)
        .superRefine((nodes, context) => {
          const seen = new Set<string>();
          nodes.forEach((node, index) => {
            if (seen.has(node.id)) {
              context.addIssue({
                code: "custom",
                message: "diagram node ids must be unique",
                path: [index, "id"],
              });
            }
            seen.add(node.id);
          });
        })
        .describe(
          "4-6 total mobile-friendly concept/outcome nodes; merge overlapping ideas instead of making a wide row",
        ),
      edges: z.array(
        z.object({
          from: z.string().describe("node id"),
          to: z.string().describe("node id"),
          label: z.string().optional().describe("1-2 words on the arrow"),
        }),
      ),
    },
    "Mobile flow diagram from TOPOLOGY ONLY: compact 1-3 word node labels and 1-3 word edge labels, nodes + directed edges along one main chain (at most two edges that skip a step or loop back), NEVER coordinates; the client computes the layout. Use for 'how X works', processes, pipelines, system structure.",
  ),
  block(
    "whatIf",
    {
      title: z.string().optional(),
      variables: z
        .array(
          z.object({
            name: z.string().describe("identifier used in expressions; lowercase, no spaces"),
            label: z.string().describe("slider label"),
            min: z.number(),
            max: z.number(),
            default: z.number(),
            step: z.number().optional(),
            unit: z.string().optional().describe('"$", "%", "yr"'),
          }),
        )
        .min(1)
        .describe("1-4 sliders"),
      outputs: z
        .array(
          z.object({
            label: z.string(),
            expression: z
              .string()
              .describe(
                'arithmetic over the variable names using ONLY + - * / ^ ( ) sqrt(x) min(a,b) max(a,b) and number constants, e.g. "price * units * (1 - discount / 100)"',
              ),
            unit: z.string().optional(),
          }),
        )
        .min(1)
        .describe("1-3 computed results"),
    },
    "Interactive what-if: sliders drive outputs recomputed live on device. Use for tradeoffs, estimates, projections ('what if I save X a month').",
  ),
  block(
    "runStamp",
    {
      iso: z.string().describe("ISO-8601 run time; the client renders the date header"),
    },
    "Server-injected timestamp header on automation runs. NEVER emit this yourself.",
  ),
  block(
    "pageMeta",
    {
      title: z.string().optional(),
      ask: z
        .boolean()
        .optional()
        .describe("true only when this page will ask the user several questions in a questionList"),
      dockAction: action.optional().describe("single most useful action, shown in the dock"),
      savePresentation: z
        .object({ categoryKey: z.string(), categoryTitle: z.string() })
        .optional()
        .describe("server-owned saved category"),
    },
    "MUST be first block of every page",
  ),
  block(
    "text",
    {
      style: z.enum(["intro", "body", "footnote"]),
      body: z.string(),
      highlights: z
        .array(z.string().min(1).max(120))
        .max(6)
        .optional()
        .describe(
          "Optional yellow marker anchors: exact short spans of rendered text, excluding markdown delimiters. Each marks its first literal occurrence; missing anchors are ignored.",
        ),
    },
    "Concise prose bridge. Every complete page has exactly one 6-14 word answer-first intro for spoken playback; it is a thesis, not a summary paragraph. A body bridge is exactly one 12-24 word sentence and never repeats the centerpiece; footnote is minor provenance or constraint text.",
  ),
  block(
    "hero",
    {
      image: imageSpec,
      imageURL: httpURL.optional().describe("server-resolved hero artwork"),
      aspect: z.enum(["poster", "wide", "square"]),
    },
    "One visual identity anchor near the start of a single-subject page. Prefer wide for editorial overviews; use poster only when portrait artwork itself is useful.",
  ),
  block(
    "titleBlock",
    {
      title: z.string().max(80).describe("short subject title; ideally 3-10 words"),
      metaLine: z
        .string()
        .max(90)
        .optional()
        .describe('compact metadata, e.g. "8.1 IMDb · 3 seasons · Apple TV · TV-MA"'),
      summary: z.string().max(180).optional().describe("one sentence; about 25 words max"),
      tags: z
        .array(z.string().max(28).describe("1-3 words"))
        .min(2)
        .max(4)
        .optional()
        .describe("2-4 distinct short tags"),
      actions: z.array(action).max(2).optional().describe("0-2 real destinations (Watch, Trailer)"),
      icon: icon.optional().describe("server-attached object above a calendar event lead"),
    },
    "Centered title cluster under a hero",
  ),
  block(
    "sectionHeader",
    { title: z.string(), subtitle: z.string().optional() },
    "Only introduces a second standalone visual component family. Never precede one ordinary support block, mirror a plan section, or create heading-and-paragraph chains.",
  ),
  block(
    "cardCarousel",
    {
      layout: z
        .enum(["rail", "grid"])
        .optional()
        .describe(
          "grid = two-column browsing wall for 4+ peers the reader compares at a glance; omit for the horizontal rail",
        ),
      presentation: z
        .enum(["standard", "poster", "paged", "hotelRail", "hotelList", "roomGrid", "roomList"])
        .optional()
        .describe(
          "standard: artwork then title/caption; poster: large portrait, title/meta over dark bottom, caption below. paged: full-width centered card with footer tags and page dots; rail only. Server-only verified catalog presentations: hotelRail (rail fallback), hotelList (rail fallback), roomGrid (grid fallback), roomList (rail fallback). Presentation never establishes resource authority.",
        ),
      cards: z.array(
        z.object({
          image: imageSpec.optional(),
          imageURL: httpURL.optional().describe("server-resolved card artwork"),
          resourceID: z
            .string()
            .optional()
            .describe("server-issued stable catalog resource identity"),
          saveCategory: savedCategorySchema.optional(),
          icon: icon.optional(),
          title: z.string(),
          caption: z.string().optional().describe("editorial one-liner"),
          meta: z
            .string()
            .optional()
            .describe('compact facts line: "3 to 4 days \u00b7 Scenic stops"'),
          strap: z
            .string()
            .optional()
            .describe('bold verdict line: "Best first trip", only when the card earns one'),
          tag: z
            .string()
            .optional()
            .describe(
              'optional concise qualitative badge ON this card’s photo ("Oceanfront", "Easy base"); use when useful, including on all cards; omit when no useful label exists',
            ),
          tags: z
            .array(z.string().min(1).max(28))
            .max(4)
            .optional()
            .describe("Short footer labels; separate from artwork tag"),
          preview: z.string().optional().describe("prose preview for a coverless conversation"),
          prompt: z
            .string()
            .optional()
            .describe(
              "complete drill-down user turn for editorial cards; managed cards use conversation or automation",
            ),
          conversation: z.string().optional().describe("conversationKey to reopen (home Continue)"),
          automation: z
            .string()
            .optional()
            .describe("automation id to open (home Automations; server-issued only)"),
        }),
      ),
    },
    "Horizontal media cards for peer items that benefit from visual browsing. EDITORIAL cards carry substance: caption + meta line (and footnote when a card earns a verdict); a bare title under a photo wastes the card. Use optional tag for a useful qualitative photo label on any or all cards; use several titled carousels to structure a browsing page (start here / classic stops / hidden gems)",
  )
    .refine((value) => value.presentation !== "paged" || value.layout !== "grid", {
      message: "Paged presentation requires rail layout",
      path: ["layout"],
    })
    .refine(
      (value) =>
        value.presentation === "roomGrid"
          ? value.layout === "grid"
          : value.presentation === "hotelRail" ||
              value.presentation === "hotelList" ||
              value.presentation === "roomList"
            ? value.layout === "rail"
            : true,
      { message: "Catalog presentation requires its legacy fallback layout", path: ["layout"] },
    ),
  block(
    "featureList",
    {
      items: z.array(
        z.object({
          icon: icon.optional(),
          title: z.string().describe("bold hook"),
          caption: z.string().optional(),
        }),
      ),
    },
    "Supporting icon + bold title + caption rows. This is decorated prose, not the page's primary visual.",
  ),
  block(
    "quote",
    { text: z.string(), attribution: z.string().optional() },
    "One striking quote, serif",
  ),
  block(
    "ratingRow",
    { icon: icon.optional(), text: z.string() },
    'Compact rating line ("8.1 on IMDb")',
  ),
  block(
    "mediaRowList",
    {
      title: z.string().optional(),
      rows: z.array(
        z.object({
          icon: icon.optional(),
          title: z.string().describe("email: subject; otherwise row title, at most ~6 words"),
          subtitle: z
            .string()
            .optional()
            .describe(
              "email: sender + short snippet; otherwise ONE compact supporting phrase of at most ~10 words, since a row clips to two phone lines, so a sentence, list, or explanation here gets truncated and lost",
            ),
          site: z
            .string()
            .trim()
            .min(1)
            .max(253)
            .optional()
            .describe(
              'brand domain whose logo fronts the row ("youtube.com", "google.com/travel/flights"); only the real service the row opens, else omit',
            ),
          action: action.optional().describe("trailing button"),
        }),
      ),
    },
    "Full-width rows for a small set of individually useful items. A row is a POINTER, never a container: answer content (lists, reasons, explanations, comparisons) belongs in listBlock/featureList/text where it can wrap, NOT in row subtitles where the phone truncates it. Email links live in Sources; use rows for email only when the user explicitly asks to browse individual messages. Also useful for bookings and availability",
  ),
  block(
    "spotList",
    {
      spots: z
        .array(
          z.object({
            image: imageSpec,
            imageURL: httpURL.optional().describe("resolved by the server, never authored"),
            name: z.string(),
            caption: z
              .string()
              .optional()
              .describe("one editorial sentence on why it earns the visit"),
            rating: z.string().optional().describe('"4.7", only from evidence'),
            meta: z.string().optional().describe('compact facts: "$$ · Trattoria · Closes 11 PM"'),
          }),
        )
        .min(1)
        .max(6),
    },
    "Full-width editorial spots: one large photo per place with name, description, and rating. The heavyweight treatment for restaurants, venues, hotels, and destinations when each place deserves the whole row; carousels stay for quick side-by-side browsing.",
  ),
  block(
    "factList",
    {
      facts: z.array(
        z.object({
          icon: icon.optional(),
          label: z.string().describe('short field label ("Price", "Opens", "Status")'),
          value: z
            .string()
            .describe("short scalar, date, status, or brief phrase; NEVER a sentence or paragraph"),
        }),
      ),
    },
    "Compact label/value quick facts for a narrow phone; values stay short",
  ),
  block(
    "chipRow",
    {
      role: z.enum(["requiredChoice", "followUp"]).optional(),
      title: z
        .string()
        .max(60)
        .optional()
        .describe("one generated heading for a follow-up row; omit for required choices"),
      chips: z
        .array(
          z.object({
            label: z.string().describe("complete visible text of the next user turn"),
            prompt: z
              .string()
              .optional()
              .describe("next user turn sent when tapped; defaults to label"),
            icon: icon.optional(),
          }),
        )
        .max(4),
    },
    "2-4 required choices or exactly 3 optional follow-ups (last block); label is the exact next user turn",
  ),
  block(
    "statRow",
    {
      stats: z.array(
        z.object({
          value: z.string(),
          label: z.string(),
          delta: z.string().optional(),
          deltaDirection: z.enum(["up", "down"]).optional(),
        }),
      ),
    },
    "2-4 big numbers side by side",
  ),
  block(
    "itemGrid",
    {
      items: z
        .array(
          z.object({
            icon: icon.optional(),
            title: z.string(),
            caption: z.string().optional().describe('"4 medium", "To taste"'),
          }),
        )
        .describe("the complete compact physical set, not a single sample item"),
      columns: z.number().int().min(2).max(4).optional().describe("default 3; 2-4"),
    },
    "Grid of a compact physical set such as ingredients or packing items; pair recipe ingredients with stepCarousel rather than writing the method as prose",
  ),
  block(
    "stepCarousel",
    {
      continuity: z
        .string()
        .trim()
        .min(1)
        .max(160)
        .optional()
        .describe(
          "ALWAYS set for new carousels: one short description of recurring objects/materials that must stay visually identical across every step image",
        ),

      steps: z
        .array(
          z.object({
            title: z
              .string()
              .max(60)
              .describe(
                'plain 2-5 word imperative, never a slogan or cute name ("Mix the wet ingredients")',
              ),
            body: z
              .string()
              .max(160)
              .describe(
                "one direct 8-14 word instructional sentence; no motivation, theme, benefit framing, or poetic language",
              ),
            meta: z
              .string()
              .max(40)
              .optional()
              .describe(
                'objective compact detail only: duration, temperature, tool, or resulting state ("20 min · Tender"); omit otherwise',
              ),
            sym: z
              .string()
              .optional()
              .describe(
                'SF Symbol name for the progress-rail glyph ("oven", "timer"); ALWAYS set, never emoji',
              ),
            railLabel: z
              .string()
              .optional()
              .describe(
                'short rail caption above the glyph: a time ("8:30 AM", "Tonight") for schedules, else omit',
              ),
            imageScene: z
              .string()
              .trim()
              .min(1)
              .max(160)
              .optional()
              .describe(
                "ALWAYS set for new cards: the exact physical object, tool or hand, action, and resulting construction/cooking state visible at this step; never a symbol, theme, metaphor, mood, category, text, name, or personal data",
              ),
            image: imageSpec
              .optional()
              .describe(
                'real-world PHOTO for steps about places, sights, or things that exist (itineraries, tours): kind "photo" + searchable query. Illustration steps (recipes, how-to) keep imageScene instead',
              ),
            imageURL: httpURL.optional().describe("server-resolved step photo"),
            icon: icon.optional(),
          }),
        )
        .describe(
          "the complete useful sequence, normally 3-6 concise cards; never stop after the first operation",
        ),
    },
    "Numbered horizontal step cards with progress rail; the procedural spine for recipes, routines, AND multi-day plans. Recipes/how-tos get one consistent generated illustration per step (imageScene); itineraries and tours get a real PHOTO per step (image, kind photo); days of a trip make excellent photo steps with railLabel day names",
  ),
  block(
    "listBlock",
    {
      style: z.enum(["bullet", "check"]),
      items: z.array(z.object({ icon: icon.optional(), text: z.string() })),
    },
    "Simple vertical list",
  ),
  block(
    "comparisonTable",
    {
      rowHeader: z.string().optional().describe('label for the first column ("Feature", "Fruit")'),
      columns: z.array(z.string()).min(1).describe("column headings"),
      rows: z
        .array(
          z.object({
            label: z.string(),
            subtitle: z.string().optional().describe('short second line ("Japan", "2.1M fans")'),
            icon: icon
              .optional()
              .describe("flag/team/object row icon; emoji or object image, all rows or none"),
            values: z.array(
              z.object({
                value: z.string(),
                verdict: z
                  .enum(["good", "bad"])
                  .optional()
                  .describe("only when this value is a clear pro or con"),
                note: z
                  .string()
                  .optional()
                  .describe('short chip line ("Slightly less range"), NEVER a repeat of value'),
              }),
            ),
          }),
        )
        .min(1),
    },
    "Rare dense matrix of short values for 4+ peers and 4+ shared attributes, or when the user explicitly asks for a table. Prefer sideBySide or oneAgainstMany on a phone.",
  ).superRefine((table, context) => {
    table.rows.forEach((row, rowIndex) => {
      if (row.values.length !== table.columns.length) {
        context.addIssue({
          code: "custom",
          message: "each table row must have one value per column",
          path: ["rows", rowIndex, "values"],
        });
      }
    });
  }),
  block(
    "timeline",
    {
      items: z.array(
        z.object({
          time: z.string(),
          title: z.string(),
          caption: z.string().optional(),
          icon: icon.optional().describe("3D object marker; replaces the plain rail dot"),
        }),
      ),
    },
    "Chronological spine for itineraries, schedules, seasons, eras, milestones, or other ordered change. Give every item an object icon when the entries are concrete things or events, so the rail reads as markers rather than dots",
  ),
  block(
    "sideBySide",
    {
      sectionTitle: z.string().optional().describe('header for the expanded view ("Trip feel")'),
      sectionIcon: icon.optional().describe("3D object beside the expanded header"),
      entities: z
        .array(
          z.object({
            name: z.string(),
            price: z.string().optional().describe('"$$$" tier or short price'),
            image: imageSpec
              .optional()
              .describe("landscape photo using the exact canonical entity name as query"),
            imageURL: httpURL.optional().describe("server-resolved entity artwork"),
            icon: icon.optional().describe("used when no image (object)"),
          }),
        )
        .length(2)
        .describe("EXACTLY 2 entities"),
      rows: z
        .array(
          z.object({
            label: z.string().describe("axis name, e.g. Pace, Cost, Transit"),
            values: z
              .array(
                z.object({
                  text: z.string().describe('one-line value ("Fast and dense")'),
                  verdict: z
                    .enum(["good", "bad"])
                    .optional()
                    .describe(
                      "green/red chip, only when this value is a clear pro or con; leave neutral facts unmarked",
                    ),
                  note: z
                    .string()
                    .optional()
                    .describe(
                      'chip takeaway ("Best network"), required with verdict, NEVER a repeat of text',
                    ),
                }),
              )
              .length(2)
              .describe("one value per entity, SAME order as entities"),
          }),
        )
        .min(1),
    },
    "Two peers across shared decision axes (exactly 2). Verdict adds a green edge chip",
  ),
  block(
    "oneAgainstMany",
    {
      sectionTitle: z.string().optional().describe("header for the expanded view"),
      sectionIcon: icon.optional(),
      anchor: z
        .object({
          name: z.string(),
          price: z.string().optional(),
          image: imageSpec
            .optional()
            .describe("landscape photo using the exact canonical entity name as query"),
          imageURL: httpURL.optional(),
          icon: icon.optional(),
          values: z
            .array(
              z.object({
                text: z.string(),
                verdict: z.enum(["good", "bad"]).optional().describe("only for a clear pro or con"),
                note: z.string().optional().describe("chip takeaway, NEVER a repeat of text"),
              }),
            )
            .describe("anchor's value per row, SAME order/length as rows"),
        })
        .describe("the fixed reference option"),
      rowLabels: z
        .array(z.string())
        .min(1)
        .describe("axis names shared by anchor + every challenger"),
      challengers: z
        .array(
          z.object({
            name: z.string(),
            price: z.string().optional(),
            image: imageSpec
              .optional()
              .describe("landscape photo using the exact canonical entity name as query"),
            imageURL: httpURL.optional(),
            icon: icon.optional(),
            values: z
              .array(
                z.object({
                  text: z.string(),
                  verdict: z
                    .enum(["good", "bad"])
                    .optional()
                    .describe("only for a clear pro or con"),
                  note: z.string().optional().describe("chip takeaway, NEVER a repeat of text"),
                }),
              )
              .describe("this challenger's value per row, SAME order/length as rowLabels"),
          }),
        )
        .min(2)
        .max(5)
        .describe("2-5 alternatives; a chip row swaps which one shows against the anchor"),
    },
    "One anchor vs many challengers; swap chips switch the visible challenger. Use for 3+ contenders",
  ).superRefine((comparison, context) => {
    const expected = comparison.rowLabels.length;
    if (comparison.anchor.values.length !== expected) {
      context.addIssue({
        code: "custom",
        message: "anchor values must match rowLabels",
        path: ["anchor", "values"],
      });
    }
    comparison.challengers.forEach((challenger, index) => {
      if (challenger.values.length !== expected) {
        context.addIssue({
          code: "custom",
          message: "challenger values must match rowLabels",
          path: ["challengers", index, "values"],
        });
      }
    });
  }),
  block(
    "reviewSummary",
    {
      intro: z.string().optional().describe("one line framing the reviews"),
      sources: z
        .array(z.object({ icon: icon.optional(), score: z.string(), source: z.string() }))
        .optional()
        .describe('aggregate ratings ("4.6" / "Google")'),
      themes: z.array(
        z.object({
          icon: icon.optional().describe("3D object for the theme (plate, storefront)"),
          title: z.string().describe('"About the food"'),
          summary: z.string().describe("what people consistently say"),
          quote: z.string().optional().describe("one standout serif pull-quote"),
          attribution: z.string().optional().describe('"Mina on Google"'),
        }),
      ),
    },
    "Grouped review themes with a standout quote each; aggregate ratings on top. Use for product/venue reviews",
  ),
  block(
    "timeAsk",
    {
      icon: icon.optional().describe("3D object for the ask (clock…)"),
      question: z.string().describe('"When should swimming start?"'),
      defaultTime: z.string().optional().describe('"18:00" 24h'),
      suggestions: z
        .array(z.object({ label: z.string(), time: z.string().describe('"HH:mm" 24h') }))
        .optional()
        .describe('4-5 chips ("Early morning" 07:00, "Noon" 12:00…)'),
    },
    "Inline CLOCK-TIME wheel with suggestion chips, only for a single time of day, never a date or date range. Pair with dockAction; the chosen time arrives in the user's answers",
  ),
  block(
    "eventCard",
    {
      dayLabel: z.string().describe('"Tomorrow, July 9th"'),
      events: z.array(
        z.object({
          timeRange: z.string().describe('"10 – 11am"'),
          title: z.string(),
          place: z.string().optional().describe("verified location, as written"),
          icon: icon.optional(),
          prompt: z.string().optional().describe("drill-down on tap"),
        }),
      ),
    },
    "Calendar event card: day header + event rows. Use to confirm created events or show a day's schedule",
  ),
  block(
    "questionList",
    {
      items: z.array(
        z.object({
          icon: icon.optional(),
          question: z.string(),
          answer: z
            .string()
            .describe(
              "Always an empty string. The row stays unanswered until the user picks; never guess or prefill.",
            ),
          input: z
            .object({
              kind: z
                .enum(["choice", "date", "dateRange", "count", "place", "area", "text", "time"])
                .describe("picker opened on tap; area = map lens for a search region or start"),
              options: z
                .array(z.string())
                .optional()
                .describe("choice options; count suggested numbers"),
              min: z.number().optional().describe("count floor"),
              max: z.number().optional().describe("count ceiling"),
              unit: z.string().optional().describe('count noun, e.g. "traveler"'),
              step: z.number().optional().describe("count increment"),
              value: z.number().optional().describe("count starting number"),
              ask: z.string().optional().describe("full sheet question for a short row label"),
              icons: z
                .array(z.string())
                .optional()
                .describe("choice only: one 3D object icon query per option, same order"),
              areas: z.array(areaSpot).optional().describe("area only: 3-6 suggested areas"),
              look: z.enum(["chips"]).optional(),
            })
            .describe("tapping opens this visible picker; required for every generated row"),
        }),
      ),
    },
    "Input-gathering cards before a multi-step task. Date and dateRange MUST use their calendar picker kinds. Always paired with dockAction Continue",
  ),
  block(
    "map",
    {
      title: z.string().optional(),
      style: z
        .enum(["standard", "satellite", "hybrid"])
        .optional()
        .describe(
          "satellite for layouts/aerial views ('show me the airport layout', terrain); hybrid = satellite + labels; default standard",
        ),
      thin: z
        .boolean()
        .optional()
        .describe(
          "true = short full-width map strip with dot pins, for orientation above place cards that already describe each place; default false = square map with labeled icon pins",
        ),
      places: z
        .array(
          z.object({
            ref: z.string().optional().describe("verified place ref or hotelId from research"),
            name: z.string().trim().min(1).describe("canonical place or venue name"),
            locality: z.string().trim().min(1).describe("city or locality"),
            searchQuery: z
              .string()
              .trim()
              .min(1)
              .describe('canonical name plus locality ("Miyake, Portland, Maine")'),
            lat: z.number().min(-90).max(90).optional(),
            lng: z.number().min(-180).max(180).optional(),
            address: z.string().optional(),
            icon: icon.optional(),
            rating: z.string().optional(),
            caption: z.string().optional(),
            price: z.string().optional(),
          }),
        )
        .min(1)
        .max(12),
    },
    "Expandable Apple Maps page with one or more resolved place entities. Every place MUST be a real venue named in this request's research evidence (never from prior knowledge), citing its verified ref when research lists one, with searchQuery as its exact canonical business name plus locality. If the user reports a wrong or misplaced pin, do NOT repeat the same searchQuery: reformulate with street or neighborhood, or replace the place",
  ),
  block(
    "route",
    {
      destination: z.object({
        name: z.string().trim().min(1).describe("canonical place or venue name"),
        locality: z.string().trim().min(1).describe("city or locality"),
        searchQuery: z
          .string()
          .trim()
          .min(1)
          .describe('canonical name plus locality ("San Jose City Hall, San Jose, California")'),
      }),
      mode: z.enum(["driving", "walking", "transit"]).optional().describe("default driving"),
    },
    "On-device route from the user's CURRENT location to one destination. NO origin; the client computes the real route, time, and distance. Use for directions/how-far/how-to-get-there requests.",
  ),
  block(
    "weather",
    {
      location: z.string(),
      focusDay: z.string().optional().describe("forecast date selected initially (yyyy-mm-dd)"),
      current: z.object({
        observedAt: z.string(),
        tempC: z.number(),
        feels: z.number(),
        condition: weatherCondition,
        high: z.number(),
        low: z.number(),
        humid: z.number(),
        windKph: z.number(),
        precipitationMm: z.number(),
        precipPct: z.number(),
        isDay: z.boolean(),
      }),
      forecast: z.array(
        z.object({
          date: z.string(),
          day: z.string(),
          condition: weatherCondition,
          high: z.number(),
          low: z.number(),
          precipPct: z.number(),
          windKph: z.number(),
          uvIndex: z.number(),
          sunrise: z.string(),
          sunset: z.string(),
          hours: z
            .array(
              z.tuple([
                z.number().int().min(0).max(23),
                z.number(),
                weatherCondition,
                z.number(),
                z.boolean(),
              ]),
            )
            .describe("local hours of this date as [hour, tempC, condition, precipPct, isDay]"),
        }),
      ),
    },
    "Native weather for one place: now with the next 24 hours, and the week, where tapping a day shows its hours. Filled by the server from getWeather; the model never writes it.",
  ),
  block(
    "photoGrid",
    {
      images: z.array(imageSpec),
      presentation: z
        .enum(["direct", "collection"])
        .optional()
        .describe(
          "Server-only gallery presentation; collection requires a trusted catalog projection and never establishes resource authority.",
        ),
    },
    "Horizontal gallery of 3-5 real photos showing different views of one visual subject, under a titled section such as A closer look.",
  ),
  block(
    "music",
    {
      title: z.string().optional(),
      tracks: z
        .array(
          z.object({
            name: z.string().describe("exact released song title"),
            artist: z.string(),
            album: z.string().optional().describe("server-resolved"),
            art: httpURL.optional().describe("server-resolved"),
            preview: httpURL.optional().describe("server-resolved"),
            url: httpURL.optional().describe("server-resolved"),
          }),
        )
        .min(1)
        .max(6),
    },
    "Songs as artwork rows with a preview play button and Open in Music or Spotify. Name real released songs; the server resolves album, artwork, preview and links from Apple's public catalog and drops songs it cannot find.",
  ),
  block(
    "reminders",
    {
      scope: z.enum(["today", "upcoming", "all"]),
      list: z.string().max(60).optional().describe("Reminders list, only when the user named one"),
      add: z
        .array(z.string().trim().min(1).max(120))
        .max(5)
        .optional()
        .describe("new reminders the user asked for; saved only when they tap Add"),
    },
    "The user's Apple Reminders, read on the iPhone and checked off there. You never see them: never state their count or contents.",
  ),
  block(
    "contact",
    {
      name: z.string().trim().min(1).max(80).describe("the person as the user named them"),
      draft: z
        .string()
        .max(400)
        .optional()
        .describe("message text when the user asked to text them"),
    },
    "One person from the user's Contacts, looked up on the iPhone, with call, message and email buttons. You never see numbers or addresses: never write them.",
  ),
  block(
    "homeControl",
    {
      q: z
        .string()
        .max(80)
        .optional()
        .describe('room or accessory words ("bedroom lights"); omit for the whole home'),
    },
    "The user's Apple Home accessories and scenes, read on the iPhone with toggles the user taps. You never see their states and never change them yourself.",
  ),
]);

export type Block = z.infer<typeof blockSchema>;
