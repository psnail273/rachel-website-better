import { expect, test } from "@playwright/test";

test("on Media, clicking a video card puts a YouTube player in its place", async ({
  page,
}) => {
  await page.goto("/performing/media");
  const card = page.getByRole("button", { name: /^Play / }).first();
  const label = await card.getAttribute("aria-label");
  expect(label).not.toBeNull();
  const title = (label ?? "").replace(/^Play /, "");

  await card.click();
  await expect(page.getByRole("button", { name: `Play ${title}` })).toHaveCount(
    0,
  );
  const player = page.getByTitle(title, { exact: true });
  await expect(player).toBeVisible();
  await expect(player).toHaveAttribute(
    "src",
    /^https:\/\/www\.youtube(-nocookie)?\.com\/embed\/[\w-]+/,
  );
});
