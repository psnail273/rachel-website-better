// @vitest-environment happy-dom
import { text } from "node:stream/consumers";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { prerender } from "react-dom/static";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { EventCard } from "../../server/calendar/events";
import { UpcomingStrip, type Upcoming } from "./upcoming-strip";

const CALENDAR_URL = "https://calendar.example/rachel";
const CARD_COUNT = 3;
const ELEMENT_NODE = 1;
const CARD_OFFSETS = [40, 320, 600, 880];
const STEP = 280;
const CLIENT_WIDTH = 600;
const SCROLL_WIDTH = 1180;
const MOST_SCROLL = SCROLL_WIDTH - CLIENT_WIDTH;
const REDUCED_MOTION = "(prefers-reduced-motion: reduce)";

const A: EventCard = {
  date: "22 November",
  title: "American Kantorei Performance",
  location: { kind: "text", text: "Concordia Seminary, St. Louis" },
};
const B: EventCard = {
  date: "16–18 October",
  title: "Harry Potter in Concert",
  location: { kind: "link", href: "https://example.com/hp" },
};
const C: EventCard = {
  date: "30 October – 2 November",
  title: "Chamber Music Society",
  location: null,
};
const D: EventCard = {
  date: "1 March",
  title: "Spring Recital",
  location: null,
};

const CARDS: Upcoming = { available: true, cards: [A, B, C] };
const FOUR: Upcoming = { available: true, cards: [A, B, C, D] };
const NONE: Upcoming = { available: true, cards: [] };
const UNAVAILABLE: Upcoming = { available: false, cards: [] };

function strip(upcoming: Upcoming) {
  return <UpcomingStrip upcoming={upcoming} calendarUrl={CALENDAR_URL} />;
}

async function renderStrip(upcoming: Upcoming): Promise<Document> {
  const { prelude } = await prerender(strip(upcoming));
  const html = await text(prelude);
  return new DOMParser().parseFromString(html, "text/html");
}

function texts(doc: Document, selector: string): (string | null)[] {
  return [...doc.querySelectorAll(selector)].map((el) => el.textContent);
}

function links(doc: Document) {
  return [...doc.querySelectorAll("a")].map((a) => ({
    text: a.textContent,
    href: a.getAttribute("href"),
    target: a.getAttribute("target"),
    rel: a.getAttribute("rel"),
  }));
}

function rowOf(): HTMLElement {
  const rows = screen.queryAllByRole("list", { name: "Upcoming events" });
  expect(rows).toHaveLength(1);
  return rows[0];
}

function buttonOf(name: string): HTMLElement {
  const found = screen.queryAllByRole("button", { name });
  expect(found).toHaveLength(1);
  return found[0];
}

function isDisabled(name: string): boolean {
  return buttonOf(name).hasAttribute("disabled");
}

function measure(row: HTMLElement, scrollWidth: number): void {
  Object.defineProperty(row, "clientWidth", {
    configurable: true,
    value: CLIENT_WIDTH,
  });
  Object.defineProperty(row, "scrollWidth", {
    configurable: true,
    value: scrollWidth,
  });
  row.querySelectorAll("li").forEach((li, index) => {
    Object.defineProperty(li, "offsetLeft", {
      configurable: true,
      value: CARD_OFFSETS[index],
    });
  });
}

function renderMeasured(): HTMLElement {
  render(strip(FOUR));
  const row = rowOf();
  measure(row, SCROLL_WIDTH);
  fireEvent.scroll(row);
  return row;
}

function offsetLeftOf(this: HTMLLIElement): number {
  const siblings = [...(this.parentElement?.children ?? [])];
  return CARD_OFFSETS[0] + STEP * siblings.indexOf(this);
}

function measureOnPrototypes(): void {
  Object.defineProperty(HTMLUListElement.prototype, "scrollWidth", {
    configurable: true,
    get: () => SCROLL_WIDTH,
  });
  Object.defineProperty(HTMLUListElement.prototype, "clientWidth", {
    configurable: true,
    get: () => CLIENT_WIDTH,
  });
  Object.defineProperty(HTMLLIElement.prototype, "offsetLeft", {
    configurable: true,
    get: offsetLeftOf,
  });
}

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  Reflect.deleteProperty(HTMLUListElement.prototype, "scrollWidth");
  Reflect.deleteProperty(HTMLUListElement.prototype, "clientWidth");
  Reflect.deleteProperty(HTMLLIElement.prototype, "offsetLeft");
});

