import type * as accounts from "../accounts.js";
import type * as automationDispatch from "../automationDispatch.js";
import type * as automationExecution from "../automationExecution.js";
import type * as automationRuns from "../automationRuns.js";
import type * as automations from "../automations.js";
import type * as background from "../background.js";
import type * as conversations from "../conversations.js";
import type * as crons from "../crons.js";
import type * as generatedImages from "../generatedImages.js";
import type * as generationActions from "../generationActions.js";
import type * as imageCache from "../imageCache.js";
import type * as inferenceTypes from "../inferenceTypes.js";
import type * as memories from "../memories.js";
import type * as ownership from "../ownership.js";
import type * as pages from "../pages.js";
import type * as profiles from "../profiles.js";
import type * as rateLimits from "../rateLimits.js";
import type * as users from "../users.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  accounts: typeof accounts;
  automationDispatch: typeof automationDispatch;
  automationExecution: typeof automationExecution;
  automationRuns: typeof automationRuns;
  automations: typeof automations;
  background: typeof background;
  conversations: typeof conversations;
  crons: typeof crons;
  generatedImages: typeof generatedImages;
  generationActions: typeof generationActions;
  imageCache: typeof imageCache;
  inferenceTypes: typeof inferenceTypes;
  memories: typeof memories;
  ownership: typeof ownership;
  pages: typeof pages;
  profiles: typeof profiles;
  rateLimits: typeof rateLimits;
  users: typeof users;
}>;

export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {
  rateLimiter: import("@convex-dev/rate-limiter/_generated/component.js").ComponentApi<"rateLimiter">;
};
