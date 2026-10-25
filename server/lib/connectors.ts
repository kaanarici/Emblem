import { logError, logWarning } from "./log";
import type { ToolSet } from "ai";
import type { GenerationActivity, GenerationSource } from "./generationProtocol";
import { presentConnectorResult } from "./connectorPresentation";
import { isRecord } from "./records";

type ConnectorStatus =
  "disconnected" | "authorizing" | "connected" | "needs_attention" | "unavailable";

type ConnectorAccount = {
  id: string;
  label: string;
  status: "connected" | "authorizing" | "needs_attention";
  addedAt?: string;
};

type ConnectorState = {
  slug: string;
  title: string;
  status: ConnectorStatus;
  logo: string;
  detail: string;
  diagnosticCode?: string;
  lastCheckedAt?: number;
  canReconnect: boolean;
  accounts?: ConnectorAccount[];
};

const TOOLKITS = [
  {
    slug: "gmail",
    title: "Gmail",
    managedAuth: true,
    statusLine: "Checking your email…",
    doneLine: "Searched your email",
    emptyLine: "No matching emails",
    readTools: ["GMAIL_FETCH_EMAILS", "GMAIL_LIST_THREADS", "GMAIL_FETCH_MESSAGE_BY_THREAD_ID"],
  },
  {
    slug: "googlecalendar",
    title: "Google Calendar",
    managedAuth: false,
    statusLine: "Checking your calendar…",
    doneLine: "Checked your calendar",
    emptyLine: "Nothing on your calendar matched",
    readTools: [
      "GOOGLECALENDAR_EVENTS_LIST",
      "GOOGLECALENDAR_FIND_EVENT",
      "GOOGLECALENDAR_FIND_FREE_SLOTS",
    ],
  },
] as const;

export function connectorsEnabled(): boolean {
  return Boolean(process.env.COMPOSIO_API_KEY?.trim());
}

let composioClient: Promise<InstanceType<typeof import("@composio/core").Composio>> | null = null;

function getComposio() {
  composioClient ??= (async () => {
    const { Composio } = await import("@composio/core");
    const { VercelProvider } = await import("@composio/vercel");
    return new Composio({
      apiKey: process.env.COMPOSIO_API_KEY!.trim(),
      provider: new VercelProvider(),
      allowTracking: false,
      disableVersionCheck: true,
    });
  })();
  return composioClient;
}

const authConfigIds = new Map<string, Promise<string>>();

class ConnectorAuthConfigMissingError extends Error {
  override name = "ConnectorAuthConfigMissingError";
}

function authConfigIdFor(slug: string): Promise<string> {
  let cached = authConfigIds.get(slug);
  if (!cached) {
    cached = (async () => {
      const composio = await getComposio();
      const existing = await controlPlaneCall((signal) =>
        composio.authConfigs.list({ toolkit: slug }, { signal }),
      );
      const id = existing.items[0]?.id;
      if (id) return id;
      const toolkit = TOOLKITS.find((candidate) => candidate.slug === slug);
      if (!toolkit?.managedAuth) {
        throw new ConnectorAuthConfigMissingError(`${slug} auth config missing`);
      }
      const created = await controlPlaneCall((signal) =>
        composio.authConfigs.create(
          slug,
          {
            type: "use_composio_managed_auth",
            name: `Emblem ${slug}`,
          },
          { signal },
        ),
      );
      return created.id;
    })();
    cached.catch(() => authConfigIds.delete(slug));
    authConfigIds.set(slug, cached);
  }
  return cached;
}

const CONNECTIONS_TTL_MS = 5 * 60_000;
const MAX_CACHED_USERS = 2000;
const MAX_STATUS_PAGES = 100;
const STATUS_READ_WAIT_MS = 30_000;
const connectionsCache = new Map<string, { at: number; states: ConnectorState[] }>();

type Account = {
  id: string;
  status: string;
  isDisabled?: boolean;
  alias?: string | null;
  createdAt?: string;
  toolkit: { slug: string };
};

type SafeFailure = {
  status: "needs_attention" | "unavailable";
  code: string;
  detail: string;
};

export type ConnectorExecutionFailure = SafeFailure & {
  source: string;
  title: string;
};

