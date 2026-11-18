import { expect, test } from "@playwright/test";
import { pages, phone } from "./support";

test.use({ viewport: phone, hasTouch: true });

test("on a phone, the menu button opens a full-window menu that lists every page, and Escape closes it", async ({
  page,
}) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Menu" }).tap();
  const menu = page.getByRole("dialog", { name: "Menu" });
  await expect(menu).toBeVisible();

  // Full-window: the menu runs from the window's top-left corner to its bottom
  // and right edges. The site keeps a scrollbar gutter (scrollbar-gutter:
  // stable), which a desktop Chromium reserves at the right edge, 15px wide,
  // as the browser's own strip; a phone's scrollbar overlays the page instead.
  const gutter = 15;
  await expect
    .poll(
      async () => {
        const box = await menu.boundingBox();
        if (box === null) return "no box";
        const fills =
          Math.round(box.x) === 0 &&
          Math.round(box.y) === 0 &&
          Math.round(box.height) === phone.height &&
          Math.round(box.x + box.width) >= phone.width - gutter;
        return fills ? "fills the window" : JSON.stringify(box);
      },
      { message: "the menu fills the window" },
    )
    .toBe("fills the window");

  for (const { name, path } of pages) {
    const link = menu.getByRole("link", { name, exact: true });
    await expect(link, `the menu lists ${name}`).toBeVisible();
    await expect(link, `${name} links to ${path}`).toHaveAttribute(
      "href",
      path,
    );
  }

  await page.keyboard.press("Escape");
  await expect(menu).toBeHidden();
});
