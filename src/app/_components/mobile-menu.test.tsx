// @vitest-environment happy-dom
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { PathnameContext } from "next/dist/shared/lib/hooks-client-context.shared-runtime";
import {
  act,
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
  if (!(panel instanceof HTMLElement)) throw new Error("panel is missing");
  const links = within(panel).queryAllByRole("link", { name });
  expect(links).toHaveLength(1);
  return links[0];
}

function panelLinks(button: HTMLElement) {
  return Array.from(panelOf(button)?.querySelectorAll("a") ?? []).map((a) => ({
    name: a.textContent,
    href: a.getAttribute("href"),
  }));
}

function renderAt(pathname: string) {
  return render(
    <PathnameContext.Provider value={pathname}>
      <SiteHeader />
    </PathnameContext.Provider>,
  );
}

// Lookups that find nothing hand back a detached stand-in, so the assertion
// that compares it fails instead of the lookup throwing.
function only(root: ParentNode, selector: string): HTMLElement {
  const found = root.querySelectorAll<HTMLElement>(selector);
  return found.length === 1 ? found[0] : document.createElement("div");
}

function childAt(parent: Element, index: number): Element {
  return parent.children[index] ?? document.createElement("div");
}

function attrs(element: Element): [string, string][] {
  return Array.from(element.attributes, (a): [string, string] => [
    a.name,
    a.value,
  ]).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
}

function tags(element: Element): string[] {
  return Array.from(element.children, (child) => child.tagName);
}

function menuToggle(): HTMLElement {
  return only(document, "button[data-menu-button]");
}

function dialogById(id: string): HTMLDialogElement {
  const found = document.getElementById(id);
  return found instanceof HTMLDialogElement
    ? found
    : document.createElement("dialog");
}

function openDialog(): { button: HTMLElement; dialog: HTMLDialogElement } {
  const button = menuToggle();
  fireEvent.click(button);
  return {
    button,
    dialog: dialogById(button.getAttribute("aria-controls") ?? ""),
  };
}

function linkNamed(dialog: HTMLElement, name: string): HTMLElement {
  const links = Array.from(dialog.querySelectorAll("a")).filter(
    (a) => a.textContent === name,
  );
  return links.length === 1 ? links[0] : document.createElement("a");
}

function accessibleName(element: Element | null): string | null {
  if (element === null) return null;
  return element.getAttribute("aria-label") ?? element.textContent;
}

const ICON_ATTRIBUTES = (): [string, string][] => [
  ["aria-hidden", "true"],
  ["fill", "none"],
  ["height", "20"],
  ["stroke", "currentColor"],
  ["stroke-width", "1.5"],
  ["viewBox", "0 0 20 20"],
  ["width", "20"],
];