type ConnectorExecutionState = {
  failures: Map<string, ConnectorExecutionFailure>;
  disabledTools: Set<string>;
  inFlight: Map<string, Promise<unknown>>;
};

export function createConnectorExecutionState(): ConnectorExecutionState {
  return {
    failures: new Map(),
    disabledTools: new Set(),
    inFlight: new Map(),
  };
}

function safeFailureResult(failure: ConnectorExecutionFailure) {
  return {
    successful: false as const,
    data: null,
    error: {
      code: failure.code,
      message: `${failure.title} could not be read for this request. Do not claim it was checked.`,
    },
  };
}

export function connectorForTool(toolName: string): { source: string; title: string } | null {
  const normalized = toolName.toUpperCase();
  const toolkit = TOOLKITS.find((candidate) =>
    candidate.readTools.some((name) => name === normalized),
  );
  return toolkit ? { source: toolkit.slug, title: toolkit.title } : null;
}

function errorDetails(value: unknown) {
  let name: string | undefined;
  let status: number | undefined;
  const messages: string[] = [];
  for (let depth = 0; depth < 4 && value != null; depth++) {
    if (typeof value === "string") {
      messages.push(value);
      break;
    }
    if (typeof value !== "object") break;
    const error = value as {
      name?: string;
      message?: string;
      status?: number;
      statusCode?: number;
      cause?: unknown;
      error?: unknown;
    };
    name ??= error.name;
    status ??= error.statusCode ?? error.status;
    if (error.message) messages.push(error.message);
    value = error.cause ?? error.error;
  }
  return { name, status, message: messages.join(" ") };
}

export function classifyConnectorFailure(error: unknown, serviceOperation = false): SafeFailure {
  const { name, status, message } = errorDetails(error);
  if (
    name === "ComposioRequestCancelledError" ||
    name === "ConnectorDeadlineError" ||
    /abort|timeout/i.test(message)
  ) {
    return {
      status: "unavailable",
      code: "connector_timeout",
      detail: "The connector service did not respond. Try again.",
    };
  }
  if (name === "ConnectorAuthConfigMissingError") {
    return {
      status: "unavailable",
      code: "connector_auth_config_missing",
      detail: "Emblem's connector service needs an OAuth configuration.",
    };
  }
  if (
    name === "ComposioNoAPIKeyError" ||
    (status === 401 && (serviceOperation || /invalid api[ -]?key/i.test(message)))
  ) {
    return {
      status: "unavailable",
      code: "connector_service_auth",
      detail: "Emblem's connector service needs configuration.",
    };
  }
  if (
    status === 403 &&
    (serviceOperation ||
      /(?:api[ -]?key|project|tool execution).{0,60}(?:permission|scope|access)|(?:permission|scope).{0,60}(?:api[ -]?key|project|tool execution)/i.test(
        message,
      ))
  ) {
    return {
      status: "unavailable",
      code: "connector_service_permission",
      detail: "Emblem's connector service lacks a required permission.",
    };
  }
  if (status === 401 || status === 403) {
    return {
      status: "needs_attention",
      code: "connection_unauthorized",
      detail: "Reconnect to restore access.",
    };
  }
  if (status === 429 || (status != null && status >= 500)) {
    return {
      status: "unavailable",
      code: status === 429 ? "connector_rate_limited" : "connector_service_error",
      detail: "The connector service is temporarily unavailable.",
    };
  }
  return {
    status: "unavailable",
    code: "connector_read_failed",
    detail: "The connector could not complete this read.",
  };
}

function accountStatus(account: Account): ConnectorAccount["status"] | null {
  if (account.isDisabled || account.status === "EXPIRED") return "needs_attention";
  if (account.status === "ACTIVE") return "connected";
  if (account.status === "INITIATED" || account.status === "INITIALIZING") return "authorizing";
  return null;
}

function toolkitAccounts(slug: string, accounts: Account[]): ConnectorAccount[] {
  return accounts
    .filter((account) => account.toolkit.slug === slug)
    .flatMap((account) => {
      const status = accountStatus(account);
      return status ? [{ account, status }] : [];
    })
    .sort((a, b) => (a.account.createdAt ?? "").localeCompare(b.account.createdAt ?? ""))
    .map(({ account, status }, index) => ({
      id: account.id,
      label: account.alias?.trim() || `Account ${index + 1}`,
      status,
      ...(account.createdAt ? { addedAt: account.createdAt } : {}),
    }));
}

