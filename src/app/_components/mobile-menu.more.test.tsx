// @vitest-environment happy-dom
import { PathnameContext } from "next/dist/shared/lib/hooks-client-context.shared-runtime";
import { cleanup, fireEvent, render } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { SiteHeader } from "./site-header";

afterEach(() => {
  cleanup();
});

function renderAt(pathname: string) {
  return render(
    <PathnameContext.Provider value={pathname}>
      <SiteHeader />
    </PathnameContext.Provider>,
  );
}

function find(selector: string): HTMLElement {
  const found = document.querySelector<HTMLElement>(selector);
  if (found === null) throw new Error(`${selector} is missing`);
  return found;
}

function openMenu() {
  const button = find("button[data-menu-button]");
  fireEvent.click(button);
  const dialog = find("dialog[data-menu]");
  return { button, dialog };
}

describe("MobileMenu more", () => {
  it("leaves focus where it was while the menu stays closed", () => {
    renderAt("/");

    expect(document.activeElement).toBe(document.body);
  });

  it("leaves the page alone when a key other than Tab is pressed at either end", () => {
    renderAt("/");
    const { dialog } = openMenu();
    const close = find("button[data-menu-close]");
    const contact = Array.from(dialog.querySelectorAll("a")).filter(
      (a) => a.textContent === "Contact",
    )[0];
    const keys = ["Enter", "ArrowDown", "a"];

    const records = keys.flatMap((key) => {
      close.focus();
      const onClose = fireEvent.keyDown(close, { key, shiftKey: true });
      const afterClose = document.activeElement === close;
      contact.focus();
      const onContact = fireEvent.keyDown(contact, { key });
      const afterContact = document.activeElement === contact;
      return [{ key, onClose, afterClose, onContact, afterContact }];
    });

    expect(records).toEqual(
      keys.map((key) => ({
        key,
        onClose: true,
        afterClose: true,
        onContact: true,
        afterContact: true,
      })),
    );
  });

  it("a cancel request closes the menu, is prevented and returns focus to the menu button", () => {
    renderAt("/");
    const { button, dialog } = openMenu();
    const id = dialog.id;

    const notPrevented = fireEvent(
      dialog,
      new Event("cancel", { bubbles: false, cancelable: true }),
    );

    expect({
      prevented: !notPrevented,
      expanded: button.getAttribute("aria-expanded"),
      gone: document.getElementById(id) === null,
      focusOnMenu: document.activeElement === button,
    }).toEqual({
      prevented: true,
      expanded: "false",
      gone: true,
      focusOnMenu: true,
    });
  });
});