const TOKENS = [
  "bg",
  "surface",
  "tint",
  "ink",
  "heading",
  "muted",
  "link",
  "accent",
  "error",
  "ornament",
  "line",
  "line-strong",
  "band",
  "on-band",
  "on-band-muted",
  "band-accent",
  "plum",
  "on-image",
  "poster",
];

function tokenClasses(el: Element | null, prefix: string): string[] {
  return [...(el?.classList ?? [])].filter((name) =>
    TOKENS.some((token) => name === `${prefix}-${token}`),
  );
}

function expectMessageState(doc: Document, message: string): void {
  const section = doc.querySelector("section");
  expect([...(section?.children ?? [])].map((c) => c.tagName)).toEqual([
    "H2",
    "DIV",
  ]);
  const prose = section?.querySelector("div");
  expect(prose?.getAttribute("data-prose")).toBe("center");
  expect(
    [...(prose?.children ?? [])].map((c) => [c.tagName, c.textContent]),
  ).toEqual([
    ["P", message],
    ["P", "See the full calendar"],
  ]);
  expect(links(doc)).toEqual([
    {
      text: "See the full calendar",
      href: CALENDAR_URL,
      target: "_blank",
      rel: "noopener noreferrer",
    },
  ]);
  expect(doc.querySelectorAll("ul")).toHaveLength(0);
  expect(doc.querySelectorAll("li")).toHaveLength(0);
  expect(doc.querySelectorAll("button")).toHaveLength(0);
  expect(doc.querySelectorAll('[role="region"]')).toHaveLength(0);
}

