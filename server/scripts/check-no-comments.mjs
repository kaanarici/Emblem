#!/usr/bin/env node
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import ts from "typescript";

const root = new URL("..", import.meta.url).pathname;
const directories = ["app", "lib", "convex", "tests", "scripts"];
const ignored = new Set(["node_modules", "_generated", ".next"]);
const extensions = /\.(?:ts|tsx|mts|js|mjs)$/;
const pragma =
  /^(?:\/\/ @vitest-environment \S+|\/\/\/ <reference [^>]+\/>|\/\/ @ts-expect-error)$/;

function* files(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (ignored.has(entry.name)) continue;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) yield* files(path);
    else if (extensions.test(entry.name)) yield path;
  }
}

function comments(path, source) {
  const file = ts.createSourceFile(
    path,
    source,
    ts.ScriptTarget.Latest,
    true,
    path.endsWith(".tsx") ? ts.ScriptKind.TSX : undefined,
  );
  const seen = new Map();
  const collect = (ranges) => {
    for (const range of ranges ?? []) {
      const text = source.slice(range.pos, range.end);
      if (!pragma.test(text)) seen.set(range.pos, text);
    }
  };
  const visit = (node) => {
    collect(ts.getLeadingCommentRanges(source, node.getFullStart()));
    collect(ts.getTrailingCommentRanges(source, node.getEnd()));
    for (const child of node.getChildren()) visit(child);
  };
  visit(file);
  collect(ts.getLeadingCommentRanges(source, file.endOfFileToken.getFullStart()));
  return [...seen].map(([position, text]) => ({ position, text }));
}

let total = 0;
for (const directory of directories) {
  for (const path of files(join(root, directory))) {
    const source = readFileSync(path, "utf8");
    for (const { position, text } of comments(path, source)) {
      const line = source.slice(0, position).split("\n").length;
      console.error(`${relative(root, path)}:${line} ${text.split("\n")[0].slice(0, 100)}`);
      total += 1;
    }
  }
}
if (total > 0) {
  console.error(
    `${total} source comment(s) found. Source comments are not allowed; document behavior in docs/.`,
  );
  process.exit(1);
}
