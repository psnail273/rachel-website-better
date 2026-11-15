// The arch step's lint-tags check, its reader of ESLint's config for one file
// (eslint --print-config <file>):
//   node tools/verify/_lint_tags.mjs <config.json> <doc> <file> < tags
// stdin holds ARCHITECTURE.md's lint: tags that name ESLint rules, one per line,
// `<n> <line> <rule>` (factory_arch_lint_tags). For each whose rule is not on for
// <file> it prints `<doc>:<line> R<n> <message>`. A rule is on when its severity
// is warn or error (1, 2, "warn", "error", alone or first in an array); off, or
// in no config, it is not. A config of `undefined` (ESLint's answer for a file
// its config ignores) turns no rule on. Exits 2 when <config.json> is neither.
import { readFileSync } from "node:fs";

const [configPath, doc, file] = process.argv.slice(2);
let rules;
let ignored = false;
try {
  const text = readFileSync(configPath, "utf8").trim();
  if (text === "undefined") {
    ignored = true;
    rules = {};
  } else {
    const config = JSON.parse(text);
    if (config === null || typeof config !== "object") throw new Error("not an object");
    rules = config.rules ?? {};
    if (rules === null || typeof rules !== "object") throw new Error("its rules are not an object");
  }
} catch (error) {
  console.error(`_lint_tags: ${configPath}: not ESLint's --print-config output: ${error.message}`);
  process.exit(2);
}

// on: true when the rule's setting turns it on (warn or error).
function on(setting) {
  const severity = Array.isArray(setting) ? setting[0] : setting;
  return severity === 1 || severity === 2 || severity === "warn" || severity === "error";
}

const out = [];
for (const raw of readFileSync(0, "utf8").split("\n")) {
  const line = raw.replace(/\r$/, "");
  const m = /^(\d+) (\d+) (\S+)$/.exec(line);
  if (!m) continue;
  const [, n, at, rule] = m;
  if (Object.hasOwn(rules, rule) && on(rules[rule])) continue;
  const why = ignored
    ? `the ESLint config ignores ${file}`
    : Object.hasOwn(rules, rule)
      ? `ESLint's config turns it off for ${file}`
      : `no ESLint config sets it for ${file}`;
  out.push(
    `${doc}:${at} R${n} lint:${rule} is not on: ${why} (eslint --print-config); turn it on (warn or error) in the ESLint config, or change this rule's Enforced by: line`,
  );
}
if (out.length > 0) process.stdout.write(out.join("\n") + "\n");