function iconOf(button: Element) {
  const icon = childAt(button, 0);
  return {
    tags: tags(button).map((tag) => tag.toLowerCase()),
    svgAttributes: attrs(icon),
    pathTags: tags(icon).map((tag) => tag.toLowerCase()),
    pathAttributes: attrs(childAt(icon, 0)),
  };
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
    const panel = panelOf(button);
    if (!(panel instanceof HTMLElement)) throw new Error("panel is missing");
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
    expect(windowTypes).toEqual(["scroll"]);
  });

  it("the menu's Contact link to /contact leaves prefetch on", () => {
    render(<SiteHeader />);
    const button = openMenu();

    const contact = panelLink(button, "Contact");
    const source = readFileSync(
      join(import.meta.dirname, "mobile-menu.tsx"),
      "utf8",
    );

    expect(contact.getAttribute("href")).toBe("/contact");
    expect(source.match(/prefetch/g) ?? []).toEqual([]);
  });

  it("tapping Menu opens a modal menu dialog with focus on its Close button", () => {
    const showModal = vi.spyOn(HTMLDialogElement.prototype, "showModal");
    renderAt("/");
    const button = menuToggle();
    const id = button.getAttribute("aria-controls") ?? "";
    const root = childAt(only(document, "header [data-shell]"), 2);
    const before = {
      rootAttributes: attrs(root),
      rootTags: tags(root),
      buttonAttributes: attrs(button),
      icon: iconOf(button),
      dialogInPage: document.getElementById(id),
    };

    fireEvent.click(button);
    const dialog = dialogById(id);
    const links = Array.from(
      dialog.querySelectorAll("[data-menu-links] a"),
      (a) => ({ name: a.textContent, href: a.getAttribute("href") }),
    );

    expect(id).not.toBe("");
    expect(before).toEqual({
      rootAttributes: [["class", "md:hidden"]],
      rootTags: ["BUTTON"],
      buttonAttributes: [
        ["aria-controls", id],
        ["aria-expanded", "false"],
        ["aria-haspopup", "dialog"],
        ["aria-label", "Menu"],
        ["data-menu-button", ""],
        ["type", "button"],
      ],
      icon: {
        tags: ["svg"],
        svgAttributes: ICON_ATTRIBUTES(),
        pathTags: ["path"],
        pathAttributes: [["d", "M0 7h20M0 13h20"]],
      },
      dialogInPage: null,
    });
    expect(showModal).toHaveBeenCalledTimes(1);
    expect(tags(root)).toEqual(["BUTTON", "DIALOG"]);
    expect(dialog.tagName).toBe("DIALOG");
    expect(dialog.open).toBe(true);
    expect(attrs(dialog)).toEqual([
      ["aria-label", "Menu"],
      ["data-menu", ""],
      ["id", id],
      ["open", ""],
    ]);
    expect(button.getAttribute("aria-expanded")).toBe("true");
    expect(links).toEqual(
      SEVEN_LINKS.map(({ name, href }) => ({ name, href })),
    );
    expect(document.activeElement).toBe(
      only(dialog, "button[data-menu-close]"),
    );
  });

  it("sets the links in sheet-link type under italic Therapy and Performing labels", () => {
    renderAt("/therapy");
    const { dialog } = openDialog();

    const block = only(dialog, "[data-menu-links]");
    const first = childAt(block, 0);
    const last = childAt(block, 3);
    const groups = [childAt(block, 1), childAt(block, 2)].map((group) => {
      const label = childAt(group, 0);
      const list = childAt(group, 1);
      return {
        attributes: attrs(group),
        tags: tags(group),
        labelAttributes: attrs(label),
        labelText: label.textContent,
        listAttributes: attrs(list),
        items: Array.from(list.children, (item) => ({
          tag: item.tagName,
          attributes: attrs(item),
          tags: tags(item),
        })),
        links: Array.from(list.querySelectorAll("a"), (a) => ({
          attributes: attrs(a),
          text: a.textContent,
        })),
      };
    });
    const labelIds = groups.map(
      (group) => group.labelAttributes.find(([name]) => name === "id")?.[1],
    );
    const listed = (href: string, text: string) => ({
      attributes: [
        ["class", "type-sheet-link"],
        ["href", href],
      ],
      text,
    });

    expect(tags(block)).toEqual(["A", "DIV", "DIV", "A"]);
    expect({ attributes: attrs(first), text: first.textContent }).toEqual(
      listed("/", "Home"),
    );
    expect({ attributes: attrs(last), text: last.textContent }).toEqual(
      listed("/contact", "Contact"),
    );
    expect(labelIds[0]).toBeTruthy();
    expect(labelIds[1]).toBeTruthy();
    expect(labelIds[0]).not.toBe(labelIds[1]);
    expect(groups).toEqual([
      {
        attributes: [
          ["aria-labelledby", labelIds[0]],
          ["data-menu-group", ""],
          ["role", "group"],
        ],
        tags: ["P", "UL"],
        labelAttributes: [
          ["class", "type-label"],
          ["data-menu-label", ""],
          ["id", labelIds[0]],
        ],
        labelText: "Therapy",
        listAttributes: [],
        items: [
          { tag: "LI", attributes: [], tags: ["A"] },
          { tag: "LI", attributes: [], tags: ["A"] },
          { tag: "LI", attributes: [], tags: ["A"] },
        ],
        links: [
          listed("/therapy/about", "About Me"),
          listed("/therapy/services", "Services"),
          listed("/therapy/education-and-training", "Education and Training"),
        ],
      },
      {
        attributes: [
          ["aria-labelledby", labelIds[1]],
          ["data-menu-group", ""],
          ["role", "group"],
        ],
        tags: ["P", "UL"],
        labelAttributes: [
          ["class", "type-label"],
          ["data-menu-label", ""],
          ["id", labelIds[1]],
        ],
        labelText: "Performing",
        listAttributes: [],
        items: [
          { tag: "LI", attributes: [], tags: ["A"] },
          { tag: "LI", attributes: [], tags: ["A"] },
        ],
        links: [
          listed("/performing/bio", "Bio"),
          listed("/performing/media", "Media"),
        ],
      },
    ]);
  });

  it("draws the menu's head row and links on the page column", () => {
    renderAt("/therapy");
    const { dialog } = openDialog();

    const head = childAt(dialog, 0);
    const headShell = childAt(head, 0);
    const brand = childAt(headShell, 0);
    const close = childAt(headShell, 1);
    const body = childAt(dialog, 1);
    const measured = {
      dialogTags: tags(dialog),
      headAttributes: attrs(head),
      headTags: tags(head),
      headShellAttributes: attrs(headShell),
      headShellTags: tags(headShell),
      brandAttributes: attrs(brand),
      brandText: brand.textContent,
      closeAttributes: attrs(close),
      closeIcon: iconOf(close),
      bodyAttributes: attrs(body),
      bodyTags: tags(body),
      linksAttributes: attrs(childAt(body, 0)),
    };

    expect(measured).toEqual({
      dialogTags: ["DIV", "DIV"],
      headAttributes: [["data-menu-head", ""]],
      headTags: ["DIV"],
      headShellAttributes: [["data-shell", ""]],
      headShellTags: ["SPAN", "BUTTON"],
      brandAttributes: [
        ["class", "type-brand"],
        ["data-menu-brand", ""],
      ],
      brandText: "Rachel Siegel",
      closeAttributes: [
        ["aria-label", "Close"],
        ["data-menu-close", ""],
        ["type", "button"],
      ],
      closeIcon: {
        tags: ["svg"],
        svgAttributes: ICON_ATTRIBUTES(),
        pathTags: ["path"],
        pathAttributes: [["d", "M1 1l18 18M19 1L1 19"]],
      },
      bodyAttributes: [["data-shell", ""]],
      bodyTags: ["DIV"],
      linksAttributes: [["data-menu-links", ""]],
    });
  });

  it("Escape closes the menu and returns focus to the menu button", () => {
    renderAt("/");
    const button = menuToggle();
    const id = button.getAttribute("aria-controls") ?? "";
    const record = (notPrevented: boolean) => ({
      prevented: !notPrevented,
      expanded: button.getAttribute("aria-expanded"),
      gone: document.getElementById(id) === null,
      focusOnMenu: document.activeElement === button,
    });

    const { dialog } = openDialog();
    const first = record(
      fireEvent.keyDown(only(dialog, "button[data-menu-close]"), {
        key: "Escape",
      }),
    );
    const reopened = openDialog().dialog;
    linkNamed(reopened, "Media").focus();
    const second = record(
      fireEvent.keyDown(linkNamed(reopened, "Media"), { key: "Escape" }),
    );

    expect([first, second]).toEqual([
      { prevented: true, expanded: "false", gone: true, focusOnMenu: true },
      { prevented: true, expanded: "false", gone: true, focusOnMenu: true },
    ]);
  });

  it("the Close button closes the menu and returns focus to the menu button", () => {
    renderAt("/");
    const button = menuToggle();
    const id = button.getAttribute("aria-controls") ?? "";
    const state = () => ({
      expanded: button.getAttribute("aria-expanded"),
      gone: document.getElementById(id) === null,
    });

    const { dialog } = openDialog();
    fireEvent.click(only(dialog, "button[data-menu-close]"));
    const closed = {
      ...state(),
      focusOnMenu: document.activeElement === button,
    };
    const { dialog: again } = openDialog();
    const reopened = state();
    act(() => {
      again.close();
    });
    const native = {
      ...state(),
      focusOnMenu: document.activeElement === button,
    };

    expect([closed, reopened, native]).toEqual([
      { expanded: "false", gone: true, focusOnMenu: true },
      { expanded: "true", gone: false },
      { expanded: "false", gone: true, focusOnMenu: true },
    ]);
  });

  it("choosing any page closes the menu and returns focus to the menu button", () => {
    renderAt("/");
    const button = menuToggle();
    const id = button.getAttribute("aria-controls") ?? "";

    const records = SEVEN_LINKS.map(({ name }) => {
      const { dialog } = openDialog();
      const link = linkNamed(dialog, name);
      const href = link.getAttribute("href");
      fireEvent.click(link);
      return {
        name,
        href,
        expanded: button.getAttribute("aria-expanded"),
        gone: document.getElementById(id) === null,
        focusOnMenu: document.activeElement === button,
      };
    });

    expect(records).toEqual(
      SEVEN_LINKS.map(({ name, href }) => ({
        name,
        href,
        expanded: "false",
        gone: true,
        focusOnMenu: true,
      })),
    );
  });

  it("Tab and Shift+Tab keep focus inside the open menu", () => {
    renderAt("/");
    const { dialog } = openDialog();
    const close = only(dialog, "button[data-menu-close]");
    const contact = linkNamed(dialog, "Contact");
    const media = linkNamed(dialog, "Media");
    const records: {
      step: string;
      prevented: boolean;
      active: string | null;
    }[] = [];
    const press = (step: string, target: HTMLElement, shiftKey: boolean) => {
      const notPrevented = fireEvent.keyDown(target, { key: "Tab", shiftKey });
      records.push({
        step,
        prevented: !notPrevented,
        active: accessibleName(document.activeElement),
      });
    };

    press("shift-tab on Close", close, true);
    press("tab on Contact", contact, false);
    press("tab on Close", close, false);
    contact.focus();
    press("shift-tab on Contact", contact, true);
    media.focus();
    press("tab on Media", media, false);

    expect(records).toEqual([
      { step: "shift-tab on Close", prevented: true, active: "Contact" },
      { step: "tab on Contact", prevented: true, active: "Close" },
      { step: "tab on Close", prevented: false, active: "Close" },
      { step: "shift-tab on Contact", prevented: false, active: "Contact" },
      { step: "tab on Media", prevented: false, active: "Media" },
    ]);
  });

  it("marks the current page's link as the current page", () => {
    const pathnames = ["/performing/media", "/", "/contact", "/therapy"];

    const lists = pathnames.map((pathname) => {
      const { unmount } = renderAt(pathname);
      const { dialog } = openDialog();
      const current = Array.from(
        only(dialog, "[data-menu-links]").querySelectorAll("a"),
        (a) => a.getAttribute("aria-current"),
      );
      unmount();
      return current;
    });

    expect(lists).toEqual([
      [null, null, null, null, null, "page", null],
      ["page", null, null, null, null, null, null],
      [null, null, null, null, null, null, "page"],
      [null, null, null, null, null, null, null],
    ]);
  });
});
