type LogContext = Record<string, string | number | boolean | undefined>;
type LogFields = Record<string, unknown>;
type Level = "error" | "warn" | "info";

const WINDOW_MS = 60_000;
const MAX_PER_WINDOW = 20;
const windows = new Map<string, { start: number; count: number; suppressed: number }>();

function describeError(error: unknown): {
  name: string;
  statusCode?: number;
  code?: string;
} {
  const value =
    error && typeof error === "object"
      ? (error as { name?: unknown; statusCode?: unknown; code?: unknown })
      : null;
  const name = typeof value?.name === "string" ? value.name : "UnknownError";
  const statusCode = typeof value?.statusCode === "number" ? value.statusCode : undefined;
  const code =
    typeof value?.code === "string" && /^[a-z0-9_-]{1,80}$/i.test(value.code)
      ? value.code
      : undefined;
  return {
    name,
    ...(statusCode === undefined ? {} : { statusCode }),
    ...(code === undefined ? {} : { code }),
  };
}

function admit(event: string): number | null {
  const now = Date.now();
  let window = windows.get(event);
  if (!window || now - window.start >= WINDOW_MS) {
    window = { start: now, count: 0, suppressed: window?.suppressed ?? 0 };
    windows.set(event, window);
  }
  if (window.count >= MAX_PER_WINDOW) {
    window.suppressed += 1;
    return null;
  }
  window.count += 1;
  const suppressed = window.suppressed;
  window.suppressed = 0;
  return suppressed;
}

export function logEvent(level: Level, event: string, fields: LogFields = {}): void {
  const suppressed = admit(event);
  if (suppressed === null) return;
  const line = JSON.stringify({ event, ...fields, ...(suppressed ? { suppressed } : {}) });
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.log(line);
}

export function logError(event: string, error: unknown, context: LogContext = {}): void {
  logEvent("error", event, { ...context, error: describeError(error) });
}

export function logWarning(event: string, error: unknown, context: LogContext = {}): void {
  logEvent("warn", event, { ...context, error: describeError(error) });
}
