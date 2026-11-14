// @vitest-environment happy-dom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { SiteHeader } from "./site-header";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

const SEVEN_LINKS = [
  { name: "Home", href: "/" },
  { name: "About Me", href: "/therapy/about" },
  { name: "Services", href: "/therapy/services" },
  { name: "Education and Training", href: "/therapy/education-and-training" },
  { name: "Bio", href: "/performing/bio" },
  { name: "Media", href: "/performing/media" },
  { name: "Contact", href: "/contact" },
];

const OTHER_KEYS = ["Enter", " ", "Tab", "ArrowDown", "a"];

function menuButton(): HTMLElement {
  const buttons = screen.queryAllByRole("button", { name: "Menu" });
  expect(buttons).toHaveLength(1);
  return buttons[0];
}

function panelOf(button: HTMLElement): HTMLElement | null {
  return document.getElementById(button.getAttribute("aria-controls") ?? "");
}

function openMenu(): HTMLElement {
  const button = menuButton();
  fireEvent.click(button);
  expect(button.getAttribute("aria-expanded")).toBe("true");
  return button;
}

function panelLink(button: HTMLElement, name: string): HTMLElement {
  const panel = panelOf(button);
  expect(panel).not.toBeNull();
  const links = within(panel as HTMLElement).queryAllByRole("link", { name });
  expect(links).toHaveLength(1);
  return links[0];
}

function panelLinks(button: HTMLElement) {
  return Array.from(panelOf(button)?.querySelectorAll("a") ?? []).map((a) => ({
    name: a.textContent,
    href: a.getAttribute("href"),
  }));
}

