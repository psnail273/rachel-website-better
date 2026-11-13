// The Scenario driver's Playwright config (tools/verify/scenarios): Playwright's
// test runner (the project's @playwright/test) runs one Scenario file with it,
//   playwright test --config tools/verify/_scenarios.config.mjs
// with these set by the driver:
//   FACTORY_SCENARIO_DIR      the Scenario folder, absolute
//   FACTORY_SCENARIO_FILE     the one Scenario file to run, absolute
//   FACTORY_SCENARIO_ORIGIN   the started app, http://127.0.0.1:<port>: the
//                             baseURL, so page.goto("/") opens its `/`
//   FACTORY_SCENARIO_REPORT   where the json reporter writes
//   FACTORY_SCENARIO_OUTPUT   Playwright's output folder (the driver's temp)
// One worker, no retries, headless Chromium (the browser bootstrap installs for
// smoke), Playwright's own timeouts (30 s a test, 5 s an expect; a script may
// set its own). The list reporter's lines go to the driver's stderr.
const env = (name) => {
  const value = process.env[name];
  if (!value)
    throw new Error(`${name} is not set; run bash tools/verify/scenarios`);
  return value;
};
const literal = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

export default {
  testDir: env("FACTORY_SCENARIO_DIR"),
  testMatch: [new RegExp(`^${literal(env("FACTORY_SCENARIO_FILE"))}$`)],
  outputDir: env("FACTORY_SCENARIO_OUTPUT"),
  workers: 1,
  retries: 0,
  fullyParallel: false,
  reporter: [
    ["list"],
    ["json", { outputFile: env("FACTORY_SCENARIO_REPORT") }],
  ],
  use: { baseURL: env("FACTORY_SCENARIO_ORIGIN"), headless: true },
};
