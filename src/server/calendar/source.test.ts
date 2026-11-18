import { afterEach, describe, expect, it, vi } from "vitest";

import { openEventsCache } from "./cache";
import type { CalendarEvent } from "./events";
import { feedUrls, fetchFeed, loadEvents, type FetchFeed } from "./source";

const A = "https://calendar.example/a.ics";
const B = "https://calendar.example/b.ics";

function ics(...vevents: string[][]): string {
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Test//EN",
    ...vevents.flatMap((v) => ["BEGIN:VEVENT", ...v, "END:VEVENT"]),
    "END:VCALENDAR",
  ];
  return lines.join("\r\n") + "\r\n";
}

const ICS_A = ics(
  [
    "SUMMARY:Early Music Missouri Concert",
    "DTSTART:20261004T190000Z",
    "DTEND:20261004T200000Z",
    "LOCATION:https://earlymusicmissouri.org/",
  ],
  [
    "SUMMARY:Open Rehearsal",
    "DTSTART;VALUE=DATE:20261122",
    "DTEND;VALUE=DATE:20261123",
  ],
);

const ICS_B = ics([
  "SUMMARY:Collegium Vocale of St. Louis Concert",
  "DTSTART:20261025T190000Z",
  "DTEND:20261025T203000Z",
  "LOCATION:Second Presbyterian Church",
]);

const EVENTS_A: CalendarEvent[] = [
  {
    title: "Early Music Missouri Concert",
    start: "2026-10-04T19:00:00.000Z",
    end: "2026-10-04T20:00:00.000Z",
    allDay: false,
    location: "https://earlymusicmissouri.org/",
  },
  {
    title: "Open Rehearsal",
    start: "2026-11-22",
    end: "2026-11-23",
    allDay: true,
    location: null,
  },
];

const EVENTS_B: CalendarEvent[] = [
  {
    title: "Collegium Vocale of St. Louis Concert",
    start: "2026-10-25T19:00:00.000Z",
    end: "2026-10-25T20:30:00.000Z",
    allDay: false,
    location: "Second Presbyterian Church",
  },
];

const CACHED: CalendarEvent[] = [
  {
    title: "Harry Potter with the Nashville Symphony",
    start: "2026-11-08T00:30:00.000Z",
    end: "2026-11-08T03:00:00.000Z",
    allDay: false,
    location: "Schermerhorn Symphony Center, Nashville",
  },
];

type Answer = Response | "network";

function fakeFetch(answers: Record<string, Answer>): {
  fetchFeed: FetchFeed;
  calls: string[][];
} {
  const calls: string[][] = [];
  const fetchFeed = (...args: [string]): Promise<Response> => {
    calls.push(args);
    const answer = answers[args[0]];
    if (answer === undefined || answer === "network") {
      return Promise.reject(new TypeError("fetch failed"));
    }
    return Promise.resolve(answer);
  };
  return { fetchFeed, calls };
}

function ok(body: string, status = 200): Response {
  return new Response(body, { status });
}

describe("feedUrls", () => {
  it("uses the configured feeds when CALENDAR_FEED_URL is unset or empty", () => {
    expect(feedUrls([A, B], {})).toEqual([A, B]);
    expect(feedUrls([A, B], { CALENDAR_FEED_URL: "" })).toEqual([A, B]);
  });

  it("uses only CALENDAR_FEED_URL when it is set", () => {
    expect(
      feedUrls([A, B], { CALENDAR_FEED_URL: "http://127.0.0.1:4010/feed.ics" }),
    ).toEqual(["http://127.0.0.1:4010/feed.ics"]);
  });
});

