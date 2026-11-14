// @vitest-environment happy-dom
import { mkdtempSync, rmSync } from "node:fs";
import { text } from "node:stream/consumers";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { prerender } from "react-dom/static";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import UpcomingLayout from "./layout";

vi.mock("next/cache", () => ({ cacheLife: vi.fn() }));

const CONFIGURED_FEED_URL =
  "https://calendar.google.com/calendar/ical/f93593a9aa8efdef9b296cd13ae5518c085ad3e1b69bb609278e09df2dc88ee4%40group.calendar.google.com/public/basic.ics";

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

type FeedFetch = (url: string, init?: RequestInit) => Promise<Response>;

let folder = "";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-11-14T12:00:00Z"));
  folder = mkdtempSync(join(tmpdir(), "upcoming-feeds-"));
  vi.stubEnv("EVENTS_CACHE_PATH", join(folder, "events.sqlite"));
  vi.stubEnv("CALENDAR_FEED_URL", "");
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
  vi.useRealTimers();
  vi.restoreAllMocks();
  rmSync(folder, { recursive: true, force: true });
});

describe("UpcomingLayout", () => {
  it("reads the feeds from the site config when no override is set", async () => {
    const fetchFake = vi.fn<FeedFetch>(() =>
      Promise.resolve(new Response(FIXTURE)),
    );
    vi.stubGlobal("fetch", fetchFake);
    await prerender(await UpcomingLayout({ children: <p>Page body</p> })).then(
      ({ prelude }) => text(prelude),
    );
    expect(fetchFake).toHaveBeenCalledTimes(1);
    expect(fetchFake.mock.calls[0]?.[0]).toBe(CONFIGURED_FEED_URL);
  });
});
