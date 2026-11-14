import { expect, test } from "@playwright/test";

test.use({ viewport: { width: 1280, height: 800 } });

test("on a desktop window, Therapy then Services opens the Services page", async ({
  page,
}) => {
  await page.goto("/");
  const main = page.getByRole("navigation", { name: "Main" });
  await main.getByRole("button", { name: "Therapy" }).click();
  await main.getByRole("link", { name: "Services" }).click();
  await expect(page).toHaveURL(/\/therapy\/services$/);
  await expect(
    page.getByRole("heading", { name: "You might be struggling with…" }),
  ).toBeVisible();
});
