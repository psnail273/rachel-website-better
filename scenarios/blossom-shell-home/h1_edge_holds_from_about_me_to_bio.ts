import { expect, test } from "@playwright/test";
import { desktop, left, phone } from "./support";

for (const [label, viewport] of [
  ["desktop", desktop],
  ["phone", phone],
] as const) {
  test.describe(`at ${label} width`, () => {
    test.use({ viewport });

    test("the h1's left edge is the same on About Me and on Bio", async ({
      page,
    }) => {
      await page.goto("/therapy/about");
      const aboutEdge = await left(
        page.getByRole("heading", { level: 1, name: "About Me" }),
      );

      await page.goto("/performing/bio");
      const bioEdge = await left(
        page.getByRole("heading", { level: 1, name: "Bio" }),
      );

      expect(
        Math.abs(bioEdge - aboutEdge),
        `About Me's h1 starts at ${aboutEdge}px, Bio's at ${bioEdge}px`,
      ).toBeLessThan(1);
    });
  });
}
