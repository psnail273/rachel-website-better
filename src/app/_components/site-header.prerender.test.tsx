// @vitest-environment happy-dom
import { text } from "node:stream/consumers";
import { prerender } from "react-dom/static";
import { afterEach, describe, expect, it } from "vitest";
import { SiteHeader } from "./site-header";

afterEach(() => {
  window.scrollTo(0, 0);
});

describe("SiteHeader prerender", () => {
  it("renders the header unscrolled, with no data-scrolled, even when the window is already scrolled", async () => {
    window.scrollTo(0, 300);

    const { prelude } = await prerender(<SiteHeader />);
    const doc = new DOMParser().parseFromString(
      await text(prelude),
      "text/html",
    );
    const header = doc.querySelector("header");

    expect(
      Array.from(header?.attributes ?? [], (a) => [a.name, a.value]),
    ).toEqual([]);
  });
});
