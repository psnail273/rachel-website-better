// The test step's reader of Vitest's JSON report (--reporter=json):
//   node tools/verify/_vitest_results.mjs <report.json> [<declared> [<errors>]]
// prints one line per test, `<file>\t<line>\t<name>\t<status>`, which the step
// sorts into the Core's results file (factory/core/lib/results.sh). <file> is
// the test file relative to the working directory (the project root), <line>
// where the test is declared (Vitest's location, which --includeTaskLocation
// turns on; 1 without it).
//
// <name> is the test file, then each describe block's title, then the test's
// own, joined by " > ": `app/api/health/route.test.ts > GET /api/health >
// answers ok`, as Vitest prints a failing test. A tab, a newline, a carriage
// return or another control character in a title shows as \t, \n, \r or \xNN, so
// the name stays on its line. Two tests with one name (the same titles in the
// same file) are one line: the worst status, at the first one's line.
//
// <status>:
//   PASS      the test passed
//   FAILURE   it failed on an assertion: its first error is an AssertionError
//             (expect's matchers, assert, expect.soft, expect.unreachable), or
//             one of expect's own Errors: expect.assertions and
//             expect.hasAssertions counted wrong, .resolves or .rejects got the
//             other outcome, a snapshot mismatched, or expect.poll's matcher
//             failed (Vitest rethrows it as an Error whose message starts
//             "expected")
//   ERROR     any other failure (a thrown error, a timeout, a missing stub), or
//             a test that never finished
//   SKIP      skipped or todo (it.skip, it.todo, a filter; a test whose
//             beforeAll failed is skipped too, and its file's line is ERROR)
// A test file whose own run failed (it didn't import, it threw at its top level,
// it has no test, or a hook or its suite failed where no test of it did) is one
// more line, named by the file alone, ERROR at line 1; so is each file listed in
// <declared> (one path a line: test files that declare tests) that the report
// doesn't hold, a test file Vitest didn't run, and each file <errors>
// (_vitest_errors.mjs's lines) names as running when an unhandled error came. An
// unhandled error with no file is a line named `unhandled error`, ERROR at
// tools/verify/test:1. A run with such an error is never all PASS, nor only
// FAILURE: the error may be what made a test pass, or fail.
//
// Exits 2 when the report isn't Vitest's JSON.
import { readFileSync } from "node:fs";
import { relative, sep } from "node:path";

let report;
try {
  report = JSON.parse(readFileSync(process.argv[2], "utf8"));
  if (!Array.isArray(report?.testResults)) throw new Error("no testResults");
} catch (error) {
  console.error(`_vitest_results: ${process.argv[2]}: ${error.message}`);
  process.exit(2);
}

const RANK = { PASS: 0, SKIP: 1, FAILURE: 2, ERROR: 3 };

const escape = (text) =>
  String(text).replace(/[\x00-\x1f\x7f]/g, (c) => {
    if (c === "\t") return "\\t";
    if (c === "\n") return "\\n";
    if (c === "\r") return "\\r";
    return "\\x" + c.charCodeAt(0).toString(16).padStart(2, "0");
  });

// assertion: whether a failure (its stack, else its message) is an assertion's.
const assertion = (failure) => {
  const text = String(failure ?? "");
  const first = text.split("\n", 1)[0];
  if (/^AssertionError(:|$)/.test(first)) return true;
  if (!first.startsWith("Error: ")) return false;
  const message = text.slice("Error: ".length);
  if (/^expected (number of assertions to be|any number of assertion)/.test(message)) return true;
  if (/^promise resolved "[\s\S]*" instead of rejecting/.test(message)) return true;
  if (/^promise rejected "[\s\S]*" instead of resolving/.test(message)) return true;
  if (/^Snapshot `[\s\S]*` mismatched/.test(message)) return true;
  return /^\s+at (Proxy\.)?__VITEST_POLL_CHAIN__/m.test(text) && message.startsWith("expected ");
};

const statusOf = (test) => {
  switch (test.status) {
    case "passed":
      return "PASS";
    case "failed":
      return assertion(test.failureMessages?.[0]) ? "FAILURE" : "ERROR";
    case "skipped":
    case "todo":
    case "disabled":
      return "SKIP";
    default:
      return "ERROR";
  }
};

const tests = new Map();
const add = (file, line, name, status) => {
  const key = `${file}\t${name}`;
  const was = tests.get(key);
  if (!was) tests.set(key, { file, line, name, status });
  else {
    if (RANK[status] > RANK[was.status]) was.status = status;
    if (line < was.line) was.line = line;
  }
};

const reported = new Set();
for (const result of report.testResults) {
  const file = relative(process.cwd(), String(result.name)).split(sep).join("/");
  reported.add(file);
  let failed = false;
  for (const test of result.assertionResults ?? []) {
    const line = Number.isInteger(test.location?.line) && test.location.line > 0 ? test.location.line : 1;
    const titles = [...(test.ancestorTitles ?? []), test.title ?? ""];
    const status = statusOf(test);
    if (status === "FAILURE" || status === "ERROR") failed = true;
    add(file, line, [file, ...titles].map(escape).join(" > "), status);
  }
  if (result.message || (result.status === "failed" && !failed)) add(file, 1, escape(file), "ERROR");
}

if (process.argv[3]) {
  for (const file of readFileSync(process.argv[3], "utf8").split("\n")) {
    if (file && !reported.has(file)) add(file, 1, escape(file), "ERROR");
  }
}

if (process.argv[4]) {
  for (const line of readFileSync(process.argv[4], "utf8").split("\n")) {
    if (!line) continue;
    const path = line.split("\t", 1)[0];
    if (!path) add("tools/verify/test", 1, "unhandled error", "ERROR");
    else {
      const file = relative(process.cwd(), path).split(sep).join("/");
      add(file, 1, escape(file), "ERROR");
    }
  }
}

const out = [...tests.values()].map((t) => `${t.file}\t${t.line}\t${t.name}\t${t.status}`);
if (out.length > 0) process.stdout.write(out.join("\n") + "\n");
