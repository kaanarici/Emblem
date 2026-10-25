import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { action, internalMutation, internalQuery, query } from "./_generated/server";
import type { MutationCtx } from "./_generated/server";
import { constantTimeEqual, hmacHex, sha256Hex } from "../lib/signing";
import { isScopeErased } from "./ownership";
import { hasExpectedMagicBytes, MAX_IMAGE_BYTES } from "../lib/imageBytes";

const HEX_64 = /^[a-f0-9]{64}$/;
const BASE64 = /^[A-Za-z0-9+/]*={0,2}$/;
const mimeType = v.union(v.literal("image/png"), v.literal("image/jpeg"), v.literal("image/webp"));
const storedImage = v.object({
  url: v.string(),
  mimeType,
  byteLength: v.number(),
});

export const get = query({
  args: {
    key: v.string(),
    ownerScopeHash: v.optional(v.string()),
    readGrant: v.optional(v.string()),
  },
  returns: v.union(storedImage, v.null()),
  handler: async (ctx, args) => {
    if (!HEX_64.test(args.key)) return null;
    const secret = process.env.GENERATED_STEP_IMAGE_STORAGE_SECRET;
    if (
      !secret ||
      !args.readGrant ||
      !constantTimeEqual(
        await hmacHex(
          secret,
          ["read-generated-image-v1", args.key, args.ownerScopeHash ?? ""].join("\0"),
        ),
        args.readGrant,
      )
    )
      return null;
    const row = await ctx.db
      .query("generatedImages")
      .withIndex("by_key", (q) => q.eq("key", args.key))
      .first();
    if (
      !row ||
      (args.ownerScopeHash !== undefined && row.ownerScopeHash !== args.ownerScopeHash) ||
      (row.ownerScopeHash && (await isScopeErased(ctx, row.ownerScopeHash)))
    )
      return null;
    const url = await ctx.storage.getUrl(row.storageId);
    return url
      ? {
          url,
          mimeType: row.mimeType,
          byteLength: row.byteLength,
        }
      : null;
  },
});

export const getInternal = internalQuery({
  args: { key: v.string(), ownerScopeHash: v.string() },
  returns: v.union(
    v.object({
      storageId: v.id("_storage"),
      mimeType,
      byteLength: v.number(),
    }),
    v.null(),
  ),
  handler: async (ctx, args) => {
    if (await isScopeErased(ctx, args.ownerScopeHash)) {
      throw new Error("generated image owner erased");
    }
    const row = await ctx.db
      .query("generatedImages")
      .withIndex("by_key", (q) => q.eq("key", args.key))
      .first();
    if (row && row.ownerScopeHash !== args.ownerScopeHash) {
      throw new Error("generated image ownership mismatch");
    }
    return row
      ? {
          storageId: row.storageId,
          mimeType: row.mimeType,
          byteLength: row.byteLength,
        }
      : null;
  },
});

async function discardUnreferenced(ctx: MutationCtx, storageId: Id<"_storage">) {
  const reference = await ctx.db
    .query("generatedImages")
    .withIndex("by_storageId", (q) => q.eq("storageId", storageId))
    .first();
  if (!reference) await ctx.storage.delete(storageId);
}

