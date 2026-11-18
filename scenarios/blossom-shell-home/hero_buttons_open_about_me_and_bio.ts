import { expect, test } from "@playwright/test";
import { desktop } from "./support";

test.use({ viewport: desktop });

test("on a desktop window, the hero's Therapy button opens About Me and, back on Home, Performing opens Bio", async ({
  page,
}) => {
  await page.goto("/");
  const hero = page.getByRole("region", { name: "Rachel Siegel" });

  await hero.getByRole("link", { name: "Therapy", exact: true }).click();
  await expect(page).toHaveURL(/\/therapy\/about$/);
  await expect(
    page.getByRole("heading", { level: 1, name: "About Me" }),
  ).toBeVisible();

  await page.goBack();
  await expect(page).toHaveURL(/\/$/);

  await hero.getByRole("link", { name: "Performing", exact: true }).click();
  await expect(page).toHaveURL(/\/performing\/bio$/);
  await expect(
    page.getByRole("heading", { level: 1, name: "Bio" }),
  ).toBeVisible();
});
