import { createHash, createHmac } from "node:crypto";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../convex/_generated/api";
import schema from "../convex/schema";
import {
  generatedStepImageStore,
  prepareGeneratedStepImages,
  resolveGeneratedStepImageQuery,
} from "../lib/generatedStepImages";

const calls = vi.hoisted(() => ({ query: vi.fn(), action: vi.fn() }));
vi.mock("convex/browser", () => ({
  ConvexHttpClient: class {
    query = calls.query;
    action = calls.action;
  },
}));
const modules = import.meta.glob("../convex/**/*.ts");
const SECRET = "test-generated-image-storage-secret";
const bytes = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const aliceIdentity = {
  issuer: "https://images-test.invalid",
  subject: "alice",
  tokenIdentifier: "https://images-test.invalid|alice",
};
const scope = (owner: string) =>
  createHash("sha256").update(`owner-scope-v1\0${owner}`).digest("hex");
const aliceScope = scope(aliceIdentity.tokenIdentifier);
const bobScope = scope("https://images-test.invalid|bob");
const sign = (fields: string[]) =>
  createHmac("sha256", SECRET).update(fields.join("\0")).digest("hex");
function upload(key = "a".repeat(64), ownerScopeHash = aliceScope) {
  const digest = createHash("sha256").update(bytes).digest("hex");
  return {
    key,
    ownerScopeHash,
    mimeType: "image/png" as const,
    byteLength: bytes.byteLength,
    digest,
    data: Buffer.from(bytes).toString("base64"),
    writeGrant: sign([
      "write-generated-image-v2",
      ownerScopeHash,
      key,
      "image/png",
      String(bytes.byteLength),
      digest,
    ]),
  };
}
function read(key: string, ownerScopeHash?: string) {
  return {
    key,
    ...(ownerScopeHash === undefined ? {} : { ownerScopeHash }),
    readGrant: sign(["read-generated-image-v1", key, ownerScopeHash ?? ""]),
  };
}

beforeEach(() => vi.stubEnv("GENERATED_STEP_IMAGE_STORAGE_SECRET", SECRET));
afterEach(() => {
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
});

