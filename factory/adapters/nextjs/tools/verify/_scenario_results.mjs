// The Scenario driver's reader of one Scenario's Playwright report (the json
// reporter's, _scenarios.config.mjs):
//   node tools/verify/_scenario_results.mjs <report.json> <scenario file, absolute>
// prints one line, `<status>\t<line>`: the Scenario's worst test's status, at the
// line of the first test with it (where its `test(` is declared).
//
// A test's status:
//   PASS      it passed (or failed as test.fail() said it would)
//   FAILURE   it failed on a check: its first error is a matcher's
//             (`Error: expect(locator).toHaveText(expected) failed`, from
//             expect, expect.soft, expect.poll or toPass), after the message a
//             script gave it too (`Error: <message>`, a blank line, then the
//             matcher's); expect.poll with a message of its own writes no
//             matcher, and is ERROR
//   ERROR     any other failure (a thrown error, a timeout, a browser or page
//             that went away), or an interrupted run
//   SKIP      skipped (test.skip, test.fixme, a condition)
// Worst first: ERROR, FAILURE, SKIP, PASS. An error outside every test (the
// file didn't load, threw at its top level) is ERROR, at its line when it is in
// the Scenario's file, else at line 1; so is a report with no test and no error.
// The line is the first one with the worst status.
//
//   node tools/verify/_scenario_results.mjs --each <report.json>
// prints a line for each test instead, `<status>\t<title>`, in the report's
// order: the looks' run (_scenario_looks.mjs), whose tests are titled with
// their baselines' names. An error outside every test prints nothing: the
// driver counts each look it doesn't find an ERROR.
//
// Exits 2 when the report isn't Playwright's JSON.
import { readFileSync } from "node:fs";

const each = process.argv[2] === "--each";
const [reportPath, file] = process.argv.slice(each ? 3 : 2);
let report;
try {
  report = JSON.parse(readFileSync(reportPath, "utf8"));
  if (!Array.isArray(report?.suites)) throw new Error("no suites");
} catch (error) {
  console.error(`_scenario_results: ${reportPath}: ${error.message}`);
  process.exit(2);
}

const RANK = { PASS: 0, SKIP: 1, FAILURE: 2, ERROR: 3 };
const plain = (text) => String(text ?? "").replace(/\u001b\[[0-9;]*m/g, "");

// A matcher's failure, as expect writes it: `expect(<what>)[.not].<matcher>(`.
const MATCHER =
  /^(Timed out \d+ms waiting for )?expect(\.soft|\.poll)?\([^)]*\)(\.(not|resolves|rejects))*\.\w+\(/;
// assertion: whether an error is expect's: its first line is a matcher's
// failure, or, after a message the script gave (expect(x, "why")), its third.
const assertion = (error) => {
  const lines = plain(error?.message).split("\n");
  return (
    MATCHER.test(lines[0].replace(/^Error: /, "")) ||
    (lines[1] === "" && MATCHER.test(lines[2] ?? ""))
  );
};

const statusOf = (test) => {
  const last = test.results?.at(-1);
  if (test.status === "skipped" || last?.status === "skipped") return "SKIP";
  if (test.status === "expected") return "PASS";
  if (last?.status === "failed" && assertion(last.errors?.[0] ?? last.error))
    return "FAILURE";
  return "ERROR";
};

const found = [];
const walk = (suite) => {
  for (const spec of suite.specs ?? [])
    for (const test of spec.tests ?? [])
      found.push({
        status: statusOf(test),
        line: spec.line || 1,
        title: spec.title,
      });
  for (const inner of suite.suites ?? []) walk(inner);
};
report.suites.forEach(walk);
if (each) {
  process.stdout.write(
    found.map((f) => `${f.status}\t${f.title}\n`).join(""),
  );
  process.exit(0);
}
// Outside every test: the errors located in the file, else the others (with no
// test loaded, Playwright adds "No tests found" to a load error).
const errors = report.errors ?? [];
const located = errors.filter((e) => e.location?.file === file);
if (located.length > 0)
  for (const error of located)
    found.push({ status: "ERROR", line: error.location.line || 1 });
else if (errors.length > 0) found.push({ status: "ERROR", line: 1 });

let worst = { status: "ERROR", line: 1 };
if (found.length > 0) {
  found.sort((a, b) => a.line - b.line);
  worst = found[0];
  for (const f of found) if (RANK[f.status] > RANK[worst.status]) worst = f;
}
process.stdout.write(`${worst.status}\t${worst.line}\n`);
