import { generateKeyPairSync, sign } from "node:crypto";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { verifyToken } from "@clerk/backend";

vi.mock("@clerk/backend", async (original) => {
  const actual = await original<typeof import("@clerk/backend")>();
  return { ...actual, verifyToken: vi.fn(actual.verifyToken) };
});

const pair = generateKeyPairSync("rsa", { modulusLength: 2048 });
const publicKey = pair.publicKey.export({ type: "spki", format: "pem" }).toString();
const now = 1_800_000_000;
let auth: typeof import("../lib/auth");
function token(claims: Record<string, unknown> = {}) {
  const parts = [
    { alg: "RS256", kid: "reuse-test" },
    {
      iss: "https://reuse.invalid",
      sub: "A",
      aud: "convex",
      iat: now - 10,
      nbf: now - 10,
      exp: now + 300,
      ...claims,
    },
  ].map((part) => Buffer.from(JSON.stringify(part)).toString("base64url"));
  const input = parts.join(".");
  return (
    input + "." + sign("RSA-SHA256", Buffer.from(input), pair.privateKey).toString("base64url")
  );
}
const request = (bearer: string) =>
  new Request("https://emblem.invalid/api/history", {
    headers: { Authorization: "Bearer " + bearer },
  });
beforeEach(async () => {
  vi.resetModules();
  vi.mocked(verifyToken).mockClear();
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(now * 1000);
  vi.stubEnv("NEXT_PUBLIC_CONVEX_URL", "https://reuse.convex.cloud");
  vi.stubEnv("CLERK_JWT_KEY", publicKey);
  vi.stubEnv("CLERK_SECRET_KEY", undefined);
  auth = await import("../lib/auth");
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

it("reuses the exact verified token for one second while creating independent Convex clients", async () => {
  const signed = token();
  const first = await auth.requestAuth(request(signed));
  vi.setSystemTime(now * 1000 + 999);
  const second = await auth.requestAuth(request(signed));
  expect([first.status, second.status]).toEqual(["authenticated", "authenticated"]);
  expect(first.convex).not.toBe(second.convex);
  expect(first.ownerKey).toBe(second.ownerKey);
  expect(verifyToken).toHaveBeenCalledTimes(1);
  vi.setSystemTime(now * 1000 + 1000);
  expect((await auth.requestAuth(request(signed))).status).toBe("authenticated");
  expect(verifyToken).toHaveBeenCalledTimes(2);
});
it("never reuses a signature result for another owner or forged bytes", async () => {
  const a = token(),
    b = token({ sub: "B" });
  expect((await auth.requestAuth(request(a))).ownerKey).toBe("https://reuse.invalid|A");
  expect((await auth.requestAuth(request(b))).ownerKey).toBe("https://reuse.invalid|B");
  const parts = a.split(".");
  parts[1] = b.split(".")[1];
  expect((await auth.requestAuth(request(parts.join(".")))).status).toBe("invalid");
  expect(verifyToken).toHaveBeenCalledTimes(3);
});
it("rechecks at exact token expiry even within the reuse window", async () => {
  vi.setSystemTime(now * 1000 + 500);
  const signed = token({ exp: now + 1 });
  await auth.requestAuth(request(signed));
  vi.setSystemTime((now + 1) * 1000);
  await auth.requestAuth(request(signed));
  expect(verifyToken).toHaveBeenCalledTimes(2);
  vi.setSystemTime((now + 7) * 1000);
  expect((await auth.requestAuth(request(signed))).status).toBe("invalid");
});
it.each([{ nbf: now + 1 }, { iat: now + 1 }, { exp: now - 1 }])(
  "does not cache a token accepted only within Clerk clock tolerance: %j",
  async (claims) => {
    const signed = token(claims);
    await auth.requestAuth(request(signed));
    await auth.requestAuth(request(signed));
    expect(verifyToken).toHaveBeenCalledTimes(2);
  },
);
it("revalidates after clock rollback", async () => {
  const signed = token();
  await auth.requestAuth(request(signed));
  vi.setSystemTime(now * 1000 - 1);
  await auth.requestAuth(request(signed));
  expect(verifyToken).toHaveBeenCalledTimes(2);
});
it("fails closed until restart when the configured public key changes", async () => {
  const signed = token();
  await auth.requestAuth(request(signed));
  const other = generateKeyPairSync("rsa", { modulusLength: 2048 });
  vi.stubEnv("CLERK_JWT_KEY", other.publicKey.export({ type: "spki", format: "pem" }).toString());
  expect((await auth.requestAuth(request(signed))).status).toBe("unavailable");
  expect(verifyToken).toHaveBeenCalledTimes(1);
});
it("bounds retained tokens and revalidates evicted tokens", async () => {
  const signed = token();
  await auth.requestAuth(request(signed));
  for (let n = 0; n < 1024; n++) await auth.requestAuth(request(token({ sub: "owner-" + n })));
  await auth.requestAuth(request(signed));
  expect(verifyToken).toHaveBeenCalledTimes(1026);
});
it("does not reuse remote JWKS verification", async () => {
  vi.stubEnv("CLERK_JWT_KEY", undefined);
  vi.stubEnv("CLERK_SECRET_KEY", "local-fixture-only");
  vi.mocked(verifyToken)
    .mockResolvedValueOnce({
      iss: "https://reuse.invalid",
      sub: "A",
      aud: "convex",
      iat: now - 10,
      exp: now + 300,
    } as never)
    .mockRejectedValueOnce(new Error("remote unavailable"));
  const signed = token();
  expect((await auth.requestAuth(request(signed))).status).toBe("authenticated");
  expect((await auth.requestAuth(request(signed))).status).toBe("invalid");
  expect(verifyToken).toHaveBeenCalledTimes(2);
});
