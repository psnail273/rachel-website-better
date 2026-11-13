// The lint step's reader of ESLint's JSON report (--format json):
//   node tools/verify/_eslint_findings.mjs <report.json>
// prints one finding per message, `<file>:<line> <rule> <message>`, the file
// relative to the working directory (the project root):
//   <rule> is the ESLint rule's id (@typescript-eslint/no-floating-promises);
//   lint-parse    the file doesn't parse (ESLint's fatal message);
//   lint-ignored  the ESLint config ignores a file the scope checks;
//   lint-other    any other message with no rule.
// A message without a line is at line 1; whitespace runs in a message become one
// space. Exits 2 when the report isn't ESLint's JSON.
import { readFileSync } from "node:fs";
import { relative, sep } from "node:path";

let report;
try {
  report = JSON.parse(readFileSync(process.argv[2], "utf8"));
  if (!Array.isArray(report)) throw new Error("not an array of results");
} catch (error) {
  console.error(`_eslint_findings: ${process.argv[2]}: ${error.message}`);
  process.exit(2);
}

const out = [];
for (const result of report) {
  const file = relative(process.cwd(), result.filePath).split(sep).join("/");
  for (const m of result.messages ?? []) {
    const text = String(m.message ?? "")
      .replace(/\s+/g, " ")
      .trim();
    let rule = m.ruleId;
    let message = text;
    if (!rule && m.fatal) rule = "lint-parse";
    else if (!rule && /^File ignored\b/.test(text)) {
      rule = "lint-ignored";
      message =
        "the ESLint config ignores this file, which tools/verify/scope checks; lint it, or take it out of the scope";
    } else if (!rule) rule = "lint-other";
    const line = Number.isInteger(m.line) && m.line > 0 ? m.line : 1;
    out.push(`${file}:${line} ${rule} ${message || "(no message)"}`);
  }
}
if (out.length > 0) process.stdout.write(out.join("\n") + "\n");