function accountState(toolkit: (typeof TOOLKITS)[number], items: Account[]): ConnectorState {
  const base = {
    slug: toolkit.slug,
    title: toolkit.title,
    logo: `https://logos.composio.dev/api/${toolkit.slug}`,
    accounts: toolkitAccounts(toolkit.slug, items),
  };
  const has = (status: ConnectorAccount["status"]) =>
    base.accounts.some((account) => account.status === status);
  const connected = base.accounts.filter((account) => account.status === "connected").length;
  if (connected > 0) {
    return {
      ...base,
      status: "connected",
      detail: connected === 1 ? "Connected" : `${connected} accounts connected`,
      canReconnect: false,
    };
  }
  if (has("authorizing")) {
    return {
      ...base,
      status: "authorizing",
      detail: "Finish approval in the browser.",
      canReconnect: false,
    };
  }
  if (has("needs_attention")) {
    return {
      ...base,
      status: "needs_attention",
      detail: "Reconnect to restore access.",
      diagnosticCode: "account_expired",
      canReconnect: true,
    };
  }
  return { ...base, status: "disconnected", detail: "Not connected", canReconnect: true };
}

export async function connectorStates(
  userId: string,
  force = false,
  signal?: AbortSignal,
): Promise<ConnectorState[]> {
  if (!connectorsEnabled()) return [];
  const cached = connectionsCache.get(userId);
  if (!force && cached && Date.now() - cached.at < CONNECTIONS_TTL_MS) return cached.states;

  const composio = await getComposio();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), STATUS_READ_WAIT_MS);
  const readSignal = signal ? AbortSignal.any([signal, controller.signal]) : controller.signal;
  const items: Account[] = [];
  try {
    let cursor: string | undefined;
    const seen = new Set<string>();
    for (let page = 0; ; page++) {
      if (page >= MAX_STATUS_PAGES) throw new Error("connector account listing incomplete");
      const result = await controlPlaneCall(
        (deadlineSignal) =>
          composio.connectedAccounts.list(
            {
              userIds: [userId],
              toolkitSlugs: TOOLKITS.map((t) => t.slug),
              limit: 100,
              ...(cursor ? { cursor } : {}),
            },
            { signal: deadlineSignal },
          ),
        readSignal,
      );
      if (result.items.length > 100) throw new Error("connector account listing incomplete");
      items.push(
        ...result.items.map(({ id, status, isDisabled, alias, createdAt, toolkit }) => ({
          id,
          status,
          isDisabled,
          alias,
          createdAt,
          toolkit: { slug: toolkit.slug },
        })),
      );
      if (!result.nextCursor) break;
      if (seen.has(result.nextCursor)) throw new Error("connector account listing incomplete");
      seen.add(result.nextCursor);
      cursor = result.nextCursor;
    }
  } catch (error) {
    connectionsCache.delete(userId);
    throw error;
  } finally {
    clearTimeout(timer);
  }
  const states = TOOLKITS.map((toolkit) => accountState(toolkit, items));
  connectionsCache.delete(userId);
  if (states.some((state) => state.status !== "connected")) return states;
  if (connectionsCache.size >= MAX_CACHED_USERS) {
    const oldest = connectionsCache.keys().next().value;
    if (oldest !== undefined) connectionsCache.delete(oldest);
  }
  connectionsCache.set(userId, { at: Date.now(), states });
  return states;
}

export async function initiateConnection(
  userId: string,
  slug: string,
  assertActive: () => Promise<void>,
  another = false,
): Promise<{ redirectUrl: string } | { alreadyConnected: true }> {
  if (!TOOLKITS.some((t) => t.slug === slug)) throw new Error(`unknown toolkit "${slug}"`);
  await assertActive();
  connectionsCache.delete(userId);
  const states = await connectorStates(userId, true);
  await assertActive();
  if (!another && states.find((s) => s.slug === slug)?.status === "connected") {
    return { alreadyConnected: true };
  }
  const composio = await getComposio();
  const authConfigId = await authConfigIdFor(slug);
  await assertActive();
  const request = await controlPlaneCall((signal) =>
    composio.connectedAccounts.link(
      userId,
      authConfigId,
      {
        allowMultiple: true,
      },
      { signal },
    ),
  );
  connectionsCache.delete(userId);
  try {
    await assertActive();
    if (!request.redirectUrl) throw new Error("composio returned no redirect URL");
    return { redirectUrl: request.redirectUrl };
  } catch (error) {
    await revokeAccount(composio, request.id);
    throw error;
  }
}

