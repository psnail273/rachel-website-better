// The smoke step's browser: loads one page headless in Chromium (Playwright,
// the project's @playwright/test) and prints what went wrong on it.
//   node tools/verify/_smoke_page.mjs <origin> <path> <seconds>
// It opens <origin><path> and waits, at most <seconds>, for the page to load and
// its network to go quiet (Playwright's networkidle: no request for 500 ms),
// so the requests its scripts make count too.
//
// stdout: one finding a line, the origin left out of every message (the server's
// port changes from run to run, and a finding must not):
//   package.json:1 smoke-console <path>: console error: <text>
//   package.json:1 smoke-page-error <path>: uncaught <name>: <message>
//   package.json:1 smoke-response <path>: <request path> answered <status>
//   package.json:1 smoke-request-failed <path>: <request path> failed: <reason>
//   package.json:1 smoke-load <path>: <why the page never loaded>
//   tools/verify/local.env:1 browser-missing <why Chromium didn't start>
// A response is judged on its status: 2xx passes, and so does a redirect (3xx
// with a Location), whose target is judged in turn; any other fails.
// Exits 0 when it got as far as judging the page (findings or none), 1 when
// Chromium didn't start.
import { chromium } from "@playwright/test";

const [origin, path, seconds] = process.argv.slice(2);
const limit = Number(seconds) * 1000;
const out = [];
const strip = (s) =>
  String(s).split(origin).join("").replace(/\s+/g, " ").trim();
const finding = (rule, message) =>
  out.push(`package.json:1 ${rule} ${path}: ${strip(message)}`);

let browser;
try {
  browser = await chromium.launch({ headless: true });
} catch (e) {
  const first = strip(
    String(e?.message ?? e)
      .split("\n")
      .find((l) => l.trim() !== "") ?? "unknown",
  );
  console.log(
    `tools/verify/local.env:1 browser-missing Chromium didn't start (${first}); run bash tools/verify/bootstrap, which installs it into PLAYWRIGHT_BROWSERS_PATH (tools/verify/local.env), and if it names missing system libraries: pnpm exec playwright install-deps chromium`,
  );
  process.exit(1);
}
try {
  const page = await browser.newPage();
  page.on("console", (m) => {
    if (m.type() === "error")
      finding("smoke-console", `console error: ${m.text()}`);
  });
  page.on("pageerror", (e) =>
    finding("smoke-page-error", `uncaught ${e.name}: ${e.message}`),
  );
  page.on("response", (r) => {
    const status = r.status();
    const redirect =
      status >= 300 && status < 400 && r.headers()["location"] !== undefined;
    if ((status < 200 || status >= 300) && !redirect)
      finding("smoke-response", `${r.url()} answered ${status}`);
  });
  page.on("requestfailed", (r) =>
    finding(
      "smoke-request-failed",
      `${r.url()} failed: ${r.failure()?.errorText ?? "unknown"}`,
    ),
  );
  try {
    await page.goto(origin + path, {
      waitUntil: "networkidle",
      timeout: limit,
    });
  } catch (e) {
    finding(
      "smoke-load",
      `the page didn't load and go quiet within ${seconds}s: ${String(e?.message ?? e).split("\n")[0]}`,
    );
  }
} finally {
  await browser.close();
}
process.stdout.write(
  [...new Set(out)]
    .sort()
    .map((l) => l + "\n")
    .join(""),
);
