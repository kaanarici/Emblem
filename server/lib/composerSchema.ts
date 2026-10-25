import { jsonSchema, zodSchema, type Schema } from "ai";
import { z } from "zod";
import { blockSchema, centerpieceBlockTypes, type Block } from "./schema";

type BlockType = Block["type"];

const compositionScaffold = [
  "pageMeta",
  "sectionHeader",
  "text",
] as const satisfies readonly BlockType[];

const COMPOSITION_ENVELOPE_TYPES: readonly BlockType[] = [
  ...new Set<BlockType>([...compositionScaffold, ...centerpieceBlockTypes]),
];

async function envelopeJSONSchema(
  base: Schema<Block>,
  extra: z.ZodType,
): Promise<Record<string, unknown>> {
  const full = structuredClone(await base.jsonSchema) as Record<string, unknown> & {
    oneOf?: unknown[];
  };
  full.oneOf = [...(full.oneOf ?? []), structuredClone(await zodSchema(extra).jsonSchema)];
  return full;
}

export function compositionEnvelopeSchema<Extra>(extra: z.ZodType<Extra>): Schema<Block | Extra> {
  const base = composerBlockSchema(new Set(COMPOSITION_ENVELOPE_TYPES));
  return jsonSchema<Block | Extra>(
    async () =>
      renameOneOfToAnyOf(await envelopeJSONSchema(base, extra)) as Awaited<
        Schema<Block | Extra>["jsonSchema"]
      >,
    {
      validate: async (value) => {
        const finish = await extra.safeParseAsync(value);
        if (finish.success) return { success: true, value: finish.data };
        const validated = await base.validate!(value);
        if (validated.success) return { success: true, value: validated.value };
        const repaired = repairComposerElement(value);
        if (repaired !== value) {
          const retried = await base.validate!(repaired);
          if (retried.success) return { success: true, value: retried.value };
        }
        return { success: false, error: validated.error };
      },
    },
  );
}

const ASPECT_ALIASES: Record<string, "square" | "portrait" | "landscape" | undefined> = {
  square: "square",
  portrait: "portrait",
  landscape: "landscape",
  wide: "landscape",
  poster: "portrait",
  tall: "portrait",
};

function repairComposerElement(value: unknown): unknown {
  if (!value || typeof value !== "object" || Array.isArray(value)) return value;
  let changed = false;
  const repairImages = (node: unknown): unknown => {
    if (Array.isArray(node)) return node.map(repairImages);
    if (!node || typeof node !== "object") return node;
    const entries = Object.entries(node as Record<string, unknown>).map(([key, child]) => [
      key,
      repairImages(child),
    ]);
    const object = Object.fromEntries(entries) as Record<string, unknown>;
    if (
      typeof object.query === "string" &&
      typeof object.kind === "string" &&
      "aspect" in object &&
      !["square", "portrait", "landscape"].includes(object.aspect as string)
    ) {
      changed = true;
      const alias =
        typeof object.aspect === "string"
          ? ASPECT_ALIASES[object.aspect.trim().toLowerCase()]
          : undefined;
      if (alias) object.aspect = alias;
      else delete object.aspect;
    }
    return object;
  };
  const block = repairImages(value) as Record<string, unknown>;
  if (typeof block.type === "string" && (typeof block.id !== "string" || !block.id.trim())) {
    changed = true;
    block.id =
      typeof block.id === "number"
        ? `${block.type}-${block.id}`
        : `${block.type}-${stableSuffix(block)}`;
  }
  return changed ? block : value;
}

function stableSuffix(value: unknown): string {
  let hash = 0;
  for (const char of JSON.stringify(value)) hash = (hash * 31 + char.charCodeAt(0)) | 0;
  return (hash >>> 0).toString(36);
}

export function isForeignComposerElement(value: unknown): boolean {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const type = (value as Record<string, unknown>).type;
  return (
    typeof type === "string" &&
    type !== "pageFinish" &&
    !(COMPOSITION_ENVELOPE_TYPES as readonly string[]).includes(type)
  );
}

export function withoutNulls(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(withoutNulls);
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.entries(value)
      .filter(([, child]) => child !== null)
      .map(([key, child]) => [key, withoutNulls(child)]),
  );
}

export function nullsAsOmitted<T>(schema: Schema<T>): Schema<T> {
  return jsonSchema<T>(async () => schema.jsonSchema, {
    validate: (value) => schema.validate!(withoutNulls(value)),
  });
}

export async function compositionEnvelopeTextCatalog<Extra>(
  extra: z.ZodType<Extra>,
): Promise<Awaited<Schema<Block | Extra>["jsonSchema"]>> {
  const base = composerBlockSchema(new Set(COMPOSITION_ENVELOPE_TYPES));
  return renameOneOfToAnyOf(await envelopeJSONSchema(base, extra), false, "google-text") as Awaited<
    Schema<Block | Extra>["jsonSchema"]
  >;
}

const PROVIDER_UNSUPPORTED_SCHEMA_KEYS = new Set([
  "$schema",
  "format",
  "pattern",
  "default",
  "minLength",
  "maxLength",
  "minItems",
  "maxItems",
]);