const MAX_DISCONNECT_BATCHES = 100;
const DISCONNECT_WAIT_MS = 30_000;

class ConnectorRevocationIncompleteError extends Error {
  override name = "ConnectorRevocationIncompleteError";
}

async function revokeAccount(
  composio: Awaited<ReturnType<typeof getComposio>>,
  id: string,
  parent?: AbortSignal,
): Promise<void> {
  if (!id)
    throw new ConnectorRevocationIncompleteError("Account removal identity is missing; retry");
  const result = await controlPlaneCall(
    (signal) =>
      composio.getClient().connectedAccounts.delete(
        id,
        { revoke_on_delete: true },
        {
          signal,
          timeout: CONNECTOR_CALL_TIMEOUT_MS,
          maxRetries: 0,
        },
      ),
    parent,
  );
  if (result.success !== true) {
    throw new ConnectorRevocationIncompleteError("Account deletion was not confirmed; retry");
  }
}

export async function disconnect(userId: string, slug: string, accountId?: string): Promise<void> {
  if (accountId) await disconnectAccount(userId, slug, accountId);
  else await disconnectAccounts(userId, slug);
}

async function disconnectAccount(userId: string, slug: string, accountId: string): Promise<void> {
  const composio = await getComposio();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), DISCONNECT_WAIT_MS);
  connectionsCache.delete(userId);
  try {
    let cursor: string | undefined;
    for (let batch = 0; batch < MAX_DISCONNECT_BATCHES; batch++) {
      const { items, nextCursor } = await controlPlaneCall(
        (signal) =>
          composio.connectedAccounts.list(
            {
              userIds: [userId],
              toolkitSlugs: [slug],
              limit: 100,
              ...(cursor ? { cursor } : {}),
            },
            { signal },
          ),
        controller.signal,
      );
      if (items.some((account) => account.id === accountId)) {
        await revokeAccount(composio, accountId, controller.signal);
        return;
      }
      if (!nextCursor || nextCursor === cursor) return;
      cursor = nextCursor;
    }
    throw new ConnectorRevocationIncompleteError("Incomplete account listing; retry");
  } finally {
    clearTimeout(timer);
    connectionsCache.delete(userId);
  }
}

export async function disconnectAll(userId: string): Promise<void> {
  if (!connectorsEnabled()) return;
  await disconnectAccounts(userId);
}

async function disconnectAccounts(userId: string, slug?: string): Promise<void> {
  const composio = await getComposio();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), DISCONNECT_WAIT_MS);
  connectionsCache.delete(userId);
  try {
    for (let batch = 0; batch < MAX_DISCONNECT_BATCHES; batch++) {
      const { items, nextCursor } = await controlPlaneCall(
        (signal) =>
          composio.connectedAccounts.list(
            {
              userIds: [userId],
              ...(slug ? { toolkitSlugs: [slug] } : {}),
              limit: 100,
            },
            { signal },
          ),
        controller.signal,
      );
      if (items.length === 0) {
        if (nextCursor)
          throw new ConnectorRevocationIncompleteError("Incomplete account listing; retry");
        return;
      }
      for (const account of items) {
        await revokeAccount(composio, account.id, controller.signal);
      }
    }
    throw new ConnectorRevocationIncompleteError("Account removal is incomplete; retry");
  } finally {
    clearTimeout(timer);
    connectionsCache.delete(userId);
  }
}

type ConnectorCallbacks = {
  onStatus?: (text: string) => void;
  onActivity?: (activity: GenerationActivity) => void;
  onSources?: (sources: GenerationSource[]) => void;
  signal?: AbortSignal;
};

type RuntimeToolkit = Pick<
  (typeof TOOLKITS)[number],
  "slug" | "title" | "statusLine" | "doneLine" | "emptyLine" | "readTools"
