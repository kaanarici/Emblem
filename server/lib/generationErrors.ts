type ProviderErrorCode =
  | "provider_billing"
  | "provider_auth"
  | "provider_rate_limit"
  | "incomplete_generation"
  | "generation_failed";

export function errorChain(error: unknown): Record<string, unknown>[] {
  const chain: Record<string, unknown>[] = [];
  let current = error;
  for (let depth = 0; depth < 4 && current && typeof current === "object"; depth += 1) {
    const link = current as Record<string, unknown>;
    chain.push(link);
    current = link.cause;
  }
  return chain;
}

export function classifyProviderError(error: unknown): ProviderErrorCode {
  const status = errorChain(error).find((link) => typeof link.statusCode === "number")?.statusCode;
  if (status === 402) return "provider_billing";
  if (status === 401 || status === 403) return "provider_auth";
  if (status === 429) return "provider_rate_limit";
  const message = error instanceof Error ? error.message : String(error);
  if (/payment|quota|billing|402/i.test(message)) return "provider_billing";
  if (/api key|unauthorized|401/i.test(message)) return "provider_auth";
  if (/rate limit|429/i.test(message)) return "provider_rate_limit";
  if (/empty|incomplete/i.test(message)) return "incomplete_generation";
  return "generation_failed";
}

export function friendlyProviderMessage(
  code: ProviderErrorCode,
  usingUserCredential: boolean,
): string {
  switch (code) {
    case "provider_billing":
      return usingUserCredential
        ? "Your inference account isn't active yet. Check billing in the provider dashboard and try again."
        : "I can't reach the model right now because the inference account isn't active yet. Activate it in the provider dashboard and ask me again.";
    case "provider_auth":
      return usingUserCredential
        ? "Your API key was rejected. Check it in Settings and try again."
        : "I can't reach the model right now because the API key was rejected. Check the server configuration and ask me again.";
    case "provider_rate_limit":
      return "The model is rate limited at the moment. Give it a few seconds and ask me again.";
    case "incomplete_generation":
    case "generation_failed":
      return "I couldn't finish generating this page. Ask me again in a moment.";
  }
}
