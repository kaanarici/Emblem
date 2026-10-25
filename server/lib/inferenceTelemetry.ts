import type { FinishReason, LanguageModelCallEndEvent, LanguageModelCallStartEvent } from "ai";
import type {
  InferenceProfile,
  InferenceRole,
  InferenceTarget,
  ResolvedInferenceProfile,
} from "./provider";

type InferenceCall = {
  role: InferenceRole;
  provider: string;
  modelId: string;
  finishReason: FinishReason;
  inputTokens?: number;
  outputTokens?: number;
  totalTokens?: number;
  noCacheTokens?: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
  reasoningTokens?: number;
  responseTimeMs?: number;
  timeToFirstOutputMs?: number;
  outputTokensPerSecond?: number;
};
export type InferenceSummary = {
  requestId: string;
  profile: InferenceProfile;
  calls: InferenceCall[];
};
export type InferenceAudit = {
  type: "inference";
  id: "inference";
  summary: InferenceSummary;
};
export type InferenceSession = {
  profile: InferenceProfile;
  models: ResolvedInferenceProfile["models"];
  start: (role: InferenceRole, event: LanguageModelCallStartEvent) => void;
  record: (role: InferenceRole, event: LanguageModelCallEndEvent) => void;
  fail: (role: InferenceRole) => void;
  audit: () => InferenceAudit | null;
};

type InferenceContext = {
  requestId: string;
  kind: "guest" | "interactive" | "background";
  profile: InferenceProfile;
};

type PendingCall = {
  role: InferenceRole;
  provider: string;
  modelId: string;
  startedAt: number;
};

export function createInferenceSession(
  runtime: ResolvedInferenceProfile,
  context: {
    requestId: string;
    kind: InferenceContext["kind"];
  },
): InferenceSession {
  const calls: InferenceCall[] = [];
  const pending = new Map<string, PendingCall>();
  const telemetryContext: InferenceContext = {
    ...context,
    requestId: boundedText(context.requestId),
    profile: runtime.profile,
  };
  const append = (call: InferenceCall) => {
    if (calls.length < 12) calls.push(call);
  };
  const start = (role: InferenceRole, event: LanguageModelCallStartEvent) => {
    pending.set(event.callId, {
      role,
      provider: event.provider,
      modelId: event.modelId,
      startedAt: performance.now(),
    });
  };
  const record = (role: InferenceRole, event: LanguageModelCallEndEvent) => {
    pending.delete(event.callId);
    append(recordInferenceCall(telemetryContext, role, runtime.profile[role], event));
  };
  const fail = (role: InferenceRole) => {
    let failed: [string, PendingCall] | undefined;
    for (const entry of pending) {
      if (entry[1].role === role) failed = entry;
    }
    if (!failed) return;
    pending.delete(failed[0]);
    append(recordInferenceFailure(telemetryContext, runtime.profile[role], failed[1]));
  };
  return {
    profile: runtime.profile,
    models: runtime.models,
    start,
    record,
    fail,
    audit: () =>
      context.kind === "background"
        ? {
            type: "inference",
            id: "inference",
            summary: {
              requestId: telemetryContext.requestId,
              profile: runtime.profile,
              calls: [...calls],
            },
          }
        : null,
  };
}

function recordInferenceCall(
  context: InferenceContext,
  role: InferenceRole,
  target: InferenceTarget,
  event: LanguageModelCallEndEvent,
): InferenceCall {
  const call: InferenceCall = {
    role,
    provider: boundedText(event.provider),
    modelId: boundedText(event.modelId),
    finishReason: event.finishReason,
    inputTokens: boundedNumber(event.usage.inputTokens, 100_000_000),
    outputTokens: boundedNumber(event.usage.outputTokens, 100_000_000),
    totalTokens: boundedNumber(event.usage.totalTokens, 200_000_000),
    noCacheTokens: boundedNumber(event.usage.inputTokenDetails.noCacheTokens, 100_000_000),
    cacheReadTokens: boundedNumber(event.usage.inputTokenDetails.cacheReadTokens, 100_000_000),
    cacheWriteTokens: boundedNumber(event.usage.inputTokenDetails.cacheWriteTokens, 100_000_000),
    reasoningTokens: boundedNumber(event.usage.outputTokenDetails.reasoningTokens, 100_000_000),
    responseTimeMs: boundedNumber(event.performance.responseTimeMs, 600_000),
    timeToFirstOutputMs: boundedNumber(event.performance.timeToFirstOutputMs, 600_000),
    outputTokensPerSecond: boundedNumber(event.performance.outputTokensPerSecond, 1_000_000),
  };
  logInferenceCall(context, target, call);
  return call;
}

function recordInferenceFailure(
  context: InferenceContext,
  target: InferenceTarget,
  pending: PendingCall,
): InferenceCall {
  const call: InferenceCall = {
    role: pending.role,
    provider: boundedText(pending.provider),
    modelId: boundedText(pending.modelId),
    finishReason: "error",
    responseTimeMs: boundedNumber(performance.now() - pending.startedAt, 600_000),
  };
  logInferenceCall(context, target, call);
  return call;
}

function logInferenceCall(context: InferenceContext, target: InferenceTarget, call: InferenceCall) {
  console.info(
    `inference_call ${JSON.stringify({
      type: "inference_call",
      requestId: context.requestId,
      kind: context.kind,
      credentialSource: target.credentialSource,
      ...call,
    })}`,
  );
}

function boundedText(value: string): string {
  return value.trim().slice(0, 160) || "unknown";
}

function boundedNumber(value: number | undefined, max: number): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? Math.min(value, max)
    : undefined;
}
