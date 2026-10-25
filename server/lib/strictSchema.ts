export function strictSchemaFetch(rewrite: (schema: unknown) => void): typeof fetch {
  return async (input, init) => {
    if (typeof init?.body === "string") {
      try {
        const body = JSON.parse(init.body);
        const format =
          body?.text?.format?.type === "json_schema"
            ? body.text.format
            : body?.response_format?.json_schema;
        if (format?.schema) {
          format.strict = true;
          rewrite(format.schema);
          init = { ...init, body: JSON.stringify(body) };
        }
      } catch {}
    }
    return fetch(input, init);
  };
}

const OPENAI_SCHEMA_KEYS = new Set([
  "type",
  "properties",
  "required",
  "additionalProperties",
  "items",
  "anyOf",
  "enum",
  "const",
  "description",
  "$ref",
  "$defs",
  "minimum",
  "maximum",
  "exclusiveMinimum",
  "exclusiveMaximum",
  "multipleOf",
  "minItems",
  "maxItems",
  "format",
]);

const OPENAI_STRING_FORMATS = new Set([
  "date-time",
  "time",
  "date",
  "duration",
  "email",
  "hostname",
  "ipv4",
  "ipv6",
  "uuid",
]);

export function makeOpenAIStrictCompatible(node: unknown): void {
  if (Array.isArray(node)) {
    for (const item of node) makeOpenAIStrictCompatible(item);
    return;
  }
  if (!node || typeof node !== "object") return;
  const schema = node as Record<string, unknown>;
  if (schema.oneOf) {
    schema.anyOf = schema.oneOf;
    delete schema.oneOf;
  }
  if (typeof schema.format === "string" && !OPENAI_STRING_FORMATS.has(schema.format)) {
    delete schema.format;
  }
  for (const key of Object.keys(schema)) {
    if (!OPENAI_SCHEMA_KEYS.has(key)) delete schema[key];
  }
  if (schema.$defs && typeof schema.$defs === "object") {
    for (const child of Object.values(schema.$defs)) makeOpenAIStrictCompatible(child);
  }
  makeOpenAIStrictCompatible(schema.items);
  makeOpenAIStrictCompatible(schema.anyOf);
  const properties = schema.properties as Record<string, unknown> | undefined;
  if (schema.type !== "object" && !properties) return;
  schema.additionalProperties = false;
  const required = new Set(Array.isArray(schema.required) ? schema.required : []);
  for (const [name, child] of Object.entries(properties ?? {})) {
    makeOpenAIStrictCompatible(child);
    if (!required.has(name)) properties![name] = { anyOf: [child, { type: "null" }] };
  }
  schema.required = Object.keys(properties ?? {});
}

const rejectsSchema = new Set<string>();
const requiresReasoning = new Set<string>();

export function openRouterFetch(modelId: string): typeof fetch {
  const strict = strictSchemaFetch(makeOpenAIStrictCompatible);
  return async (input, init) => {
    for (;;) {
      const body = parseBody(init);
      if (!body) return strict(input, init);
      const reasoningOff = body.reasoning?.effort === "none";
      const schema = body.response_format?.json_schema;
      if (reasoningOff && requiresReasoning.has(modelId)) delete body.reasoning;
      if (schema?.schema && rejectsSchema.has(modelId)) putSchemaInPrompt(body, schema);
      const response = await strict(input, { ...init, body: JSON.stringify(body) });
      if (response.status !== 400) return response;
      const reason = await response.clone().text();
      if (reasoningOff && !requiresReasoning.has(modelId) && /reasoning/i.test(reason)) {
        requiresReasoning.add(modelId);
      } else if (schema?.schema && !rejectsSchema.has(modelId)) {
        rejectsSchema.add(modelId);
      } else {
        return response;
      }
    }
  };
}

function parseBody(init: RequestInit | undefined) {
  if (typeof init?.body !== "string") return undefined;
  try {
    return JSON.parse(init.body);
  } catch {
    return undefined;
  }
}

function putSchemaInPrompt(
  body: { messages?: { role?: string; content?: unknown }[]; response_format?: unknown },
  format: { name?: string; schema: unknown },
) {
  makeOpenAIStrictCompatible(format.schema);
  const instruction = `Respond with only a JSON object named ${JSON.stringify(format.name ?? "output")} that matches this JSON Schema:\n${JSON.stringify(format.schema)}`;
  const system = body.messages?.find((message) => message.role === "system");
  if (system && typeof system.content === "string") system.content += `\n\n${instruction}`;
  else body.messages = [{ role: "system", content: instruction }, ...(body.messages ?? [])];
  body.response_format = { type: "json_object" };
}