const GOOGLE_TEXT_VALIDATION_KEYS = new Set([
  "minItems",
  "maxItems",
  "minLength",
  "maxLength",
  "pattern",
  "format",
]);

function renameOneOfToAnyOf(
  node: unknown,
  isPropertiesMap = false,
  target: "provider" | "google-text" = "provider",
): unknown {
  if (Array.isArray(node)) return node.map((item) => renameOneOfToAnyOf(item, false, target));
  if (!node || typeof node !== "object") return node;
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(node)) {
    if (isPropertiesMap) {
      result[key] = renameOneOfToAnyOf(value, false, target);
      continue;
    }
    if (
      PROVIDER_UNSUPPORTED_SCHEMA_KEYS.has(key) &&
      !(target === "google-text" && GOOGLE_TEXT_VALIDATION_KEYS.has(key))
    )
      continue;
    result[key === "oneOf" ? "anyOf" : key] = renameOneOfToAnyOf(
      value,
      key === "properties",
      target,
    );
  }
  return result;
}

function composerBlockSchema(allowed: ReadonlySet<BlockType>): Schema<Block> {
  const canonical = zodSchema(blockSchema);
  return jsonSchema<Block>(
    async () => {
      const full = structuredClone(await canonical.jsonSchema) as Record<string, unknown> & {
        oneOf?: unknown[];
      };
      const branches = full.oneOf?.filter((branch) => {
        if (!branch || typeof branch !== "object") return false;
        const properties = (branch as { properties?: Record<string, unknown> }).properties;
        const discriminator = properties?.type;
        const type =
          discriminator && typeof discriminator === "object"
            ? (discriminator as { const?: unknown }).const
            : undefined;
        return typeof type === "string" && allowed.has(type as BlockType);
      });
      if (!branches || branches.length !== allowed.size) {
        throw new Error("Composition palette does not match the block catalog");
      }
      for (const branch of branches) {
        if (!branch || typeof branch !== "object") continue;
        const objectBranch = branch as {
          properties?: Record<string, unknown>;
          required?: string[];
        };
        const discriminator = objectBranch.properties?.type;
        const type =
          discriminator && typeof discriminator === "object"
            ? (discriminator as { const?: unknown }).const
            : undefined;
        if (!objectBranch.properties) continue;
        if (type === "pageMeta") {
          delete objectBranch.properties.dockAction;
          delete objectBranch.properties.savePresentation;
          objectBranch.required = objectBranch.required?.filter((key) => key !== "dockAction");
        } else if (type === "titleBlock") {
          delete objectBranch.properties.icon;
          objectBranch.required = objectBranch.required?.filter((key) => key !== "icon");
          objectBranch.properties.actions = {
            type: "array",
            maxItems: 2,
            description:
              "0-2 verified link pills beneath the title. Include when requested; independent of the dock primary action. Copy exact URLs from the user or successful research.",
            items: {
              type: "object",
              properties: {
                label: { type: "string", description: "1-2 words ('Watch', 'Official site')" },
                url: { type: "string", description: "exact verified HTTP(S) URL" },
              },
              required: ["label", "url"],
              additionalProperties: false,
            },
          };
        } else if (type === "hero") {
          delete objectBranch.properties.imageURL;
        } else if (type === "cardCarousel") {
          objectBranch.required = [
            ...new Set([...(objectBranch.required ?? []), "layout", "presentation"]),
          ];
          (objectBranch.properties.layout as { description?: string }).description =
            "Choose rail for horizontal browsing or grid for a two-column wall. Emit before cards.";
          (objectBranch.properties.presentation as { description?: string }).description =
            "Choose standard for copy below art, poster for overlay copy, or paged for full-width centered cards with tags and dots (rail only). Emit before cards.";
          (objectBranch.properties.presentation as { enum?: string[] }).enum = [
            "standard",
            "poster",
            "paged",
          ];
          const cardProperties = nestedArrayProperties(objectBranch.properties.cards);

          for (const key of [
            "imageURL",
            "resourceID",
            "saveCategory",
            "prompt",
            "conversation",
            "automation",
            "preview",
          ]) {
            delete cardProperties?.[key];
          }
        } else if (type === "questionList") {
          const input = nestedArrayProperties(objectBranch.properties.items)?.input as
            { properties?: Record<string, unknown> } | undefined;
          delete input?.properties?.look;
        } else if (type === "photoGrid") {
          delete objectBranch.properties.presentation;
        } else if (type === "stepCarousel") {
          const stepProperties = nestedArrayProperties(objectBranch.properties.steps);
          delete stepProperties?.imageURL;
        } else if (type === "statRow") {
          const statProperties = nestedArrayProperties(objectBranch.properties.stats);
          delete statProperties?.deltaDirection;
        } else if (type === "spotList") {
          const spotProperties = nestedArrayProperties(objectBranch.properties.spots);
          delete spotProperties?.imageURL;
        } else if (type === "sideBySide") {
          delete nestedArrayProperties(objectBranch.properties.entities)?.imageURL;
        } else if (type === "oneAgainstMany") {
          const anchor = objectBranch.properties.anchor as
            { properties?: Record<string, unknown> } | undefined;
          delete anchor?.properties?.imageURL;
          delete nestedArrayProperties(objectBranch.properties.challengers)?.imageURL;
        } else if (type === "mediaRowList") {
          const rowProperties = nestedArrayProperties(objectBranch.properties.rows);
          if (rowProperties) {
            rowProperties.action = {
              type: "object",
              description:
                "verified destination button; url is copied EXACTLY from a research result, never invented",
              properties: {
                label: {
                  type: "string",
                  description: "1-2 words ('Watch', 'Open', 'Book')",
                },
                url: { type: "string", description: "exact HTTP(S) URL from research" },
              },
              required: ["label", "url"],
              additionalProperties: false,
            };
          }
        } else if (type === "map") {
          const placeProperties = nestedArrayProperties(objectBranch.properties.places);
          for (const key of ["lat", "lng", "address"]) delete placeProperties?.[key];
        } else if (type === "eventCard") {
          delete nestedArrayProperties(objectBranch.properties.events)?.prompt;
        } else if (type === "music") {
          const trackProperties = nestedArrayProperties(objectBranch.properties.tracks);
          for (const key of ["album", "art", "preview", "url"]) delete trackProperties?.[key];
        }
      }
      return compactImageGrammar({ ...full, oneOf: branches }) as Awaited<
        Schema<Block>["jsonSchema"]
      >;
    },
    {
      validate: async (value) => {
        const parsed = await blockSchema.safeParseAsync(value);
        if (!parsed.success) return { success: false, error: parsed.error };
        if (!allowed.has(parsed.data.type)) {
          return {
            success: false,
            error: new Error(`Block type ${parsed.data.type} is outside the response plan`),
          };
        }
        if (hasComposerExecutable(parsed.data)) {
          return {
            success: false,
            error: new Error("Executable destinations are server-owned"),
          };
        }
        return { success: true, value: parsed.data };
      },
    },
  );
}

