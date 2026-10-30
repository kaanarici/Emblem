import { createCerebras } from "@ai-sdk/cerebras";
import { createGoogleGenerativeAI } from "@ai-sdk/google";
import { createGroq } from "@ai-sdk/groq";
import { createOpenAI } from "@ai-sdk/openai";
import { createOpenAICompatible } from "@ai-sdk/openai-compatible";
import { defaultSettingsMiddleware, wrapLanguageModel, type LanguageModel } from "ai";
import { makeOpenAIStrictCompatible, openRouterFetch, strictSchemaFetch } from "./strictSchema";

export const MANAGED_LUNA = "openai/gpt-6-luna";
export const DEFAULT_MODELS = {
  cerebras: "qwen-3.8-27b",
  google: "gemini-3.5-flash-lite",
  groq: "openai/gpt-oss-120b",
  openai: "gpt-6-luna",
  openrouter: MANAGED_LUNA,
  modelgo: "",
} as const;

type PlatformProvider = keyof typeof DEFAULT_MODELS;
type PlatformTarget = { provider: PlatformProvider; modelId: string };

export type InferenceRole = "research" | "compose";
export type InferenceTarget = {
  readonly provider: PlatformProvider | "openrouter";
  readonly modelId: string;
  readonly credentialSource: "platform" | "user";
  readonly supportsImages: boolean;
};
export type InferenceProfile = {
  readonly research: InferenceTarget;
  readonly compose: InferenceTarget;
};
export type ResolvedInferenceProfile = {
  readonly profile: InferenceProfile;
  readonly models: Readonly<Record<InferenceRole, LanguageModel>>;
};

type ResolvedTarget = {
  target: InferenceTarget;
  model: LanguageModel;
};

export type UserInferenceCredential = {
  provider: "cerebras" | "openrouter" | "openai";
  modelId: string;
  apiKey: string;
};

const CREDENTIAL_ENV = {
  cerebras: "CEREBRAS_API_KEY",
  google: "GEMINI_API_KEY",
  groq: "GROQ_API_KEY",
  openai: "OPENAI_API_KEY",
  openrouter: "OPENROUTER_API_KEY",
  modelgo: "MODELGO_API_KEY",
} as const satisfies Record<InferenceTarget["provider"], string>;

const USER_SELECTABLE: readonly {
  readonly provider: UserInferenceCredential["provider"];
  readonly modelId: string;
  readonly supportsImages: boolean;
}[] = [
  { provider: "cerebras", modelId: DEFAULT_MODELS.cerebras, supportsImages: true },
  { provider: "openai", modelId: DEFAULT_MODELS.openai, supportsImages: true },
  { provider: "openrouter", modelId: "inception/mercury-3", supportsImages: false },
  { provider: "openrouter", modelId: MANAGED_LUNA, supportsImages: true },
];

export class InferenceConfigurationError extends Error {}
export class InferenceCapabilityError extends InferenceConfigurationError {}

type InferenceRequirements = {
  readonly images?: boolean;
  readonly managedModel?: string | null;
};

function languageModel(
  provider: InferenceTarget["provider"],
  modelId: string,
  apiKey: string = requireEnv(CREDENTIAL_ENV[provider]),
): LanguageModel {
  switch (provider) {
    case "cerebras":
      return createCerebras({ apiKey, fetch: cerebrasStrictFetch })(modelId);
    case "google":
      return createGoogleGenerativeAI({ apiKey })(modelId);
    case "groq":
      return createGroq({ apiKey })(modelId);
    case "openai":
      return openAIModel(modelId, apiKey);
    case "openrouter":
      return openRouterModel(modelId, apiKey);
    case "modelgo":
      return createOpenAICompatible({
        name: "modelgo",
        baseURL: "https://api.modelgo.ai/v1",
        apiKey,
        supportsStructuredOutputs: true,
        includeUsage: true,
        fetch: strictSchemaFetch(makeOpenAIStrictCompatible),
      }).chatModel(modelId);
  }
}

function isPlatformProvider(value: string): value is PlatformProvider {
  return Object.hasOwn(DEFAULT_MODELS, value);
}

