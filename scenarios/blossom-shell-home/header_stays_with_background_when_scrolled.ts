import { expect, test } from "@playwright/test";
import { parseColor, style } from "./support";

test("on Home, scrolled to the bottom, the header is still at the top of the window, now with a background", async ({
  page,
}) => {
  await page.goto("/");
  const header = page.getByRole("banner");
  await expect(header).toBeVisible();
  await expect
    .poll(async () => parseColor(await style(header, "background-color")).a, {
      message: "at the top of the page the header has no background",
    })
    .toBe(0);

  await page.mouse.move(640, 400);
  await page.keyboard.press("End");
  await expect
    .poll(
      () =>
        page.evaluate(
          () =>
            Math.ceil(window.scrollY + window.innerHeight) >=
            document.documentElement.scrollHeight - 1,
        ),
      { message: "the page is scrolled to the bottom" },
    )
    .toBe(true);

  await expect(header).toBeInViewport({ ratio: 1 });
  await expect
    .poll(async () => Math.round((await header.boundingBox())?.y ?? -1), {
      message: "the header sits at the top of the window",
    })
    .toBe(0);
  await expect
    .poll(async () => parseColor(await style(header, "background-color")).a, {
      message: "the header now has a background",
    })
    .toBeGreaterThan(0.5);
});
