import { expect, test } from "@playwright/test";

test("on Home, the first Tab shows a Skip to content link and Enter puts focus in the main content", async ({
  page,
}) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();

  await page.keyboard.press("Tab");
  const skip = page.getByRole("link", { name: "Skip to content" });
  await expect(skip).toBeFocused();
  await expect(skip).toBeVisible();
  await expect(skip, "the link shows inside the window").toBeInViewport({
    ratio: 1,
  });

  await page.keyboard.press("Enter");
  const main = page.getByRole("main");
  await expect
    .poll(
      () =>
        main.evaluate((el) => el.contains(document.activeElement)),
      { message: "focus is in the main content" },
    )
    .toBe(true);
});