describe("UpcomingStrip", () => {
  it("shows a section headed Upcoming", async () => {
    const doc = await renderStrip(CARDS);
    expect(texts(doc, "h2")).toEqual(["Upcoming"]);
    expect(doc.querySelector("section")?.getAttribute("aria-labelledby")).toBe(
      "upcoming-heading",
    );
    expect(doc.querySelector("h2")?.getAttribute("id")).toBe(
      "upcoming-heading",
    );
    expect(texts(await renderStrip(NONE), "h2")).toEqual(["Upcoming"]);
    expect(texts(await renderStrip(UNAVAILABLE), "h2")).toEqual(["Upcoming"]);
  });

  it("renders each card with its date, title and location", async () => {
    const doc = await renderStrip(CARDS);
    const cards = [...doc.querySelectorAll("section li")].map((li) =>
      [...li.children].map((child) => [child.tagName, child.textContent]),
    );
    expect(cards).toEqual([
      [
        ["P", "22 November"],
        ["H3", "American Kantorei Performance"],
        ["P", "Concordia Seminary, St. Louis"],
      ],
      [
        ["P", "16–18 October"],
        ["H3", "Harry Potter in Concert"],
        ["A", "Details about Harry Potter in Concert"],
      ],
      [
        ["P", "30 October – 2 November"],
        ["H3", "Chamber Music Society"],
      ],
    ]);
  });

  it("opens a URL location as a Details link in a new tab", async () => {
    const doc = await renderStrip(CARDS);
    expect(links(doc)).toEqual([
      {
        text: "Details about Harry Potter in Concert",
        href: "https://example.com/hp",
        target: "_blank",
        rel: "noopener noreferrer",
      },
    ]);
    const parts = [...(doc.querySelector("a")?.childNodes ?? [])].map(
      (node) => ({
        element: node.nodeType === ELEMENT_NODE,
        tag: node.nodeType === ELEMENT_NODE ? node.nodeName : null,
        text: node.textContent,
      }),
    );
    expect(parts).toEqual([
      { element: false, tag: null, text: "Details" },
      { element: true, tag: "SPAN", text: " about Harry Potter in Concert" },
    ]);
    expect(doc.querySelector("a > span")?.getAttribute("class")).toBe(
      "sr-only",
    );
    expect(doc.querySelectorAll("a svg")).toHaveLength(0);

    render(strip(CARDS));
    expect(
      screen.queryAllByRole("link", {
        name: "Details about Harry Potter in Concert",
      }),
    ).toHaveLength(1);
  });

  it("says none are scheduled when no events are upcoming", async () => {
    const doc = await renderStrip(NONE);
    expectMessageState(doc, "No upcoming events are scheduled right now.");
  });

  it("shows the fallback message and a calendar link when no events are available", async () => {
    const doc = await renderStrip(UNAVAILABLE);
    expectMessageState(doc, "Events are unavailable right now.");
  });

  it("makes the scrolling row keyboard-focusable with an accessible name", async () => {
    const doc = await renderStrip(CARDS);
    const rows = [...doc.querySelectorAll("ul")];
    expect(
      rows.map((r) => ({
        events: r.getAttribute("data-events"),
        label: r.getAttribute("aria-label"),
        tabindex: r.getAttribute("tabindex"),
      })),
    ).toEqual([{ events: "", label: "Upcoming events", tabindex: "0" }]);
    expect(rows[0]?.querySelectorAll("li")).toHaveLength(CARD_COUNT);
    expect(
      [...doc.querySelectorAll("li")].map((li) =>
        li.getAttribute("data-event"),
      ),
    ).toEqual(["", "", ""]);
    expect(doc.querySelectorAll('[role="region"]')).toHaveLength(0);
  });

  it("sets each card's date in heading on the surface ground", async () => {
    const doc = await renderStrip(CARDS);
    const items = [...doc.querySelectorAll("li")];

    expect(items.map((li) => tokenClasses(li, "bg"))).toEqual([
      ["bg-surface"],
      ["bg-surface"],
      ["bg-surface"],
    ]);
    expect(
      items.map((li) => tokenClasses(li.firstElementChild, "text")),
    ).toEqual([["text-heading"], ["text-heading"], ["text-heading"]]);
  });

  it("scrolls the row forward and back by one card", async () => {
    const row = renderMeasured();
    const scrollBy = vi.spyOn(row, "scrollBy");

    fireEvent.click(buttonOf("Next events"));
    expect(scrollBy).toHaveBeenCalledTimes(1);
    expect(scrollBy).toHaveBeenNthCalledWith(1, {
      left: STEP,
      behavior: "smooth",
    });
    await vi.waitFor(() => {
      expect(row.scrollLeft).toBe(STEP);
    });
    fireEvent.scroll(row);
    expect(isDisabled("Previous events")).toBe(false);
    expect(isDisabled("Next events")).toBe(false);

    fireEvent.click(buttonOf("Previous events"));
    expect(scrollBy).toHaveBeenNthCalledWith(2, {
      left: -STEP,
      behavior: "smooth",
    });
    await vi.waitFor(() => {
      expect(row.scrollLeft).toBe(0);
    });
    fireEvent.scroll(row);
    expect(isDisabled("Previous events")).toBe(true);
    expect(scrollBy).toHaveBeenCalledTimes(2);
  });

  it("scrolls without smooth motion when reduced motion is preferred", () => {
    vi.stubGlobal("matchMedia", (query: string) => ({
      matches: query === REDUCED_MOTION,
      media: query,
    }));
    const row = renderMeasured();
    const scrollBy = vi.spyOn(row, "scrollBy");

    fireEvent.click(buttonOf("Next events"));
    expect(scrollBy).toHaveBeenCalledTimes(1);
    expect(scrollBy).toHaveBeenNthCalledWith(1, {
      left: STEP,
      behavior: "auto",
    });
    expect(row.scrollLeft).toBe(STEP);
  });

  it("shows Previous events and Next events in a centred Cluster under an overflowing row", () => {
    const row = renderMeasured();
    const cluster = row.nextElementSibling;
    expect(cluster?.tagName).toBe("DIV");
    expect(cluster?.getAttribute("data-cluster")).toBe("center");
    expect(
      [...(cluster?.children ?? [])].map((b) => [
        b.tagName,
        b.getAttribute("type"),
        b.getAttribute("aria-label"),
        b.hasAttribute("disabled"),
      ]),
    ).toEqual([
      ["BUTTON", "button", "Previous events", true],
      ["BUTTON", "button", "Next events", false],
    ]);
    const icons = [...(cluster?.children ?? [])].map((b) => ({
      count: b.childNodes.length,
      tag: b.firstElementChild?.tagName.toLowerCase(),
      hidden: b.firstElementChild?.getAttribute("aria-hidden"),
      width: b.firstElementChild?.getAttribute("width"),
      height: b.firstElementChild?.getAttribute("height"),
    }));
    const icon = {
      count: 1,
      tag: "svg",
      hidden: "true",
      width: "20",
      height: "20",
    };
    expect(icons).toEqual([icon, icon]);
    const parent = row.parentElement;
    expect(parent?.tagName).toBe("DIV");
    expect(parent?.getAttribute("data-stack")).toBe("heading");
    expect(parent?.children).toHaveLength(2);
    expect(parent?.children[0]).toBe(row);
    expect(parent?.children[1]).toBe(cluster);
  });

  it("disables Previous events within 1px of the start of the row", () => {
    const row = renderMeasured();
    row.scrollLeft = 1;
    fireEvent.scroll(row);
    expect(isDisabled("Previous events")).toBe(true);
    expect(isDisabled("Next events")).toBe(false);
    row.scrollLeft = 2;
    fireEvent.scroll(row);
    expect(isDisabled("Previous events")).toBe(false);
    expect(isDisabled("Next events")).toBe(false);
  });

  it("disables Next events within 1px of the end of the row", () => {
    const row = renderMeasured();
    row.scrollLeft = MOST_SCROLL - 1;
    fireEvent.scroll(row);
    expect(isDisabled("Next events")).toBe(true);
    expect(isDisabled("Previous events")).toBe(false);
    row.scrollLeft = MOST_SCROLL - 2;
    fireEvent.scroll(row);
    expect(isDisabled("Next events")).toBe(false);
    expect(isDisabled("Previous events")).toBe(false);
  });

  it("shows no arrows when the row doesn't overflow", async () => {
    const doc = await renderStrip(CARDS);
    expect(doc.querySelectorAll("button")).toHaveLength(0);
    expect(
      [...(doc.querySelector('[data-stack="heading"]')?.children ?? [])].map(
        (c) => c.tagName,
      ),
    ).toEqual(["UL"]);

    render(strip(FOUR));
    expect(screen.queryAllByRole("button")).toEqual([]);

    const row = rowOf();
    measure(row, CLIENT_WIDTH + 1);
    fireEvent.scroll(row);
    expect(screen.queryAllByRole("button")).toEqual([]);
    expect(row.nextElementSibling).toBeNull();

    measure(row, CLIENT_WIDTH + 2);
    fireEvent(window, new Event("resize"));
    expect(
      screen.queryAllByRole("button").map((b) => b.getAttribute("aria-label")),
    ).toEqual(["Previous events", "Next events"]);

    measure(row, CLIENT_WIDTH);
    fireEvent(window, new Event("resize"));
    expect(screen.queryAllByRole("button")).toEqual([]);
  });

  it("shows the arrows as soon as an overflowing row mounts", () => {
    measureOnPrototypes();
    render(strip(FOUR));
    expect(
      screen
        .queryAllByRole("button")
        .map((b) => [b.getAttribute("aria-label"), b.hasAttribute("disabled")]),
    ).toEqual([
      ["Previous events", true],
      ["Next events", false],
    ]);
  });

  it("stops listening for resizes once it unmounts", () => {
    const add = vi.spyOn(window, "addEventListener");
    const remove = vi.spyOn(window, "removeEventListener");
    const { unmount } = render(strip(FOUR));
    unmount();
    const added = add.mock.calls.filter(([type]) => type === "resize");
    const removed = remove.mock.calls.filter(([type]) => type === "resize");
    expect(added).toHaveLength(1);
    expect(removed).toHaveLength(1);
    expect(removed[0]?.[1]).toBe(added[0]?.[1]);
  });
});