function platformResearch(): PlatformTarget {
  const provider = optionalEnv("LLM_PROVIDER") ?? "cerebras";
  if (!isPlatformProvider(provider)) {
    throw new InferenceConfigurationError("LLM_PROVIDER is unsupported");
  }
  const modelId = optionalEnv("LLM_MODEL") ?? DEFAULT_MODELS[provider];
  if (!modelId) throw new InferenceConfigurationError("LLM_MODEL is required for ModelGo");
  if (modelId.length > 160) throw new InferenceConfigurationError("LLM_MODEL is too long");
  return { provider, modelId };
}

function platformCompose(research: PlatformTarget): PlatformTarget {
  const configured = optionalEnv("LLM_COMPOSE_MODEL");
  if (
    !configured &&
    (research.provider === "openai" ||
      research.provider === "openrouter" ||
      research.provider === "modelgo")
  ) {
    return research;
  }
  const model = configured ?? DEFAULT_MODELS.cerebras;
  if (model.length > 160) throw new InferenceConfigurationError("LLM_COMPOSE_MODEL is too long");
  for (const provider of ["google", "openai", "openrouter", "modelgo"] as const) {
    if (model.startsWith(`${provider}:`)) {
      const modelId = model.slice(provider.length + 1).trim();
      if (!modelId) throw new InferenceConfigurationError("Composition model id is missing");
      return { provider, modelId };
    }
  }
  return { provider: "cerebras", modelId: model };
}

function resolvePlatformTarget({ provider, modelId }: PlatformTarget): ResolvedTarget {
  return {
    target: {
      provider,
      modelId,
      credentialSource: "platform",
      supportsImages:
        provider === "google" ||
        ((provider === "cerebras" || provider === "openai" || provider === "openrouter") &&
          modelId === DEFAULT_MODELS[provider]),
    },
    model: languageModel(provider, modelId),
  };
}

export function platformCredentialEnv(): string[] {
  const research = platformResearch();
  const providers = [research.provider, platformCompose(research).provider];
  return [...new Set(providers.map((provider) => CREDENTIAL_ENV[provider]))];
}

export function resolveInferenceProfile(
  credential?: UserInferenceCredential,
  requirements: InferenceRequirements = {},
): ResolvedInferenceProfile {
  if (credential && requirements.managedModel) {
    throw new InferenceConfigurationError("Choose managed inference or your own key, not both");
  }
  const managedSelection = requirements.managedModel
    ? USER_SELECTABLE.find(
        (model) => model.provider === "openrouter" && model.modelId === requirements.managedModel,
      )
    : undefined;
  if (requirements.managedModel && !managedSelection) {
    throw new InferenceConfigurationError("Unsupported managed inference model");
  }
  let research: ResolvedTarget;
  let compose: ResolvedTarget;
  if (managedSelection) {
    research = compose = {
      target: { ...managedSelection, credentialSource: "platform" },
      model: languageModel("openrouter", managedSelection.modelId),
    };
  } else if (credential) {
    research = compose = resolveUserModel(credential);
  } else {
    const researchTarget = platformResearch();
    const composeTarget = platformCompose(researchTarget);
    research = resolvePlatformTarget(researchTarget);
    compose =
      composeTarget.provider === researchTarget.provider &&
      composeTarget.modelId === researchTarget.modelId
        ? research
        : resolvePlatformTarget(composeTarget);
  }
  for (const { target } of [research, compose]) {
    if (requirements.images && !target.supportsImages) {
      throw new InferenceCapabilityError(`${target.modelId} does not support image input`);
    }
  }
  return {
    profile: { research: research.target, compose: compose.target },
    models: { research: research.model, compose: compose.model },
  };
}

export function usesOpenAIStrictSchema(target: Pick<InferenceTarget, "provider" | "modelId">) {
  return (
    target.provider === "openai" ||
    target.provider === "openrouter" ||
    target.provider === "modelgo"
  );
}

export function getModel(): LanguageModel {
  return resolvePlatformTarget(platformResearch()).model;
}