describe("generated image ownership and storage", () => {
  it("binds every upload field to its grant, stamps ownership, and deduplicates bytes", async () => {
    const t = convexTest(schema, modules);
    const args = upload();
    for (const changed of [
      { writeGrant: "0".repeat(64) },
      { ownerScopeHash: bobScope },
      { ownerScopeHash: "shared" },
      { key: "b".repeat(64) },
      { mimeType: "image/jpeg" as const },
      { byteLength: 9 },
      { digest: "c".repeat(64) },
    ]) {
      await expect(t.action(api.generatedImages.store, { ...args, ...changed })).rejects.toThrow(
        "unauthorized generated image upload",
      );
    }
    await expect(t.action(api.generatedImages.store, { ...args, data: "eA==" })).rejects.toThrow(
      "invalid generated image bytes",
    );
    const result = await t.action(api.generatedImages.store, args);
    expect(result.inserted).toBe(true);
    expect(await t.run((ctx) => ctx.db.query("generatedImages").first())).toMatchObject({
      ownerScopeHash: aliceScope,
    });
    expect(await t.action(api.generatedImages.store, args)).toEqual({ ...result, inserted: false });
    expect(await t.run((ctx) => ctx.db.system.query("_storage").collect())).toHaveLength(1);
    expect(await t.query(api.generatedImages.get, read(args.key, aliceScope))).toMatchObject({
      mimeType: "image/png",
      byteLength: 8,
    });
  });

  it("denies unsigned reads, tampered read scope, cross-owner reads and cross-owner key reuse", async () => {
    const t = convexTest(schema, modules);
    const args = upload();
    await t.action(api.generatedImages.store, args);
    expect(await t.query(api.generatedImages.get, { key: args.key })).toBeNull();
    expect(
      await t.query(api.generatedImages.get, {
        ...read(args.key, aliceScope),
        ownerScopeHash: bobScope,
      }),
    ).toBeNull();
    expect(await t.query(api.generatedImages.get, read(args.key, bobScope))).toBeNull();
    await expect(t.action(api.generatedImages.store, upload(args.key, bobScope))).rejects.toThrow(
      "ownership mismatch",
    );
    await expect(
      t.query(internal.generatedImages.getInternal, { key: args.key, ownerScopeHash: bobScope }),
    ).rejects.toThrow("ownership mismatch");
    expect(await t.query(api.generatedImages.get, read(args.key))).not.toBeNull();
  });

  it("erases owned rows and blobs, preserves other/shared/legacy images, and rejects replay", async () => {
    const t = convexTest(schema, modules);
    const args = upload();
    const a = await t.action(api.generatedImages.store, args);
    const b = await t.action(api.generatedImages.store, upload("b".repeat(64), bobScope));
    const shared = await t.action(api.generatedImages.store, upload("c".repeat(64), "shared"));
    const legacy = await t.run(async (ctx) => {
      const storageId = await ctx.storage.store(new Blob([bytes]));
      const id = await ctx.db.insert("generatedImages", {
        key: "d".repeat(64),
        storageId,
        mimeType: "image/png",
        byteLength: 8,
        createdAt: 0,
      });
      return { id, storageId };
    });
    const alice = t.withIdentity(aliceIdentity);
    expect(await alice.query(api.accounts.purgeStatus, {})).toEqual({ done: false });
    expect(await alice.mutation(api.accounts.purgeSelf, {})).toEqual({ done: true, deleted: 1 });
    expect(await t.run((ctx) => ctx.storage.get(a.storageId))).toBeNull();
    expect(await t.query(api.generatedImages.get, read(args.key))).toBeNull();
    await expect(t.action(api.generatedImages.store, args)).rejects.toThrow("owner erased");
    expect(await alice.mutation(api.accounts.purgeSelf, {})).toEqual({ done: true, deleted: 0 });
    expect(await alice.query(api.accounts.purgeStatus, {})).toEqual({ done: true });
    for (const id of [b.storageId, shared.storageId, legacy.storageId]) {
      expect(await t.run(async (ctx) => (await ctx.storage.get(id)) !== null)).toBe(true);
    }
    expect(await t.run((ctx) => ctx.db.get(legacy.id))).not.toHaveProperty("ownerScopeHash");
    expect(await t.query(api.generatedImages.get, read("d".repeat(64)))).not.toBeNull();
    await expect(
      t.action(api.generatedImages.store, upload("d".repeat(64), bobScope)),
    ).rejects.toThrow("ownership mismatch");
    expect(await t.run((ctx) => ctx.db.query("ownerErasures").collect())).toEqual([
      expect.objectContaining({ ownerScopeHash: aliceScope }),
    ]);
  });

  it("deletes a late callback blob inside the commit transaction after erasure", async () => {
    const t = convexTest(schema, modules);
    const args = upload();
    expect(
      await t.query(internal.generatedImages.getInternal, {
        key: args.key,
        ownerScopeHash: aliceScope,
      }),
    ).toBeNull();
    const storageId = await t.run((ctx) => ctx.storage.store(new Blob([bytes])));
    await t.withIdentity(aliceIdentity).mutation(api.accounts.purgeSelf, {});
    expect(
      await t.mutation(internal.generatedImages.commit, {
        key: args.key,
        ownerScopeHash: aliceScope,
        storageId,
        mimeType: "image/png",
        byteLength: 8,
      }),
    ).toBeNull();
    expect(await t.run((ctx) => ctx.storage.get(storageId))).toBeNull();
    expect(await t.run((ctx) => ctx.db.query("generatedImages").first())).toBeNull();
  });

  it("cleans a losing concurrent upload without deleting the winning blob", async () => {
    const t = convexTest(schema, modules);
    const args = upload();
    const winner = await t.action(api.generatedImages.store, args);
    const storageId = await t.run((ctx) => ctx.storage.store(new Blob([bytes])));
    expect(
      await t.mutation(internal.generatedImages.commit, {
        key: args.key,
        ownerScopeHash: aliceScope,
        storageId,
        mimeType: "image/png",
        byteLength: 8,
      }),
    ).toEqual({ ...winner, inserted: false });
    expect(await t.run((ctx) => ctx.storage.get(storageId))).toBeNull();
    expect(await t.run(async (ctx) => (await ctx.storage.get(winner.storageId)) !== null)).toBe(
      true,
    );
  });

  it("propagates the sealed descriptor owner through real Node HMACs to Convex storage", async () => {
    const t = convexTest(schema, modules);
    calls.query.mockImplementation((ref, args) => t.query(ref, args));
    calls.action.mockImplementation((ref, args) => t.action(ref, args));
    vi.stubEnv("NEXT_PUBLIC_CONVEX_URL", "https://local-test.convex.cloud");
    const tokenSecret = "synthetic-sealing-secret";
    const [block] = prepareGeneratedStepImages(
      [
        {
          type: "stepCarousel",
          id: "steps",
          steps: [{ title: "Whisk butter", body: "Whisk butter with sugar until glossy." }],
        },
      ],
      { ownerScope: aliceIdentity.tokenIdentifier, tokenSecret },
    );
    if (block.type !== "stepCarousel") throw new Error("step carousel required");
    const query = block.steps[0].icon!.image!.query;
    const provider = vi.fn(async () =>
      Response.json({
        candidates: [
          {
            content: {
              parts: [
                {
                  inlineData: {
                    mimeType: "image/png",
                    data: Buffer.from(bytes).toString("base64"),
                  },
                },
              ],
            },
          },
        ],
      }),
    );
    const url = await resolveGeneratedStepImageQuery(query, {
      tokenSecret,
      apiKey: "synthetic-only",
      fetch: provider,
    });
    expect(url).toMatch(/^\/api\/generated-step-image\?key=[a-f0-9]{64}$/);
    const row = await t.run((ctx) => ctx.db.query("generatedImages").first());
    expect(row?.ownerScopeHash).toBe(aliceScope);
    expect(query).not.toContain(aliceIdentity.tokenIdentifier);
    expect(await generatedStepImageStore.get(row!.key, bobScope)).toBeNull();
    expect(await generatedStepImageStore.get(row!.key)).not.toBeNull();
    await generatedStepImageStore.put("e".repeat(64), { bytes, mimeType: "image/png" });
    expect(
      await t.run((ctx) =>
        ctx.db
          .query("generatedImages")
          .withIndex("by_key", (q) => q.eq("key", "e".repeat(64)))
          .first(),
      ),
    ).toMatchObject({ ownerScopeHash: "shared" });
    await t.withIdentity(aliceIdentity).mutation(api.accounts.purgeSelf, {});
    expect(
      await resolveGeneratedStepImageQuery(query, {
        tokenSecret,
        apiKey: "synthetic-only",
        fetch: provider,
      }),
    ).toBeNull();
    expect(
      await t.run((ctx) =>
        ctx.db
          .query("generatedImages")
          .withIndex("by_ownerScopeHash", (q) => q.eq("ownerScopeHash", aliceScope))
          .first(),
      ),
    ).toBeNull();
  });
});
