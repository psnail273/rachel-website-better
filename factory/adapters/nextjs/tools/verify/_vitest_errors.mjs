// The test step's Vitest reporter for the errors no test holds: Vitest's JSON
// report leaves out an unhandled rejection or an uncaught exception, which can
// come while a test that passes, or fails on its assertion, runs.
//   vitest run --reporter=<this file>   (FACTORY_VITEST_ERRORS names the output)
// At the run's end it writes one line per unhandled error,
//   <test file>\t<type>: <message>
// <test file> the absolute path of the file Vitest says was running, else empty;
// the message on one line. _vitest_results.mjs reads it.
import { writeFileSync } from "node:fs";

export default class {
  onTestRunEnd(_modules, errors) {
    const out = process.env.FACTORY_VITEST_ERRORS;
    if (!out) return;
    const lines = (errors ?? []).map((e) => {
      const what = `${e?.type ?? "Error"}: ${e?.message ?? e?.name ?? "unknown"}`;
      return `${e?.VITEST_TEST_PATH ?? ""}\t${what.replace(/\s+/g, " ")}\n`;
    });
    writeFileSync(out, lines.join(""));
  }
}
