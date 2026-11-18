import { expect, test } from "@playwright/test";
import { pages } from "./support";

for (const { name: on, path: at } of pages) {
  test(`on ${on}, the footer links to every page in its columns, to Wellness Alliance and to a mailto address`, async ({
    page,
  }) => {
    await page.goto(at);
    const footer = page.getByRole("contentinfo");
    await expect(footer).toBeVisible();

    // The footer's columns list the six inner pages; it has no Home link
    // (the human's call).
    for (const { name, path } of pages.filter(({ path }) => path !== "/")) {
      await expect.soft(
        footer.locator(`a[href="${path}"]`).first(),
        `the footer links to ${name} (${path})`,
      ).toBeVisible();
    }
    await expect.soft(
      footer
        .locator('a[href="https://wellnessalliancestl.com/rsiegel"]')
        .first(),
      "the footer links to https://wellnessalliancestl.com/rsiegel",
    ).toBeVisible();
    const mail = footer.locator('a[href^="mailto:"]').first();
    await expect(mail, "the footer links to a mailto: address").toBeVisible();
    await expect(mail).toHaveAttribute("href", /^mailto:\S+@\S+$/);
  });
}
