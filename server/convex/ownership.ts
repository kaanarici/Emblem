import { ownerScopeInput, sha256Hex } from "../lib/signing";
import type { MutationCtx, QueryCtx } from "./_generated/server";

export async function ownerIdentity(ctx: QueryCtx) {
  const identity = await ctx.auth.getUserIdentity();
  if (identity && (await isOwnerErased(ctx, identity.tokenIdentifier))) {
    throw new Error("account erased");
  }
  return identity;
}

export async function ownerKey(ctx: QueryCtx): Promise<string | null> {
  return (await ownerIdentity(ctx))?.tokenIdentifier ?? null;
}

export async function requireOwnerKey(ctx: QueryCtx): Promise<string> {
  const owner = await ownerKey(ctx);
  if (!owner) throw new Error("authentication required");
  return owner;
}

export async function ownerScopeHash(owner: string): Promise<string> {
  return await sha256Hex(ownerScopeInput(owner));
}

export async function isScopeErased(ctx: Pick<QueryCtx, "db">, scope: string): Promise<boolean> {
  return (
    (await ctx.db
      .query("ownerErasures")
      .withIndex("by_ownerScopeHash", (q) => q.eq("ownerScopeHash", scope))
      .first()) !== null
  );
}

export async function isOwnerErased(ctx: Pick<QueryCtx, "db">, owner: string): Promise<boolean> {
  return await isScopeErased(ctx, await ownerScopeHash(owner));
}

export async function fenceOwnerWrites(ctx: MutationCtx, owner: string): Promise<string> {
  const scope = await ownerScopeHash(owner);
  if (!(await isScopeErased(ctx, scope))) {
    await ctx.db.insert("ownerErasures", { ownerScopeHash: scope });
  }
  return scope;
}
