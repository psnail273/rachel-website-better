// Shared by the Scenarios of "Rachel's new site". Declares no test.
import {
  expect,
  type APIRequestContext,
  type Locator,
  type Page,
} from "@playwright/test";

// tabTo: press Tab, as a keyboard visitor does, until the target has focus.
export async function tabTo(page: Page, target: Locator, most = 40) {
  for (let i = 0; i < most; i++) {
    await page.keyboard.press("Tab");
    if (await target.evaluate((el) => el === document.activeElement)) return;
  }
  await expect(target, `Tab reaches it within ${most} presses`).toBeFocused();
}

// The calendar feed the app reads: the product's own override,
// CALENDAR_FEED_URL (src/server/calendar/source.ts), which
// tools/verify/scenario-env points at the Scenario driver's fixture server for
// the app and for this Playwright run alike. The driver starts each Scenario
// file with nothing served there (the feed unreachable: 404) and an empty events
// cache (EVENTS_CACHE_PATH, in the run's state folder).
export function feedUrl(): string {
  const value = process.env.CALENDAR_FEED_URL ?? "";
  expect(
    value,
    "CALENDAR_FEED_URL names the fixture server (tools/verify/scenario-env; run bash factory/core/scenarios.sh)",
  ).toMatch(/^http:\/\/127\.0\.0\.1:\d+\//);
  return value;
}

// serveFeed: the feed answers the given iCalendar body from now on.
export async function serveFeed(request: APIRequestContext, ics: string) {
  const response = await request.put(feedUrl(), {
    data: ics,
    headers: { "content-type": "text/calendar; charset=utf-8" },
  });
  expect(response.status(), "the fixture server takes the feed").toBe(204);
}

// stopFeed: the feed is unreachable (404) from now on.
export async function stopFeed(request: APIRequestContext) {
  const response = await request.delete(feedUrl());
  expect(response.status(), "the fixture server drops the feed").toBe(204);
}

// revalidate: the app renders every page afresh on its next visit, reading the
// feed and the cache again, through its on-demand revalidation route (enabled by
// ON_DEMAND_REVALIDATION in tools/verify/scenario-env).
export async function revalidate(request: APIRequestContext) {
  const response = await request.post("/api/revalidate");
  expect(response.status(), "POST /api/revalidate revalidates").toBe(200);
}

// The fixture: past, future and same-titled consecutive-day events, written out
// of order. All-day events, so their days are America/Chicago's as they stand.
// The future ones fall next year, the past one last year, so "now" sorts them
// the same whenever the Scenario runs.
export type Fixture = {
  ics: string;
  past: string;
  future: string[]; // soonest first
  run: { title: string; range: string };
};

export function fixture(now = new Date()): Fixture {
  const year = Number(
    new Intl.DateTimeFormat("en-US", {
      timeZone: "America/Chicago",
      year: "numeric",
    }).format(now),
  );
  const next = year + 1;
  const last = year - 1;
  const day = (y: number, m: number, d: number) =>
    `${y}${String(m).padStart(2, "0")}${String(d).padStart(2, "0")}`;
  const event = (
    uid: string,
    title: string,
    start: string,
    end: string,
    location?: string,
  ) =>
    [
      "BEGIN:VEVENT",
      `UID:${uid}@scenario.fixture`,
      `DTSTAMP:${start}T000000Z`,
      `DTSTART;VALUE=DATE:${start}`,
      `DTEND;VALUE=DATE:${end}`,
      `SUMMARY:${title}`,
      ...(location ? [`LOCATION:${location}`] : []),
      "END:VEVENT",
    ].join("\r\n");

  const past = "Spring Recorder Recital";
  const soonest = "Harry Potter in Concert";
  const run = "Early Music Missouri Festival";
  const latest = "Brahms Quintet with Friends";
  const ics = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Scenarios//Rachel's new site//EN",
    event(
      "brahms",
      latest,
      day(next, 12, 3),
      day(next, 12, 4),
      "Sheldon Concert Hall\\, St. Louis",
    ),
    event(
      "festival-2",
      run.toLowerCase(),
      day(next, 10, 17),
      day(next, 10, 18),
    ),
    event(
      "recital",
      past,
      day(last, 3, 1),
      day(last, 3, 2),
      "Christ Church Cathedral",
    ),
    event(
      "festival-1",
      run,
      day(next, 10, 16),
      day(next, 10, 17),
      "https://example.org/festival",
    ),
    event("potter", soonest, day(next, 9, 5), day(next, 9, 6)),
    event("festival-3", run, day(next, 10, 18), day(next, 10, 19)),
    "END:VCALENDAR",
    "",
  ].join("\r\n");
  return {
    ics,
    past,
    future: [soonest, run, latest],
    run: { title: run, range: "Oct 16–18" },
  };
}

// The Upcoming strip's cards, as the page shows them.
export function upcomingCards(page: Page): Locator {
  return page
    .getByRole("region", { name: "Upcoming events" })
    .getByRole("listitem");
}

// expectFixtureShown: the strip shows the fixture's future events only, soonest
// first, with the consecutive-day run as one card showing its date range.
export async function expectFixtureShown(page: Page, f: Fixture) {
  await expect(
    page.getByRole("heading", { level: 2, name: "Upcoming" }),
  ).toBeVisible();
  const cards = upcomingCards(page);
  await expect(cards.getByRole("heading", { level: 3 })).toHaveText(f.future);
  await expect(cards.filter({ hasText: f.past })).toHaveCount(0);
  await expect(cards.filter({ hasText: f.run.title })).toContainText(
    f.run.range,
  );
}
