import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import { inferenceSummaryValidator } from "./inferenceTypes";

export const automationSourceValidator = v.union(
  v.literal("gmail"),
  v.literal("googlecalendar"),
  v.literal("weather"),
  v.literal("web"),
  v.literal("memory"),
);

const briefingTimeValidator = v.object({
  hour: v.number(),
  minute: v.number(),
});

export const briefingTimesValidator = v.object({
  morning: v.optional(briefingTimeValidator),
  afternoon: v.optional(briefingTimeValidator),
  evening: v.optional(briefingTimeValidator),
});

export const dailyUpdateTimesValidator = v.array(briefingTimeValidator);

const coverImageKind = v.union(v.literal("photo"), v.literal("poster"), v.literal("still"));
const coverImageAspect = v.union(
  v.literal("square"),
  v.literal("portrait"),
  v.literal("landscape"),
);

export const coverImageValidator = v.object({
  query: v.string(),
  kind: coverImageKind,
  aspect: v.optional(coverImageAspect),
});

export const pageFields = {
  conversationKey: v.string(),
  pageKey: v.string(),
  previousPageKey: v.optional(v.string()),
  parentPageKey: v.optional(v.string()),
  sourceCardKey: v.optional(v.string()),
  requestedAt: v.optional(v.number()),
  prompt: v.string(),
  title: v.optional(v.string()),
  blocks: v.string(),
  activities: v.optional(v.string()),
  sources: v.optional(v.string()),
  coverImageQuery: v.optional(v.string()),
  coverImageKind: v.optional(coverImageKind),
  coverImageAspect: v.optional(coverImageAspect),
  coverImageUrl: v.optional(v.string()),
  userTokenIdentifier: v.string(),
  archived: v.optional(v.boolean()),
};

export const automationFields = {
  userTokenIdentifier: v.string(),
  title: v.string(),
  prompt: v.string(),
  preset: v.optional(v.literal("daily_brief")),
  updateTimes: v.optional(dailyUpdateTimesValidator),
  briefingTimes: v.optional(briefingTimesValidator),
  hour: v.optional(v.number()),
  minute: v.optional(v.number()),
  weekdays: v.optional(v.array(v.number())),
  timezone: v.optional(v.string()),
  enabled: v.boolean(),
  nextRunAt: v.optional(v.number()),
  lastRunAt: v.optional(v.number()),
  conversationKey: v.optional(v.string()),
  sources: v.optional(v.array(automationSourceValidator)),
};

export const automationRunFields = {
  automationId: v.id("automations"),
  userTokenIdentifier: v.string(),
  status: v.union(
    v.literal("queued"),
    v.literal("running"),
    v.literal("completed"),
    v.literal("failed"),
    v.literal("cancelled"),
    v.literal("needs_attention"),
  ),
  title: v.optional(v.string()),
  blocks: v.optional(v.string()),
  summary: v.optional(v.string()),
  error: v.optional(v.string()),
  startedAt: v.number(),
  runningAt: v.optional(v.number()),
  finishedAt: v.optional(v.number()),
  trigger: v.optional(v.union(v.literal("manual"), v.literal("schedule"))),
  occurrenceKey: v.optional(v.string()),
  attempt: v.optional(v.number()),
  leaseGeneration: v.optional(v.number()),
  leaseExpiresAt: v.optional(v.number()),
  instruction: v.optional(v.string()),
  timezone: v.optional(v.string()),
  sources: v.optional(v.array(automationSourceValidator)),
  terminalBlockCount: v.optional(v.number()),
  inference: v.optional(inferenceSummaryValidator),
};

