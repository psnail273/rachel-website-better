import { expect, test } from "@playwright/test";

test("on Contact, Wellness Alliance links to Rachel's page and the email link is a mailto", async ({
  page,
}) => {
  await page.goto("/contact");
  await expect(
    page.getByRole("link", { name: "Wellness Alliance" }),
  ).toHaveAttribute("href", "https://wellnessalliancestl.com/rsiegel");
  await expect(
    page.getByRole("link", { name: "email me directly" }),
  ).toHaveAttribute("href", /^mailto:\S+@\S+$/);
});