>;

const CONNECTOR_CALL_TIMEOUT_MS = 10_000;

function connectorSignal(parent?: AbortSignal): AbortSignal {
  const timeout = AbortSignal.timeout(CONNECTOR_CALL_TIMEOUT_MS);
  return parent ? AbortSignal.any([parent, timeout]) : timeout;
}

function markToolkitFailure(
  execution: ConnectorExecutionState,
  toolkit: RuntimeToolkit,
  failure: SafeFailure,
): ConnectorExecutionFailure {
  const recorded = { ...failure, source: toolkit.slug, title: toolkit.title };
  execution.failures.set(toolkit.slug, recorded);
  toolkit.readTools.forEach((name) => execution.disabledTools.add(name));
  return recorded;
}

function allowedToolkitTools(tools: ToolSet, toolkit: RuntimeToolkit): ToolSet {
  const returned = new Map(
    Object.entries(tools).map(([name, definition]) => [name.toUpperCase(), definition]),
  );
  return Object.fromEntries(
    toolkit.readTools.flatMap((name) => {
      const definition = returned.get(name);
      return definition ? [[name, definition]] : [];
    }),
  );
}

const MAX_ARGUMENT_ITEMS = 20;
const MAX_ARGUMENT_KEYS = 40;
const MAX_ARGUMENT_STRING = 1000;
const MAX_ARGUMENT_DEPTH = 3;
const MAX_RESULT_BYTES = 24 * 1024;
const MAX_RESULT_PREVIEW_BYTES = 10 * 1024;
const MAX_RESULT_DEPTH = 5;
const MAX_RESULT_ITEMS = 20;
const MAX_RESULT_KEYS = 50;
const MAX_RESULT_STRING = 4000;

function normalizedKey(key: string): string {
  return key.replace(/[_-]/g, "").toLowerCase();
}

function clampToolArguments(toolName: string, value: unknown): unknown {
  if (!isRecord(value)) return value;
  const bounded = clampArgumentObject(value, 0);
  if (toolName === "GMAIL_LIST_THREADS") bounded.verbose = false;
  return bounded;
}

function clampArgumentObject(
  value: Record<string, unknown>,
  depth: number,
): Record<string, unknown> {
  const bounded: Record<string, unknown> = {};
  for (const [key, child] of Object.entries(value).slice(0, MAX_ARGUMENT_KEYS)) {
    const normalized = normalizedKey(key);
    if (["includeattachments", "downloadattachments"].includes(normalized)) {
      bounded[key] = false;
      continue;
    }
    if (
      ["proto", "constructor", "prototype", "payload"].includes(normalized) ||
      normalized.startsWith("raw") ||
      normalized.includes("attachment")
    ) {
      continue;
    }
    if (
      typeof child === "number" &&
      [
        "maxresults",
        "limit",
        "count",
        "pagesize",
        "calendarexpansionmax",
        "groupexpansionmax",
      ].includes(normalized)
    ) {
      bounded[key] = Math.max(1, Math.min(MAX_ARGUMENT_ITEMS, Math.floor(child)));
    } else if (typeof child === "string") {
      bounded[key] = child.slice(0, MAX_ARGUMENT_STRING);
    } else if (Array.isArray(child)) {
      bounded[key] = child
        .slice(0, MAX_ARGUMENT_ITEMS)
        .flatMap((item) => clampArgumentItem(item, depth + 1));
    } else if (isRecord(child)) {
      if (depth < MAX_ARGUMENT_DEPTH) bounded[key] = clampArgumentObject(child, depth + 1);
    } else {
      bounded[key] = child;
    }
  }
  return bounded;
}

function clampArgumentItem(item: unknown, depth: number): unknown[] {
  if (typeof item === "string") return [item.slice(0, MAX_ARGUMENT_STRING)];
  if (Array.isArray(item)) return [];
  if (isRecord(item)) return depth < MAX_ARGUMENT_DEPTH ? [clampArgumentObject(item, depth)] : [];
  return [item];
}

