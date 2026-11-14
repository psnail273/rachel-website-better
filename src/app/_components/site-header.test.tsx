// @vitest-environment happy-dom
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { SiteHeader } from "./site-header";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

function findTab(name: string): HTMLElement {
  const tabs = screen.queryAllByRole("button", { name });
  expect(tabs).toHaveLength(1);
  return tabs[0];
}

function findLink(name: string): HTMLElement {
  const links = screen.queryAllByRole("link", { name });
  expect(links).toHaveLength(1);
  return links[0];
}

function linksControlledBy(tab: HTMLElement) {
  const list = document.getElementById(tab.getAttribute("aria-controls") ?? "");
  return Array.from(list?.querySelectorAll("a") ?? []).map((a) => ({
    name: a.textContent,
    href: a.getAttribute("href"),
  }));
}

function countOf(role: "link" | "button", names: string[]): number[] {
  return names.map((name) => screen.queryAllByRole(role, { name }).length);
}

describe("SiteHeader", () => {
  it('links "Rachel Siegel" to the home page', () => {
    render(<SiteHeader />);

    const home = findLink("Rachel Siegel");

    expect(home.getAttribute("href")).toBe("/");
  });

  it("shows Therapy and Performing buttons and a Contact link to /contact", () => {
    render(<SiteHeader />);

    const therapy = findTab("Therapy");
    const performing = findTab("Performing");
    const contact = findLink("Contact");

    expect(contact.getAttribute("href")).toBe("/contact");
    expect(therapy.getAttribute("aria-expanded")).toBe("false");
    expect(performing.getAttribute("aria-expanded")).toBe("false");
    expect(
      countOf("link", [
        "About Me",
        "Services",
        "Education and Training",
        "Bio",
        "Media",
      ]),
    ).toEqual([0, 0, 0, 0, 0]);
  });

  it("clicking Therapy shows its three links", () => {
    render(<SiteHeader />);
    const therapy = findTab("Therapy");

    fireEvent.click(therapy);

    expect(linksControlledBy(therapy)).toEqual([
      { name: "About Me", href: "/therapy/about" },
      { name: "Services", href: "/therapy/services" },
      {
        name: "Education and Training",
        href: "/therapy/education-and-training",
      },
    ]);
    expect(countOf("link", ["Bio", "Media"])).toEqual([0, 0]);
  });

  it("clicking Performing shows its two links", () => {
    render(<SiteHeader />);
    const performing = findTab("Performing");

    fireEvent.click(performing);

    expect(linksControlledBy(performing)).toEqual([
      { name: "Bio", href: "/performing/bio" },
      { name: "Media", href: "/performing/media" },
    ]);
    expect(countOf("link", ["About Me"])).toEqual([0]);
  });

  it("Enter on a tab opens it with focus on its first item", () => {
    render(<SiteHeader />);
    const therapy = findTab("Therapy");
    therapy.focus();

    fireEvent.keyDown(therapy, { key: "Enter" });

    expect(therapy.getAttribute("aria-expanded")).toBe("true");
    expect(document.activeElement).toBe(findLink("About Me"));
  });

  it("Space on a tab opens it with focus on its first item", () => {
    render(<SiteHeader />);
    const performing = findTab("Performing");
    performing.focus();

    fireEvent.keyDown(performing, { key: " " });

    expect(performing.getAttribute("aria-expanded")).toBe("true");
    expect(document.activeElement).toBe(findLink("Bio"));
  });

  it("ArrowDown on a tab opens it with focus on its first item", () => {
    render(<SiteHeader />);
    const performing = findTab("Performing");
    performing.focus();

    fireEvent.keyDown(performing, { key: "ArrowDown" });

    expect(performing.getAttribute("aria-expanded")).toBe("true");
    expect(document.activeElement).toBe(findLink("Bio"));
  });

  it("arrow keys move focus between a dropdown's items", () => {
    render(<SiteHeader />);
    const therapy = findTab("Therapy");
    therapy.focus();
    fireEvent.keyDown(therapy, { key: "ArrowDown" });
    expect(document.activeElement).toBe(findLink("About Me"));

    fireEvent.keyDown(findLink("About Me"), { key: "ArrowDown" });
    expect(document.activeElement).toBe(findLink("Services"));

    fireEvent.keyDown(findLink("Services"), { key: "ArrowDown" });
    expect(document.activeElement).toBe(findLink("Education and Training"));

    fireEvent.keyDown(findLink("Education and Training"), { key: "ArrowDown" });
    expect(document.activeElement).toBe(findLink("About Me"));

    fireEvent.keyDown(findLink("About Me"), { key: "ArrowUp" });
    expect(document.activeElement).toBe(findLink("Education and Training"));

    fireEvent.keyDown(findLink("Education and Training"), { key: "ArrowUp" });
    expect(document.activeElement).toBe(findLink("Services"));
  });

  it("Escape closes a dropdown and returns focus to its tab", () => {
    render(<SiteHeader />);
    const therapy = findTab("Therapy");
    therapy.focus();
    fireEvent.keyDown(therapy, { key: "Enter" });
    expect(document.activeElement).toBe(findLink("About Me"));

    fireEvent.keyDown(findLink("About Me"), { key: "Escape" });

    expect(therapy.getAttribute("aria-expanded")).toBe("false");
    expect(
      countOf("link", ["About Me", "Services", "Education and Training"]),
    ).toEqual([0, 0, 0]);
    expect(document.activeElement).toBe(therapy);
  });

  it("clicking outside an open dropdown closes it", () => {
    render(<SiteHeader />);
    const therapy = findTab("Therapy");
    fireEvent.click(therapy);
    expect(therapy.getAttribute("aria-expanded")).toBe("true");

    fireEvent.pointerDown(document.body);

    expect(therapy.getAttribute("aria-expanded")).toBe("false");
    expect(countOf("link", ["About Me"])).toEqual([0]);

    fireEvent.click(therapy);
    expect(therapy.getAttribute("aria-expanded")).toBe("true");

    fireEvent.pointerDown(findLink("Services"));

    expect(therapy.getAttribute("aria-expanded")).toBe("true");
    expect(countOf("link", ["Services"])).toEqual([1]);
  });

  it("aria-expanded follows each dropdown as it opens and closes", () => {
    render(<SiteHeader />);
    const therapy = findTab("Therapy");
    const performing = findTab("Performing");

    fireEvent.click(therapy);
    expect(therapy.getAttribute("aria-expanded")).toBe("true");
    expect(performing.getAttribute("aria-expanded")).toBe("false");

    fireEvent.click(therapy);
    expect(therapy.getAttribute("aria-expanded")).toBe("false");
    expect(performing.getAttribute("aria-expanded")).toBe("false");
    expect(
      countOf("link", ["About Me", "Services", "Education and Training"]),
    ).toEqual([0, 0, 0]);

    fireEvent.click(performing);
    expect(performing.getAttribute("aria-expanded")).toBe("true");
    expect(therapy.getAttribute("aria-expanded")).toBe("false");
  });

  it("removes its document pointerdown listeners on unmount", () => {
    const addSpy = vi.spyOn(document, "addEventListener");
    const removeSpy = vi.spyOn(document, "removeEventListener");

    const { unmount } = render(<SiteHeader />);
    const added = addSpy.mock.calls
      .filter(([type]) => type === "pointerdown")
      .map(([, listener]) => listener);
    expect(added).toHaveLength(2);

    unmount();
    const removed = removeSpy.mock.calls
      .filter(([type]) => type === "pointerdown")
      .map(([, listener]) => listener);

    expect(removed).toHaveLength(2);
    expect(new Set(removed)).toEqual(new Set(added));
  });

  it("the Contact link to /contact leaves prefetch on", () => {
    render(<SiteHeader />);

    const contact = findLink("Contact");
    const source = readFileSync(
      join(import.meta.dirname, "site-header.tsx"),
      "utf8",
    );

    expect(contact.getAttribute("href")).toBe("/contact");
    expect(source.match(/prefetch/g) ?? []).toEqual([]);
  });
});
