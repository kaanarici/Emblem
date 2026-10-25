import { parseGenerationNDJSON } from "../lib/generationProtocol";
import { asRecord } from "../lib/records";
import type { InferenceSummary } from "../lib/inferenceTelemetry";
import { createExecutionGrant, type AutomationSource } from "../lib/executionGrant";

export async function generatePage(
  prompt: string,
  timezone: string,
  execution: {
    ownerKey: string;
    runId: string;
    leaseGeneration: number;
    sources: AutomationSource[];
    memories?: string[];
  },
): Promise<{
  title: string | undefined;
  blocks: unknown[];
  terminalBlockCount: number;
  inference?: InferenceSummary;
}> {
  const secret = process.env.AUTOMATION_SERVICE_KEY;
  if (!secret) throw new Error("AUTOMATION_SERVICE_KEY is not configured");
  const origin = process.env.GENERATE_ORIGIN;
  if (!origin) throw new Error("GENERATE_ORIGIN is not configured");
  const grant = await createExecutionGrant(execution, secret);
  const res = await fetch(`${origin}/api/generate`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Execution-Grant": grant,
    },
    body: JSON.stringify({
      messages: [{ role: "user", content: prompt }],
      timezone,
      memoryContext: execution.memories,
    }),
    signal: AbortSignal.timeout(150_000),
  });
  if (!res.ok) throw new Error(`generate responded ${res.status}`);

  const { blocks, terminal, inference } = parseGenerationNDJSON(await res.text());

  const pageMeta = blocks.map(asRecord).find((block) => block?.type === "pageMeta");
  const title = typeof pageMeta?.title === "string" ? pageMeta.title : undefined;
  blocks.unshift({ type: "runStamp", id: "stamp", iso: new Date().toISOString() });
  return { title, blocks, terminalBlockCount: terminal.blockCount, inference };
}

export function summarize(title: string | undefined, blocks: unknown[]): string {
  const texts = blocks
    .map(asRecord)
    .flatMap((block) =>
      block?.type === "text" && typeof block.body === "string" ? [block.body] : [],
    )
    .slice(0, 3);
  return [title, texts.join(" ")].filter(Boolean).join(": ").slice(0, 400);
}