function sanitizeToolResult(value: unknown, depth = 0, seen = new WeakSet<object>()): unknown {
  if (typeof value === "string") {
    return value.length <= MAX_RESULT_STRING ? value : `${value.slice(0, MAX_RESULT_STRING - 1)}…`;
  }
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value === "bigint") return value.toString();
  if (value == null || typeof value === "boolean") return value;
  if (typeof value !== "object") return undefined;
  if (ArrayBuffer.isView(value)) return "[binary omitted]";
  if (depth >= MAX_RESULT_DEPTH) return "[truncated]";
  if (seen.has(value)) return "[circular]";
  seen.add(value);

  if (Array.isArray(value)) {
    return value
      .slice(0, MAX_RESULT_ITEMS)
      .map((item) => sanitizeToolResult(item, depth + 1, seen));
  }

  const bounded: Record<string, unknown> = {};
  let retained = 0;
  for (const [key, childValue] of Object.entries(value)) {
    const normalized = normalizedKey(key);
    if (
      normalized.startsWith("raw") ||
      normalized.endsWith("payload") ||
      normalized.includes("attachment")
    ) {
      continue;
    }
    const child = sanitizeToolResult(childValue, depth + 1, seen);
    if (child !== undefined) {
      bounded[key] = child;
      if (++retained === MAX_RESULT_KEYS) break;
    }
  }
  return bounded;
}

function boundedToolResult(value: unknown): unknown {
  const sanitized = sanitizeToolResult(value) ?? null;
  const serialized = JSON.stringify(sanitized) ?? "null";
  if (Buffer.byteLength(serialized, "utf8") <= MAX_RESULT_BYTES) return sanitized;

  const successful =
    value &&
    typeof value === "object" &&
    typeof (value as { successful?: unknown }).successful === "boolean"
      ? (value as { successful: boolean }).successful
      : undefined;
  return {
    ...(successful === undefined ? {} : { successful }),
    truncated: true,
    preview: Buffer.from(serialized, "utf8").subarray(0, MAX_RESULT_PREVIEW_BYTES).toString("utf8"),
  };
}

class ConnectorDeadlineError extends Error {
  override name = "ConnectorDeadlineError";
}

function withConnectorDeadline<T>(work: () => Promise<T>, signal?: AbortSignal): Promise<T> {
  if (signal?.aborted) return Promise.reject(new ConnectorDeadlineError("Connector call aborted"));
  return new Promise<T>((resolve, reject) => {
    let settled = false;
    const finish = (callback: () => void) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      signal?.removeEventListener("abort", onAbort);
      callback();
    };
    const onAbort = () =>
      finish(() => reject(new ConnectorDeadlineError("Connector call aborted")));
    const timer = setTimeout(
      () => finish(() => reject(new ConnectorDeadlineError("Connector call timed out"))),
      CONNECTOR_CALL_TIMEOUT_MS,
    );
    signal?.addEventListener("abort", onAbort, { once: true });
    void Promise.resolve()
      .then(work)
      .then(
        (value) => finish(() => resolve(value)),
        (error) => finish(() => reject(error)),
      );
  });
}

function controlPlaneCall<T>(
  work: (signal: AbortSignal) => Promise<T>,
  parent?: AbortSignal,
): Promise<T> {
  const signal = connectorSignal(parent);
  return withConnectorDeadline(() => work(signal), signal);
}

const ACCOUNT_SUFFIX = /__A\d+$/;

function baseToolName(name: string): string {
  return name.replace(ACCOUNT_SUFFIX, "");
}

function accountTools(
  tools: ToolSet,
  account: ConnectorAccount,
  index: number,
  accounts: ConnectorAccount[],
): ToolSet {
  if (accounts.length < 2) return tools;
  return Object.fromEntries(
    Object.entries(tools).map(([name, definition]) => {
      if (typeof definition.description !== "function") {
        definition.description = `[${account.label}] ${definition.description ?? ""}`.trim();
      }
      return [index === 0 ? name : `${name}__A${index + 1}`, definition];
    }),
  );
}

