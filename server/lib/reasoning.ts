import type { JSONValue } from "ai";
import { DEFAULT_MODELS, MANAGED_LUNA, type InferenceTarget } from "./provider";

export type ReasoningEffort = "none" | "medium";

type MessageLike = { role: string; content: unknown };

export function reasoningEffortFor(messages: readonly MessageLike[]): ReasoningEffort {
  const content = [...messages].reverse().find((message) => message.role === "user")?.content;
  const text = typeof content === "string" ? content : JSON.stringify(content ?? "");
  const strongTask =
    /\b(analy[sz]e|compare|debug|diagnose|investigate|research|strategy|architect|trade-?offs?|root cause)\b/i.test(
      text,
    );
  if (strongTask) return "medium";
  const signals = [
    text.length > 700,
    /\bstep by step\b/i.test(text),
    /```|\b(error|stack trace|schema|implementation|codebase)\b/i.test(text),
    (text.match(/\?/g)?.length ?? 0) > 1,
    /\b(first|then|after that|finally|constraints?|requirements?)\b/i.test(text),
  ].filter(Boolean).length;
  return signals >= 2 ? "medium" : "none";
}

type ReasoningCallOptions = {
  reasoning?: ReasoningEffort;
  providerOptions?: Record<string, Record<string, JSONValue>>;
};

export function reasoningOptions(
  provider: InferenceTarget["provider"],
  effort: ReasoningEffort,
  modelId?: string,
): ReasoningCallOptions {
  if (provider === "cerebras") {
    if (effort === "none" && modelId !== DEFAULT_MODELS.cerebras) return { reasoning: "none" };
    return {
      providerOptions: {
        cerebras: {
          reasoningEffort: effort,
          reasoning_format: "parsed",
        },
      },
    };
  }
  if (provider === "openai" || provider === "modelgo") return {};
  if (provider === "openrouter") {
    const resolved = modelId === MANAGED_LUNA ? "none" : effort;
    return { providerOptions: { openrouter: { reasoning: { effort: resolved } } } };
  }
  return { reasoning: effort };
}
