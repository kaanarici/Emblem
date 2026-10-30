import { platformCredentialEnv } from "./provider";

type EnvSpec = {
  name: string;
  whenMissing: string;
};

const SPEC: EnvSpec[] = [
  { name: "RATE_LIMIT_SECRET", whenMissing: "paid endpoint admission fails closed" },
  { name: "NEXT_PUBLIC_CONVEX_URL", whenMissing: "persistence and auth unavailable" },
  { name: "CEREBRAS_API_KEY", whenMissing: "Cerebras inference unavailable" },
  { name: "EXA_API_KEY", whenMissing: "web search + on-device tool relay return empty" },
  { name: "TMDB_API_KEY", whenMissing: "posters skip TMDB and use fallback sources" },
  { name: "OMDB_API_KEY", whenMissing: "posters skip OMDb and use fallback sources" },
  {
    name: "GEMINI_API_KEY",
    whenMissing: "Google inference unavailable, and images need FAL_KEY",
  },
  {
    name: "GENERATED_STEP_IMAGE_TOKEN_SECRET",
    whenMissing: "generated step illustrations disabled",
  },
  {
    name: "FAL_KEY",
    whenMissing: "icons and step illustrations generate with Gemini instead of fal",
  },
  { name: "XAI_API_KEY", whenMissing: "TTS disabled" },
  { name: "GROQ_API_KEY", whenMissing: "groq provider unavailable" },
  { name: "MODELGO_API_KEY", whenMissing: "ModelGo inference unavailable" },
  { name: "OPENAI_API_KEY", whenMissing: "OpenAI provider unavailable" },
  { name: "OPENROUTER_API_KEY", whenMissing: "managed OpenRouter model selections unavailable" },
  {
    name: "GENERATED_STEP_IMAGE_STORAGE_SECRET",
    whenMissing: "generated image storage and shared artwork cache writes unavailable",
  },
  { name: "NUITEE_SANDBOX_API_KEY", whenMissing: "hotel search and hotel details unavailable" },
  { name: "COMPOSIO_API_KEY", whenMissing: "connectors (Gmail/Calendar) disabled" },
  { name: "AUTOMATION_SERVICE_KEY", whenMissing: "scheduled automation runs cannot call generate" },
];

let reported = false;

export function reportEnv(): void {
  if (reported) return;
  reported = true;
  const required = new Set(["NEXT_PUBLIC_CONVEX_URL"]);
  try {
    for (const name of platformCredentialEnv()) required.add(name);
  } catch (error) {
    console.error(`env invalid: ${error instanceof Error ? error.message : String(error)}`);
  }
  let missingRequired = 0;
  for (const { name, whenMissing } of SPEC) {
    if (process.env[name]?.trim()) continue;
    if (required.has(name)) {
      missingRequired += 1;
      console.error(`env missing (REQUIRED): ${name}: ${whenMissing}`);
    } else {
      console.warn(`env missing: ${name}: ${whenMissing}`);
    }
  }
  if (missingRequired > 0) {
    console.error(`env check: ${missingRequired} required variable(s) missing`);
  }
}
