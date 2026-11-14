import type { EventCard } from "../../server/calendar/events";

export type Upcoming = { cards: EventCard[]; available: boolean };

export function UpcomingStrip(props: {
  upcoming: Upcoming;
  calendarUrl: string;
}): null {
  void props;
  return null;
}
