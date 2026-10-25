import { errorChain } from "@/lib/generationErrors";
import { logEvent } from "@/lib/log";
import { api } from "@/convex/_generated/api";
import { verifyExecutionGrant, type AutomationSource } from "@/lib/executionGrant";
import {
  generationFailure,
  generationTerminal,
  NDJSON_HEADERS,
  ndjsonLine,
} from "@/lib/generationProtocol";
import type { Attachment, WireMessage } from "@/lib/generationStream";
import { contextSection } from "@/lib/prompt";
import type { ConvexHttpClient } from "convex/browser";

const CONNECT_TIMEOUT_RETRY_DELAYS_MS = [150, 450] as const;

type ServiceRequest = {
  attempted: boolean;
  accepted: boolean;
  unavailable?: boolean;
  ownerKey: string | null;
  sources: AutomationSource[] | undefined;
  requestId: string | null;
};

type RequestLocation = {
  city?: string;
  region?: string;
  country?: string;
  latitude?: number;
  longitude?: number;
};

const REJECTED = { accepted: false, ownerKey: null, sources: undefined, requestId: null } as const;

export async function serviceRequest(
  req: Request,
  convex: ConvexHttpClient | null,
): Promise<ServiceRequest> {
  const secret = process.env.AUTOMATION_SERVICE_KEY;
  const grantToken = req.headers.get("x-execution-grant");
  if (!grantToken) return { attempted: false, ...REJECTED };
  if (!secret) return { attempted: true, ...REJECTED };
  const grant = await verifyExecutionGrant(grantToken, secret);
  if (!grant) return { attempted: true, ...REJECTED };
  try {
    if (!convex) throw new Error("execution authority unavailable");
    const live = await convex.mutation(api.automations.executionAuthority, {
      grant: grantToken,
      checkId: crypto.randomUUID(),
    });
    if (!live) return { attempted: true, ...REJECTED };
  } catch {
    return { attempted: true, unavailable: true, ...REJECTED };
  }
  return {
    attempted: true,
    accepted: true,
    ownerKey: grant.ownerKey,
    sources: grant.sources,
    requestId: grant.runId,
  };
}

export function protocolFailureResponse(
  message: string,
  code: string,
  retryable: boolean,
  extraHeaders: Record<string, string> = {},
): Response {
  const body = [
    generationFailure(code, message, retryable),
    generationTerminal("failed", 0, { persisted: false }),
  ]
    .map(ndjsonLine)
    .join("");
  return new Response(body, { status: 200, headers: { ...NDJSON_HEADERS, ...extraHeaders } });
}

export async function retryOnConnectTimeout<T>(operation: () => Promise<T>): Promise<T> {
  for (let attempt = 0; ; attempt += 1) {
    try {
      return await operation();
    } catch (error) {
      const delay = CONNECT_TIMEOUT_RETRY_DELAYS_MS[attempt];
      const connectTimeout = errorChain(error).some(
        (link) => link.code === "UND_ERR_CONNECT_TIMEOUT",
      );
      if (delay === undefined || !connectTimeout) throw error;
      logEvent("warn", "generation claim connect timeout", { retryInMs: delay });
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }
}

function currentTime(timezone?: string): string {
  const now = new Date();
  try {
    if (timezone) {
      const formatted = new Intl.DateTimeFormat("en-US", {
        timeZone: timezone,
        weekday: "long",
        year: "numeric",
        month: "long",
        day: "numeric",
        hour: "numeric",
        minute: "2-digit",
      }).format(now);
      return `${formatted} (${timezone})`;
    }
  } catch {}
  return `${now.toUTCString().replace(" GMT", "")} UTC`;
}

function locationLine(location?: RequestLocation): string | null {
  if (!location) return null;
  const place = [location.city, location.region, location.country].filter(Boolean).join(", ");
  const coordinates =
    location.latitude != null
      ? ` (${location.latitude.toFixed(3)}, ${location.longitude?.toFixed(3)})`
      : "";
  return place + coordinates || null;
}

export function withRequestContext(
  messages: WireMessage[],
  attachments: Attachment[] | undefined,
  location: RequestLocation | undefined,
  timezone: string | undefined,
  homeControl = false,
): WireMessage[] {
  const documents = (attachments ?? []).filter((attachment) => attachment.text?.trim());
  const last = messages[messages.length - 1];
  if (!last) return messages;
  const documentText = documents
    .map((document) => `\n\n[Attached document ${document.name}]: ${document.text}`)
    .join("");
  const situation = contextSection({
    timeContext: currentTime(timezone),
    locationLine: locationLine(location),
    homeControl,
  });
  return [
    ...messages.slice(0, -1),
    { role: last.role, content: `${last.content}${documentText}\n\n${situation}` },
  ];
}
