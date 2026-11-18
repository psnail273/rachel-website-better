import { expect, test } from "@playwright/test";

test.use({ viewport: { width: 390, height: 844 }, hasTouch: true });

test("on a phone, the menu button then Education and Training opens the Education page", async ({
  page,
}) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Menu" }).tap();
  // The open full-screen menu: the footer also links Education and Training.
  await page
    .getByRole("dialog", { name: "Menu" })
    .getByRole("link", { name: "Education and Training" })
    .tap();
  await expect(page).toHaveURL(/\/therapy\/education-and-training$/);
  await expect(
    page.getByRole("heading", { name: "Specialized Training" }),
  ).toBeVisible();
});
