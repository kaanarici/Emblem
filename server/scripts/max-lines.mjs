#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import { relative } from "node:path";
import { ESLint } from "eslint";
import tseslint from "typescript-eslint";
import { MAX_LINES, maxLinesOptions, productionFiles } from "../eslint.config.mjs";

const root = new URL("..", import.meta.url).pathname;
const baselinePath = new URL("../max-lines-baseline.json", import.meta.url);
const baseline = JSON.parse(readFileSync(baselinePath, "utf8"));
const eslint = new ESLint({
  cwd: root,
  overrideConfigFile: true,
  overrideConfig: [
    { ignores: ["convex/_generated/"] },
    {
      files: productionFiles,
      languageOptions: { parser: tseslint.parser },
      rules: { "max-lines": ["error", { max: 1, ...maxLinesOptions }] },
    },
  ],
});
const sizes = new Map();
for (const result of await eslint.lintFiles(productionFiles)) {
  const lines = Number(result.messages[0]?.message.match(/\((\d+)\)/)?.[1] ?? 1);
  sizes.set(relative(root, result.filePath), lines);
}

const tightened = Object.fromEntries(
  Object.entries(baseline)
    .map(([file, max]) => [file, Math.min(max, sizes.get(file) ?? 0)])
    .filter(([, max]) => max > MAX_LINES)
    .sort(([a], [b]) => a.localeCompare(b)),
);
if (process.argv.includes("--write")) {
  writeFileSync(baselinePath, `${JSON.stringify(tightened, null, 2)}\n`);
  console.log(`max-lines-baseline.json: ${Object.keys(tightened).length} files over ${MAX_LINES}.`);
} else {
  const loose = Object.keys(baseline).filter((file) => tightened[file] !== baseline[file]);
  if (loose.length > 0) {
    console.error(
      `These files shrank below their max-lines baseline: ${loose.join(", ")}.\nRun npm run lint:ratchet to lock in the smaller size.`,
    );
    process.exit(1);
  }
}
