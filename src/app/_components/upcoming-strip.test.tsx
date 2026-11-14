// @vitest-environment happy-dom
import { text } from "node:stream/consumers";
import { prerender } from "react-dom/static";
import { describe, expect, it } from "vitest";
import type { EventCard } from "../../server/calendar/events";
import { UpcomingStrip, type Upcoming } from "./upcoming-strip";

const CALENDAR_URL = "https://calendar.example/rachel";
const CARD_COUNT = 3;

const A: EventCard = {
  date: "Nov 22",
  title: "American Kantorei Performance",
  location: { kind: "text", text: "Concordia Seminary, St. Louis" },
};
const B: EventCard = {
  date: "Oct 16–18",
  title: "Harry Potter in Concert",
  location: { kind: "link", href: "https://example.com/hp" },
};
const C: EventCard = {
  date: "Mar 1",
  title: "Chamber Music Society",
  location: null,
};

const CARDS: Upcoming = { available: true, cards: [A, B, C] };
const NONE: Upcoming = { available: true, cards: [] };
const UNAVAILABLE: Upcoming = { available: false, cards: [] };

async function renderStrip(upcoming: Upcoming): Promise<Document> {
  const { prelude } = await prerender(
    <UpcomingStrip upcoming={upcoming} calendarUrl={CALENDAR_URL} />,
  );
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
        ["P", "Nov 22"],
        ["H3", "American Kantorei Performance"],
        ["P", "Concordia Seminary, St. Louis"],
      ],
      [
        ["P", "Oct 16–18"],
        ["H3", "Harry Potter in Concert"],
        ["A", "Details"],
      ],
      [
        ["P", "Mar 1"],
        ["H3", "Chamber Music Society"],
      ],
    ]);
  });

  it("opens a URL location as a Details link in a new tab", async () => {
    const doc = await renderStrip(CARDS);
    expect(links(doc)).toEqual([
      {
        text: "Details",
        href: "https://example.com/hp",
        target: "_blank",
        rel: "noopener noreferrer",
      },
    ]);
  });

  it("says none are scheduled when no events are upcoming", async () => {
    const doc = await renderStrip(NONE);
    expect(texts(doc, "section p")).toEqual([
      "No upcoming events are scheduled right now.",
    ]);
    expect(doc.querySelectorAll("li")).toHaveLength(0);
    expect(doc.querySelectorAll("a")).toHaveLength(0);
    expect(doc.querySelectorAll('[role="region"]')).toHaveLength(0);
  });

  it("shows the fallback message and a calendar link when no events are available", async () => {
    const doc = await renderStrip(UNAVAILABLE);
    expect(texts(doc, "section p")).toEqual([
      "Events are unavailable right now.",
      "See the full calendar",
    ]);
    expect(links(doc)).toEqual([
      {
        text: "See the full calendar",
        href: CALENDAR_URL,
        target: "_blank",
        rel: "noopener noreferrer",
      },
    ]);
    expect(doc.querySelectorAll("li")).toHaveLength(0);
    expect(doc.querySelectorAll('[role="region"]')).toHaveLength(0);
  });

  it("makes the scrolling row keyboard-focusable with an accessible name", async () => {
    const doc = await renderStrip(CARDS);
    const regions = [...doc.querySelectorAll('[role="region"]')];
    expect(
      regions.map((r) => ({
        tabindex: r.getAttribute("tabindex"),
        label: r.getAttribute("aria-label"),
      })),
    ).toEqual([{ tabindex: "0", label: "Upcoming events" }]);
    expect(regions[0]?.querySelectorAll("li").length).toBe(CARD_COUNT);
  });
});
