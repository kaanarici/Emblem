const labels = [
  "AI_NoObjectGeneratedError",
  "AI_TypeValidationError",
  "AI_JSONParseError",
  "ZodError",
  "ProviderRefusalError",
  "AbortError",
  "TimeoutError",
  "Error",
] as const;
const codes = [
  "provider_refused",
  "provider_billing",
  "provider_auth",
  "provider_rate_limit",
  "incomplete_generation",
  "generation_failed",
] as const;
const finishReasons = [
  "stop",
  "length",
  "content-filter",
  "tool-calls",
  "error",
  "other",
  "unknown",
] as const;
const issueCodes = [
  "invalid_type",
  "too_big",
  "too_small",
  "invalid_format",
  "not_multiple_of",
  "unrecognized_keys",
  "invalid_union",
  "invalid_key",
  "invalid_element",
  "invalid_value",
  "custom",
] as const;

const ownedFailureKinds = ["duplicateKeys", "Unicode", "closedElementValidation"] as const;
export type OwnedPreviewFailureKind = (typeof ownedFailureKinds)[number];
const ownedFailures = new WeakMap<
  object,
  { kind: OwnedPreviewFailureKind; validationError?: unknown }
>();

export function markOwnedPreviewFailure<T extends Error>(
  error: T,
  kind: OwnedPreviewFailureKind,
  validationError?: unknown,
): T {
  if (ownedFailureKinds.includes(kind) && !ownedFailures.has(error))
    ownedFailures.set(error, { kind, validationError });
  return error;
}

const paths = [
  "type",
  "id",
  "body",
  "style",
  "title",
  "subtitle",
  "heading",
  "caption",
  "meta",
  "image.query",
  "image.kind",
  "image.aspect",
  "steps",
  "steps[].title",
  "steps[].body",
  "steps[].meta",
  "steps[].icon",
  "steps[].image.query",
  "steps[].image.kind",
  "steps[].image.aspect",
  "steps[].icon.image.query",
  "steps[].icon.image.kind",
  "steps[].icon.image.aspect",
  "cards",
  "cards[].title",
  "cards[].caption",
  "cards[].meta",
  "cards[].prompt",
  "cards[].tags",
  "cards[].tags[]",
  "cards[].image.query",
  "cards[].image.kind",
  "cards[].image.aspect",
  "columns",
  "columns[]",
  "rows",
  "rows[].label",
  "rows[].subtitle",
  "rows[].values",
  "rows[].values[].value",
  "rows[].values[].note",
  "requiredInput",
  "requiredInput.question",
  "requiredInput.kind",
  "requiredInput.options",
  "requiredInput.options[]",
  "followUps",
  "followUps[].label",
  "followUps[].prompt",
  "followUps[].iconQuery",
  "followUps[].iconIntent",
  "primaryAction",
  "primaryAction.kind",
  "primaryAction.label",
  "primaryAction.url",
  "primaryAction.prompt",
] as const;
const pathPatterns = paths.map((path) => ({ path, parts: path.replaceAll("[]", ".#").split(".") }));
type Label = (typeof labels)[number] | "OtherError";
type IssueCode = (typeof issueCodes)[number];
type ChainEntry = {
  label: Label;
  status?: number;
  code?: (typeof codes)[number];
  finishReason?: (typeof finishReasons)[number];
};
type Issue = { depth: number; code: IssueCode; path?: (typeof paths)[number] };
type StructuralErrorDiagnostic = {
  version: 1;
  chain: ChainEntry[];
  issues: Issue[];
  truncated: boolean;
  detailUnavailable: boolean;
};
type ComposeErrorDiagnostic = StructuralErrorDiagnostic & {
  ownedFailureKind?: OwnedPreviewFailureKind;
  ownedValidation?: StructuralErrorDiagnostic;
};

type Read = { value?: unknown; blocked: boolean };
function own(value: unknown, key: string): Read {
  if (value === null || (typeof value !== "object" && typeof value !== "function"))
    return { blocked: false };
  try {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor) return { blocked: false };
    return "value" in descriptor ? { value: descriptor.value, blocked: false } : { blocked: true };
  } catch {
    return { blocked: true };
  }
}
export function ownValidationError(result: unknown): unknown {
  return own(result, "error").value;
}
function member<const T extends readonly string[]>(
  value: unknown,
  choices: T,
): T[number] | undefined {
  return typeof value === "string" && choices.includes(value) ? (value as T[number]) : undefined;
}
function arraySize(value: unknown): number | undefined {
  try {
    if (!Array.isArray(value)) return undefined;
    const { value: length, blocked } = own(value, "length");
    return !blocked && typeof length === "number" && Number.isSafeInteger(length) && length >= 0
      ? length
      : undefined;
  } catch {
    return undefined;
  }
}
function staticPath(value: unknown): (typeof paths)[number] | undefined {
  const length = arraySize(value);
  if (length === undefined || length < 1 || length > 8) return undefined;
  const parts: unknown[] = [];
  for (let index = 0; index < length; index++) {
    const item = own(value, String(index));
    if (item.blocked) return undefined;
    parts.push(item.value);
  }
  return pathPatterns.find(
    (pattern) =>
      pattern.parts.length === length &&
      pattern.parts.every((part, index) =>
        part === "#"
          ? typeof parts[index] === "number" &&
            Number.isSafeInteger(parts[index]) &&
            (parts[index] as number) >= 0
          : parts[index] === part,
      ),
  )?.path;
}