export function userInferenceCredential(headers: Headers): UserInferenceCredential | undefined {
  const provider = headers.get("x-emblem-inference-provider")?.trim();
  const apiKey = headers.get("x-emblem-inference-key")?.trim();
  if (!provider && !apiKey) return undefined;
  if (!apiKey || apiKey.length > 512) {
    throw new InferenceConfigurationError("Invalid user inference API key");
  }
  if (provider !== "cerebras" && provider !== "openrouter" && provider !== "openai") {
    throw new InferenceConfigurationError("Unsupported user inference provider");
  }
  const requested = headers.get("x-emblem-inference-model")?.trim();
  const selected = requested
    ? USER_SELECTABLE.find((m) => m.provider === provider && m.modelId === requested)
    : USER_SELECTABLE.find((m) => m.provider === provider);
  if (!selected) {
    throw new InferenceConfigurationError("Unsupported user inference model");
  }
  return { provider, modelId: selected.modelId, apiKey };
}

function resolveUserModel({ provider, modelId, apiKey }: UserInferenceCredential): ResolvedTarget {
  const supportsImages =
    USER_SELECTABLE.find((m) => m.provider === provider && m.modelId === modelId)?.supportsImages ??
    false;
  return {
    target: { provider, modelId, credentialSource: "user", supportsImages },
    model: languageModel(provider, modelId, apiKey),
  };
}

const OPENAI_REASONING_EFFORTS = [
  "none",
  "minimal",
  "low",
  "medium",
  "high",
  "xhigh",
  "max",
] as const;
const OPENAI_REASONING_MODEL = /^(?:o\d|gpt-(?:[5-9]|\d{2,}))/;

function openAIReasoningEffort(): (typeof OPENAI_REASONING_EFFORTS)[number] {
  const configured = optionalEnv("OPENAI_REASONING_EFFORT") ?? "none";
  const effort = OPENAI_REASONING_EFFORTS.find((value) => value === configured);
  if (!effort) {
    throw new InferenceConfigurationError(
      `OPENAI_REASONING_EFFORT must be one of ${OPENAI_REASONING_EFFORTS.join(", ")}`,
    );
  }
  return effort;
}

function openAIModel(modelId: string, apiKey: string): LanguageModel {
  if (!modelId) throw new InferenceConfigurationError("OpenAI model id is missing");
  const model = createOpenAI({
    apiKey,
    fetch: strictSchemaFetch(makeOpenAIStrictCompatible),
  }).responses(modelId);
  return wrapLanguageModel({
    model,
    middleware: defaultSettingsMiddleware({
      settings: {
        providerOptions: {
          openai: OPENAI_REASONING_MODEL.test(modelId)
            ? {
                store: false,
                forceReasoning: true,
                reasoningEffort: openAIReasoningEffort(),
                reasoningSummary: null,
              }
            : { store: false },
        },
      },
    }),
  });
}

function openRouterModel(modelId: string, apiKey: string): LanguageModel {
  return createOpenAICompatible({
    name: "openrouter",
    baseURL: "https://openrouter.ai/api/v1",
    apiKey,
    supportsStructuredOutputs: true,
    includeUsage: true,
    fetch: openRouterFetch(modelId),
  }).chatModel(modelId);
}

const cerebrasStrictFetch: typeof fetch = async (input, init) => {
  if (init?.body && typeof init.body === "string") {
    try {
      const body = JSON.parse(init.body);
      let changed = false;
      if (body.model === DEFAULT_MODELS.cerebras && body.reasoning_effort == null) {
        body.reasoning_effort = "none";
        changed = true;
      }
      const jsonSchema = body?.response_format?.json_schema;
      if (jsonSchema?.schema) {
        jsonSchema.strict = true;
        makeCerebrasStrictCompatible(jsonSchema.schema);
        changed = true;
      }
      if (changed) init = { ...init, body: JSON.stringify(body) };
    } catch {}
  }
  return fetch(input, init);
};

const schemaMapKeys = new Set(["$defs", "dependentSchemas", "patternProperties", "properties"]);

