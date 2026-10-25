import { v } from "convex/values";

const inferenceTargetValidator = v.object({
  provider: v.union(
    v.literal("cerebras"),
    v.literal("groq"),
    v.literal("google"),
    v.literal("openrouter"),
    v.literal("openai"),
  ),
  modelId: v.string(),
  credentialSource: v.union(v.literal("platform"), v.literal("user")),
  supportsImages: v.optional(v.boolean()),
});

const inferenceCallValidator = v.object({
  role: v.union(v.literal("research"), v.literal("compose")),
  provider: v.string(),
  modelId: v.string(),
  finishReason: v.union(
    v.literal("stop"),
    v.literal("length"),
    v.literal("content-filter"),
    v.literal("tool-calls"),
    v.literal("error"),
    v.literal("other"),
  ),
  inputTokens: v.optional(v.number()),
  outputTokens: v.optional(v.number()),
  totalTokens: v.optional(v.number()),
  noCacheTokens: v.optional(v.number()),
  cacheReadTokens: v.optional(v.number()),
  cacheWriteTokens: v.optional(v.number()),
  reasoningTokens: v.optional(v.number()),
  responseTimeMs: v.optional(v.number()),
  timeToFirstOutputMs: v.optional(v.number()),
  outputTokensPerSecond: v.optional(v.number()),
});

export const inferenceSummaryValidator = v.object({
  requestId: v.string(),
  profile: v.object({
    research: inferenceTargetValidator,
    compose: inferenceTargetValidator,
  }),
  calls: v.array(inferenceCallValidator),
});
