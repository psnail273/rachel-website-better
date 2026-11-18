"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { EventCard } from "../../server/calendar/events";
import { tieLabel, tieLast } from "../../lib/tie";
import {
  Cluster,
  Prose,
  Section,
  SectionHeading,
  Stack,
} from "./layout/components";

export type Upcoming = { cards: EventCard[]; available: boolean };

const LINK_PROPS = { target: "_blank", rel: "noopener noreferrer" } as const;
const REDUCED_MOTION = "(prefers-reduced-motion: reduce)";
const EDGE_SLACK = 1;

type Arrows = { previous: boolean; next: boolean } | null;

const ARROW_CLASS =
  "flex size-13 cursor-pointer items-center justify-center rounded-full border border-heading bg-heading text-bg disabled:cursor-default disabled:bg-transparent disabled:text-heading disabled:opacity-30";

const CARD_CLASS =
  "relative flex flex-[0_0_calc(100%_-_2_*_var(--space-flow))] snap-start flex-col items-start bg-surface p-heading min-h-48 sm:max-w-md sm:flex-[1_0_15.5rem]";
const LINKED_CARD_CLASS =
  "transition-colors duration-150 ease-[cubic-bezier(0.2,0.7,0.2,1)] hover:bg-tint";

function Chevron({ direction }: { direction: "left" | "right" }) {
  return (
    <svg
      width="20"
      height="20"
      viewBox="0 0 20 20"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path
        d={
          direction === "left"
            ? "M12.5 4.5 7 10l5.5 5.5"
            : "M7.5 4.5 13 10l-5.5 5.5"
        }
      />
    </svg>
  );
}

function Card({ card }: { card: EventCard }) {
  const { location } = card;
  return (
    <li
      data-event=""
      className={
        location?.kind === "link"
          ? `${CARD_CLASS} ${LINKED_CARD_CLASS}`
          : CARD_CLASS
      }
    >
      <p className="type-event-date text-heading">{tieLast(card.date)}</p>
      <h3 className="type-card-title mt-tight text-balance text-ink">
        {tieLabel(card.title)}
      </h3>
      {location?.kind === "text" ? (
        <p className="type-small mt-tight text-muted">
          {tieLast(location.text)}
        </p>
      ) : null}
      {location?.kind === "link" ? (
        <a
          href={location.href}
          {...LINK_PROPS}
          className="type-small mt-auto pt-flow after:absolute after:inset-0 after:content-['']"
        >
          Details
          <span className="sr-only">{` about ${card.title}`}</span>
        </a>
      ) : null}
    </li>
  );
}

function Cards({ cards }: { cards: EventCard[] }) {
  const row = useRef<HTMLUListElement>(null);
  const [arrows, setArrows] = useState<Arrows>(null);

  const measure = useCallback(() => {
    const el = row.current;
    if (el === null) return;
    const most = el.scrollWidth - el.clientWidth;
    const next: Arrows =
      most > EDGE_SLACK
        ? {
            previous: el.scrollLeft > EDGE_SLACK,
            next: el.scrollLeft < most - EDGE_SLACK,
          }
        : null;
    setArrows((current) =>
      current?.previous === next?.previous && current?.next === next?.next
        ? current
        : next,
    );
  }, []);

  useEffect(() => {
    measure();
    window.addEventListener("resize", measure);
    return () => {
      window.removeEventListener("resize", measure);
    };
  }, [measure]);

  function scroll(direction: 1 | -1): void {
    const el = row.current;
    if (el === null) return;
    const cards = [...el.querySelectorAll<HTMLLIElement>("li")];
    const step =
      (cards.at(1)?.offsetLeft ?? 0) - (cards.at(0)?.offsetLeft ?? 0);
    el.scrollBy({
      left: direction * step,
      behavior: window.matchMedia(REDUCED_MOTION).matches ? "auto" : "smooth",
    });
  }

  return (
    <Stack space="heading">
      <ul
        ref={row}
        data-events=""
        aria-label="Upcoming events"
        tabIndex={0}
        onScroll={measure}
        className="flex snap-x snap-mandatory gap-flow overflow-x-auto -outline-offset-2 [scrollbar-width:none]"
      >
        {cards.map((card, index) => (
          <Card key={index} card={card} />
        ))}
      </ul>
      {arrows === null ? null : (
        <Cluster align="center">
          <button
            type="button"
            aria-label="Previous events"
            disabled={!arrows.previous}
            onClick={() => {
              scroll(-1);
            }}
            className={ARROW_CLASS}
          >
            <Chevron direction="left" />
          </button>
          <button
            type="button"
            aria-label="Next events"
            disabled={!arrows.next}
            onClick={() => {
              scroll(1);
            }}
            className={ARROW_CLASS}
          >
            <Chevron direction="right" />
          </button>
        </Cluster>
      )}
    </Stack>
  );
}

function Body({
  upcoming,
  calendarUrl,
}: {
  upcoming: Upcoming;
  calendarUrl: string;
}) {
  const message = !upcoming.available
    ? "Events are unavailable right now."
    : upcoming.cards.length === 0
      ? "No upcoming events are scheduled right now."
      : null;
  if (message === null) return <Cards cards={upcoming.cards} />;
  return (
    <Prose align="center">
      <p>{message}</p>
      <p>
        <a href={calendarUrl} {...LINK_PROPS}>
          See the full calendar
        </a>
      </p>
    </Prose>
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
    <Section labelledBy="upcoming-heading">
      <SectionHeading level={2} id="upcoming-heading">
        Upcoming
      </SectionHeading>
      <Body upcoming={upcoming} calendarUrl={calendarUrl} />
    </Section>
  );
}