describe("loadEvents", () => {
  it("stores a successful read and serves it when a later read fails", async () => {
    const cache = openEventsCache(":memory:");
    const first = await loadEvents(
      [A],
      fakeFetch({ [A]: ok(ICS_A) }).fetchFeed,
      cache,
    );
    const stored = cache.read(A);
    const second = await loadEvents(
      [A],
      fakeFetch({ [A]: "network" }).fetchFeed,
      cache,
    );
    cache.close();
    expect(first).toEqual({ events: EVENTS_A, available: true });
    expect(stored).toEqual(EVENTS_A);
    expect(second).toEqual({ events: EVENTS_A, available: true });
  });

  it("replaces a feed's cached events on each successful read", async () => {
    const cache = openEventsCache(":memory:");
    await loadEvents([A], fakeFetch({ [A]: ok(ICS_A) }).fetchFeed, cache);
    const second = await loadEvents(
      [A],
      fakeFetch({ [A]: ok(ICS_B) }).fetchFeed,
      cache,
    );
    const stored = cache.read(A);
    const third = await loadEvents(
      [A],
      fakeFetch({ [A]: "network" }).fetchFeed,
      cache,
    );
    cache.close();
    expect(second).toEqual({ events: EVENTS_B, available: true });
    expect(stored).toEqual(EVENTS_B);
    expect(third).toEqual({ events: EVENTS_B, available: true });
  });

  it("reports no events available when every read fails and the cache is empty", async () => {
    const cache = openEventsCache(":memory:");
    const one = await loadEvents(
      [A],
      fakeFetch({ [A]: "network" }).fetchFeed,
      cache,
    );
    const two = await loadEvents(
      [A, B],
      fakeFetch({ [A]: "network", [B]: ok(ICS_B, 500) }).fetchFeed,
      cache,
    );
    const none = fakeFetch({});
    const zero = await loadEvents([], none.fetchFeed, cache);
    cache.close();
    expect(one).toEqual({ events: [], available: false });
    expect(two).toEqual({ events: [], available: false });
    expect(zero).toEqual({ events: [], available: false });
    expect(none.calls).toEqual([]);
  });

  it("treats a status outside 200 to 299 as a failed read", async () => {
    async function run(status: number) {
      const cache = openEventsCache(":memory:");
      cache.replace(A, CACHED);
      const result = await loadEvents(
        [A],
        fakeFetch({ [A]: ok(ICS_A, status) }).fetchFeed,
        cache,
      );
      const stored = cache.read(A);
      cache.close();
      return { result, stored };
    }
    const s300 = await run(300);
    const s404 = await run(404);
    const s500 = await run(500);
    const s299 = await run(299);
    const failed = {
      result: { events: CACHED, available: true },
      stored: CACHED,
    };
    expect(s300).toEqual(failed);
    expect(s404).toEqual(failed);
    expect(s500).toEqual(failed);
    expect(s299).toEqual({
      result: { events: EVENTS_A, available: true },
      stored: EVENTS_A,
    });
  });

  it("treats text with no calendar as a failed read", async () => {
    async function run(body: string) {
      const cache = openEventsCache(":memory:");
      cache.replace(A, CACHED);
      const result = await loadEvents(
        [A],
        fakeFetch({ [A]: ok(body) }).fetchFeed,
        cache,
      );
      const stored = cache.read(A);
      cache.close();
      return { result, stored };
    }
    const failed = {
      result: { events: CACHED, available: true },
      stored: CACHED,
    };
    expect(await run("")).toEqual(failed);
    expect(await run("hello world")).toEqual(failed);
    expect(await run("<html><body>Not found</body></html>")).toEqual(failed);
    expect(await run("<p>BEGIN:VCALENDAR</p>")).toEqual(failed);
  });

  it("treats a body that fails to read as a failed read", async () => {
    const cache = openEventsCache(":memory:");
    cache.replace(A, CACHED);
    const broken = new Response(
      new ReadableStream({
        start(c) {
          c.error(new Error("broken"));
        },
      }),
      { status: 200 },
    );
    const result = await loadEvents(
      [A],
      fakeFetch({ [A]: broken }).fetchFeed,
      cache,
    );
    const stored = cache.read(A);
    cache.close();
    expect(result).toEqual({ events: CACHED, available: true });
    expect(stored).toEqual(CACHED);
  });

  it("counts a calendar with no events as a successful read", async () => {
    async function run(body: string) {
      const cache = openEventsCache(":memory:");
      cache.replace(A, CACHED);
      const result = await loadEvents(
        [A],
        fakeFetch({ [A]: ok(body) }).fetchFeed,
        cache,
      );
      const stored = cache.read(A);
      cache.close();
      return { result, stored };
    }
    const empty = { result: { events: [], available: true }, stored: [] };
    expect(
      await run("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n"),
    ).toEqual(empty);
    expect(await run("begin:vcalendar\nend:vcalendar\n")).toEqual(empty);
    expect(await run("  BEGIN:VCALENDAR  \r\nEND:VCALENDAR\r\n")).toEqual(
      empty,
    );
  });

  it("merges a live feed's events with a failing feed's cached events", async () => {
    const answers = { [A]: ok(ICS_A), [B]: ok(ICS_B, 500) };
    const cache = openEventsCache(":memory:");
    cache.replace(B, CACHED);
    const forward = await loadEvents(
      [A, B],
      fakeFetch(answers).fetchFeed,
      cache,
    );
    const storedA = cache.read(A);
    const storedB = cache.read(B);
    cache.close();

    const other = openEventsCache(":memory:");
    other.replace(B, CACHED);
    const reversed = await loadEvents(
      [B, A],
      fakeFetch({ [A]: ok(ICS_A), [B]: ok(ICS_B, 500) }).fetchFeed,
      other,
    );
    other.close();

    expect(forward).toEqual({
      events: [...EVENTS_A, ...CACHED],
      available: true,
    });
    expect(storedA).toEqual(EVENTS_A);
    expect(storedB).toEqual(CACHED);
    expect(reversed).toEqual({
      events: [...CACHED, ...EVENTS_A],
      available: true,
    });
  });

  it("reports events available when only a failing feed's cache has them", async () => {
    const cache = openEventsCache(":memory:");
    cache.replace(B, CACHED);
    const result = await loadEvents(
      [A, B],
      fakeFetch({ [A]: "network", [B]: "network" }).fetchFeed,
      cache,
    );
    cache.close();
    expect(result).toEqual({ events: CACHED, available: true });
  });

  it("fetches each feed once by its URL alone", async () => {
    const cache = openEventsCache(":memory:");
    const fake = fakeFetch({ [A]: ok(ICS_A), [B]: ok(ICS_B) });
    const result = await loadEvents([A, B], fake.fetchFeed, cache);
    cache.close();
    expect(result).toEqual({
      events: [...EVENTS_A, ...EVENTS_B],
      available: true,
    });
    expect(fake.calls).toEqual([[A], [B]]);
  });
});

describe("fetchFeed", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("fetches the url once with a 10 second timeout signal and returns the response", async () => {
    const response = new Response("body", { status: 200 });
    const fake = vi.fn(() => Promise.resolve(response));
    vi.stubGlobal("fetch", fake);
    const timeoutSignal = AbortSignal.timeout(10_000);
    const timeout = vi
      .spyOn(AbortSignal, "timeout")
      .mockReturnValue(timeoutSignal);

    const result = await fetchFeed(A);

    expect(result).toBe(response);
    expect(timeout).toHaveBeenCalledExactlyOnceWith(10_000);
    expect(fake).toHaveBeenCalledExactlyOnceWith(A, { signal: timeoutSignal });
    timeout.mockRestore();
  });
});
