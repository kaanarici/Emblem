export type WebResearchPolicy = "allow" | "suppress" | "model";

const explicitLiveRequest =
  /\b(?:latest|current|today|tonight|tomorrow|this\s+(?:week|month|year)|recent(?:ly)?|newest|upcoming|news|updates?|release\s+(?:date|notes?)|availability|available\s+now|where\s+(?:can|do|should)\s+(?:i|we)\s+(?:watch|stream|buy|find)|prices?|cost|scores?|standings?|schedules?|weather|forecast|ratings?|reviews?|specs?|versions?|near\s+me|nearby|open\s+now|restaurants?|hotels?|flights?|tickets?|venues?)\b/i;
const numberedReleaseRequest =
  /\b(?:season|version|ios|ipados|macos|android)\s*(?:v\s*)?\d+(?:\.\d+)*\b/i;
const datedEventRequest =
  /\b(?:19|20)\d{2}\b.{0,40}\b(?:awards?|nominations?|emmys?|oscars?|festival|conference|election|games?|cup)\b|\b(?:awards?|nominations?|emmys?|oscars?|festival|conference|election|games?|cup)\b.{0,40}\b(?:19|20)\d{2}\b/i;
const stableProcedureRequest =
  /^(?:how\s+(?:do|can|should)\s+(?:i|we)|show\s+me\s+how\s+to)\b|^(?:please\s+)?(?:create|make|cook|bake)\b.{0,100}\b(?:recipe|cookies?|cake|bread|pastry|dough|meal|dish)\b/i;
const explicitEvergreenOrientation =
  /^(?:tell\s+me\s+about|give\s+me\s+(?:an?\s+)?overview\s+of|orient\s+me\s+to|what\s+(?:is|are|was|were)|who\s+(?:is|are|was|were)|should\s+(?:i|we)\s+(?:watch|read|play))\b/i;
const nonTopicLead =
  /^(?:please\s+)?(?:best|top|recommend|rank|compare|create|make|cook|bake|design|draft|write|summarize|explain|build|find|search|look\s+up|show|list|open|read|check|plan|schedule|add|send|buy|book|order|watch|stream|where|when|why|which|can|could|would|will|do|does|did|is|are)\b/i;

function normalizedRequest(value: string): string {
  return value.normalize("NFKC").trim().replace(/\s+/g, " ");
}

function isEvergreenOrientationRequest(value: string): boolean {
  const request = normalizedRequest(value);
  if (!request || request.length > 140 || /https?:\/\//i.test(request)) return false;
  if (/^["“][^"”]+["”]$/.test(request)) return true;
  if (explicitEvergreenOrientation.test(request)) return true;
  if (/[?\n]/.test(request) || nonTopicLead.test(request)) return false;
  const words = request.match(/[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)?/gu) ?? [];
  return words.length >= 1 && words.length <= 8;
}

export function requestReferencesPersonalData(value: string): boolean {
  return /\b(email|e-mail|gmail|inbox|unread|newsletter|mail(?:box)?|calendar|schedule|meeting|appointment|invite|event(?:s)? (?:today|tomorrow|this week)|my (?:day|week|morning|agenda)|reply|respond to|message from|daily (?:brief|update)|brief me|catch me up|needs? (?:my|your) attention)\b/i.test(
    value,
  );
}

export function requiresCalendarRead(value: string): boolean {
  const request = normalizedRequest(value);
  if (/\b(calendar|agenda|schedule|meetings?|appointments?|invites?)\b/i.test(request)) {
    return true;
  }
  if (
    /\b(daily (?:brief|update)|morning brief|evening update|brief me|catch me up|my day)\b/i.test(
      request,
    )
  ) {
    return true;
  }
  return /^(?:please\s+)?(?:give|show) me (?:my |an? )?update(?:\s+(?:for\s+)?(?:today|tonight|this (?:morning|afternoon|evening)))?[.!?]*$/i.test(
    request,
  );
}

export function webResearchPolicy(value: string): WebResearchPolicy {
  const request = normalizedRequest(value);
  if (
    explicitLiveRequest.test(request) ||
    numberedReleaseRequest.test(request) ||
    datedEventRequest.test(request)
  )
    return "allow";
  if (isEvergreenOrientationRequest(request) || stableProcedureRequest.test(request)) {
    return "suppress";
  }
  return "model";
}

const WEATHER_NOUN = /\b(?:weather|forecast|precipitation|humidity|uv\s+index)\b/i;
const CONDITION =
  "(?:rain(?:y|ing)?|snow(?:y|ing)?|wind(?:y)?|storm(?:y|s)?|sunny|cloudy|hot|cold|warm|chilly|freezing|humid|foggy)";
const WEATHER_QUESTION = new RegExp(
  [
    `\\b(?:will|is|does|did|should)\\s+it\\s+(?:be\\s+|going\\s+to\\s+(?:be\\s+)?|gonna\\s+(?:be\\s+)?)?${CONDITION}\\b`,
    `\\bhow\\s+(?:hot|cold|warm|windy|rainy|humid)\\s+(?:is|will|was)\\b`,
    `\\b(?:chance|odds)\\s+of\\s+(?:rain|snow|storms?)\\b`,
    `\\b(?:temperature|temp)\\s+(?:in|at|outside|today|tonight|tomorrow|this)\\b`,
    `\\b(?:need|bring|take)\\s+(?:an?\\s+)?(?:umbrella|raincoat|jacket)\\b`,
  ].join("|"),
  "i",
);

function asksAboutWeather(request: string): boolean {
  return WEATHER_NOUN.test(request) || WEATHER_QUESTION.test(request);
}

export function conversationMayNeedWeather(
  messages: { role: "user" | "assistant"; content: string }[],
): boolean {
  const latestUserIndex = messages.findLastIndex(({ role }) => role === "user");
  const latest = messages[latestUserIndex]?.content ?? "";
  if (asksAboutWeather(latest)) return true;
  const prior = messages[latestUserIndex - 1];
  return prior?.role === "assistant" && /^weather:/m.test(prior.content);
}

export function requestsExplanation(prompt: string): boolean {
  return /\b(?:how\s+(?:does|do|did|is|are|can|would|to)\b|how\s+it\s+works|why\s+(?:does|do|is|are|did)\b|what\s+(?:causes|happens\s+when)\b|explain\b|walk\s+me\s+through\b|architecture\s+of\b|under\s+the\s+hood\b|process\s+(?:of|behind)\b|relationship\s+between\b)/i.test(
    prompt,
  );
}

export function isUnsupportedFollowUpAction(label: string, prompt: string): boolean {
  const unsupported =
    /^(?:play|stream|open\s+(?:netflix|hulu|disney|prime|apple\s+tv|the\s+streaming)|watch\b.{0,30}\bnow|start\s+(?:watching|(?:the\s+)?(?:first\s+)?(?:episode|season))|save\b.{0,30}\bnotes?|create\s+(?:a\s+)?note)\b/i;
  return unsupported.test(label.trim()) || unsupported.test(prompt.trim());
}

export function automationIntentIsExplicit(userText: string): boolean {
  return (
    /\b(automate|automation|daily|recurring|repeat|weekly|weekdays?|weekends?)\b/.test(userText) ||
    /\b(each|every) (day|morning|afternoon|evening|night|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/.test(
      userText,
    )
  );
}

export function calendarIntentIsExplicit(userText: string): boolean {
  return (
    /\bschedule\b/.test(userText) ||
    /\b(add|create|put)\b.{0,60}\b(calendar|event|appointment|meeting)\b/.test(userText)
  );
}
