import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import schema from "../convex/schema";
import { api } from "../convex/_generated/api";

vi.mock("@/lib/rateLimit", async (original) => {
  const { rateLimitFixture } = await import("./support/rateLimits");
  return rateLimitFixture(await original<typeof import("../lib/rateLimit")>());
});

const mocks = vi.hoisted(() => ({ auth: vi.fn(), list: vi.fn(), link: vi.fn(), remove: vi.fn() }));
vi.mock("@/lib/auth", async (original) => ({
  ...(await original<typeof import("../lib/auth")>()),
  requestAuth: mocks.auth,
}));
vi.mock("@composio/core", () => ({
  Composio: class {
    connectedAccounts = { list: mocks.list, link: mocks.link };
    authConfigs = { list: async () => ({ items: [{ id: "gmail-config" }] }) };
    getClient() {
      return { connectedAccounts: { delete: mocks.remove } };
    }
  },
}));
vi.mock("@composio/vercel", () => ({ VercelProvider: class {} }));
import { GET, POST } from "../app/api/connectors/route";
const modules = import.meta.glob("../convex/**/*.ts");
let sequence = 0;
beforeEach(() => {
  vi.clearAllMocks();
  sequence++;
  vi.stubEnv("COMPOSIO_API_KEY", "synthetic-connector-key");
  mocks.list.mockResolvedValue({ items: [] });
  mocks.link.mockResolvedValue({
    id: "new-pending-account",
    redirectUrl: "https://connect.example/local",
  });
  mocks.remove.mockResolvedValue({ success: true });
});
afterEach(() => vi.unstubAllEnvs());

function request(action = "connect") {
  return new Request("https://emblem.invalid/api/connectors", {
    method: "POST",
    body: JSON.stringify({ action, toolkit: "gmail" }),
  });
}
function setup() {
  const t = convexTest(schema, modules);
  const subject = `owner-${sequence}`;
  const alice = t.withIdentity({ issuer: "https://erasure.invalid", subject });
  mocks.auth.mockResolvedValue({
    authenticated: true,
    status: "authenticated",
    ownerKey: `https://erasure.invalid|${subject}`,
    convex: alice,
  });
  return { t, alice };
}

describe("connector effects obey account erasure", () => {
  it("refuses new links and provider reads after the actual local purge", async () => {
    const { alice } = setup();
    await alice.mutation(api.accounts.beginErasure, {});
    await alice.mutation(api.accounts.purgeSelf, {});
    expect((await POST(request())).status).toBe(403);
    expect((await GET(new Request("https://emblem.invalid/api/connectors"))).status).toBe(403);
    expect(mocks.link).not.toHaveBeenCalled();
    expect(mocks.list).not.toHaveBeenCalled();
  });

  it("removes a held link that completes after erasure instead of returning its URL", async () => {
    const { alice } = setup();
    let release!: (value: { id: string; redirectUrl: string }) => void;
    let started!: () => void;
    const entered = new Promise<void>((resolve) => {
      started = resolve;
    });
    mocks.link.mockImplementation(() => {
      started();
      return new Promise((resolve) => {
        release = resolve;
      });
    });
    const pending = POST(request());
    await entered;
    await alice.mutation(api.accounts.beginErasure, {});
    await alice.mutation(api.accounts.purgeSelf, {});
    release({ id: "late-account", redirectUrl: "https://connect.example/never-publish" });
    const response = await pending;
    expect(response.status).toBe(403);
    expect(await response.json()).not.toHaveProperty("redirectUrl");
    expect(mocks.remove).toHaveBeenCalledWith(
      "late-account",
      { revoke_on_delete: true },
      {
        signal: expect.any(AbortSignal),
        timeout: 10_000,
        maxRetries: 0,
      },
    );
  });

  it("reports failed compensation and retains authenticated disconnect recovery", async () => {
    const { alice } = setup();
    mocks.link.mockImplementation(async () => {
      await alice.mutation(api.accounts.beginErasure, {});
      return { id: "retry-account", redirectUrl: "https://connect.example/never-publish" };
    });
    mocks.remove.mockResolvedValueOnce({ success: false });
    const failed = await POST(request());
    expect(failed.status).toBe(503);
    expect(await failed.json()).not.toHaveProperty("redirectUrl");
    mocks.list
      .mockResolvedValueOnce({ items: [{ id: "retry-account" }] })
      .mockResolvedValueOnce({ items: [] });
    const retry = await POST(request("disconnect"));
    expect(retry.status).toBe(200);
    expect(mocks.remove).toHaveBeenLastCalledWith(
      "retry-account",
      { revoke_on_delete: true },
      {
        signal: expect.any(AbortSignal),
        timeout: 10_000,
        maxRetries: 0,
      },
    );
  });

  it("allows an unaffected owner to link normally", async () => {
    const { t, alice } = setup();
    expect(await alice.query(api.accounts.isErased, {})).toBe(false);
    await expect(t.query(api.accounts.isErased, {})).rejects.toThrow("authentication required");
    const response = await POST(request());
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      ok: true,
      redirectUrl: "https://connect.example/local",
    });
    expect(mocks.remove).not.toHaveBeenCalled();
  });

  it("does not publish a provider status read that crosses erasure", async () => {
    const { alice } = setup();
    mocks.list.mockImplementation(async () => {
      await alice.mutation(api.accounts.beginErasure, {});
      return { items: [{ id: "old-account", status: "ACTIVE", toolkit: { slug: "gmail" } }] };
    });
    const response = await GET(new Request("https://emblem.invalid/api/connectors?refresh=1"));
    expect(response.status).toBe(403);
    expect(await response.json()).not.toHaveProperty("toolkits");
  });

  it("compensates a link when its final authority lookup is unavailable", async () => {
    setup();
    let linked = false;
    mocks.auth.mockResolvedValue({
      status: "authenticated",
      authenticated: true,
      ownerKey: `unavailable-${sequence}`,
      convex: {
        query: async () => {
          if (linked) throw new Error("status lookup unavailable");
          return false;
        },
      },
    });
    mocks.link.mockImplementation(async () => {
      linked = true;
      return {
        id: "uncertain-authority-account",
        redirectUrl: "https://connect.example/never-publish",
      };
    });
    const response = await POST(request());
    expect(response.status).toBe(503);
    expect(await response.json()).not.toHaveProperty("redirectUrl");
    expect(mocks.remove).toHaveBeenCalledWith(
      "uncertain-authority-account",
      { revoke_on_delete: true },
      {
        signal: expect.any(AbortSignal),
        timeout: 10_000,
        maxRetries: 0,
      },
    );
  });
});
