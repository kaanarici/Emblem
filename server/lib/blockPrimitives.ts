import { z } from "zod";

const imageAspect = z.enum(["square", "portrait", "landscape"]);
export type ImageAspect = z.infer<typeof imageAspect>;

export const httpURL = z
  .string()
  .trim()
  .url()
  .refine((value) => {
    const protocol = new URL(value).protocol;
    return protocol === "http:" || protocol === "https:";
  }, "URL must use HTTP or HTTPS");

export const hexColor = z
  .string()
  .regex(/^#[0-9A-Fa-f]{6}$/, "color must be a #RRGGBB hex value")
  .describe("optional visual accent as exact #RRGGBB; omit when color adds no meaning");

export const imageSpec = z
  .object({
    query: z
      .string()
      .describe('poster/still/photo: exact search terms. object: simple noun ("eggplant")'),
    kind: z
      .enum(["poster", "still", "logo", "photo", "object", "generated"])
      .describe(
        "object = private 3D icon library; generated = server-owned step illustration token",
      ),
    aspect: imageAspect
      .optional()
      .describe(
        "optional target crop: square | portrait | landscape only. Omit for object icons. wide/poster are hero.aspect frame values, never image.aspect.",
      ),
  })
  .describe("A real image, resolved by search");

export const icon = z
  .object({
    emoji: z.string().optional(),
    sym: z.string().optional(),
    image: imageSpec.optional(),
  })
  .describe(
    "One primary icon. Physical things use object image + sym fallback; abstract things use sym only. NEVER emit color; the client theme owns it.",
  );

export const areaSpot = z.object({
  label: z.string().trim().min(1).max(40).describe("area name: Queens, Downtown, JFK Airport"),
  sym: z.string().describe("SF Symbol: building.2, tram.fill, airplane, ferry, tree"),
  icon: z.string().describe("3D object icon query: skyscraper, bridge, airplane"),
  lat: z.number(),
  lng: z.number(),
  km: z.number().describe("approximate area radius in km"),
});
export type AreaSpot = z.infer<typeof areaSpot>;

const directionsTarget = z.object({
  name: z.string().trim().min(1).describe("canonical place or venue name"),
  locality: z.string().trim().min(1).describe("city or locality used to disambiguate the place"),
  query: z
    .string()
    .trim()
    .min(1)
    .describe("place name plus locality for MapKit search; do not substitute a street address"),
  mode: z.enum(["driving", "walking", "transit"]).describe("requested route mode"),
});

export const action = z
  .object({
    label: z.string().trim().min(1).max(24).describe("1-2 words"),
    sym: z.string().trim().min(1).optional(),
    url: httpURL.optional().describe("verified HTTP(S) destination opened externally"),
    prompt: z
      .string()
      .trim()
      .min(1)
      .optional()
      .describe("sent as next user turn, generates a new page"),
    conversation: z
      .string()
      .trim()
      .min(1)
      .optional()
      .describe("conversationKey to reopen (home Continue cards)"),
    openAutomation: z
      .string()
      .trim()
      .min(1)
      .optional()
      .describe("automation id to open (home Automations cards; server-issued only)"),
    native: z.enum(["directions"]).optional().describe("client-native action instead of a prompt"),
    automation: z
      .object({
        idempotencyKey: z
          .string()
          .trim()
          .min(1)
          .max(200)
          .optional()
          .describe("server-issued generation identity used to deduplicate creation"),
        title: z
          .string()
          .trim()
          .min(1)
          .describe("short automation name, e.g. 'Morning AI briefing'"),
        prompt: z
          .string()
          .trim()
          .min(1)
          .describe("the STANDALONE request to run on each occurrence"),
        hour: z.number().int().min(0).max(23).describe("local hour 0-23"),
        minute: z.number().int().min(0).max(59).describe("0-59"),
        weekdays: z
          .array(z.number().int().min(1).max(7))
          .max(7)
          .optional()
          .describe("1=Mon..7=Sun; omit for daily"),
      })
      .optional()
      .describe("schedules a recurring run when tapped; the ONLY way to do anything time-based"),
    calendar: z
      .object({
        idempotencyKey: z
          .string()
          .trim()
          .min(1)
          .max(200)
          .describe("server-issued identity used to deduplicate local execution"),
        title: z.string().trim().min(1).max(120),
        date: z
          .string()
          .regex(/^\d{4}-\d{2}-\d{2}$/)
          .describe("local yyyy-MM-dd date"),
        durationMinutes: z.number().int().min(5).max(1_440),
        timeAnswerKey: z
          .string()
          .trim()
          .min(1)
          .max(300)
          .describe("exact visible timeAsk question whose selected answer supplies the time"),
      })
      .optional()
      .describe("creates one calendar event only after the user taps the action"),
    destination: directionsTarget
      .optional()
      .describe("verified place identity for native directions"),
  })
  .superRefine((value, context) => {
    const destinationCount = [
      value.url,
      value.prompt,
      value.conversation,
      value.openAutomation,
      value.native,
      value.automation,
      value.calendar,
    ].filter((destination) => destination != null).length;
    if (destinationCount !== 1) {
      context.addIssue({
        code: "custom",
        message: "action must have exactly one executable destination",
      });
    }
    if ((value.native === "directions") !== (value.destination != null)) {
      context.addIssue({
        code: "custom",
        message: "destination is required only for native directions",
        path: ["destination"],
      });
    }
  })
  .describe(
    "Exactly one executable destination: url, prompt, conversation, openAutomation, native directions, automation, or calendar event",
  );

export type Action = z.infer<typeof action>;

export const weatherCondition = z.enum([
  "clear",
  "partly-cloudy",
  "cloudy",
  "fog",
  "drizzle",
  "rain",
  "snow",
  "thunderstorm",
  "wind",
]);
