import { expect, test, type Page } from "@playwright/test";
import {
  fixture,
  revalidate,
  serveFeed,
  stopFeed,
  type Fixture,
} from "./support";

// The strip by its current names: the region "Upcoming", its cards in the list
// "Upcoming events". Shows the fixture's future events only, soonest first,
// with the consecutive-day run as one card showing a date range.
async function expectFixtureShown(page: Page, f: Fixture) {
  const strip = page.getByRole("region", { name: "Upcoming", exact: true });
  await expect(
    strip.getByRole("heading", { level: 2, name: "Upcoming" }),
  ).toBeVisible();
  const cards = strip
    .getByRole("list", { name: "Upcoming events" })
    .getByRole("listitem");
  await expect(cards.getByRole("heading", { level: 3 })).toHaveText(f.future);
  await expect(cards.filter({ hasText: f.past })).toHaveCount(0);
  // One card for the run, showing its first and last day as a range (the
  // fixture's run is October 16 to 18 next year), in any order of day and month.
  const run = cards.filter({ hasText: f.run.title });
  await expect(run).toHaveCount(1);
  await expect(run).toContainText(/\b16\s*[–-]\s*(?:Oct\w*\s*)?18\b/);
  await expect(run).toContainText(/\bOct/);
}

test("after the feed goes unreachable, Home still shows the same future events from the cache", async ({
  page,
  request,
}) => {
  const f = fixture();
  await serveFeed(request, f.ics);
  await revalidate(request);
  await page.goto("/");
  await expectFixtureShown(page, f);

  await stopFeed(request);
  await revalidate(request);
  await page.goto("/");
  await expectFixtureShown(page, f);
});
