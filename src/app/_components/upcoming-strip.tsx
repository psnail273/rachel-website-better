import type { EventCard } from "../../server/calendar/events";

export type Upcoming = { cards: EventCard[]; available: boolean };

const LINK_PROPS = { target: "_blank", rel: "noopener noreferrer" } as const;

function Body({
  upcoming,
  calendarUrl,
}: {
  upcoming: Upcoming;
  calendarUrl: string;
}) {
  if (!upcoming.available) {
    return (
      <>
        <p>Events are unavailable right now.</p>
        <p>
          <a href={calendarUrl} {...LINK_PROPS}>
            See the full calendar
          </a>
        </p>
      </>
    );
  }
  if (upcoming.cards.length === 0) {
    return <p>No upcoming events are scheduled right now.</p>;
  }
  return (
    <div
      role="region"
      aria-label="Upcoming events"
      tabIndex={0}
      className="overflow-x-auto rounded-2xl"
    >
      <ul className="flex snap-x gap-4 pb-3">
        {upcoming.cards.map((card, index) => (
          <li
            key={index}
            className="w-60 shrink-0 snap-start rounded-2xl bg-surface p-4"
          >
            <p className="text-sm font-semibold text-heading">{card.date}</p>
            <h3 className="mt-1 text-lg">{card.title}</h3>
            {card.location?.kind === "text" ? (
              <p className="mt-1 text-sm">{card.location.text}</p>
            ) : null}
            {card.location?.kind === "link" ? (
              <a
                href={card.location.href}
                {...LINK_PROPS}
                className="mt-1 inline-block text-sm"
              >
                Details
              </a>
            ) : null}
          </li>
        ))}
      </ul>
    </div>
  );
}

export function UpcomingStrip({
  upcoming,
  calendarUrl,
}: {
  upcoming: Upcoming;
  calendarUrl: string;
}) {
  return (
    <section
      aria-labelledby="upcoming-heading"
      className="w-full max-w-5xl self-center"
    >
      <h2 id="upcoming-heading" className="mb-4 text-2xl">
        Upcoming
      </h2>
      <Body upcoming={upcoming} calendarUrl={calendarUrl} />
    </section>
  );
}