export const commit = internalMutation({
  args: {
    key: v.string(),
    ownerScopeHash: v.string(),
    storageId: v.id("_storage"),
    mimeType,
    byteLength: v.number(),
  },
  returns: v.union(
    v.object({
      inserted: v.boolean(),
      storageId: v.id("_storage"),
    }),
    v.null(),
  ),
  handler: async (ctx, args) => {
    const file = await ctx.db.system.get("_storage", args.storageId);
    if (!file) throw new Error("generated image storage unavailable");
    if (
      file.size !== args.byteLength ||
      (file.contentType !== undefined && file.contentType !== args.mimeType)
    ) {
      throw new Error("generated image storage metadata mismatch");
    }
    const existing = await ctx.db
      .query("generatedImages")
      .withIndex("by_key", (q) => q.eq("key", args.key))
      .first();
    if (
      (await isScopeErased(ctx, args.ownerScopeHash)) ||
      (existing && existing.ownerScopeHash !== args.ownerScopeHash)
    ) {
      await discardUnreferenced(ctx, args.storageId);
      return null;
    }
    if (existing) {
      if (!(await ctx.db.system.get("_storage", existing.storageId))) {
        throw new Error("generated image storage unavailable");
      }
      if (existing.storageId !== args.storageId) await discardUnreferenced(ctx, args.storageId);
      return { inserted: false, storageId: existing.storageId };
    }
    await ctx.db.insert("generatedImages", {
      key: args.key,
      ownerScopeHash: args.ownerScopeHash,
      storageId: args.storageId,
      mimeType: args.mimeType,
      byteLength: args.byteLength,
      createdAt: Date.now(),
    });
    return { inserted: true, storageId: args.storageId };
  },
});

export const store = action({
  args: {
    key: v.string(),
    ownerScopeHash: v.string(),
    mimeType,
    byteLength: v.number(),
    digest: v.string(),
    data: v.string(),
    writeGrant: v.string(),
  },
  returns: v.object({
    storageId: v.id("_storage"),
    inserted: v.boolean(),
  }),
  handler: async (
    ctx,
    args,
  ): Promise<{
    storageId: Id<"_storage">;
    inserted: boolean;
  }> => {
    const secret = process.env.GENERATED_STEP_IMAGE_STORAGE_SECRET;
    if (!secret) throw new Error("generated image storage is not configured");
    if (
      (!HEX_64.test(args.ownerScopeHash) && args.ownerScopeHash !== "shared") ||
      !HEX_64.test(args.key) ||
      !HEX_64.test(args.digest) ||
      !HEX_64.test(args.writeGrant) ||
      !Number.isSafeInteger(args.byteLength) ||
      args.byteLength <= 0 ||
      args.byteLength > MAX_IMAGE_BYTES
    ) {
      throw new Error("invalid generated image upload");
    }
    const payload = [
      "write-generated-image-v2",
      args.ownerScopeHash,
      args.key,
      args.mimeType,
      String(args.byteLength),
      args.digest,
    ].join("\0");
    const expectedGrant = await hmacHex(secret, payload);
    if (!constantTimeEqual(expectedGrant, args.writeGrant)) {
      throw new Error("unauthorized generated image upload");
    }

    const existing = await ctx.runQuery(internal.generatedImages.getInternal, {
      key: args.key,
      ownerScopeHash: args.ownerScopeHash,
    });
    if (existing) {
      return { storageId: existing.storageId, inserted: false };
    }

    if (args.data.length > Math.ceil((MAX_IMAGE_BYTES * 4) / 3) + 4 || !BASE64.test(args.data)) {
      throw new Error("invalid generated image payload");
    }
    const bytes = decodeBase64(args.data);
    if (bytes.byteLength !== args.byteLength || !hasExpectedMagicBytes(bytes, args.mimeType)) {
      throw new Error("invalid generated image bytes");
    }
    const digest = await sha256Hex(bytes);
    if (!constantTimeEqual(digest, args.digest)) {
      throw new Error("generated image digest mismatch");
    }

    const body = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(body).set(bytes);
    const storageId = await ctx.storage.store(new Blob([body], { type: args.mimeType }));
    const committed = await ctx.runMutation(internal.generatedImages.commit, {
      key: args.key,
      ownerScopeHash: args.ownerScopeHash,
      storageId,
      mimeType: args.mimeType,
      byteLength: args.byteLength,
    });
    if (!committed) throw new Error("generated image owner unavailable");
    return committed;
  },
});

function decodeBase64(value: string): Uint8Array {
  const decoded = atob(value);
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}
