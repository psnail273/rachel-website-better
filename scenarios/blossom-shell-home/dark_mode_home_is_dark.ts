import { expect, test } from "@playwright/test";
import { luminance, parseColor, style } from "./support";

test.use({ colorScheme: "dark" });

test("with dark mode emulated, Home's page background is dark and its text is light", async ({
  page,
}) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  const body = page.locator("body");

  const background = parseColor(await style(body, "background-color"));
  expect(background.a, "the page has a background colour").toBe(1);
  expect(
    luminance(background),
    `the page background (${JSON.stringify(background)}) is dark`,
  ).toBeLessThan(0.1);

  const text = parseColor(await style(body, "color"));
  expect(
    luminance(text),
    `the text (${JSON.stringify(text)}) is light`,
  ).toBeGreaterThan(0.5);

  const upcoming = page.getByRole("heading", { level: 2, name: "Upcoming" });
  await expect(upcoming).toBeVisible();
  const headingText = parseColor(await style(upcoming, "color"));
  expect(
    luminance(headingText),
    `the Upcoming heading (${JSON.stringify(headingText)}) is light`,
  ).toBeGreaterThan(0.5);
});
