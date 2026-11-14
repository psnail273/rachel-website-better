import { expect, test } from "@playwright/test";

const withStrip = ["/performing/bio", "/performing/media"];
const withoutStrip = [
  "/therapy/about",
  "/therapy/services",
  "/therapy/education-and-training",
  "/contact",
];

test("Bio and Media show the Upcoming strip; the Therapy pages and Contact don't", async ({
  page,
}) => {
  for (const path of withStrip) {
    await page.goto(path);
    await expect(
      page.getByRole("heading", { level: 1 }),
      `${path} loads`,
    ).toBeVisible();
    await expect(
      page.getByRole("heading", { level: 2, name: "Upcoming" }),
      `${path} shows the Upcoming strip`,
    ).toBeVisible();
  }
  for (const path of withoutStrip) {
    await page.goto(path);
    await expect(
      page.getByRole("heading", { level: 1 }),
      `${path} loads`,
    ).toBeVisible();
    await expect(
      page.getByRole("heading", { name: "Upcoming" }),
      `${path} shows no Upcoming strip`,
    ).toHaveCount(0);
  }
});
