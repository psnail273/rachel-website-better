import { expect, test } from "@playwright/test";
import { revalidate, stopFeed } from "./support";

// The feed unreachable and the cache empty: the driver starts this file with
// the events cache empty, and nothing serves CALENDAR_FEED_URL; the app renders
// Home afresh from that.
test("with the feed unreachable and an empty cache, Home's strip shows the fallback and the page has no error", async ({
  page,
  request,
}) => {
  await stopFeed(request);
  await revalidate(request);
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });

  const response = await page.goto("/");
  expect(response?.status()).toBe(200);

  const strip = page.getByRole("region", { name: "Upcoming", exact: true });
  await expect(
    strip.getByRole("heading", { level: 2, name: "Upcoming" }),
  ).toBeVisible();
  await expect(
    strip.getByText("Events are unavailable right now."),
  ).toBeVisible();
  await expect(
    strip.getByRole("link", { name: "See the full calendar" }),
  ).toHaveAttribute("href", /^https:\/\/calendar\.google\.com\/calendar\//);
  await expect(
    page.getByRole("region", { name: "Upcoming events" }),
  ).toHaveCount(0);
  await page.waitForLoadState("networkidle");
  expect(errors).toEqual([]);
});
