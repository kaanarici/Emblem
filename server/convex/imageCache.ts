import { action, internalMutation, query } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";
import { constantTimeEqual, hmacHex } from "../lib/signing";

const IMAGE_CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const PURGE_BATCH = 200;
const HEX_64 = /^[a-f0-9]{64}$/;
const MAX_KEY_LENGTH = 512;
const MAX_URL_LENGTH = 2048;
const MAX_SOURCE_LENGTH = 64;

export const get = query({
  args: { key: v.string(), now: v.number() },
  returns: v.union(v.null(), v.object({ url: v.string(), source: v.string() })),
  handler: async (ctx, args) => {
    const row = await ctx.db
      .query("imageCache")
      .withIndex("by_key", (q) => q.eq("key", args.key))
      .first();
    if (!row || row.createdAt <= args.now - IMAGE_CACHE_TTL_MS) return null;
    return { url: row.url, source: row.source };
  },
});

export const commit = internalMutation({
  args: { key: v.string(), url: v.string(), source: v.string() },
  returns: v.object({ inserted: v.boolean() }),
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("imageCache")
      .withIndex("by_key", (q) => q.eq("key", args.key))
      .first();
    const now = Date.now();
    if (existing && existing.createdAt > now - IMAGE_CACHE_TTL_MS) return { inserted: false };
    if (existing) await ctx.db.delete("imageCache", existing._id);
    await ctx.db.insert("imageCache", {
      key: args.key,
      url: args.url,
      source: args.source,
      createdAt: now,
    });
    return { inserted: true };
  },
});

export const purgeExpired = internalMutation({
  args: {},
  returns: v.object({ deleted: v.number(), more: v.boolean() }),
  handler: async (ctx) => {
    const expired = await ctx.db
      .query("imageCache")
      .withIndex("by_createdAt", (q) => q.lte("createdAt", Date.now() - IMAGE_CACHE_TTL_MS))
      .take(PURGE_BATCH + 1);
    const batch = expired.slice(0, PURGE_BATCH);
    for (const row of batch) await ctx.db.delete("imageCache", row._id);
    if (expired.length > PURGE_BATCH) {
      await ctx.scheduler.runAfter(0, internal.imageCache.purgeExpired, {});
    }
    return { deleted: batch.length, more: expired.length > PURGE_BATCH };
  },
});

function safeCacheURL(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password;
  } catch {
    return false;
  }
}

export const put = action({
  args: {
    key: v.string(),
    url: v.string(),
    source: v.string(),
    writeGrant: v.string(),
  },
  returns: v.object({ inserted: v.boolean() }),
  handler: async (ctx, args): Promise<{ inserted: boolean }> => {
    const secret = process.env.GENERATED_STEP_IMAGE_STORAGE_SECRET;
    if (!secret) throw new Error("image cache writes are not configured");
    if (
      !HEX_64.test(args.writeGrant) ||
      args.key.length === 0 ||
      args.key.length > MAX_KEY_LENGTH ||
      args.source.length === 0 ||
      args.source.length > MAX_SOURCE_LENGTH ||
      args.url.length > MAX_URL_LENGTH ||
      !safeCacheURL(args.url)
    ) {
      throw new Error("invalid image cache entry");
    }
    const expected = await hmacHex(secret, [args.key, args.url, args.source].join("\0"));
    if (!constantTimeEqual(expected, args.writeGrant)) {
      throw new Error("unauthorized image cache write");
    }
    return ctx.runMutation(internal.imageCache.commit, {
      key: args.key,
      url: args.url,
      source: args.source,
    });
  },
});
