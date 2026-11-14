import type { EventsCache } from "./cache";
import { parseIcs, type CalendarEvent } from "./events";

export type FetchFeed = (url: string) => Promise<Response>;

export type EventsResult = { events: CalendarEvent[]; available: boolean };

export function feedUrls(
  configured: readonly string[],
  env: Readonly<Record<string, string | undefined>>,
): string[] {
  const override = env.CALENDAR_FEED_URL;
  return override !== undefined && override !== ""
    ? [override]
    : [...configured];
}

async function readFeed(
  url: string,
  fetchFeed: FetchFeed,
): Promise<string | null> {
  try {
    const response = await fetchFeed(url);
    if (!response.ok) return null;
    const body = await response.text();
    const isCalendar = body
      .split(/\r\n|\r|\n/)
      .some((line) => line.trim().toUpperCase() === "BEGIN:VCALENDAR");
    return isCalendar ? body : null;
  } catch {
    return null;
  }
}

export async function loadEvents(
  feeds: readonly string[],
  fetchFeed: FetchFeed,
  cache: EventsCache,
): Promise<EventsResult> {
  const events: CalendarEvent[] = [];
  let available = false;
  for (const url of feeds) {
    const body = await readFeed(url, fetchFeed);
    if (body !== null) {
      const parsed = parseIcs(body);
      cache.replace(url, parsed);
      events.push(...parsed);
      available = true;
    } else {
      const cached = cache.read(url);
      events.push(...cached);
      if (cached.length > 0) available = true;
    }
  }
  return { events, available };
}
