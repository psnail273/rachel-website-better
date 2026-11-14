import { cacheLife } from "next/cache";
import type { ReactNode } from "react";
import { siteConfig } from "../../lib/site-config";
import { eventsCachePath, openEventsCache } from "../../server/calendar/cache";
import { buildEventCards } from "../../server/calendar/events";
import { feedUrls, loadEvents } from "../../server/calendar/source";
import { UpcomingStrip, type Upcoming } from "../_components/upcoming-strip";

const FEED_TIMEOUT_MS = 10_000;

async function loadUpcoming(): Promise<Upcoming> {
  "use cache";
  cacheLife("hours");
  const cache = openEventsCache(eventsCachePath(process.env));
  try {
    const { events, available } = await loadEvents(
      feedUrls(
        siteConfig.calendarFeeds.map((feed) => feed.icsUrl),
        process.env,
      ),
      (url) => fetch(url, { signal: AbortSignal.timeout(FEED_TIMEOUT_MS) }),
      cache,
    );
    return { cards: buildEventCards(events, new Date()), available };
  } finally {
    cache.close();
  }
}

export default async function UpcomingLayout({
  children,
}: Readonly<{ children: ReactNode }>) {
  return (
    <>
      {children}
      <UpcomingStrip
        upcoming={await loadUpcoming()}
        calendarUrl={siteConfig.publicCalendarUrl}
      />
    </>
  );
}
