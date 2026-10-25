import { asRecord } from "./records";
import { blockSchema, type Block } from "./schema";
import type { InferenceAudit, InferenceSummary } from "./inferenceTelemetry";

export function ndjsonLine(value: unknown): string {
  return (
    JSON.stringify(value).replace(
      /[\u0085\u2028\u2029]/g,
      (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`,
    ) + "\n"
  );
}

export function generationFailure(
  code: string,
  message: string,
  retryable: boolean,
): GenerationFailure {
  return { type: "error", id: "generation-error", code, message, retryable };
}

export const GENERATION_CANCELLED = generationFailure("cancelled", "Generation cancelled.", false);

export type GenerationTerminal = {
  type: "terminal";
  id: "terminal";
  status: "completed" | "failed" | "cancelled";
  blockCount: number;
  revision?: number;
  persisted?: boolean;
};

export function generationTerminal(
  status: GenerationTerminal["status"],
  blockCount: number,
  options: { persisted?: boolean; revision?: number } = {},
): GenerationTerminal {
  return {
    type: "terminal",
    id: "terminal",
    status,
    blockCount,
    ...(options.revision === undefined ? {} : { revision: options.revision }),
    ...(options.persisted === undefined ? {} : { persisted: options.persisted }),
  };
}

export const NDJSON_HEADERS = {
  "Content-Type": "application/x-ndjson; charset=utf-8",
  "Cache-Control": "no-store",
  "Content-Encoding": "identity",
  "X-Accel-Buffering": "no",
} as const;

type GenerationPagePreview = {
  type: "pagePreview";
  id: "page-preview";
  revision: number;
  attempt: number;
  blocks: Block[];
  draft: string | null;
};

export function generationPagePreview(
  revision: number,
  attempt: number,
  blocks: readonly Block[],
  draft: string | null = null,
): GenerationPagePreview {
  if (![revision, attempt].every((n) => Number.isSafeInteger(n) && n > 0)) {
    throw new Error("generation preview revision and attempt must be positive integers");
  }
  return { type: "pagePreview", id: "page-preview", revision, attempt, blocks: [...blocks], draft };
}

type GenerationPageSnapshot = {
  type: "pageSnapshot";
  id: "page-snapshot";
  revision: number;
  blocks: unknown[];
};

export class GenerationFailedError extends Error {
  constructor(
    message: string,
    readonly inference?: InferenceSummary,
  ) {
    super(message);
  }
}

export type GenerationFailure = {
  type: "error";
  id: "generation-error";
  code: string;
  message: string;
  retryable: boolean;
};

export type GenerationActivity = {
  type: "activity";
  id: string;
  source: string;
  category: "personal" | "web" | "device" | "memory";
  title: string;
  status: "started" | "succeeded" | "empty" | "failed" | "unavailable";
  message: string;
};

export type GenerationSource = {
  id: string;
  title: string;
  url: string;
  domain: string;
  favicon?: string;
  publishedAt?: string;
  snippet?: string;
};

export type GenerationSources = {
  type: "sources";
  id: "sources";
  items: GenerationSource[];
};

type ParsedGeneration = {
  blocks: unknown[];
  terminal: GenerationTerminal;
  inference?: InferenceSummary;
};

export function generationPageSnapshot(
  revision: number,
  blocks: readonly unknown[],
): GenerationPageSnapshot {
  if (!Number.isSafeInteger(revision) || revision < 1) {
    throw new Error("generation snapshot revision must be a positive integer");
  }
  return {
    type: "pageSnapshot",
    id: "page-snapshot",
    revision,
    blocks: [...blocks],
  };
}

export function isRenderablePage(blocks: unknown[]): boolean {
  return pageCompositionIssues(blocks).length === 0;
}

export function pageCompositionIssues(blocks: unknown[]): string[] {
  const items = blocks.map(asRecord);
  const issues: string[] = [];
  const types = items.map((item) => item?.type);
  if (types[0] !== "pageMeta") issues.push("pageMeta must be first");
  if (types.filter((type) => type === "pageMeta").length !== 1) {
    issues.push("pageMeta must appear exactly once");
  }
  if (
    !items.some((item) =>
      item?.type === "titleBlock"
        ? typeof item.summary === "string" && item.summary.trim().length > 0
        : typeof item?.type === "string" &&
          !["pageMeta", "status", "sectionHeader", "chipRow", "runStamp"].includes(item.type),
    )
  ) {
    issues.push("page needs useful content");
  }
  const ids = items.flatMap((item) => (typeof item?.id === "string" ? [item.id] : []));
  if (new Set(ids).size !== ids.length) issues.push("block ids must be unique");
  const chipRows = types.flatMap((type, index) => (type === "chipRow" ? [index] : []));
  if (chipRows.length > 1) issues.push("chipRow may appear at most once");
  if (chipRows.some((index) => index !== blocks.length - 1)) {
    issues.push("chipRow must be last");
  }
  return issues;
}

function isInertAction(value: unknown): boolean {
  const action = asRecord(value);
  return action != null && Object.keys(action).length === 1 && typeof action.label === "string";
}

function withoutInertActions(value: unknown): unknown {
  const block = asRecord(value);
  if (block?.type === "titleBlock" && Array.isArray(block.actions)) {
    if (!block.actions.every(isInertAction)) return value;
    const { actions: _actions, ...rest } = block;
    return rest;
  }
  if (block?.type === "mediaRowList" && Array.isArray(block.rows)) {
    return {
      ...block,
      rows: block.rows.map((row) => {
        const fields = asRecord(row);
        if (!fields || !isInertAction(fields.action)) return row;
        const { action: _action, ...rest } = fields;
        return rest;
      }),
    };
  }
  return value;
}

export function parseGenerationNDJSON(text: string): ParsedGeneration {
  let blocks: unknown[] = [];
  let terminal: GenerationTerminal | null = null;
  let inference: InferenceSummary | undefined;
  let failure: GenerationFailure | null = null;
  let contentStarted = false;
  let trailerStarted = false;
  let sourcesSeen = false;
  let snapshotRevision = 0;
  let previewRevision = 0;
  let previewAttempt = 0;

  for (const line of text.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    let value: unknown;
    try {
      value = JSON.parse(trimmed);
    } catch {
      throw new Error("generate returned invalid NDJSON");
    }
    const item = asRecord(value);
    const type = item?.type;
    if (terminal) throw new Error("generate returned an event after terminal");
    if (type === "pagePreview") {
      if (
        item?.id !== "page-preview" ||
        !Number.isSafeInteger(item.revision) ||
        (item.revision as number) <= previewRevision ||
        !Number.isSafeInteger(item.attempt) ||
        (item.attempt as number) < Math.max(1, previewAttempt) ||
        !Array.isArray(item.blocks) ||
        !item.blocks.every((block) => blockSchema.safeParse(withoutInertActions(block)).success)
      ) {
        throw new Error("generate returned an invalid page preview");
      }
      previewRevision = item.revision as number;
      previewAttempt = item.attempt as number;
      continue;
    }
    if (type === "status") {
      if (contentStarted || trailerStarted) {
        throw new Error("generate returned status after page content");
      }
      continue;
    }
    if (type === "activity") {
      if (!contentStarted) throw new Error("generate returned activity before page content");
      if (sourcesSeen) throw new Error("generate returned activity after sources");
      trailerStarted = true;
      continue;
    }
    if (type === "sources") {
      if (!contentStarted) throw new Error("generate returned sources before page content");
      if (sourcesSeen) throw new Error("generate returned multiple sources events");
      sourcesSeen = true;
      trailerStarted = true;
      continue;
    }
    if (type === "metric") {
      trailerStarted = true;
      continue;
    }
    if (type === "error") {
      failure = value as GenerationFailure;
      trailerStarted = true;
      continue;
    }
    if (type === "inference") {
      if (inference) throw new Error("generate returned multiple inference events");
      inference = (value as InferenceAudit).summary;
      trailerStarted = true;
      continue;
    }
    if (type === "pageSnapshot") {
      if (trailerStarted) throw new Error("generate returned a snapshot after terminal metadata");
      if (
        item?.id !== "page-snapshot" ||
        typeof item.revision !== "number" ||
        !Number.isSafeInteger(item.revision) ||
        (item.revision as number) <= snapshotRevision ||
        !Array.isArray(item.blocks)
      ) {
        throw new Error("generate returned an invalid page snapshot");
      }
      contentStarted = true;
      snapshotRevision = item.revision as number;
      blocks = [...item.blocks];
      continue;
    }
    if (type === "terminal") {
      if (terminal) throw new Error("generate returned multiple terminal events");
      terminal = value as GenerationTerminal;
      continue;
    }
    throw new Error(
      `generate returned an unsupported event${typeof type === "string" ? ` ${type}` : ""}`,
    );
  }

  if (!terminal) throw new Error("generate ended without a terminal event");
  if (terminal.status !== "completed") {
    throw new GenerationFailedError(failure?.message || `generation ${terminal.status}`, inference);
  }
  if (snapshotRevision === 0) throw new Error("generate ended without a page snapshot");
  if (terminal.revision !== snapshotRevision) {
    throw new Error("generate terminal snapshot revision mismatch");
  }
  if (terminal.blockCount !== blocks.length) {
    throw new Error("generate terminal block count mismatch");
  }
  if (!isRenderablePage(blocks)) {
    throw new Error("generate did not produce a renderable page");
  }
  return { blocks, terminal, inference };
}