function structuralErrorDiagnostic(error: unknown, maxIssues = 5): StructuralErrorDiagnostic {
  const chain: ChainEntry[] = [];
  const issues: Issue[] = [];
  const seen = new Set<unknown>();
  let truncated = false;
  let blocked = false;
  let current = error;
  for (let depth = 0; depth < 4; depth++) {
    if (seen.has(current)) {
      truncated = true;
      break;
    }
    seen.add(current);
    const name = own(current, "name");
    const status = own(current, "statusCode");
    const code = own(current, "code");
    const finish = own(current, "finishReason");
    blocked ||= name.blocked || status.blocked || code.blocked || finish.blocked;
    const label = member(name.value, labels) ?? "OtherError";
    const entry: ChainEntry = { label };
    if (
      typeof status.value === "number" &&
      Number.isInteger(status.value) &&
      status.value >= 100 &&
      status.value <= 599
    )
      entry.status = status.value;
    const knownCode = member(code.value, codes);
    if (knownCode) entry.code = knownCode;
    const knownFinish = member(finish.value, finishReasons);
    if (knownFinish) entry.finishReason = knownFinish;
    chain.push(entry);
    if (label === "ZodError") {
      const source = own(current, "issues");
      blocked ||= source.blocked;
      const length = arraySize(source.value);
      if (length !== undefined) {
        const available = Math.min(length, maxIssues - issues.length);
        if (length > available) truncated = true;
        for (let index = 0; index < available; index++) {
          const item = own(source.value, String(index));
          const code = own(item.value, "code");
          const path = own(item.value, "path");
          blocked ||= item.blocked || code.blocked || path.blocked;
          const known = member(code.value, issueCodes);
          if (!known) continue;
          const safePath = staticPath(path.value);
          issues.push({ depth, code: known, ...(safePath ? { path: safePath } : {}) });
        }
      }
    }
    const cause = own(current, "cause");
    blocked ||= cause.blocked;
    if (cause.value === undefined || cause.value === null) break;
    if (depth === 3) {
      truncated = true;
      break;
    }
    current = cause.value;
  }
  return {
    version: 1,
    chain,
    issues,
    truncated,
    detailUnavailable:
      blocked ||
      !(
        issues.length ||
        chain.some(
          (entry) =>
            entry.status !== undefined ||
            entry.code ||
            entry.finishReason ||
            (entry.label !== "OtherError" && entry.label !== "Error"),
        )
      ),
  };
}

function composeErrorDiagnostic(error: unknown): ComposeErrorDiagnostic {
  const diagnostic: ComposeErrorDiagnostic = structuralErrorDiagnostic(error);
  const seen = new Set<unknown>();
  let current = error;
  for (let depth = 0; depth < 4 && current !== null && typeof current === "object"; depth++) {
    if (seen.has(current)) break;
    seen.add(current);
    const owned = ownedFailures.get(current);
    if (owned) {
      diagnostic.ownedFailureKind = owned.kind;
      if (owned.validationError !== undefined) {
        diagnostic.ownedValidation = structuralErrorDiagnostic(
          owned.validationError,
          5 - diagnostic.issues.length,
        );
      }
      diagnostic.detailUnavailable = false;
      break;
    }
    const cause = own(current, "cause");
    if (cause.blocked) break;
    current = cause.value;
  }
  return diagnostic;
}

function facts(diagnostic: ComposeErrorDiagnostic): Set<string> {
  const result = new Set<string>();
  diagnostic.chain.forEach((entry, depth) => {
    if (entry.label !== "OtherError" && entry.label !== "Error")
      result.add(`class:${depth}:${entry.label}`);
    if (entry.status !== undefined) result.add(`status:${depth}:${entry.status}`);
    if (entry.code) result.add(`code:${depth}:${entry.code}`);
    if (entry.finishReason) result.add(`finish:${depth}:${entry.finishReason}`);
  });
  for (const issue of diagnostic.issues) {
    result.add(`issue:${issue.depth}:${issue.code}`);
    if (issue.path) result.add(`path:${issue.depth}:${issue.code}:${issue.path}`);
  }
  if (diagnostic.ownedFailureKind) result.add(`owned:${diagnostic.ownedFailureKind}`);
  if (diagnostic.ownedValidation) {
    for (const fact of facts(diagnostic.ownedValidation)) result.add(`ownedValidation:${fact}`);
  }
  return result;
}
type ComposeErrorObservation = {
  observation: "initial" | "enrichment";
  source: "sdk-onError" | "compose-catch";
  requestId?: string;
  diagnostic: ComposeErrorDiagnostic;
};
export function createComposeErrorDiagnostics(requestId: string) {
  const safeRequestId =
    typeof requestId === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(requestId)
      ? requestId
      : undefined;
  let first: Set<string> | undefined;
  let enriched = false;
  return (
    error: unknown,
    source: ComposeErrorObservation["source"],
  ): ComposeErrorObservation | undefined => {
    const diagnostic = composeErrorDiagnostic(error);
    const next = facts(diagnostic);
    let observation: ComposeErrorObservation["observation"] = "initial";
    if (first) {
      if (enriched || next.size <= first.size || ![...first].every((fact) => next.has(fact)))
        return undefined;
      enriched = true;
      observation = "enrichment";
    } else first = next;
    return {
      observation,
      source: source === "sdk-onError" ? source : "compose-catch",
      ...(safeRequestId ? { requestId: safeRequestId } : {}),
      diagnostic,
    };
  };
}
