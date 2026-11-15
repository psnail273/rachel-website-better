// The arch step's lint-tags check, its reader of ESLint's config (the project's
// installed ESLint, its Node API: ESLint#calculateConfigForFile):
//   node tools/verify/_lint_tags.mjs <doc> <files> < tags
// stdin holds ARCHITECTURE.md's lint: tags that name ESLint rules, one per line,
// `<n> <line> <rule>` (factory_arch_lint_tags). <files> lists the files the lint
// step lints, one per line, the representative file first. A tag holds when its
// rule is on for at least one of them: its severity is warn or error (1, 2,
// "warn", "error", alone or first in an array); off, or in no config, it is not.
// A config of `undefined` (ESLint's answer for a file its config ignores) turns
// no rule on. Files are asked in order, and asking stops once every tag holds.
// For each tag on for no file it prints `<doc>:<line> R<n> <message>`, the
// message saying why the rule is not on for the representative file. Exits 2,
// the reason on stderr, when ESLint can't be loaded or can't give a file's config.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [doc, filesPath] = process.argv.slice(2);
const files = readFileSync(filesPath, "utf8")
  .split("\n")
  .map((f) => f.replace(/\r$/, ""))
  .filter((f) => f !== "");

const tags = [];
for (const raw of readFileSync(0, "utf8").split("\n")) {
  const m = /^(\d+) (\d+) (\S+)$/.exec(raw.replace(/\r$/, ""));
  if (m) tags.push({ n: m[1], at: m[2], rule: m[3] });
}
if (tags.length === 0 || files.length === 0) process.exit(0);

let eslint;
try {
  const resolved = createRequire(join(process.cwd(), "package.json")).resolve("eslint");
  const mod = await import(pathToFileURL(resolved).href);
  const ESLint = mod.ESLint ?? mod.default?.ESLint;
  if (typeof ESLint !== "function") throw new Error("it exports no ESLint class");
  eslint = new ESLint({ cwd: process.cwd() });
} catch (error) {
  console.error(`_lint_tags: could not load the project's ESLint: ${error.message}`);
  process.exit(2);
}

// rulesFor: the file's rules, or null when ESLint's config ignores it.
async function rulesFor(file) {
  let config;
  try {
    config = await eslint.calculateConfigForFile(file);
  } catch (error) {
    console.error(`_lint_tags: ESLint could not give the config for ${file}: ${error.message}`);
    process.exit(2);
  }
  if (config === undefined) return null;
  if (config === null || typeof config !== "object") {
    console.error(`_lint_tags: ESLint's config for ${file} is not an object`);
    process.exit(2);
  }
  const rules = config.rules ?? {};
  if (rules === null || typeof rules !== "object") {
    console.error(`_lint_tags: ESLint's config for ${file}: its rules are not an object`);
    process.exit(2);
  }
  return rules;
}

// on: true when the rule's setting turns it on (warn or error).
function on(setting) {
  const severity = Array.isArray(setting) ? setting[0] : setting;
  return severity === 1 || severity === 2 || severity === "warn" || severity === "error";
}

const first = files[0];
const firstRules = await rulesFor(first);
let left = tags.filter((t) => !(firstRules && Object.hasOwn(firstRules, t.rule) && on(firstRules[t.rule])));
for (const file of files.slice(1)) {
  if (left.length === 0) break;
  if (file === first) continue;
  const rules = await rulesFor(file);
  if (rules === null) continue;
  left = left.filter((t) => !(Object.hasOwn(rules, t.rule) && on(rules[t.rule])));
}

const out = left.map(({ n, at, rule }) => {
  const why =
    firstRules === null
      ? `the ESLint config ignores ${first}`
      : Object.hasOwn(firstRules, rule)
        ? `ESLint's config turns it off for ${first}`
        : `no ESLint config sets it for ${first}`;
  return `${doc}:${at} R${n} lint:${rule} is not on: ${why} (eslint --print-config); turn it on (warn or error) in the ESLint config, or change this rule's Enforced by: line`;
});
if (out.length > 0) process.stdout.write(out.join("\n") + "\n");
