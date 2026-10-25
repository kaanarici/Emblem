import { ownerKey } from "./ownership";
import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import {
  MAX_PROFILE_FIELD_CHARS,
  MAX_PROFILE_INSTRUCTION_CHARS,
  type UserProfile,
} from "../lib/memoryPolicy";

const profileValidator = v.object({
  nickname: v.optional(v.string()),
  occupation: v.optional(v.string()),
  about: v.optional(v.string()),
  instructions: v.optional(v.string()),
  memoryEnabled: v.optional(v.boolean()),
});

function normalize(profile: UserProfile): UserProfile {
  const clip = (value: string | undefined, max: number) => {
    const trimmed = value?.trim();
    return trimmed ? trimmed.slice(0, max) : undefined;
  };
  return {
    nickname: clip(profile.nickname, MAX_PROFILE_FIELD_CHARS),
    occupation: clip(profile.occupation, MAX_PROFILE_FIELD_CHARS),
    about: clip(profile.about, MAX_PROFILE_FIELD_CHARS),
    instructions: clip(profile.instructions, MAX_PROFILE_INSTRUCTION_CHARS),
    memoryEnabled: profile.memoryEnabled,
  };
}

export const get = query({
  args: {},
  returns: v.union(v.null(), profileValidator),
  handler: async (ctx) => {
    const owner = await ownerKey(ctx);
    if (!owner) return null;
    const row = await ctx.db
      .query("profiles")
      .withIndex("by_ownerKey", (q) => q.eq("ownerKey", owner))
      .unique();
    if (!row) return null;
    return {
      nickname: row.nickname,
      occupation: row.occupation,
      about: row.about,
      instructions: row.instructions,
      memoryEnabled: row.memoryEnabled,
    };
  },
});

export const save = mutation({
  args: { profile: profileValidator },
  returns: v.union(v.null(), profileValidator),
  handler: async (ctx, args) => {
    const owner = await ownerKey(ctx);
    if (!owner) return null;
    const fields = normalize(args.profile);
    const existing = await ctx.db
      .query("profiles")
      .withIndex("by_ownerKey", (q) => q.eq("ownerKey", owner))
      .unique();
    if (existing) {
      await ctx.db.replace("profiles", existing._id, {
        ownerKey: owner,
        ...fields,
        updatedAt: Date.now(),
      });
    } else {
      await ctx.db.insert("profiles", {
        ownerKey: owner,
        ...fields,
        updatedAt: Date.now(),
      });
    }
    return fields;
  },
});
