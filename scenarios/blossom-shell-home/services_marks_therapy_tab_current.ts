import { expect, test } from "@playwright/test";
import { desktop } from "./support";

test.use({ viewport: desktop });

// aria-current marks the current item with any token but "false".
const current = /^(page|step|location|date|time|true)$/;

test("on Services, the header's Therapy tab is marked as the current section and Performing isn't", async ({
  page,
}) => {
  await page.goto("/therapy/services");
  const nav = page
    .getByRole("banner")
    .getByRole("navigation", { name: "Main" });
  const therapy = nav.getByRole("button", { name: "Therapy" });
  const performing = nav.getByRole("button", { name: "Performing" });
  await expect(therapy).toBeVisible();
  await expect(performing).toBeVisible();
  await expect(therapy).toHaveAttribute("aria-current", current);
  await expect(performing).not.toHaveAttribute("aria-current", current);
});