describe("MobileMenu", () => {
  it("shows one closed Menu button and no panel", () => {
    render(<SiteHeader />);

    const button = menuButton();
    const controls = button.getAttribute("aria-controls") ?? "";

    expect(button.getAttribute("aria-expanded")).toBe("false");
    expect(controls).not.toBe("");
    expect(document.getElementById(controls)).toBeNull();
    expect(screen.queryAllByRole("link", { name: "Home" })).toHaveLength(0);
  });

  it("clicking Menu opens a panel with links to all seven routes", () => {
    render(<SiteHeader />);

    const button = openMenu();

    expect(panelLinks(button)).toEqual(SEVEN_LINKS);
  });

  it("the panel groups the pages under Therapy and Performing", () => {
    render(<SiteHeader />);

    const button = openMenu();
    const panel = panelOf(button) as HTMLElement;
    const groups = within(panel)
      .queryAllByRole("group")
      .map((group) => ({
        name: group.getAttribute("aria-labelledby")
          ? (document.getElementById(
              group.getAttribute("aria-labelledby") ?? "",
            )?.textContent ?? null)
          : null,
        links: Array.from(group.querySelectorAll("a")).map(
          (a) => a.textContent,
        ),
      }));
    const home = panelLink(button, "Home");
    const contact = panelLink(button, "Contact");
    const outside = within(panel)
      .queryAllByRole("group")
      .map((group) => [group.contains(home), group.contains(contact)]);

    expect(groups).toEqual([
      {
        name: "Therapy",
        links: ["About Me", "Services", "Education and Training"],
      },
      { name: "Performing", links: ["Bio", "Media"] },
    ]);
    expect(outside).toEqual([
      [false, false],
      [false, false],
    ]);
  });

  it("clicking Menu again closes the panel and focuses the button", () => {
    render(<SiteHeader />);

    const button = openMenu();
    const controls = button.getAttribute("aria-controls") ?? "";
    panelLink(button, "Bio").focus();
    fireEvent.click(button);

    expect(button.getAttribute("aria-expanded")).toBe("false");
    expect(document.getElementById(controls)).toBeNull();
    expect(document.activeElement).toBe(button);
  });

  it("following any panel link closes the panel", () => {
    render(<SiteHeader />);
    const button = menuButton();
    const controls = button.getAttribute("aria-controls") ?? "";

    const results = SEVEN_LINKS.map(({ name }) => {
      fireEvent.click(button);
      const links = within(panelOf(button) ?? document.body).queryAllByRole(
        "link",
        { name },
      );
      if (links.length === 1) fireEvent.click(links[0]);
      return {
        name,
        found: links.length,
        expanded: button.getAttribute("aria-expanded"),
        panelGone: document.getElementById(controls) === null,
      };
    });

    expect(results).toEqual(
      SEVEN_LINKS.map(({ name }) => ({
        name,
        found: 1,
        expanded: "false",
        panelGone: true,
      })),
    );
  });

  it("Escape on a panel link closes the panel and focuses the button", () => {
    render(<SiteHeader />);

    const button = openMenu();
    const media = panelLink(button, "Media");
    media.focus();
    const notPrevented = fireEvent.keyDown(media, { key: "Escape" });

    expect(notPrevented).toBe(false);
    expect(button.getAttribute("aria-expanded")).toBe("false");
    expect(panelOf(button)).toBeNull();
    expect(document.activeElement).toBe(button);
  });

  it("Escape on the open Menu button closes the panel and keeps focus", () => {
    render(<SiteHeader />);

    const button = openMenu();
    button.focus();
    const notPrevented = fireEvent.keyDown(button, { key: "Escape" });

    expect(notPrevented).toBe(false);
    expect(button.getAttribute("aria-expanded")).toBe("false");
    expect(panelOf(button)).toBeNull();
    expect(document.activeElement).toBe(button);
  });

  it("Escape on the closed Menu button changes nothing", () => {
    render(<SiteHeader />);

    const button = menuButton();
    button.focus();
    const notPrevented = fireEvent.keyDown(button, { key: "Escape" });

    expect(notPrevented).toBe(true);
    expect(button.getAttribute("aria-expanded")).toBe("false");
    expect(document.activeElement).toBe(button);
  });

  it("other keys leave the open panel open and unprevented", () => {
    render(<SiteHeader />);

    const button = openMenu();
    const home = panelLink(button, "Home");
    const results = OTHER_KEYS.map((key) => {
      button.focus();
      const onButton = fireEvent.keyDown(button, { key });
      home.focus();
      const onLink = fireEvent.keyDown(home, { key });
      return {
        key,
        onButton,
        onLink,
        focused: document.activeElement === home,
      };
    });

    expect(results).toEqual(
      OTHER_KEYS.map((key) => ({
        key,
        onButton: true,
        onLink: true,
        focused: true,
      })),
    );
    expect(button.getAttribute("aria-expanded")).toBe("true");
    expect(panelLinks(button)).toHaveLength(7);
  });

  it("other keys leave the closed Menu button closed and unprevented", () => {
    render(<SiteHeader />);

    const button = menuButton();
    button.focus();
    const results = OTHER_KEYS.map((key) => fireEvent.keyDown(button, { key }));

    expect(results).toEqual(OTHER_KEYS.map(() => true));
    expect(button.getAttribute("aria-expanded")).toBe("false");
    expect(panelOf(button)).toBeNull();
  });

  it("adds no document or window listener as it opens and closes", () => {
    const documentSpy = vi.spyOn(document, "addEventListener");
    const windowSpy = vi.spyOn(window, "addEventListener");
    render(<SiteHeader />);

    const button = openMenu();
    fireEvent.click(button);
    fireEvent.click(button);
    fireEvent.keyDown(panelLink(button, "Home"), { key: "Escape" });
    fireEvent.click(button);
    fireEvent.click(panelLink(button, "Bio"));

    const documentTypes = documentSpy.mock.calls
      .map((call) => call[0])
      .filter((type) => type !== "selectionchange");
    const windowTypes = windowSpy.mock.calls.map((call) => call[0]);
    expect(documentTypes).toEqual(["pointerdown", "pointerdown"]);
    expect(windowTypes).toEqual([]);
  });
});
