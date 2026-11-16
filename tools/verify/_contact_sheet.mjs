// The contact sheet's browser (tools/verify/contact-sheet): one headless
// Chromium (Playwright, the project's @playwright/test) takes a full-page
// screenshot of each page route at each width, in each colour scheme, and lists
// what axe couldn't decide on it, and what the layout check reports on it.
//   node tools/verify/_contact_sheet.mjs <origin> <seconds> <folder> <commit> <route>...
// For each route, each width (390, 768, 1280; the window 900 tall) and each
// scheme (light, dark), in that order, it opens <origin><route> in a fresh
// browser context with reduced motion, waits, at most <seconds>, for the page to
// load and its network to go quiet (networkidle), and writes the whole page,
// animations stopped, to <folder>/<slug>-<width>-<scheme>.png (_routes.mjs's
// routeSlug: `home` for `/`, `therapy-about` for `/therapy/about`), as the
// Board names its files. At 390 and 1280 px (AXE_WIDTHS, smoke's axe widths) it
// then runs axe on the page (_axe.mjs: smoke's rules) and keeps its incomplete
// results: what axe checked and couldn't decide, such as the contrast of text
// over an image or a gradient. In the light scheme it then runs the layout
// check (_layout.mjs, smoke's) on a page that carries [data-shell] and keeps
// its reported items: one-word lines, ragged and short paragraphs, which no
// measure can rule on alone; a route whose page had one at 390 px is taken at
// 1920 px too (<slug>-1920-light.png), light alone, so each of the layout
// check's widths has a screenshot. Then <folder>/index.md lists each route's
// screenshots, under a line naming <commit>, the commit the sheet was taken
// from, and under `## Axe couldn't decide` those results, for the Verifier to
// judge by eye: one line per route, rule and selector (_axe.mjs's describe),
//   - `<route>` <rule id> `<selector>`: <axe's message> (<screenshot>, ...)
// naming the screenshots it showed in, axe's message for the first of them
// (its help when it gives none), or `- none`; an axe run that failed is a line
// of its own there,
//   - `<route>` <width> <scheme>: axe didn't run: <why>
// and no finding: the list gates nothing. Under `## Layout to judge` come the
// layout check's reported items, for the Verifier to judge by eye in the
// screenshot each names: one line per route, width, check and selector,
//   - `<route>` <width> <check> `<selector>`: <measured> (want <expected>) (<screenshot>)
// in the order taken, or `- none`; a layout check that failed is a line there,
//   - `<route>` <width> light: the layout check didn't run: <why>
// and no finding either. The folder must exist; the caller empties it first.
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
import { axe, describe } from "./_axe.mjs";
import { layoutOf, REPORTED } from "./_layout.mjs";
import { routeSlug } from "./_routes.mjs";

const [origin, seconds, folder, commit, ...routes] = process.argv.slice(2);
const limit = Number(seconds) * 1000;
const WIDTHS = [390, 768, 1280];
const AXE_WIDTHS = [390, 1280];
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

// undecided: axe's incomplete results, by `<route> <rule> <selector>`, with
// the screenshots they showed in and the message of the first; unrun: the
// lines for the axe runs that failed.
const undecided = new Map();
const unrun = [];
// layoutLines: the layout check's reported items, and its failed runs, as the
// index lists them; shelled: the routes whose page carried [data-shell].
const layoutLines = [];
const shelled = new Set();

// undecide(route, name, page): axe's incomplete results on the page, whose
// screenshot is <name>, kept in undecided.
const undecide = async (route, name, page) => {
  const result = await axe(page);
  for (const v of result.incomplete)
    for (const node of v.nodes) {
      const target = await describe(page, node.target);
      const key = `\`${route}\` ${v.id} \`${target}\``;
      const known = undecided.get(key) ?? {
        message:
          [...node.any, ...node.all, ...node.none].find((c) => c.message)
            ?.message ?? v.help,
        shots: [],
      };
      if (!known.shots.includes(name)) known.shots.push(name);
      undecided.set(key, known);
    }
};

// shoot(route, width, scheme): the screenshot's file name, or null with a
// finding when it wasn't taken; at AXE_WIDTHS, axe's undecided results too.
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
    if (AXE_WIDTHS.includes(width))
      try {
        await undecide(route, name, page);
      } catch (e) {
        unrun.push(
          `- \`${route}\` ${width} ${scheme}: axe didn't run: ${strip(firstLine(e))}`,
        );
      }
    if (scheme === "light")
      try {
        const layout = await layoutOf(page);
        if (layout) shelled.add(route);
        for (const item of layout?.items ?? [])
          if (REPORTED.includes(item.check))
            layoutLines.push(
              `- \`${route}\` ${width} ${item.check} \`${item.selector}\`: ${strip(item.measured)} (want ${item.want}) (${name})`,
            );
      } catch (e) {
        layoutLines.push(
          `- \`${route}\` ${width} light: the layout check didn't run: ${strip(firstLine(e))}`,
        );
      }
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
  `Taken from ${commit}: each page route at ${WIDTHS.join(", ")} px wide (the window ${HEIGHT} tall, the whole page captured), light and dark, with reduced motion, and at 1920 px, light, when its page carries [data-shell]. Each file is \`<route-slug>-<width>-<scheme>.png\`, named as the Board's are (\`docs/design/board/\`).`,
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
    if (shelled.has(route)) {
      const name = await shoot(route, 1920, "light");
      if (name) names.push(name);
    }
    index.push(`- \`${route}\`: ${names.join(", ") || "no screenshot"}`);
  }
} finally {
  await browser.close();
}
index.push(
  "",
  "## Axe couldn't decide",
  "",
  `What axe checked at ${AXE_WIDTHS.join(" and ")} px and couldn't decide (its incomplete results; smoke's rules), such as the contrast of text over an image: judge each by eye in the screenshots it names. None gates. One line per route, rule and selector:`,
  "",
);
const undecidedLines = [...undecided].map(
  ([key, { message, shots }]) =>
    `- ${key}: ${strip(message)} (${shots.join(", ")})`,
);
if (undecidedLines.length + unrun.length === 0) index.push("- none");
index.push(...undecidedLines, ...unrun);
index.push(
  "",
  "## Layout to judge",
  "",
  "What the layout check (_layout.mjs) reports on the pages that carry [data-shell], in the light scheme: lines of one word, ragged and short paragraphs. None gates: judge each by eye in the screenshot it names, a fault when it shows (a word stranded on a line of its own, a paragraph's right edge ragged, a statement stopping well short with empty space beside it), none when the break reads as meant. One line per route, width, check and selector:",
  "",
);
if (layoutLines.length === 0) index.push("- none");
index.push(...layoutLines);
writeFileSync(join(folder, "index.md"), index.join("\n") + "\n");
process.stdout.write(
  [...new Set(out)]
    .sort()
    .map((l) => l + "\n")
    .join(""),
);
