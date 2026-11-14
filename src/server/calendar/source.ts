import type { EventsCache } from "./cache";
import type { CalendarEvent } from "./events";

export type FetchFeed = (url: string) => Promise<Response>;

export type EventsResult = { events: CalendarEvent[]; available: boolean };

export function feedUrls(
  configured: readonly string[],
  env: Readonly<Record<string, string | undefined>>,
): string[] {
  void configured;
  void env;
  return [];
}

export async function loadEvents(
  feeds: readonly string[],
  fetchFeed: FetchFeed,
  cache: EventsCache,
): Promise<EventsResult> {
  void feeds;
  void fetchFeed;
  void cache;
  return await Promise.resolve({ events: [], available: feeds.length === 0 });
}