export function instrumentConnectorTools(
  tools: ToolSet,
  connected: readonly RuntimeToolkit[],
  callbacks: ConnectorCallbacks,
  execution: ConnectorExecutionState,
): void {
  let activitySequence = 0;
  for (const [name, tool] of Object.entries(tools)) {
    const toolkit = connected.find((candidate) =>
      name.toUpperCase().startsWith(`${candidate.slug.toUpperCase()}_`),
    );
    const execute = tool.execute?.bind(tool);
    if (!toolkit || !execute) continue;
    tool.execute = async (args, options) => {
      const knownFailure = execution.failures.get(toolkit.slug);
      if (knownFailure) return safeFailureResult(knownFailure);

      const pending = execution.inFlight.get(toolkit.slug);
      if (pending) {
        await pending;
        const pendingFailure = execution.failures.get(toolkit.slug);
        if (pendingFailure) return safeFailureResult(pendingFailure);
      }

      const id =
        (options as { toolCallId?: string } | undefined)?.toolCallId ??
        `${toolkit.slug}-${activitySequence++}`;
      callbacks.onStatus?.(toolkit.statusLine);
      callbacks.onActivity?.({
        type: "activity",
        id,
        source: toolkit.slug,
        category: "personal",
        title: toolkit.title,
        status: "started",
        message: toolkit.statusLine.replace(/…$/, ""),
      });

      const run = (async () => {
        const fail = (error: unknown) => {
          const failure = markToolkitFailure(execution, toolkit, classifyConnectorFailure(error));
          logWarning("connector tool failed", error, { toolkit: toolkit.slug, code: failure.code });
          callbacks.onActivity?.({
            type: "activity",
            id,
            source: toolkit.slug,
            category: "personal",
            title: toolkit.title,
            status: "failed",
            message: `${toolkit.title} couldn't be read`,
          });
          return safeFailureResult(failure);
        };
        try {
          const result = await withConnectorDeadline(
            () => execute(clampToolArguments(baseToolName(name), args), options),
            options?.abortSignal,
          );
          if (toolResultStatus(result) === "failed") return fail(result);
          const presented = presentConnectorResult(baseToolName(name), result);
          const presentedStatus = toolResultStatus(presented.result);
          callbacks.onActivity?.({
            type: "activity",
            id,
            source: toolkit.slug,
            category: "personal",
            title: toolkit.title,
            status: presentedStatus,
            message: presentedStatus === "empty" ? toolkit.emptyLine : toolkit.doneLine,
          });
          if (presented.sources) callbacks.onSources?.(presented.sources);
          return boundedToolResult(presented.result);
        } catch (error) {
          return fail(error);
        }
      })();
      execution.inFlight.set(toolkit.slug, run);
      try {
        return await run;
      } finally {
        if (execution.inFlight.get(toolkit.slug) === run) {
          execution.inFlight.delete(toolkit.slug);
        }
      }
    };
  }
}

