// The mutate step's reader of StrykerJS's JSON report (its json reporter, the
// mutation-testing-report-schema):
//   node tools/verify/_stryker_mutants.mjs <report.json> [<ranges>]
// prints one line per mutant (with <ranges>, only those inside them: a file of
// lines <file>, for the whole file, or <file>\t<first line>\t<last line>, as
// Stryker's mutate ranges, a mutant inside when it starts and ends on those
// lines; the mutate step's, in the Editor's loop, whose incremental report
// carries results for code it no longer mutates),
//   <file>\t<line>\t<column>\t<status>\t<mutator>: `<code>` -> `<mutant>`\t<tests>
// <file> as the report names it (relative to the project root); <line> and
// <column> where the mutant starts, from 1. <status>: killed, survived (Survived,
// or NoCoverage: no test reached it), timed-out, ignored (a `// Stryker disable`
// comment kept it from running), or errored (CompileError, RuntimeError, and any
// other). <code> is the source the mutant replaces, up to its line's end and
// then ... when it runs over more lines; it and <mutant> show a tab, a newline
// or a carriage return as \t, \n or \r. <tests> is the test files whose tests
// covered the mutant, comma-separated, or none; or "all (static)" for a static
// mutant (one in code that runs as its module loads, such as a module-level
// constant), which Stryker runs against every test of the files related to it.
//
// Exits 2 when the report isn't Stryker's JSON.
import { readFileSync } from "node:fs";

let report;
try {
  report = JSON.parse(readFileSync(process.argv[2], "utf8"));
  if (!report?.files || typeof report.files !== "object") throw new Error("no files");
} catch (error) {
  console.error(`_stryker_mutants: ${process.argv[2]}: ${error.message}`);
  process.exit(2);
}

// The ranges, by file: true for the whole file, else [first, last] pairs.
let ranges = null;
if (process.argv[3]) {
  ranges = new Map();
  for (const line of readFileSync(process.argv[3], "utf8").split("\n")) {
    if (!line) continue;
    const [file, first, last] = line.split("\t");
    if (first === undefined) ranges.set(file, true);
    else if (ranges.get(file) !== true)
      ranges.set(file, [...(ranges.get(file) ?? []), [Number(first), Number(last)]]);
  }
}
const inRanges = (file, start, end) => {
  if (ranges === null) return true;
  const r = ranges.get(file);
  return r === true || (r ?? []).some(([first, last]) => start.line >= first && end.line <= last);
};

const STATUS = {
  Killed: "killed",
  Survived: "survived",
  NoCoverage: "survived",
  Timeout: "timed-out",
  Ignored: "ignored",
};

const shown = (text) =>
  String(text).replace(/[\t\n\r]/g, (c) => (c === "\t" ? "\\t" : c === "\n" ? "\\n" : "\\r"));

// The test file of each test id.
const testFile = new Map();
for (const [file, entry] of Object.entries(report.testFiles ?? {})) {
  for (const test of entry?.tests ?? []) testFile.set(String(test.id), file);
}

const out = [];
for (const [file, entry] of Object.entries(report.files)) {
  const lines = String(entry?.source ?? "").split("\n").map((l) => l.replace(/\r$/, ""));
  for (const m of entry?.mutants ?? []) {
    const start = m.location?.start ?? { line: 1, column: 1 };
    const end = m.location?.end ?? start;
    if (!inRanges(file, start, end)) continue;
    const text = lines[start.line - 1] ?? "";
    const code =
      end.line === start.line
        ? text.slice(start.column - 1, end.column - 1)
        : text.slice(start.column - 1) + "...";
    const files = m.static
      ? ["all (static)"]
      : [...new Set((m.coveredBy ?? []).map((id) => testFile.get(String(id))).filter(Boolean))].sort();
    const status = STATUS[m.status] ?? "errored";
    const change = `${m.mutatorName}: \`${shown(code)}\` -> \`${shown(m.replacement ?? "")}\``;
    out.push([file, start.line, start.column, status, change, files.join(", ") || "none"].join("\t"));
  }
}
if (out.length > 0) process.stdout.write(out.join("\n") + "\n");