export function makeCerebrasStrictCompatible(node: unknown): void {
  normalizeCerebrasSchema(node);
  compactCerebrasSchema(node);
}

function normalizeCerebrasSchema(node: unknown): void {
  if (Array.isArray(node)) {
    for (const item of node) normalizeCerebrasSchema(item);
    return;
  }
  if (node && typeof node === "object") {
    const obj = node as Record<string, unknown>;
    for (const key of [
      "$schema",
      "description",
      "title",
      "default",
      "examples",
      "minLength",
      "maxLength",
      "pattern",
      "format",
      "minItems",
      "maxItems",
    ]) {
      delete obj[key];
    }
    if (obj.oneOf) {
      obj.anyOf = obj.oneOf;
      delete obj.oneOf;
    }
    if ("const" in obj) {
      obj.enum = [obj.const];
      delete obj.const;
    }
    if (obj.type === "object") obj.additionalProperties = false;
    for (const [key, value] of Object.entries(obj)) {
      if (schemaMapKeys.has(key) && value && typeof value === "object") {
        for (const child of Object.values(value)) normalizeCerebrasSchema(child);
      } else {
        normalizeCerebrasSchema(value);
      }
    }
  }
}

function compactCerebrasSchema(node: unknown): void {
  if (!node || Array.isArray(node) || typeof node !== "object") return;
  const root = node as Record<string, unknown>;
  const occurrences = new Map<string, { count: number; schema: Record<string, unknown> }>();

  const collect = (value: unknown, isRoot = false) => {
    if (Array.isArray(value)) {
      for (const child of value) collect(child);
      return;
    }
    if (!value || typeof value !== "object") return;
    const schema = value as Record<string, unknown>;
    if (!isRoot && isReusableSchema(schema)) {
      const signature = JSON.stringify(schema);
      const occurrence = occurrences.get(signature);
      if (occurrence) occurrence.count += 1;
      else occurrences.set(signature, { count: 1, schema });
    }
    for (const child of Object.values(schema)) collect(child);
  };
  collect(root, true);

  const candidates = [...occurrences.entries()]
    .filter(
      ([signature, { count }]) =>
        count > 1 && (count - 1) * signature.length > signature.length + 100,
    )
    .sort((a, b) => b[0].length - a[0].length);
  if (candidates.length === 0) return;

  const definitions =
    root.$defs && typeof root.$defs === "object" ? (root.$defs as Record<string, unknown>) : {};
  root.$defs = definitions;

  candidates.forEach(([signature, { schema }], index) => {
    const name = `s${index}`;
    replaceMatchingSchema(root, signature, `#/$defs/${name}`);
    definitions[name] = schema;
  });
}

function isReusableSchema(schema: Record<string, unknown>): boolean {
  return (
    "type" in schema ||
    "anyOf" in schema ||
    "enum" in schema ||
    "items" in schema ||
    "properties" in schema
  );
}

function replaceMatchingSchema(value: unknown, signature: string, reference: string): void {
  if (Array.isArray(value)) {
    for (let index = 0; index < value.length; index += 1) {
      const child = value[index];
      if (child && typeof child === "object" && JSON.stringify(child) === signature) {
        value[index] = { $ref: reference };
      } else {
        replaceMatchingSchema(child, signature, reference);
      }
    }
    return;
  }
  if (!value || typeof value !== "object") return;
  const object = value as Record<string, unknown>;
  for (const [key, child] of Object.entries(object)) {
    if (key === "$defs") continue;
    if (child && typeof child === "object" && JSON.stringify(child) === signature) {
      object[key] = { $ref: reference };
    } else {
      replaceMatchingSchema(child, signature, reference);
    }
  }
  const definitions = object.$defs;
  if (definitions && typeof definitions === "object") {
    for (const child of Object.values(definitions)) {
      replaceMatchingSchema(child, signature, reference);
    }
  }
}

function requireEnv(name: string): string {
  const value = optionalEnv(name);
  if (!value) {
    throw new InferenceConfigurationError(`Missing ${name} in the environment`);
  }
  return value;
}

function optionalEnv(name: string): string | undefined {
  return process.env[name]?.trim() || undefined;
}
