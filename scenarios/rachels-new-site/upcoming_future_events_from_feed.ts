import { test } from "@playwright/test";
import { expectFixtureShown, fixture, revalidate, serveFeed } from "./support";

test("with the feed serving the fixture, Home shows only the future events, soonest first, the run as one ranged card", async ({
  page,
  request,
}) => {
  const f = fixture();
  await serveFeed(request, f.ics);
  await revalidate(request);
  await page.goto("/");
  await expectFixtureShown(page, f);
});
