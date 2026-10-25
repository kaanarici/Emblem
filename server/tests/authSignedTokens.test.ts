import { generateKeyPairSync, sign, type KeyObject } from "node:crypto";
import { verifyToken } from "@clerk/backend";
import { ConvexHttpClient } from "convex/browser";
import { makeFunctionReference } from "convex/server";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { authFailure, requestAuth } from "../lib/auth";

const issuer = "https://emblem-auth.invalid";
const deployment = "https://auth-qualification.convex.cloud";
const now = 1_800_000_000;
let privateKey: KeyObject;
let otherPrivateKey: KeyObject;
let publicKey: string;

function signedToken(overrides: Record<string, unknown> = {}, key = privateKey) {
  const header = Buffer.from(
    JSON.stringify({ alg: "RS256", typ: "JWT", kid: "ephemeral" }),
  ).toString("base64url");
  const payload = Buffer.from(
    JSON.stringify({
      iss: issuer,
      sub: "user_A",
      aud: "convex",
      sid: "sess_local",
      iat: now - 30,
      nbf: now - 30,
      exp: now + 300,
      ...overrides,
    }),
  ).toString("base64url");
  const input = `${header}.${payload}`;
  return `${input}.${sign("RSA-SHA256", Buffer.from(input), key).toString("base64url")}`;
}

function request(token: string) {
  return new Request("https://emblem.invalid/api", {
    headers: { Authorization: `Bearer ${token}` },
  });
}

function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