const ICON_IMAGE_KINDS = ["object", "photo", "logo"] as const;
const COMPOSED_IMAGE_KINDS = ["poster", "still", "logo", "photo", "object"] as const;

const compactIconImage = {
  type: "object",
  description: "object: simple physical noun; photo: exact place; logo: exact brand",
  properties: {
    query: { type: "string" },
    kind: { type: "string", enum: [...ICON_IMAGE_KINDS] },
  },
  required: ["query", "kind"],
  additionalProperties: false,
};

function isPropertySet(node: Record<string, unknown>, names: readonly string[]): boolean {
  const properties = node.properties;
  if (!properties || typeof properties !== "object") return false;
  const keys = Object.keys(properties);
  return keys.length === names.length && names.every((name) => keys.includes(name));
}

function compactImageGrammar(node: unknown): unknown {
  if (Array.isArray(node)) return node.map(compactImageGrammar);
  if (!node || typeof node !== "object") return node;
  const result = Object.fromEntries(
    Object.entries(node).map(([key, value]) => [key, compactImageGrammar(value)]),
  ) as Record<string, unknown>;
  if (isPropertySet(result, ["emoji", "sym", "image"])) {
    const properties = result.properties as Record<string, unknown>;
    result.properties = { ...properties, image: compactIconImage };
  } else if (isPropertySet(result, ["query", "kind", "aspect"])) {
    const properties = result.properties as Record<string, Record<string, unknown>>;
    const { $ref: _ref, enum: _enum, ...kind } = properties.kind ?? {};
    result.properties = {
      ...properties,
      kind: { ...kind, type: "string", enum: [...COMPOSED_IMAGE_KINDS] },
    };
  }
  return result;
}

function nestedArrayProperties(value: unknown): Record<string, unknown> | undefined {
  if (!value || typeof value !== "object") return undefined;
  const items = (value as { items?: unknown }).items;
  if (!items || typeof items !== "object") return undefined;
  return (items as { properties?: Record<string, unknown> }).properties;
}

function hasComposerExecutable(block: Block): boolean {
  switch (block.type) {
    case "pageMeta":
      return block.dockAction != null || block.savePresentation != null;
    case "titleBlock":
      return block.icon != null || (block.actions?.some((action) => action.url == null) ?? false);
    case "hero":
      return block.imageURL != null;
    case "cardCarousel":
      return (
        block.presentation === "hotelRail" ||
        block.presentation === "hotelList" ||
        block.presentation === "roomGrid" ||
        block.presentation === "roomList" ||
        block.cards.some(
          (card) =>
            card.imageURL != null ||
            card.resourceID != null ||
            card.saveCategory != null ||
            card.prompt != null ||
            card.conversation != null ||
            card.automation != null,
        )
      );
    case "photoGrid":
      return block.presentation != null;
    case "mediaRowList":
      return block.rows.some((row) => row.action != null && row.action.url == null);
    case "eventCard":
      return block.events.some((event) => event.prompt != null);
    case "music":
      return block.tracks.some(
        (track) =>
          track.album != null || track.art != null || track.preview != null || track.url != null,
      );
    default:
      return false;
  }
}
