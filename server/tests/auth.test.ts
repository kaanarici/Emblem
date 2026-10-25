import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { authFailure, requestAuth } from "../lib/auth";

describe("request authentication boundaries", () => {
  const transport = vi.fn<typeof fetch>();

  beforeEach(() => {
    vi.stubEnv("NEXT_PUBLIC_CONVEX_URL", "https://auth-qualification.convex.cloud");
    vi.stubEnv("CLERK_SECRET_KEY", undefined);
    vi.stubEnv("CLERK_JWT_KEY", undefined);
    transport.mockReset().mockRejectedValue(new Error("unexpected network request"));
    vi.stubGlobal("fetch", transport);
    vi.spyOn(console, "error").mockImplementation(() => {});
  });

  afterEach(() => {
    try {
      expect(transport).not.toHaveBeenCalled();
    } finally {
      vi.unstubAllEnvs();
      vi.unstubAllGlobals();
    }
  });

  it("allows an absent header to be a guest without Clerk configuration", async () => {
    const auth = await requestAuth(new Request("https://emblem.invalid/api"));
    expect(auth).toMatchObject({ status: "guest", authenticated: false, ownerKey: null });
    expect(auth.convex).not.toBeNull();
    expect(authFailure(auth)).toBeNull();
  });

  it.each(["", " \t ", "Basic nope", "Bearer", "Bearer   "])(
    "refuses a present malformed authorization header %j",
    async (authorization) => {
      const auth = await requestAuth(
        new Request("https://emblem.invalid/api", {
          headers: { Authorization: authorization },
        }),
      );
      expect(auth).toMatchObject({ status: "invalid", authenticated: false, ownerKey: null });
      const failure = authFailure(auth);
      expect(failure?.status).toBe(401);
      expect(failure?.headers.get("Cache-Control")).toBe("no-store");
      expect(await failure?.json()).toEqual({
        error: "authentication expired or invalid",
        code: "invalid_auth",
      });
    },
  );

  it("refuses a bearer request when verification configuration is absent", async () => {
    const auth = await requestAuth(
      new Request("https://emblem.invalid/api", {
        headers: { Authorization: "Bearer unverified" },
      }),
    );
    expect(auth).toEqual({
      status: "unavailable",
      authenticated: false,
      ownerKey: null,
      convex: null,
    });
    const failure = authFailure(auth);
    expect(failure?.status).toBe(503);
    expect(failure?.headers.get("Cache-Control")).toBe("no-store");
    expect(await failure?.json()).toEqual({
      error: "authentication backend unavailable",
      code: "auth_unavailable",
    });
  });

  it("reports unavailable when the Convex deployment is absent", async () => {
    vi.stubEnv("NEXT_PUBLIC_CONVEX_URL", undefined);
    const auth = await requestAuth(new Request("https://emblem.invalid/api"));
    expect(auth).toEqual({
      status: "unavailable",
      authenticated: false,
      ownerKey: null,
      convex: null,
    });
    expect(authFailure(auth)?.status).toBe(503);
  });
});
