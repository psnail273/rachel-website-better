import { expect, test } from "@playwright/test";

test("on Bio, the therapy section link opens About Me", async ({ page }) => {
  await page.goto("/performing/bio");
  await page
    .getByRole("link", { name: "the therapy section of this website" })
    .click();
  await expect(page).toHaveURL(/\/therapy\/about$/);
  await expect(
    page.getByRole("heading", { level: 1, name: "About Me" }),
  ).toBeVisible();
});