describe("signed tokens through the installed Clerk verifier and Convex HTTP client", () => {
  const transport = vi.fn<typeof fetch>();

  beforeAll(() => {
    const pair = generateKeyPairSync("rsa", { modulusLength: 2048 });
    privateKey = pair.privateKey;
    publicKey = pair.publicKey.export({ type: "spki", format: "pem" }).toString();
    otherPrivateKey = generateKeyPairSync("rsa", { modulusLength: 2048 }).privateKey;
  });

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(now * 1000);
    vi.stubEnv("NEXT_PUBLIC_CONVEX_URL", deployment);
    vi.stubEnv("CLERK_JWT_KEY", publicKey);
    vi.stubEnv("CLERK_SECRET_KEY", undefined);
    transport.mockReset().mockRejectedValue(new Error("unexpected network request"));
    vi.stubGlobal("fetch", transport);
    vi.spyOn(console, "error").mockImplementation(() => {});
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  it.each([
    ["user_A", "convex"],
    ["user_B", ["other", "convex"]],
  ])("verifies real RS256 signatures and canonical scope for %s", async (sub, aud) => {
    const token = signedToken({ sub, aud });
    expect(await verifyToken(token, { jwtKey: publicKey, audience: "convex" })).toMatchObject({
      iss: issuer,
      sub,
      aud,
    });
    const auth = await requestAuth(request(token));
    expect(auth).toMatchObject({
      status: "authenticated",
      authenticated: true,
      ownerKey: `${issuer}|${sub}`,
    });
    expect(auth.convex).toBeInstanceOf(ConvexHttpClient);
    expect(authFailure(auth)).toBeNull();
    expect(transport).not.toHaveBeenCalled();
  });

  it("uses an escaped local public key even when a dummy secret is also configured", async () => {
    vi.stubEnv("CLERK_JWT_KEY", `  ${publicKey.replace(/\n/g, "\\n")}  `);
    vi.stubEnv("CLERK_SECRET_KEY", "sk_test_local_dummy_not_a_credential");
    expect((await requestAuth(request(signedToken()))).status).toBe("authenticated");
    expect(transport).not.toHaveBeenCalled();
  });

  it.each([
    ["expired", { exp: now - 60 }, "token-expired"],
    ["future activation", { nbf: now + 60 }, "token-not-active-yet"],
    ["future issuance", { iat: now + 60 }, "token-iat-in-the-future"],
    ["wrong string audience", { aud: "other" }, "token-verification-failed"],
    ["wrong audience array", { aud: ["other"] }, "token-verification-failed"],
    ["missing subject", { sub: undefined }, "token-verification-failed"],
    ["non-string subject", { sub: 123 }, "token-verification-failed"],
    ["missing expiry", { exp: undefined }, "token-verification-failed"],
  ])("refuses %s using actual Clerk claim validation", async (_name, overrides, reason) => {
    const token = signedToken(overrides as Record<string, unknown>);
    await expect(
      verifyToken(token, { jwtKey: publicKey, audience: "convex" }),
    ).rejects.toMatchObject({ reason });
    const auth = await requestAuth(request(token));
    expect(auth).toMatchObject({ status: "invalid", authenticated: false, ownerKey: null });
    expect(authFailure(auth)?.status).toBe(401);
    expect(transport).not.toHaveBeenCalled();
  });

  it("refuses an otherwise valid token signed by a different ephemeral RSA key", async () => {
    const token = signedToken({}, otherPrivateKey);
    await expect(
      verifyToken(token, { jwtKey: publicKey, audience: "convex" }),
    ).rejects.toMatchObject({ reason: "token-invalid-signature" });
    const auth = await requestAuth(request(token));
    expect(auth).toMatchObject({ status: "invalid", authenticated: false, ownerKey: null });
    expect(authFailure(auth)?.status).toBe(401);
    expect(transport).not.toHaveBeenCalled();
  });

  it.each([
    ["missing audience", { aud: undefined }],
    ["empty audience", { aud: [] }],
    ["malformed audience", { aud: ["convex", 123] }],
    ["missing issuer", { iss: undefined }],
    ["empty issuer", { iss: "" }],
    ["non-string issuer", { iss: { domain: issuer } }],
    ["empty subject", { sub: "" }],
  ])("refuses %s at the bridge even when Clerk accepts its signature", async (_name, overrides) => {
    const token = signedToken(overrides);
    await expect(
      verifyToken(token, { jwtKey: publicKey, audience: "convex" }),
    ).resolves.toBeDefined();
    const auth = await requestAuth(request(token));
    expect(auth).toMatchObject({ status: "invalid", authenticated: false, ownerKey: null });
    expect(authFailure(auth)?.status).toBe(401);
    expect(transport).not.toHaveBeenCalled();
  });

  it.each(["not-a-jwt", "a.b.c", "e30.e30.", "Bearer token", "one.two.three.four"])(
    "refuses malformed JWT %j without transport",
    async (token) => {
      const auth = await requestAuth(request(token));
      expect(auth).toMatchObject({ status: "invalid", authenticated: false, ownerKey: null });
      expect(authFailure(auth)?.status).toBe(401);
      expect(transport).not.toHaveBeenCalled();
    },
  );

  it("keeps A, B and guest clients separate through overlapping real client requests", async () => {
    const tokenA = signedToken({ sub: "user_A" });
    const tokenB = signedToken({ sub: "user_B", aud: ["convex", "other"] });
    const [a, b, guest] = await Promise.all([
      requestAuth(request(tokenA)),
      requestAuth(request(tokenB)),
      requestAuth(new Request("https://emblem.invalid/api")),
    ]);
    expect([a.ownerKey, b.ownerKey, guest.ownerKey]).toEqual([
      `${issuer}|user_A`,
      `${issuer}|user_B`,
      null,
    ]);
    expect([a.status, b.status, guest.status]).toEqual(["authenticated", "authenticated", "guest"]);
    const clients = [a.convex!, b.convex!, guest.convex!];
    expect(new Set(clients).size).toBe(3);
    for (const client of clients) expect(client).toBeInstanceOf(ConvexHttpClient);
    expect(transport).not.toHaveBeenCalled();

    const gates = [deferred(), deferred(), deferred()];
    const arrived = deferred();
    const observed: { label: number; authorization: string | null }[] = [];
    const expectedHeaders = [`Bearer ${tokenA}`, `Bearer ${tokenB}`, null];
    transport.mockImplementation(async (input, init) => {
      const wire = new Request(input, init);
      expect(wire.url).toBe(`${deployment}/api/query`);
      expect(wire.method).toBe("POST");
      const body = (await wire.json()) as {
        path: string;
        args: [{ label: number }];
        format: string;
      };
      expect(body.path).toBe("authQualification:probe");
      expect(body.format).toBe("convex_encoded_json");
      const label = body.args[0].label;
      expect([0, 1, 2]).toContain(label);
      const authorization = wire.headers.get("Authorization");
      expect(authorization).toBe(expectedHeaders[label]);
      observed.push({ label, authorization });
      if (observed.length === 3) arrived.resolve();
      await gates[label].promise;
      return Response.json({ status: "success", value: label, logLines: [] });
    });
    const probe = makeFunctionReference<"query">("authQualification:probe");
    const completed: number[] = [];
    const queries = clients.map((client, label) =>
      client.query(probe, { label }).then((value) => {
        completed.push(label);
        return value;
      }),
    );
    try {
      await Promise.race([arrived.promise, Promise.all(queries)]);
      expect(transport).toHaveBeenCalledTimes(3);
      expect(completed).toEqual([]);
      expect(observed.sort((x, y) => x.label - y.label)).toEqual(
        expectedHeaders.map((authorization, label) => ({ label, authorization })),
      );
      for (const label of [2, 1, 0]) {
        gates[label].resolve();
        expect(await queries[label]).toBe(label);
      }
      expect(completed).toEqual([2, 1, 0]);
    } finally {
      for (const gate of gates) gate.resolve();
      await Promise.allSettled(queries);
    }
  });
});