export default defineSchema({
  backgroundWakeup: defineTable({
    scheduledAt: v.optional(v.number()),
    scheduledId: v.optional(v.id("_scheduled_functions")),
  }),
  users: defineTable({
    tokenIdentifier: v.string(),
    name: v.optional(v.string()),
    email: v.optional(v.string()),
    imageUrl: v.optional(v.string()),
  }).index("by_tokenIdentifier", ["tokenIdentifier"]),

  pages: defineTable(pageFields)
    .index("by_userTokenIdentifier_and_conversationKey_and_requestedAt", [
      "userTokenIdentifier",
      "conversationKey",
      "requestedAt",
    ])
    .index("by_userTokenIdentifier_and_conversationKey_and_pageKey", [
      "userTokenIdentifier",
      "conversationKey",
      "pageKey",
    ]),

  rateLimitReservations: defineTable({
    nonce: v.string(),
    signature: v.string(),
    count: v.number(),
    expiresAt: v.number(),
  })
    .index("by_nonce", ["nonce"])
    .index("by_expiresAt", ["expiresAt"]),

  conversationSummaries: defineTable({
    userTokenIdentifier: v.string(),
    conversationKey: v.string(),
    pageId: v.id("pages"),
    title: v.string(),
    customTitle: v.optional(v.string()),
    updatedAt: v.number(),
    archived: v.boolean(),
    pinnedAt: v.optional(v.number()),
    preview: v.optional(v.string()),
    image: v.optional(coverImageValidator),
    imageURL: v.optional(v.string()),
  })
    .index("by_userTokenIdentifier_and_conversationKey", ["userTokenIdentifier", "conversationKey"])
    .index("by_userTokenIdentifier_and_archived_and_pinnedAt_and_updatedAt", [
      "userTokenIdentifier",
      "archived",
      "pinnedAt",
      "updatedAt",
    ])
    .index("by_userTokenIdentifier_and_archived_and_updatedAt", [
      "userTokenIdentifier",
      "archived",
      "updatedAt",
    ]),

  generationRuns: defineTable({
    userTokenIdentifier: v.string(),
    requestId: v.string(),
    fingerprint: v.string(),
    conversationKey: v.string(),
    previousPageKey: v.optional(v.string()),
    parentPageKey: v.optional(v.string()),
    sourceCardKey: v.optional(v.string()),
    status: v.union(
      v.literal("running"),
      v.literal("completed"),
      v.literal("failed"),
      v.literal("cancelled"),
    ),
    tombstoned: v.boolean(),
    leaseGeneration: v.number(),
    leaseExpiresAt: v.number(),
    failure: v.optional(v.string()),
    pageId: v.optional(v.id("pages")),
  })
    .index("by_userTokenIdentifier_and_requestId", ["userTokenIdentifier", "requestId"])
    .index("by_userTokenIdentifier_and_conversationKey_and_tombstoned", [
      "userTokenIdentifier",
      "conversationKey",
      "tombstoned",
    ])
    .index("by_status_and_tombstoned", ["status", "tombstoned"]),

  generationActions: defineTable({
    userTokenIdentifier: v.string(),
    requestId: v.string(),
    actionKey: v.string(),
    fingerprint: v.string(),
    result: v.string(),
  })
    .index("by_userTokenIdentifier_and_requestId_and_actionKey", [
      "userTokenIdentifier",
      "requestId",
      "actionKey",
    ])
    .index("by_userTokenIdentifier", ["userTokenIdentifier"]),

  automations: defineTable(automationFields)
    .index("by_userTokenIdentifier", ["userTokenIdentifier"])
    .index("by_enabled_and_nextRunAt", ["enabled", "nextRunAt"]),

  automationRuns: defineTable(automationRunFields)
    .index("by_automationId", ["automationId"])
    .index("by_automationId_and_occurrenceKey", ["automationId", "occurrenceKey"])
    .index("by_userTokenIdentifier", ["userTokenIdentifier"])
    .index("by_userTokenIdentifier_and_status", ["userTokenIdentifier", "status"])
    .index("by_status_and_startedAt", ["status", "startedAt"])
    .index("by_status_and_leaseExpiresAt", ["status", "leaseExpiresAt"]),

  automationDispatchBudgets: defineTable({
    ownerKey: v.string(),
    tokens: v.number(),
    updatedAt: v.number(),
  }).index("by_ownerKey", ["ownerKey"]),

  imageCache: defineTable({
    key: v.string(),
    url: v.string(),
    source: v.string(),
    createdAt: v.number(),
  })
    .index("by_key", ["key"])
    .index("by_createdAt", ["createdAt"]),

  generatedImages: defineTable({
    key: v.string(),
    ownerScopeHash: v.optional(v.string()),
    storageId: v.id("_storage"),
    mimeType: v.union(v.literal("image/png"), v.literal("image/jpeg"), v.literal("image/webp")),
    byteLength: v.number(),
    createdAt: v.number(),
  })
    .index("by_key", ["key"])
    .index("by_storageId", ["storageId"])
    .index("by_ownerScopeHash", ["ownerScopeHash"]),

  ownerErasures: defineTable({
    ownerScopeHash: v.string(),
  }).index("by_ownerScopeHash", ["ownerScopeHash"]),

  memories: defineTable({
    ownerKey: v.string(),
    text: v.string(),
    createdAt: v.number(),
  }).index("by_ownerKey", ["ownerKey"]),

  profiles: defineTable({
    ownerKey: v.string(),
    nickname: v.optional(v.string()),
    occupation: v.optional(v.string()),
    about: v.optional(v.string()),
    instructions: v.optional(v.string()),
    memoryEnabled: v.optional(v.boolean()),
    updatedAt: v.number(),
  }).index("by_ownerKey", ["ownerKey"]),
});
