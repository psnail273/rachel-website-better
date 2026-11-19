// The lint step's reader of secretlint's JSON report (--format json, secrets
// masked):
//   node tools/verify/_secretlint_findings.mjs <report.json>
// prints one finding per message, `<file>:<line> secret-<rule> <message>`, the
// file relative to the working directory (the project root) and <rule> the
// secretlint rule's id without its @secretlint/secretlint-rule- prefix
// (secret-aws, secret-privatekey, secret-github). A message with no rule is
// secret-other. The message is secretlint's, its secret masked as secretlint
// masks it, so the finding never carries it. A message without a line is at
// line 1; whitespace runs become one space. Exits 2 when the report isn't
// secretlint's JSON.
import { readFileSync } from "node:fs";
import { relative, sep } from "node:path";

let report;
try {
  report = JSON.parse(readFileSync(process.argv[2], "utf8"));
  if (!Array.isArray(report)) throw new Error("not an array of results");
} catch (error) {
  console.error(`_secretlint_findings: ${process.argv[2]}: ${error.message}`);
  process.exit(2);
}

const out = [];
for (const result of report) {
  const file = relative(process.cwd(), String(result.filePath)).split(sep).join("/");
  for (const m of result.messages ?? []) {
    const rule = String(m.ruleId ?? "")
      .replace(/^@secretlint\/secretlint-rule-/, "")
      .replace(/[^A-Za-z0-9._-]+/g, "-");
    const text = String(m.message ?? "")
      .replace(/\s+/g, " ")
      .trim();
    const line = Number.isInteger(m.loc?.start?.line) && m.loc.start.line > 0 ? m.loc.start.line : 1;
    out.push(`${file}:${line} secret-${rule || "other"} ${text || "(no message)"}`);
  }
}
if (out.length > 0) process.stdout.write(out.join("\n") + "\n");
