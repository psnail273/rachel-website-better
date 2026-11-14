export type CalendarEvent = {
  title: string;
  start: string;
  end: string;
  allDay: boolean;
  location: string | null;
};

export type CardLocation =
  { kind: "link"; href: string } | { kind: "text"; text: string };

export type EventCard = {
  date: string;
  title: string;
  location: CardLocation | null;
};

export function parseIcs(text: string): CalendarEvent[] {
  void text;
  return [];
}

export function buildEventCards(
  events: readonly CalendarEvent[],
  now: Date,
): EventCard[] {
  void events;
  void now;
  return [];
}
