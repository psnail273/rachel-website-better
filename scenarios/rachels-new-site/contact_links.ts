import { expect, test } from "@playwright/test";

test("on Contact, Wellness Alliance links to Rachel's page and the email link is a mailto", async ({
  page,
}) => {
  await page.goto("/contact");
  // The page's own links: the footer repeats the Wellness Alliance name.
  const main = page.getByRole("main");
  await expect(
    main.getByRole("link", { name: "Wellness Alliance" }),
  ).toHaveAttribute("href", "https://wellnessalliancestl.com/rsiegel");
  await expect(
    main.getByRole("link", { name: "email me directly" }),
  ).toHaveAttribute("href", /^mailto:\S+@\S+$/);
});
