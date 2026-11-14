// @vitest-environment happy-dom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { SiteHeader } from "./site-header";

afterEach(() => {
  cleanup();
});

function tab(): HTMLElement {
  return screen.getByRole("button", { name: /Therapy/ });
}

function firstItem(): HTMLElement {
  const list = document.getElementById(
    tab().getAttribute("aria-controls") ?? "",
  );
  const first = list?.querySelector("a");
  expect(first).toBeTruthy();
  return first as HTMLElement;
}

function openTabWithClick(): HTMLElement {
  render(<SiteHeader />);
  const t = tab();
  fireEvent.click(t);
  t.focus();
  return t;
}

describe("NavDropdown keyboard", () => {
  it.each(["Enter", " ", "ArrowDown"])(
    "prevents the default of %j keydown on a closed tab",
    (key) => {
      render(<SiteHeader />);

      const notPrevented = fireEvent.keyDown(tab(), { key });

      expect(notPrevented).toBe(false);
      expect(tab().getAttribute("aria-expanded")).toBe("true");
    },
  );

  it.each(["Tab", "a", "ArrowUp", "Escape"])(
    "leaves a closed tab closed and %j keydown unprevented",
    (key) => {
      render(<SiteHeader />);

      const notPrevented = fireEvent.keyDown(tab(), { key });

      expect(notPrevented).toBe(true);
      expect(tab().getAttribute("aria-expanded")).toBe("false");
    },
  );

  it("prevents the default of Space keyup on the tab only", () => {
    render(<SiteHeader />);

    const space = fireEvent.keyUp(tab(), { key: " " });
    const enter = fireEvent.keyUp(tab(), { key: "Enter" });
    const letter = fireEvent.keyUp(tab(), { key: "a" });

    expect(space).toBe(false);
    expect(enter).toBe(true);
    expect(letter).toBe(true);
  });

  it.each(["Enter", " ", "ArrowDown"])(
    "moves focus to the first item on %j when the tab is already open",
    (key) => {
      const t = openTabWithClick();

      fireEvent.keyDown(t, { key });
      fireEvent.keyUp(t, { key });

      expect(t.getAttribute("aria-expanded")).toBe("true");
      expect(document.activeElement).toBe(firstItem());
    },
  );

  it("closes an open tab on Escape and keeps focus on the tab", () => {
    const t = openTabWithClick();

    const notPrevented = fireEvent.keyDown(t, { key: "Escape" });

    expect(notPrevented).toBe(false);
    expect(t.getAttribute("aria-expanded")).toBe("false");
    expect(document.activeElement).toBe(t);
  });

  it.each(["Enter", "Tab"])(
    "leaves %j keydown on a dropdown link unprevented with focus kept",
    (key) => {
      const t = openTabWithClick();
      const link = firstItem();
      link.focus();

      const notPrevented = fireEvent.keyDown(link, { key });

      expect(notPrevented).toBe(true);
      expect(document.activeElement).toBe(link);
      expect(t.getAttribute("aria-expanded")).toBe("true");
    },
  );
});
