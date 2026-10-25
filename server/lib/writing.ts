import { z } from "zod";

const draftSchema = z.object({
  id: z.string().trim().min(1).max(100),
  label: z.string().trim().min(1).max(40),
  sym: z.string().trim().min(1).max(80).optional(),
  body: z
    .string()
    .min(1)
    .max(20000)
    .refine((body) => body.trim().length > 0, "draft must contain text")
    .describe("complete plain-text draft, using paragraph breaks rather than Markdown formatting"),
});

export const writingDraftsSchema = z
  .array(draftSchema)
  .min(1)
  .max(5)
  .refine(
    (drafts) => new Set(drafts.map((draft) => draft.id)).size === drafts.length,
    "draft ids must be unique",
  );

export const rewriteSchema = z.object({
  body: z.string().trim().min(1).max(20000),
  style: z.enum(["bolder", "crisper", "playful", "shorter", "casual", "direct"]),
});

export const draftUpdateSchema = z.object({
  conversationKey: z.string().trim().min(1).max(200),
  pageKey: z.string().trim().min(1).max(200),
  blockID: z.string().trim().min(1).max(200),
  draftID: z.string().trim().min(1).max(100),
  previousBody: z.string().max(20000),
  body: z
    .string()
    .min(1)
    .max(20000)
    .refine((body) => body.trim().length > 0, "draft must contain text"),
});

export function replaceDraft(blocks: unknown, update: z.infer<typeof draftUpdateSchema>) {
  if (!Array.isArray(blocks)) throw new Error("invalid page");
  const index = blocks.findIndex(
    (block) => block?.type === "writing" && block?.id === update.blockID,
  );
  if (index < 0) throw new Error("draft not found");
  const drafts = writingDraftsSchema.parse(blocks[index].drafts);
  const draft = drafts.find((draft) => draft.id === update.draftID);
  if (!draft) throw new Error("draft not found");
  if (draft.body !== update.body && draft.body !== update.previousBody) return null;
  draft.body = update.body;
  return blocks.map((block, position) => (position === index ? { ...block, drafts } : block));
}
