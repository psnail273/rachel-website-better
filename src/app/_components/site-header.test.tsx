// @vitest-environment happy-dom
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { PathnameContext } from "next/dist/shared/lib/hooks-client-context.shared-runtime";
import { afterEach, describe, expect, it, vi } from "vitest";
import { SiteHeader } from "./site-header";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  window.scrollTo(0, 0);
});

function renderAt(pathname: string) {
  return render(
    <PathnameContext.Provider value={pathname}>
      <SiteHeader />
    </PathnameContext.Provider>,
  );
}

function attributesOf(element: Element | null | undefined) {
  if (!element) return null;
  return Array.from(element.attributes, (attribute) => [
    attribute.name,
    attribute.value,
  ]).sort(([a], [b]) => (a < b ? -1 : 1));
}

function sorted(pairs: string[][]): string[][] {
  return [...pairs].sort(([a], [b]) => (a < b ? -1 : 1));
}

function childAt(element: Element | null | undefined, index: number) {
  return element?.children.item(index) ?? null;
}

function tagsOf(element: Element | null | undefined): string[] | null {
  if (!element) return null;
  return Array.from(element.children, (child) => child.tagName);
}

function currentOfTabs(): (string | null)[] {
  return [findTab("Therapy"), findTab("Performing"), findLink("Contact")].map(
    (tab) => tab.getAttribute("aria-current"),
  );
}

function panelOf(tab: HTMLElement): HTMLElement | null {
  return document.getElementById(tab.getAttribute("aria-controls") ?? "");
}

