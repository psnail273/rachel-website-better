// The lint step's reader of knip's JSON report (--reporter json):
//   node tools/verify/_knip_findings.mjs <report.json> <files>
// <files> lists the files the gates check (tools/verify/scope), one per line; an
// issue in any other file is left out. It prints one finding per issue,
// `<file>:<line> knip-<kind> <message>`, <kind> being knip's issue type in
// kebab case:
//   knip-files                 a file nothing imports (at line 1)
//   knip-exports, knip-types   an export, or an exported type, nothing imports
//   knip-dependencies, knip-dev-dependencies, knip-optional-peer-dependencies
//                              a package.json entry nothing imports
//   knip-unlisted              an import of a package package.json doesn't list
//   knip-unresolved            an import that resolves to nothing
//   knip-binaries              a script's binary no listed package provides
//   and any other type knip reports (duplicates, enum-members, ...) alike.
// An issue without a line is at line 1; whitespace runs in a name become one space.
// Exits 2 when the report isn't knip's JSON.
import { readFileSync } from "node:fs";

let report;
let files;
try {
  report = JSON.parse(readFileSync(process.argv[2], "utf8"));
  if (!report || !Array.isArray(report.issues)) throw new Error("no issues array");
  files = new Set(
    readFileSync(process.argv[3], "utf8")
      .split("\n")
      .map((f) => f.replace(/\r$/, ""))
      .filter((f) => f !== ""),
  );
} catch (error) {
  console.error(`_knip_findings: ${process.argv[2]}: ${error.message}`);
  process.exit(2);
}

const kebab = (s) => s.replace(/[A-Z]/g, (c) => "-" + c.toLowerCase());
const said = {
  files: () => "nothing imports this file; use it or delete it",
  exports: (n) => `${n} is exported but nothing imports it`,
  types: (n) => `type ${n} is exported but nothing imports it`,
  dependencies: (n) => `${n} is a dependency nothing imports`,
  devDependencies: (n) => `${n} is a devDependency nothing uses`,
  optionalPeerDependencies: (n) => `${n} is an optional peer dependency nothing imports`,
  unlisted: (n) => `${n} is imported but package.json doesn't list it`,
  unresolved: (n) => `${n} is imported but resolves to nothing`,
  binaries: (n) => `${n} is run but no listed package provides it`,
};
// An issue's name: its own, or for a group (duplicates) its members' joined.
const nameOf = (item) =>
  String(
    Array.isArray(item) ? item.map(nameOf).join(", ") : (item?.name ?? item?.symbol ?? ""),
  )
    .replace(/\s+/g, " ")
    .trim();
const lineOf = (item) => {
  const line = Array.isArray(item) ? item[0]?.line : item?.line;
  return Number.isInteger(line) && line > 0 ? line : 1;
};

const out = [];
for (const issue of report.issues) {
  const file = String(issue.file ?? "");
  if (!files.has(file)) continue;
  for (const [kind, items] of Object.entries(issue)) {
    if (!Array.isArray(items)) continue;
    for (const item of items) {
      const name = nameOf(item) || "(unnamed)";
      const message = said[kind]
        ? said[kind](name)
        : `${name}: knip's ${kebab(kind)} issue`;
      out.push(`${file}:${lineOf(item)} knip-${kebab(kind)} ${message}`);
    }
  }
}
if (out.length > 0) process.stdout.write(out.join("\n") + "\n");
