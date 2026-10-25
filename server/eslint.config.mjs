import { readFileSync } from "node:fs";
import js from "@eslint/js";
import convex from "@convex-dev/eslint-plugin";
import tseslint from "typescript-eslint";
import globals from "globals";

export const MAX_LINES = 500;
export const productionFiles = ["app/**/*.{ts,tsx}", "lib/**/*.ts", "convex/**/*.ts", "*.ts"];
export const maxLinesOptions = { skipBlankLines: true, skipComments: true };
const maxLinesBaseline = JSON.parse(
  readFileSync(new URL("./max-lines-baseline.json", import.meta.url), "utf8"),
);

const convexSharedLib = [
  "automationErrors",
  "automationSchedule",
  "blockImages",
  "executionGrant",
  "generationProtocol",
  "imageBytes",
  "inferenceTelemetry",
  "log",
  "memoryPolicy",
  "presentationTime",
  "rateLimitGrant",
  "records",
  "signing",
  "writing",
];

const reactAndNext = {
  group: ["next", "next/*", "react", "react/*", "react-dom", "react-dom/*"],
  message: "Next and React stay out of Convex.",
};
const appImports = {
  regex: "^(@/|(\\.\\./)+)app(/|$)",
  message: "Only Next owns app/. Put logic routes share in lib/.",
};
const convexModules = {
  regex: "^(@/|(\\.\\./)+)convex/(?!_generated/)",
  message: "Reach Convex through convex/_generated/api, never by importing a Convex module.",
};
const testsAndScripts = {
  regex: "^(@/|(\\.\\./)+)(tests|scripts)(/|$)",
  message: "Production code never imports tests/ or scripts/.",
};
const unsharedLib = {
  regex: `^(@/|(\\.\\./)+)lib/(?!(${convexSharedLib.join("|")})$)`,
  message:
    "Convex may import only the lib modules in convexSharedLib (eslint.config.mjs). Those must not reach Next, providers or Node-only APIs.",
};

export default tseslint.config(
  { ignores: ["node_modules/", ".next/", "convex/_generated/", "next-env.d.ts"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  ...convex.configs.recommended,
  {
    languageOptions: { globals: { ...globals.node } },
    rules: {
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_", caughtErrors: "none" },
      ],
      "no-empty": ["error", { allowEmptyCatch: true }],
      eqeqeq: ["error", "smart"],
      "no-control-regex": "off",
    },
  },
  {
    files: ["**/*.{ts,tsx,mts,cts}"],
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/no-misused-promises": "error",
    },
  },
  {
    files: ["convex/**/*.ts"],
    rules: {
      "@convex-dev/import-wrong-runtime": "error",
      "@convex-dev/no-filter-in-query": "error",
      "no-restricted-imports": [
        "error",
        { patterns: [reactAndNext, appImports, testsAndScripts, unsharedLib] },
      ],
    },
  },
  {
    files: ["lib/**/*.ts"],
    rules: {
      "no-restricted-imports": [
        "error",
        { patterns: [appImports, convexModules, testsAndScripts] },
      ],
    },
  },
  {
    files: ["app/**/*.{ts,tsx}"],
    rules: {
      "no-restricted-imports": ["error", { patterns: [convexModules, testsAndScripts] }],
    },
  },
  {
    files: productionFiles,
    rules: { "max-lines": ["error", { max: MAX_LINES, ...maxLinesOptions }] },
  },
  ...Object.entries(maxLinesBaseline).map(([file, max]) => ({
    files: [file],
    rules: { "max-lines": ["error", { max, ...maxLinesOptions }] },
  })),
  {
    files: ["tests/**"],
    rules: { "@typescript-eslint/no-explicit-any": "off" },
  },
);