function currentOfPanelLinks(tab: HTMLElement): (string | null)[] {
  return Array.from(panelOf(tab)?.querySelectorAll("a") ?? []).map((a) =>
    a.getAttribute("aria-current"),
  );
}

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

  it("takes data-scrolled once the page has scrolled past 24 px", () => {
    renderAt("/");
    const header = document.querySelector("header");
    const atRest = attributesOf(header);

    window.scrollTo(0, 24);
    fireEvent.scroll(window);
    const atTheLimit = attributesOf(header);

    window.scrollTo(0, 25);
    fireEvent.scroll(window);
    const pastTheLimit = attributesOf(header);

    window.scrollTo(0, 0);
    fireEvent.scroll(window);
    const backAtTop = attributesOf(header);

    expect([atRest, atTheLimit, pastTheLimit, backAtTop]).toEqual([
      [],
      [],
      [["data-scrolled", ""]],
      [],
    ]);
  });

  it("takes data-scrolled at once when the page loads already scrolled", () => {
    window.scrollTo(0, 300);

    renderAt("/");

    expect(attributesOf(document.querySelector("header"))).toEqual([
      ["data-scrolled", ""],
    ]);
  });

  it("removes its window scroll listener on unmount", () => {
    const addSpy = vi.spyOn(window, "addEventListener");
    const removeSpy = vi.spyOn(window, "removeEventListener");

    const { unmount } = renderAt("/");
    const added = addSpy.mock.calls;
    unmount();
    const removed = removeSpy.mock.calls;

    expect(added.map((call) => call[0])).toEqual(["scroll"]);
    expect(added[0]?.[2]).toEqual({ passive: true });
    expect(removed.map((call) => call[0])).toEqual(["scroll"]);
    expect(removed[0]?.[1]).toBe(added[0]?.[1]);
  });

  it("renders the brand and the nav in the header's PageShell with their attributes", () => {
    renderAt("/");
    const header = document.querySelector("header");
    const shell = childAt(header, 0);
    const brand = childAt(shell, 0);
    const nav = childAt(shell, 1);
    const contact = childAt(nav, 2);
    const label = childAt(contact, 0);

    expect(attributesOf(header)).toEqual([]);
    expect(header?.children.length).toBe(1);
    expect(attributesOf(shell)).toEqual([["data-shell", ""]]);
    expect(tagsOf(shell)).toEqual(["A", "NAV", "DIV"]);
    expect(attributesOf(brand)).toEqual(
      sorted([
        ["href", "/"],
        ["data-brand", ""],
        ["class", "type-brand"],
      ]),
    );
    expect(brand?.textContent).toBe("Rachel Siegel");
    expect(attributesOf(nav)).toEqual(
      sorted([
        ["aria-label", "Main"],
        ["data-nav", ""],
      ]),
    );
    expect(tagsOf(nav)).toEqual(["DIV", "DIV", "A"]);
    expect(attributesOf(childAt(nav, 0))).toEqual([["data-dropdown", ""]]);
    expect(attributesOf(childAt(nav, 1))).toEqual([["data-dropdown", ""]]);
    expect(attributesOf(contact)).toEqual(
      sorted([
        ["href", "/contact"],
        ["data-nav-tab", ""],
        ["class", "type-nav"],
      ]),
    );
    expect(tagsOf(contact)).toEqual(["SPAN"]);
    expect(attributesOf(label)).toEqual([["data-nav-label", ""]]);
    expect(label?.textContent).toBe("Contact");
  });

  it("marks the Therapy tab current on a /therapy/ page", () => {
    renderAt("/therapy/services");

    expect(currentOfTabs()).toEqual(["true", null, null]);
  });

  it("marks the Performing tab current on a /performing/ page", () => {
    renderAt("/performing/media");

    expect(currentOfTabs()).toEqual([null, "true", null]);
  });

  it("marks no tab current on Home", () => {
    renderAt("/");

    expect(currentOfTabs()).toEqual([null, null, null]);
  });

  it("marks the Contact tab as the current page on /contact", () => {
    renderAt("/contact");

    expect(currentOfTabs()).toEqual([null, null, "page"]);
  });

  it("marks the current page's link in an open dropdown", () => {
    renderAt("/therapy/services");
    const therapy = findTab("Therapy");
    const performing = findTab("Performing");

    fireEvent.click(therapy);
    const therapyLinks = currentOfPanelLinks(therapy);
    fireEvent.click(therapy);
    fireEvent.click(performing);
    const performingLinks = currentOfPanelLinks(performing);

    expect(therapyLinks).toEqual([null, "page", null]);
    expect(performingLinks).toEqual([null, null]);
  });

  it("draws each dropdown tab as its label and a 10px chevron", () => {
    renderAt("/");
    const therapy = findTab("Therapy");
    const performing = findTab("Performing");
    const chevron = childAt(therapy, 1);

    expect(attributesOf(therapy)).toEqual(
      sorted([
        ["aria-controls", therapy.getAttribute("aria-controls") ?? ""],
        ["aria-expanded", "false"],
        ["class", "type-nav"],
        ["data-nav-tab", ""],
        ["type", "button"],
      ]),
    );
    expect(therapy.getAttribute("aria-controls")).not.toBe("");
    expect(tagsOf(therapy)).toEqual(["SPAN", "svg"]);
    expect(attributesOf(childAt(therapy, 0))).toEqual([["data-nav-label", ""]]);
    expect(childAt(therapy, 0)?.textContent).toBe("Therapy");
    expect(attributesOf(chevron)).toEqual(
      sorted([
        ["aria-hidden", "true"],
        ["data-chevron", ""],
        ["fill", "none"],
        ["height", "10"],
        ["stroke", "currentColor"],
        ["stroke-width", "1.5"],
        ["viewBox", "0 0 10 10"],
        ["width", "10"],
      ]),
    );
    expect(tagsOf(chevron)).toEqual(["path"]);
    expect(attributesOf(childAt(chevron, 0))).toEqual([
      ["d", "M1 3.5 5 7.5 9 3.5"],
    ]);
    expect(therapy.textContent).toBe("Therapy");
    expect(tagsOf(performing)).toEqual(["SPAN", "svg"]);
    expect(attributesOf(childAt(performing, 0))).toEqual([
      ["data-nav-label", ""],
    ]);
    expect(childAt(performing, 0)?.textContent).toBe("Performing");
    expect(attributesOf(childAt(performing, 1))).toEqual(attributesOf(chevron));
    expect(performing.textContent).toBe("Performing");
  });

  it("renders the open panel as exactly its links", () => {
    renderAt("/");
    const therapy = findTab("Therapy");

    fireEvent.click(therapy);
    const id = therapy.getAttribute("aria-controls") ?? "";
    const panel = document.getElementById(id);
    const items = Array.from(panel?.children ?? []);

    expect(id).not.toBe("");
    expect(panel?.tagName).toBe("UL");
    expect(attributesOf(panel)).toEqual(
      sorted([
        ["data-dropdown-panel", ""],
        ["id", id],
      ]),
    );
    expect(items.map((item) => item.tagName)).toEqual(["LI", "LI", "LI"]);
    expect(items.map((item) => attributesOf(item))).toEqual([[], [], []]);
    expect(items.map((item) => tagsOf(item))).toEqual([["A"], ["A"], ["A"]]);
    expect(
      items.map((item) => ({
        attributes: attributesOf(childAt(item, 0)),
        text: childAt(item, 0)?.textContent,
      })),
    ).toEqual([
      {
        attributes: sorted([
          ["class", "type-nav-item"],
          ["href", "/therapy/about"],
        ]),
        text: "About Me",
      },
      {
        attributes: sorted([
          ["class", "type-nav-item"],
          ["href", "/therapy/services"],
        ]),
        text: "Services",
      },
      {
        attributes: sorted([
          ["class", "type-nav-item"],
          ["href", "/therapy/education-and-training"],
        ]),
        text: "Education and Training",
      },
    ]);
    expect(panel?.parentElement).toBe(therapy.parentElement);
  });

  it("opens the square panel from the keyboard and closes it with Escape or a click outside", () => {
    renderAt("/");
    const therapy = findTab("Therapy");
    therapy.focus();

    const perKey = ["Enter", " ", "ArrowDown"].map((key) => {
      fireEvent.keyDown(therapy, { key });
      const open = {
        expanded: therapy.getAttribute("aria-expanded"),
        marker: panelOf(therapy)?.getAttribute("data-dropdown-panel"),
        focusOnFirst: document.activeElement === findLink("About Me"),
      };
      fireEvent.keyDown(findLink("About Me"), { key: "Escape" });
      const closed = {
        expanded: therapy.getAttribute("aria-expanded"),
        panelPresent: panelOf(therapy) !== null,
        focusOnTab: document.activeElement === therapy,
      };
      return { open, closed };
    });
    fireEvent.click(therapy);
    const openedByClick = therapy.getAttribute("aria-expanded");
    fireEvent.pointerDown(document.body);
    const afterOutside = {
      expanded: therapy.getAttribute("aria-expanded"),
      panelPresent: panelOf(therapy) !== null,
    };

    const keyResult = {
      open: { expanded: "true", marker: "", focusOnFirst: true },
      closed: { expanded: "false", panelPresent: false, focusOnTab: true },
    };
    expect(perKey).toEqual([keyResult, keyResult, keyResult]);
    expect(openedByClick).toBe("true");
    expect(afterOutside).toEqual({ expanded: "false", panelPresent: false });
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
