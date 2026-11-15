// The contact sheet's browser (tools/verify/contact-sheet): one headless
// Chromium (Playwright, the project's @playwright/test) takes a full-page
// screenshot of each page route at each width, in each colour scheme.
//   node tools/verify/_contact_sheet.mjs <origin> <seconds> <folder> <commit> <route>...
// For each route, each width (390, 768, 1280; the window 900 tall) and each
// scheme (light, dark), in that order, it opens <origin><route> in a fresh
// browser context with reduced motion, waits, at most <seconds>, for the page to
// load and its network to go quiet (networkidle), and writes the whole page,
// animations stopped, to <folder>/<slug>-<width>-<scheme>.png (_routes.mjs's
// routeSlug: `home` for `/`, `therapy-about` for `/therapy/about`), as the
// Board names its files. Then <folder>/index.md lists each route's screenshots,
// under a line naming <commit>, the commit the sheet was taken from. The
// folder must exist; the caller empties it first.
//
// stdout: one finding a line, sorted, the origin left out of every message:
//   package.json:1 contact-sheet-load <route> <width> <scheme>: <why the page
//                  never loaded or its screenshot wasn't taken>
//   tools/verify/local.env:1 browser-missing <why Chromium didn't start>
// A screenshot that wasn't taken is left out of the index.
// Exits 0 when it got as far as the pages (findings or none), 1 when Chromium
// didn't start.
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { chromium } from "@playwright/test";
import { routeSlug } from "./_routes.mjs";

const [origin, seconds, folder, commit, ...routes] = process.argv.slice(2);
const limit = Number(seconds) * 1000;
const WIDTHS = [390, 768, 1280];
const HEIGHT = 900;
const SCHEMES = ["light", "dark"];
const out = [];
const host = origin.replace(/^[a-z]+:\/\//, "");
const strip = (s) =>
  String(s)
    .split(origin)
    .join("")
    .split(host)
    .join("<host>")
    .replace(/\s+/g, " ")
    .trim();
const firstLine = (e) => String(e?.message ?? e).split("\n")[0];

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

// shoot(route, width, scheme): the screenshot's file name, or null with a
// finding when it wasn't taken.
const shoot = async (route, width, scheme) => {
  const name = `${routeSlug(route)}-${width}-${scheme}.png`;
  const context = await browser.newContext({
    viewport: { width, height: HEIGHT },
    colorScheme: scheme,
    reducedMotion: "reduce",
  });
  try {
    const page = await context.newPage();
    await page.goto(origin + route, {
      waitUntil: "networkidle",
      timeout: limit,
    });
    await page.screenshot({
      path: join(folder, name),
      fullPage: true,
      animations: "disabled",
      timeout: limit,
    });
    return name;
  } catch (e) {
    out.push(
      `package.json:1 contact-sheet-load ${route} ${width} ${scheme}: ${strip(firstLine(e))}`,
    );
    return null;
  } finally {
    await context.close();
  }
};

const index = [
  "# Contact sheet",
  "",
  `Taken from ${commit}: each page route at ${WIDTHS.join(", ")} px wide (the window ${HEIGHT} tall, the whole page captured), light and dark, with reduced motion. Each file is \`<route-slug>-<width>-<scheme>.png\`, named as the Board's are (\`docs/design/board/\`).`,
  "",
];
try {
  for (const route of routes) {
    const names = [];
    for (const width of WIDTHS)
      for (const scheme of SCHEMES) {
        const name = await shoot(route, width, scheme);
        if (name) names.push(name);
      }
    index.push(`- \`${route}\`: ${names.join(", ") || "no screenshot"}`);
  }
} finally {
  await browser.close();
}
writeFileSync(join(folder, "index.md"), index.join("\n") + "\n");
process.stdout.write(
  [...new Set(out)]
    .sort()
    .map((l) => l + "\n")
    .join(""),
);
