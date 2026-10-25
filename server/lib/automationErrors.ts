import { ConvexError } from "convex/values";
import { asRecord } from "./records";

export const AUTOMATION_ERROR_STATUS = {
  invalid_input: 400,
  not_found: 404,
  busy: 409,
  limit_reached: 409,
  rate_limited: 429,
  invalid_state: 409,
} as const;

type AutomationErrorCode = keyof typeof AUTOMATION_ERROR_STATUS;
type AutomationErrorData = {
  kind: "automation";
  code: AutomationErrorCode;
  message: string;
};

export function failAutomation(code: AutomationErrorCode, message: string): never {
  throw new ConvexError({ kind: "automation", code, message });
}

export function readAutomationError(error: unknown): AutomationErrorData | null {
  if (!(error instanceof ConvexError)) return null;
  const value = asRecord(error.data);
  if (
    !value ||
    value.kind !== "automation" ||
    typeof value.code !== "string" ||
    typeof value.message !== "string" ||
    !Object.hasOwn(AUTOMATION_ERROR_STATUS, value.code)
  )
    return null;
  return value as AutomationErrorData;
}
