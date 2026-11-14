import { test } from "@playwright/test";
import {
  expectFixtureShown,
  fixture,
  revalidate,
  serveFeed,
  stopFeed,
} from "./support";

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
