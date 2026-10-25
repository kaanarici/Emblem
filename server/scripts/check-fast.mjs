#!/usr/bin/env node
import { execFileSync, spawn } from "node:child_process";
import { existsSync } from "node:fs";

const root = new URL("..", import.meta.url).pathname;
const started = performance.now();
const git = (...args) =>
  execFileSync("git", args, { cwd: root, encoding: "utf8" }).split("\n").filter(Boolean);
const ref = process.argv[2] ?? "origin/main";
const base = git("merge-base", "HEAD", ref)[0];
const changed = [
  ...new Set([
    ...git("diff", "--name-only", "--relative", base, "--", "."),
    ...git("ls-files", "--others", "--exclude-standard"),
  ]),
].filter((file) => existsSync(`${root}${file}`));
const code = changed.filter((file) => /\.(?:[cm]?[jt]sx?)$/.test(file));
const wide = changed.some((file) =>
  /^(?:package(?:-lock)?\.json|tsconfig\.json|vitest\.config\.ts|eslint\.config\.mjs|max-lines-baseline\.json)$/.test(
    file,
  ),
);
if (code.length === 0 && !wide) {
  console.log(`check:fast: no server code changed since ${base.slice(0, 10)}.`);
  process.exit(0);
}

const bin = (name) => `${root}node_modules/.bin/${name}`;
const steps = [
  ["types", bin("tsc"), ["--noEmit"]],
  ["lint", bin("eslint"), wide ? ["."] : ["--no-warn-ignored", ...code]],
  ["comments", "node", ["scripts/check-no-comments.mjs"]],
  ["max-lines", "node", ["scripts/max-lines.mjs"]],
  ["knip", bin("knip"), []],
  ["format", bin("prettier"), ["--check", "--ignore-unknown", ...changed]],
  ["tests", bin("vitest"), wide ? ["run"] : ["related", "--run", "--passWithNoTests", ...code]],
];
const run = ([name, command, args]) =>
  new Promise((resolve) => {
    const begin = performance.now();
    const child = spawn(command, args, { cwd: root, env: { ...process.env, FORCE_COLOR: "1" } });
    let output = "";
    child.stdout.on("data", (chunk) => (output += chunk));
    child.stderr.on("data", (chunk) => (output += chunk));
    child.on("close", (status) =>
      resolve({ name, status, output, seconds: (performance.now() - begin) / 1000 }),
    );
  });

const results = await Promise.all(steps.map(run));
for (const { name, status, output } of results)
  if (status !== 0) console.log(`\n── ${name}\n${output}`);
const summary = results.map(
  ({ name, status, seconds }) => `${status === 0 ? "ok" : "FAIL"} ${name} ${seconds.toFixed(1)}s`,
);
console.log(
  `check:fast (${changed.length} files since ${base.slice(0, 10)}${wide ? ", config changed: full lint and tests" : ""}): ${summary.join(" · ")} · total ${((performance.now() - started) / 1000).toFixed(1)}s`,
);
process.exit(results.every(({ status }) => status === 0) ? 0 : 1);
