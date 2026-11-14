import { expect, test } from "@playwright/test";
import { tabTo } from "./support";

test.use({ viewport: { width: 1280, height: 800 } });

test("the Performing dropdown works by keyboard, and Escape closes a dropdown back to its tab", async ({
  page,
}) => {
  await page.goto("/");
  const main = page.getByRole("navigation", { name: "Main" });

  const performing = main.getByRole("button", { name: "Performing" });
  await tabTo(page, performing);
  await page.keyboard.press("Enter");
  await page.keyboard.press("ArrowDown");
  await expect(main.getByRole("link", { name: "Media" })).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/\/performing\/media$/);
  await expect(
    page.getByRole("heading", { level: 1, name: "Media" }),
  ).toBeVisible();

  const therapy = main.getByRole("button", { name: "Therapy" });
  await tabTo(page, therapy);
  await page.keyboard.press("Enter");
  const aboutMe = main.getByRole("link", { name: "About Me" });
  await expect(aboutMe).toBeVisible();
  await expect(aboutMe).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(aboutMe).toHaveCount(0);
  await expect(therapy).toHaveAttribute("aria-expanded", "false");
  await expect(therapy).toBeFocused();
});
