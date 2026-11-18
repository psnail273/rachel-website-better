import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const readme = readFileSync(
  join(import.meta.dirname, "..", "README.md"),
  "utf8",
);

describe("README", () => {
  it("names Fraunces as the only typeface and neither Geist nor Source Sans 3", () => {
    const lower = readme.toLowerCase();

    expect(lower).not.toContain("geist");
    expect(lower).not.toContain("source sans");
    expect(readme.split("\n")).toContain(
      "This project loads Fraunces, the site's only typeface, from its variable font files in `src/app/fonts/` with [`next/font/local`](https://nextjs.org/docs/app/api-reference/components/font).",
    );
  });
});
