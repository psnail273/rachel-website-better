import { cacheLife } from "next/cache";
import type { ReactNode } from "react";
import { siteConfig } from "../../lib/site-config";
import { eventsCachePath, openEventsCache } from "../../server/calendar/cache";
import { buildEventCards } from "../../server/calendar/events";
import { feedUrls, fetchFeed, loadEvents } from "../../server/calendar/source";
import { UpcomingStrip, type Upcoming } from "../_components/upcoming-strip";

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
      fetchFeed,
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
