import type { AuthConfig } from "convex/server";

let domain: string | undefined;
try {
  domain = process.env.CLERK_JWT_ISSUER_DOMAIN?.trim();
} catch (error) {
  if (
    !(error instanceof Error) ||
    error.message !==
      "Environment variable CLERK_JWT_ISSUER_DOMAIN is used in auth config file but its value was not set"
  ) {
    throw error;
  }
}

export default {
  providers: domain ? [{ domain, applicationID: "convex" }] : [],
} satisfies AuthConfig;
