import { syncConversationSummary } from "../../convex/conversations";
import type { Doc, Id } from "../../convex/_generated/dataModel";
import type { MutationCtx } from "../../convex/_generated/server";

type NewPage = Omit<Doc<"pages">, "_id" | "_creationTime">;

export async function insertPage(ctx: MutationCtx, page: NewPage): Promise<Id<"pages">> {
  const id = await ctx.db.insert("pages", page);
  await syncConversationSummary(ctx, (await ctx.db.get(id))!);
  return id;
}
