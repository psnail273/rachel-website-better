// @vitest-environment happy-dom
import { cleanup, render } from "@testing-library/react";
import { PathnameContext } from "next/dist/shared/lib/hooks-client-context.shared-runtime";
import { afterEach, describe, expect, it } from "vitest";
import { SiteHeader } from "./site-header";

afterEach(() => {
  cleanup();
  window.scrollTo(0, 0);
});

function tree(pathname: string) {
  return (
    <PathnameContext.Provider value={pathname}>
      <SiteHeader />
    </PathnameContext.Provider>
  );
}

function attributesOf(element: Element | null) {
  if (!element) return null;
  return Array.from(element.attributes, (attribute) => [
    attribute.name,
    attribute.value,
  ]).sort(([a = ""], [b = ""]) => (a < b ? -1 : 1));
}

describe("SiteHeader over the hero", () => {
  it("takes data-over-hero on Home alone and follows client-side moves", () => {
    const { container, rerender } = render(tree("/"));
    const header = container.querySelector("header");
    const paths = [
      "/",
      "/performing/bio",
      "/",
      "/therapy/about",
      "/contact",
      "/therapy/services",
      "/",
    ];
    const seen = [attributesOf(header)];
    for (const path of paths.slice(1)) {
      rerender(tree(path));
      seen.push(attributesOf(header));
    }
    const over = [["data-over-hero", ""]];
    expect(seen).toEqual([over, [], over, [], [], [], over]);
  });
});