export async function connectorContext(
  userId: string,
  callbacks: ConnectorCallbacks = {},
  allowedSlugs?: string[],
): Promise<{
  tools: ToolSet;
  states: ConnectorState[];
  execution: ConnectorExecutionState;
}> {
  const execution = createConnectorExecutionState();
  if (!connectorsEnabled()) return { tools: {}, states: [], execution };
  const permitted = allowedSlugs
    ? TOOLKITS.filter((toolkit) => allowedSlugs.includes(toolkit.slug))
    : TOOLKITS;
  if (permitted.length === 0) return { tools: {}, states: [], execution };
  let states: ConnectorState[] = [];
  try {
    states = (await connectorStates(userId, false, callbacks.signal)).filter((state) =>
      permitted.some((toolkit) => toolkit.slug === state.slug),
    );
  } catch (error) {
    const failure = classifyConnectorFailure(error, true);
    logError("connector accounts failed to load", error, { code: failure.code });
    for (const toolkit of permitted) markToolkitFailure(execution, toolkit, failure);
    return {
      tools: {},
      states: permitted.map((toolkit) => ({
        slug: toolkit.slug,
        title: toolkit.title,
        status: failure.status,
        logo: `https://logos.composio.dev/api/${toolkit.slug}`,
        detail: failure.detail,
        diagnosticCode: failure.code,
        lastCheckedAt: Date.now(),
        canReconnect: failure.status === "needs_attention",
        accounts: [],
      })),
      execution,
    };
  }

  const connected = permitted.filter(
    (toolkit) => states.find((state) => state.slug === toolkit.slug)?.status === "connected",
  );
  if (connected.length === 0) return { tools: {}, states, execution };

  let composio: Awaited<ReturnType<typeof getComposio>>;
  try {
    composio = await getComposio();
  } catch (error) {
    const failure = classifyConnectorFailure(error, true);
    connected.forEach((toolkit) => markToolkitFailure(execution, toolkit, failure));
    return { tools: {}, states, execution };
  }

  const toolsets = await Promise.all(
    connected.map(async (toolkit) => {
      const accounts = (states.find((state) => state.slug === toolkit.slug)?.accounts ?? []).filter(
        (account) => account.status === "connected",
      );
      try {
        const perAccount = await Promise.all(
          accounts.map(async (account, index) => {
            const returned = (await composio.tools.get(
              userId,
              {
                tools: [...toolkit.readTools],
              },
              {
                signal: connectorSignal(callbacks.signal),
                beforeExecute: ({ params }) => ({ ...params, connectedAccountId: account.id }),
              },
            )) as ToolSet;
            return accountTools(allowedToolkitTools(returned, toolkit), account, index, accounts);
          }),
        );
        const tools: ToolSet = Object.assign({}, ...perAccount);
        if (Object.keys(tools).length === 0) {
          markToolkitFailure(execution, toolkit, {
            status: "unavailable",
            code: "connector_tools_unavailable",
            detail: "Emblem could not load read access for this connection.",
          });
          return {};
        }
        instrumentConnectorTools(tools, [toolkit], callbacks, execution);
        return tools;
      } catch (error) {
        const failure = classifyConnectorFailure(error, true);
        logError("connector tools failed to load", error, {
          toolkit: toolkit.slug,
          code: failure.code,
        });
        markToolkitFailure(execution, toolkit, failure);
        return {};
      }
    }),
  );
  return { tools: Object.assign({}, ...toolsets), states, execution };
}

function toolResultStatus(value: unknown): "succeeded" | "empty" | "failed" {
  if (value == null) return "empty";
  if (Array.isArray(value)) return value.length === 0 ? "empty" : "succeeded";
  if (typeof value !== "object") return "succeeded";
  const record = value as Record<string, unknown>;
  if (record.successful === false) return "failed";
  const data =
    record.data && typeof record.data === "object"
      ? (record.data as Record<string, unknown>)
      : record;
  for (const key of ["items", "messages", "events", "threads"]) {
    if (Array.isArray(data[key])) return data[key].length === 0 ? "empty" : "succeeded";
  }
  return Object.keys(data).length === 0 ? "empty" : "succeeded";
}

export function connectorGuidance(states: ConnectorState[]): string {
  const connected = states.filter((state) => state.status === "connected");
  const disconnected = states.filter((state) => state.status === "disconnected");
  const unavailable = states.filter(
    (state) => state.status === "needs_attention" || state.status === "unavailable",
  );
  const lines: string[] = [];
  if (connected.length > 0) {
    lines.push(
      `The user has connected personal sources: ${connected.map((state) => state.title).join(", ")}. Use their read-only tools whenever the request involves the user's own email, schedule, or events.`,
    );
  }
  for (const state of connected) {
    const accounts = (state.accounts ?? []).filter((account) => account.status === "connected");
    if (accounts.length < 2) continue;
    lines.push(
      `${state.title} has ${accounts.length} connected accounts: ${accounts.map((account, index) => `${account.label} (tools${index === 0 ? " without a suffix" : ` ending __A${index + 1}`})`).join(", ")}. Read every account unless the user names one.`,
    );
  }
  if (disconnected.length > 0) {
    lines.push(
      `${disconnected.map((state) => state.title).join(", ")} ${disconnected.length === 1 ? "is" : "are"} not connected. Never state or imply that ${disconnected.length === 1 ? "it was" : "they were"} checked.`,
    );
  }
  if (unavailable.length > 0) {
    lines.push(
      `${unavailable.map((state) => state.title).join(", ")} cannot currently be read. If the request needs one of them, say that the connection ${unavailable.some((state) => state.status === "needs_attention") ? "needs attention" : "is temporarily unavailable"}. Never imply it was checked.`,
    );
  }
  return lines.length > 0 ? `\n\n${lines.join("\n")}` : "";
}
