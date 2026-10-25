import {
  generationPagePreview,
  generationPageSnapshot,
  generationTerminal,
  ndjsonLine,
  type GenerationFailure,
  type GenerationTerminal,
} from "@/lib/generationProtocol";
import type { InferenceSession } from "@/lib/inferenceTelemetry";
import { recordGenerationLatency, type LatencyStages } from "@/lib/latency";
import type { Block } from "@/lib/schema";

const PREVIEW_INTERVAL_MS = 50;

export type GenerationTiming = {
  requestStarted: number;
  stages: LatencyStages;
  signal: AbortSignal;
};

export type GenerationEmitter = ReturnType<typeof createGenerationEmitter>;

export function createGenerationEmitter(options: {
  controller: ReadableStreamDefaultController<Uint8Array>;
  signal: AbortSignal;
  isCancelled: () => boolean;
  previewEnabled: boolean;
  timing: GenerationTiming;
  inference: InferenceSession;
}) {
  const { controller, signal, isCancelled, previewEnabled, timing, inference } = options;
  const encoder = new TextEncoder();
  let progressSent = false;
  let statusSequence = 0;
  let timingRecorded = false;
  let snapshotRevision = 0;
  let lastSnapshot: string | null = null;
  let previewRevision = 0;
  let previewAttempt = 1;
  let previewSerialized = "";
  let previewAt = -Infinity;
  let previewSize = 0;

  const open = () => !isCancelled() && !signal.aborted;
  const send = (value: unknown) => {
    if (open()) controller.enqueue(encoder.encode(ndjsonLine(value)));
  };
  const sendTiming = () => {
    if (timingRecorded || signal.aborted) return;
    timingRecorded = true;
    timing.stages.total = performance.now() - timing.requestStarted;
    send(recordGenerationLatency("model", timing.stages));
  };
  const terminal = (
    status: GenerationTerminal["status"],
    blockCount: number,
    options: { persisted?: boolean; revision?: number },
  ) => {
    sendTiming();
    const audit = inference.audit();
    if (audit) send(audit);
    send(generationTerminal(status, blockCount, options));
  };

  return {
    get progressSent() {
      return progressSent;
    },
    status(text: string, id = `status-${statusSequence++}`) {
      progressSent = true;
      send({ type: "status", id, text });
    },
    beginPreviewAttempt(attempt: number) {
      previewAttempt = attempt;
    },
    preview(blocks: Block[], flush = false, draft: string | null = null) {
      if (!previewEnabled || !open()) return;
      const serialized = JSON.stringify([draft, blocks]);
      if (serialized === previewSerialized) return;
      const now = performance.now();
      if (
        !flush &&
        blocks.length > 0 &&
        blocks.length === previewSize &&
        now - previewAt < PREVIEW_INTERVAL_MS
      )
        return;
      previewAt = now;
      previewSize = blocks.length;
      previewSerialized = serialized;
      send(generationPagePreview(++previewRevision, previewAttempt, blocks, draft));
    },
    completed(
      blocks: readonly unknown[],
      persisted: boolean | undefined,
      trailer: readonly unknown[],
    ) {
      const payload = JSON.stringify(blocks);
      if (payload !== lastSnapshot) {
        lastSnapshot = payload;
        snapshotRevision += 1;
        if (timing.stages.firstBlock == null && blocks.length > 1) {
          timing.stages.firstBlock = performance.now() - timing.requestStarted;
        }
        send(generationPageSnapshot(snapshotRevision, blocks));
      }
      for (const value of trailer) send(value);
      terminal("completed", blocks.length, { persisted, revision: snapshotRevision });
    },
    failed(failure: GenerationFailure) {
      this.preview([]);
      send(failure);
      terminal(signal.aborted || failure.code === "cancelled" ? "cancelled" : "failed", 0, {
        persisted: false,
      });
    },
  };
}
