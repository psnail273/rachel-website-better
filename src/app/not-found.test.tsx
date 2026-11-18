// @vitest-environment happy-dom
import { text } from "node:stream/consumers";
import type { ReactElement } from "react";
import { prerender } from "react-dom/static";
import { describe, expect, it } from "vitest";

type PageModule = { default: () => ReactElement };

const pages = import.meta.glob<PageModule>("./not-found.tsx");
const page = await pages["./not-found.tsx"]?.();

async function renderPage(): Promise<Document> {
  expect(page).toBeDefined();
  const NotFound = page?.default;
  expect(NotFound).toBeDefined();
  if (NotFound === undefined) {
    return new DOMParser().parseFromString("", "text/html");
  }
  const { prelude } = await prerender(<NotFound />);
  return new DOMParser().parseFromString(await text(prelude), "text/html");
}

function attrs(el: Element | undefined | null): Record<string, string> {
  return Object.fromEntries(
    Array.from(el?.attributes ?? [], (a) => [a.name, a.value]),
  );
}

const BUTTON_CLASSES = [
  "border",
  "border-heading",
  "duration-150",
  "ease-[cubic-bezier(0.2,0.7,0.2,1)]",
  "h-14",
  "hover:bg-heading",
  "hover:text-bg",
  "inline-flex",
  "items-center",
  "justify-center",
  "max-w-full",
  "self-center",
  "text-heading",
  "transition-colors",
  "type-button",
  "w-50",
];

describe("NotFound", () => {
  it("shows the heading, the lead and a Back to Home page button in one centred section", async () => {
    const doc = await renderPage();

    expect(page).toBeDefined();
    expect(Object.keys(page ?? {})).toEqual(["default"]);
    expect(doc.body.children).toHaveLength(1);
    const section = doc.body.children[0];
    expect(section?.tagName).toBe("SECTION");
    expect(attrs(section)).toEqual({
      "data-section": "",
      "aria-labelledby": "not-found-heading",
    });
    expect(section?.children).toHaveLength(1);
    const center = section?.children[0];
    expect(center?.tagName).toBe("DIV");
    expect(attrs(center)).toEqual({ "data-center": "" });
    expect(center?.children).toHaveLength(2);
    const h1 = center?.children[0];
    expect(h1?.tagName).toBe("H1");
    expect(attrs(h1)).toEqual({
      "data-heading": "1",
      id: "not-found-heading",
      class: "type-h1",
    });
    expect(h1?.textContent).toBe("This page wandered off");
    const stack = center?.children[1];
    expect(stack?.tagName).toBe("DIV");
    expect(attrs(stack)).toEqual({ "data-stack": "heading" });
    expect(stack?.children).toHaveLength(2);
    const lead = stack?.children[0];
    expect(lead?.tagName).toBe("P");
    expect(attrs(lead)).toEqual({ "data-lead": "", class: "type-lead" });
    expect(lead?.textContent).toBe("The page you’re looking for isn’t here.");
    const link = stack?.children[1];
    expect(link?.tagName).toBe("A");
    expect(link?.getAttribute("href")).toBe("/");
    expect(link?.textContent).toBe("Back to Home");
    expect((link?.getAttribute("class") ?? "").split(" ").sort()).toEqual(
      BUTTON_CLASSES,
    );
    expect(doc.body.textContent).not.toContain("404");
  });

  it("paints no background or inline style of its own over the body's bg", async () => {
    const doc = await renderPage();

    expect(page).toBeDefined();
    expect(Array.from(doc.querySelectorAll("style, [style]"))).toEqual([]);
    expect(
      Array.from(doc.querySelectorAll("[class*='bg-']"), (el) => el.tagName),
    ).toEqual(["A"]);
  });
});
