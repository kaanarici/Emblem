export const AUTOMATION_SOURCES = ["gmail", "googlecalendar", "weather", "web", "memory"] as const;

export type AutomationSource = (typeof AUTOMATION_SOURCES)[number];

type ExecutionGrant = {
  aud: "generate";
  ownerKey: string;
  runId: string;
  leaseGeneration: number;
  sources: AutomationSource[];
  exp: number;
};

const encoder = new TextEncoder();

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64UrlToBytes(value: string): Uint8Array<ArrayBuffer> {
  const base64 = value
    .replace(/-/g, "+")
    .replace(/_/g, "/")
    .padEnd(Math.ceil(value.length / 4) * 4, "=");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

async function key(secret: string, usage: KeyUsage[]): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    usage,
  );
}

export async function createExecutionGrant(
  claims: Omit<ExecutionGrant, "aud" | "exp"> & { exp?: number },
  secret: string,
): Promise<string> {
  const payload: ExecutionGrant = {
    aud: "generate",
    ownerKey: claims.ownerKey,
    runId: claims.runId,
    leaseGeneration: claims.leaseGeneration,
    sources: claims.sources,
    exp: claims.exp ?? Date.now() + 5 * 60_000,
  };
  const encoded = bytesToBase64Url(encoder.encode(JSON.stringify(payload)));
  const signature = await crypto.subtle.sign(
    "HMAC",
    await key(secret, ["sign"]),
    encoder.encode(encoded),
  );
  return `${encoded}.${bytesToBase64Url(new Uint8Array(signature))}`;
}

export async function verifyExecutionGrant(
  token: string,
  secret: string,
  now = Date.now(),
): Promise<ExecutionGrant | null> {
  if (token.length > 8192) return null;
  const [encoded, signature, extra] = token.split(".");
  if (!encoded || !signature || extra) return null;
  try {
    const valid = await crypto.subtle.verify(
      "HMAC",
      await key(secret, ["verify"]),
      base64UrlToBytes(signature),
      encoder.encode(encoded),
    );
    if (!valid) return null;
    const claims = JSON.parse(
      new TextDecoder().decode(base64UrlToBytes(encoded)),
    ) as Partial<ExecutionGrant>;
    if (
      claims.aud !== "generate" ||
      typeof claims.ownerKey !== "string" ||
      !claims.ownerKey ||
      typeof claims.runId !== "string" ||
      !claims.runId ||
      !Number.isSafeInteger(claims.leaseGeneration) ||
      (claims.leaseGeneration ?? 0) < 1 ||
      typeof claims.exp !== "number" ||
      claims.exp <= now ||
      claims.exp > now + 10 * 60_000 ||
      !Array.isArray(claims.sources) ||
      claims.sources.length > AUTOMATION_SOURCES.length ||
      new Set(claims.sources).size !== claims.sources.length ||
      claims.sources.some((source) => !AUTOMATION_SOURCES.includes(source as AutomationSource))
    ) {
      return null;
    }
    return claims as ExecutionGrant;
  } catch {
    return null;
  }
}
