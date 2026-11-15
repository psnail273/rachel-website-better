// The Scenario driver's looks (tools/verify/scenarios): Playwright's test runner
// runs this file with _scenarios.config.mjs, before any Scenario, to hold each
// page route's look to the baseline recorded when the human last approved a
// Playtest. Set by the driver, beside the config's:
//   FACTORY_SCENARIO_LOOKS    the baselines' folder, absolute: <Scenario
//                             folder>/looks
//   FACTORY_SCENARIO_ROUTES   the page routes (_routes.mjs), one a line
// One test per route, width (390, 1280; the window 900 tall) and scheme (light,
// dark), with reduced motion, titled with its baseline's name,
// `<route-slug>-<width>-<scheme>` (_routes.mjs's routeSlug, as the Board names
// its files): it opens the route, waits for its network to go quiet, and
// checks the whole page against <looks>/<title>.png (toHaveScreenshot, with
// the config's maxDiffPixelRatio, animations stopped and the caret hidden).
// With no baseline it takes the page as it is now, the whole page with
// animations stopped, to <its output folder>/<title>-actual.png for the human
// to judge, and is skipped, saying so; unless the run records them (`playwright
// test --update-snapshots=changed`, the driver's record mode, which writes a
// baseline that is missing or differs).
import { existsSync } from "node:fs";
import { join } from "node:path";
import { expect, test } from "@playwright/test";
import { routeSlug } from "./_routes.mjs";

const looks = process.env.FACTORY_SCENARIO_LOOKS ?? "";
const routes = (process.env.FACTORY_SCENARIO_ROUTES ?? "")
  .split("\n")
  .filter((r) => r !== "");
const HEIGHT = 900;

for (const width of [390, 1280])
  for (const colorScheme of ["light", "dark"])
    test.describe(`${width} ${colorScheme}`, () => {
      test.use({
        viewport: { width, height: HEIGHT },
        colorScheme,
        reducedMotion: "reduce",
      });
      for (const route of routes) {
        const name = `${routeSlug(route)}-${width}-${colorScheme}`;
        test(name, async ({ page }, testInfo) => {
          await page.goto(route, { waitUntil: "networkidle" });
          if (
            testInfo.config.updateSnapshots === "none" &&
            !existsSync(join(looks, `${name}.png`))
          ) {
            await page.screenshot({
              path: testInfo.outputPath(`${name}-actual.png`),
              fullPage: true,
              animations: "disabled",
            });
            test.skip(
              true,
              `no baseline ${name}.png: the next Playtest the human approves records it`,
            );
          }
          await expect(page).toHaveScreenshot(`${name}.png`, {
            fullPage: true,
          });
        });
      }
    });
