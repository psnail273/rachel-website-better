import { expect, test } from "@playwright/test";
import { style } from "./support";

test("an unknown URL shows the not-found page in the site's palette, and Back to Home opens Home", async ({
  page,
}) => {
  // The site's palette, as a known page shows it.
  await page.goto("/contact");
  const knownHeading = page.getByRole("heading", { level: 1 });
  await expect(knownHeading).toBeVisible();
  const siteBackground = await style(page.locator("body"), "background-color");
  const siteText = await style(page.locator("body"), "color");
  const siteHeading = await style(knownHeading, "color");

  await page.goto(`/no-such-page-${Date.now()}`);
  const heading = page.getByRole("heading", {
    level: 1,
    name: "This page wandered off",
  });
  await expect(heading).toBeVisible();
  expect(
    await style(page.locator("body"), "background-color"),
    "the page background is the site's",
  ).toBe(siteBackground);
  expect(
    await style(page.locator("body"), "color"),
    "the text colour is the site's",
  ).toBe(siteText);
  expect(await style(heading, "color"), "the heading colour is the site's").toBe(
    siteHeading,
  );

  await page.getByRole("link", { name: "Back to Home" }).click();
  await expect(page).toHaveURL(/^[^?#]*:\/\/[^/]+\/$/);
  await expect(
    page.getByRole("heading", { level: 1, name: "Rachel Siegel" }),
  ).toBeVisible();
});
