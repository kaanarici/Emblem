import { mutation } from "./_generated/server";
import { v } from "convex/values";
import { ownerIdentity } from "./ownership";

export const ensure = mutation({
  args: {},
  returns: v.union(
    v.null(),
    v.object({
      tokenIdentifier: v.string(),
      name: v.optional(v.string()),
      email: v.optional(v.string()),
      imageUrl: v.optional(v.string()),
    }),
  ),
  handler: async (ctx) => {
    const identity = await ownerIdentity(ctx);
    if (!identity) return null;

    const profile = {
      tokenIdentifier: identity.tokenIdentifier,
      name: identity.name,
      email: identity.email,
      imageUrl: identity.pictureUrl,
    };

    const existing = await ctx.db
      .query("users")
      .withIndex("by_tokenIdentifier", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();

    if (!existing) {
      await ctx.db.insert("users", profile);
    } else if (
      existing.name !== profile.name ||
      existing.email !== profile.email ||
      existing.imageUrl !== profile.imageUrl
    ) {
      await ctx.db.patch("users", existing._id, profile);
    }

    return profile;
  },
});
