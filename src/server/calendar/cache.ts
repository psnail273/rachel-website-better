import type { CalendarEvent } from "./events";

export type EventsCache = {
  read(feed: string): CalendarEvent[];
  replace(feed: string, events: readonly CalendarEvent[]): void;
  close(): void;
};

export function openEventsCache(path: string): EventsCache {
  void path;
  return {
    read: () => [],
    replace: () => undefined,
    close: () => undefined,
  };
}

export function eventsCachePath(
  env: Readonly<Record<string, string | undefined>>,
): string {
  void env;
  return "";
}
