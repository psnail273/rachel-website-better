// @vitest-environment happy-dom
import { mkdtempSync, rmSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { text } from "node:stream/consumers";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { cacheLife } from "next/cache";
import { prerender } from "react-dom/static";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import UpcomingLayout from "./layout";

vi.mock("next/cache", () => ({ cacheLife: vi.fn() }));

const FEED_URL = "https://feed.test/calendar.ics";
const TEN_SECONDS_MS = 10_000;
const PUBLIC_CALENDAR_URL =
  "https://calendar.google.com/calendar/embed?src=f93593a9aa8efdef9b296cd13ae5518c085ad3e1b69bb609278e09df2dc88ee4%40group.calendar.google.com&ctz=America%2FChicago";

const FIXTURE =
  [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "X-WR-TIMEZONE:America/Chicago",
    "BEGIN:VEVENT",
    "SUMMARY:Fall Recital",
    "DTSTART:20261101T000000Z",
    "DTEND:20261101T020000Z",
    "LOCATION:Old Hall",
    "END:VEVENT",
    "BEGIN:VEVENT",
    "SUMMARY:Harry Potter in Concert",
    "DTSTART:20261205T013000Z",
    "DTEND:20261205T040000Z",
    "LOCATION:https://example.com/hp",
    "END:VEVENT",
    "BEGIN:VEVENT",
    "SUMMARY:American Kantorei Performance",
    "DTSTART:20261123T003000Z",
    "DTEND:20261123T020000Z",
    "LOCATION:Concordia Seminary\\, St. Louis",
    "END:VEVENT",
    "BEGIN:VEVENT",
    "SUMMARY:harry potter in concert",
    "DTSTART:20261206T013000Z",
    "DTEND:20261206T040000Z",
    "LOCATION:https://example.com/hp",
    "END:VEVENT",
    "BEGIN:VEVENT",
    "SUMMARY:Chamber Music Society",
    "DTSTART:20270301T200000Z",
    "DTEND:20270301T220000Z",
    "END:VEVENT",
    "END:VCALENDAR",
  ].join("\r\n") + "\r\n";

const THREE_CARDS = [
  [
    ["P", "Nov 22"],
    ["H3", "American Kantorei Performance"],
    ["P", "Concordia Seminary, St. Louis"],
  ],
  [
    ["P", "Dec 4–5"],
    ["H3", "Harry Potter in Concert"],
    ["A", "Details"],
  ],
  [
    ["P", "Mar 1"],
    ["H3", "Chamber Music Society"],
  ],
];

type FeedFetch = (url: string, init?: RequestInit) => Promise<Response>;

let folder = "";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-11-14T12:00:00Z"));
  folder = mkdtempSync(join(tmpdir(), "upcoming-"));
  vi.stubEnv("EVENTS_CACHE_PATH", join(folder, "events.sqlite"));
  vi.stubEnv("CALENDAR_FEED_URL", FEED_URL);
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
  vi.useRealTimers();
  vi.restoreAllMocks();
  rmSync(folder, { recursive: true, force: true });
});

function feedFake() {
  return vi.fn<FeedFetch>(() => Promise.resolve(new Response(FIXTURE)));
}

function failingFake() {
  return vi.fn<FeedFetch>(() => Promise.reject(new TypeError("fetch failed")));
}

async function renderLayout(): Promise<Document> {
  const { prelude } = await prerender(
    await UpcomingLayout({ children: <p>Page body</p> }),
  );
  const html = await text(prelude);
  return new DOMParser().parseFromString(html, "text/html");
}

function cardsOf(doc: Document) {
  return [...doc.querySelectorAll("section li")].map((li) =>
    [...li.children].map((child) => [child.tagName, child.textContent]),
  );
}

describe("UpcomingLayout", () => {
  it("renders the page, then the Upcoming strip from the feed", async () => {
    const fetchFake = feedFake();
    vi.stubGlobal("fetch", fetchFake);
    const doc = await renderLayout();
    expect([...doc.body.children].map((el) => el.tagName)).toEqual([
      "P",
      "SECTION",
    ]);
    expect(doc.body.children[0]?.textContent).toBe("Page body");
    expect(cardsOf(doc)).toEqual(THREE_CARDS);
    expect(fetchFake).toHaveBeenCalledTimes(1);
    expect(fetchFake).toHaveBeenCalledWith(FEED_URL, {
      signal: expect.any(AbortSignal) as unknown,
    });
  });

  it("serves the cached events when the feed can't be read", async () => {
    vi.stubGlobal("fetch", feedFake());
    await renderLayout();
    const failing = failingFake();
    vi.stubGlobal("fetch", failing);
    const doc = await renderLayout();
    expect(cardsOf(doc)).toEqual(THREE_CARDS);
    expect(failing).toHaveBeenCalledTimes(1);
    expect(failing.mock.calls[0]?.[0]).toBe(FEED_URL);
  });

  it("shows the fallback when the feed can't be read and the cache is empty", async () => {
    vi.stubGlobal("fetch", failingFake());
    const doc = await renderLayout();
    expect(
      [...doc.querySelectorAll("section p")].map((p) => p.textContent),
    ).toEqual(["Events are unavailable right now.", "See the full calendar"]);
    expect(
      [...doc.querySelectorAll("a")].map((a) => ({
        text: a.textContent,
        href: a.getAttribute("href"),
        target: a.getAttribute("target"),
        rel: a.getAttribute("rel"),
      })),
    ).toEqual([
      {
        text: "See the full calendar",
        href: PUBLIC_CALENDAR_URL,
        target: "_blank",
        rel: "noopener noreferrer",
      },
    ]);
  });

  it("caches the events for an hour", async () => {
    vi.stubGlobal("fetch", feedFake());
    await renderLayout();
    expect(cacheLife).toHaveBeenCalledTimes(1);
    expect(cacheLife).toHaveBeenCalledWith("hours");
  });

  it("closes the cache and limits each feed read to 10 seconds", async () => {
    const close = vi.spyOn(DatabaseSync.prototype, "close");
    const timeout = vi.spyOn(AbortSignal, "timeout");
    vi.stubGlobal("fetch", feedFake());
    await renderLayout();
    vi.stubGlobal("fetch", failingFake());
    await renderLayout();
    expect(close).toHaveBeenCalledTimes(2);
    expect(timeout.mock.calls).toEqual([[TEN_SECONDS_MS], [TEN_SECONDS_MS]]);
  });
});
