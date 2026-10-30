import { afterEach, describe, expect, it, vi } from "vitest";
import { generateText, Output, stepCountIs, streamText, tool } from "ai";
import { z } from "zod";
import { convexTest } from "convex-test";
import { internal } from "../convex/_generated/api";
import schema from "../convex/schema";
import {
  platformCredentialEnv,
  resolveInferenceProfile,
  usesOpenAIStrictSchema,
} from "../lib/provider";
import { reasoningOptions } from "../lib/reasoning";

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

function configure() {
  vi.stubEnv("LLM_PROVIDER", "modelgo");
  vi.stubEnv("LLM_MODEL", "test-model");
  vi.stubEnv("LLM_COMPOSE_MODEL", "");
  vi.stubEnv("MODELGO_API_KEY", "test-modelgo-key");
}

describe("ModelGo inference", () => {
  it("persists ModelGo inference on a completed automation through its audit mutation", async () => {
    configure();
    const t = convexTest(schema, import.meta.glob("../convex/**/*.ts"));
    const runId = await t.run(async (ctx) => {
      const automationId = await ctx.db.insert("automations", {
        userTokenIdentifier: "issuer|alice",
        title: "Morning",
        prompt: "Morning briefing",
        enabled: true,
      });
      return ctx.db.insert("automationRuns", {
        automationId,
        userTokenIdentifier: "issuer|alice",
        status: "completed",
        leaseGeneration: 1,
        startedAt: 1,
      });
    });
    const inference = {
      requestId: String(runId),
      profile: resolveInferenceProfile().profile,
      calls: [],
    };
    await t.mutation(internal.automationDispatch.recordRunInference, {
      runId,
      leaseGeneration: 1,
      inference,
    });
    expect(
      await t.run(async (ctx) => (await ctx.db.get("automationRuns", runId))?.inference),
    ).toEqual(inference);
  });

  it("requires an explicit model and only the ModelGo credential for both stages", () => {
    configure();
    vi.stubEnv("LLM_MODEL", "");
    expect(() => resolveInferenceProfile()).toThrow("LLM_MODEL is required");
    vi.stubEnv("LLM_MODEL", "test-model");
    vi.stubEnv("MODELGO_API_KEY", "");
    expect(() => resolveInferenceProfile()).toThrow("MODELGO_API_KEY");
    vi.stubEnv("MODELGO_API_KEY", "test-modelgo-key");
    const runtime = resolveInferenceProfile();
    expect(platformCredentialEnv()).toEqual(["MODELGO_API_KEY"]);
    expect(runtime.profile.compose).toEqual(runtime.profile.research);
    expect(runtime.models.compose).toBe(runtime.models.research);
    expect(usesOpenAIStrictSchema(runtime.profile.compose)).toBe(true);
    expect(reasoningOptions("modelgo", "medium", "test-model")).toEqual({});
    expect(() => resolveInferenceProfile(undefined, { images: true })).toThrow(
      "does not support image input",
    );
  });

  it("preserves the Cerebras default and supports independent composition selection", () => {
    configure();
    vi.stubEnv("LLM_PROVIDER", "");
    vi.stubEnv("LLM_MODEL", "");
    vi.stubEnv("CEREBRAS_API_KEY", "test-cerebras-key");
    expect(resolveInferenceProfile().profile.research.provider).toBe("cerebras");
    vi.stubEnv("LLM_COMPOSE_MODEL", "modelgo:compose-model");
    const runtime = resolveInferenceProfile();
    expect(runtime.profile.research.provider).toBe("cerebras");
    expect(runtime.profile.compose.modelId).toBe("compose-model");
    expect(runtime.profile.compose.provider).toBe("modelgo");
    expect(platformCredentialEnv()).toEqual(["CEREBRAS_API_KEY", "MODELGO_API_KEY"]);
    vi.stubEnv("LLM_COMPOSE_MODEL", "modelgo:");
    expect(() => resolveInferenceProfile()).toThrow("Composition model id is missing");
  });

  it("executes a research tool and sends its result back through Chat Completions", async () => {
    configure();
    const requests: Record<string, any>[] = [];
    vi.stubGlobal("fetch", async (input: string, init: RequestInit) => {
      expect(String(input)).toBe("https://api.modelgo.ai/v1/chat/completions");
      expect(new Headers(init.headers).get("authorization")).toBe("Bearer test-modelgo-key");
      const body = JSON.parse(String(init.body));
      requests.push(body);
      const message =
        requests.length === 1
          ? {
              role: "assistant",
              content: null,
              tool_calls: [
                {
                  id: "recall-1",
                  type: "function",
                  function: { name: "recall", arguments: "{}" },
                },
              ],
            }
          : { role: "assistant", content: "Verified preference: tea" };
      return Response.json({
        id: "research",
        created: 1,
        model: "test-model",
        choices: [
          {
            index: 0,
            message,
            finish_reason: requests.length === 1 ? "tool_calls" : "stop",
          },
        ],
        usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
      });
    });
    let executions = 0;
    const result = await generateText({
      model: resolveInferenceProfile().models.research,
      prompt: "Recall my preference",
      tools: {
        recall: tool({
          inputSchema: z.object({}),
          execute: () => {
            executions++;
            return { preference: "tea" };
          },
        }),
      },
      stopWhen: stepCountIs(2),
    });
    expect(executions).toBe(1);
    expect(result.text).toBe("Verified preference: tea");
    expect(requests).toHaveLength(2);
    expect(requests[0].tools[0].function.name).toBe("recall");
    expect(requests[1].messages).toContainEqual({
      role: "tool",
      tool_call_id: "recall-1",
      content: '{"preference":"tea"}',
    });
  });

  it("streams validated composition and normalizes the strict schema on the wire", async () => {
    configure();
    vi.stubGlobal("fetch", async (input: string, init: RequestInit) => {
      expect(String(input)).toBe("https://api.modelgo.ai/v1/chat/completions");
      const body = JSON.parse(String(init.body));
      expect(body.stream).toBe(true);
      expect(body.model).toBe("test-model");
      expect(body.response_format.type).toBe("json_schema");
      expect(body.response_format.json_schema.strict).toBe(true);
      const element = body.response_format.json_schema.schema.properties.elements.items;
      expect(element.required).toEqual(["title", "subtitle"]);
      expect(element.additionalProperties).toBe(false);
      expect(element.properties.subtitle.anyOf).toContainEqual({ type: "null" });
      const chunks = [
        { delta: { content: '{"elements":[{"title":"Hello"' }, finish_reason: null },
        { delta: { content: ',"subtitle":"World"}]}' }, finish_reason: null },
        { delta: {}, finish_reason: "stop" },
      ].map((choice) =>
        JSON.stringify({
          id: "compose",
          created: 1,
          model: "test-model",
          choices: [{ index: 0, ...choice }],
        }),
      );
      return new Response([...chunks, "[DONE]"].map((chunk) => `data: ${chunk}\n\n`).join(""), {
        headers: { "content-type": "text/event-stream" },
      });
    });
    const result = streamText({
      model: resolveInferenceProfile().models.compose,
      prompt: "Compose a page",
      output: Output.array({
        element: z.object({ title: z.string(), subtitle: z.string().optional() }),
      }),
    });
    expect(await result.output).toEqual([{ title: "Hello", subtitle: "World" }]);
  });
});
