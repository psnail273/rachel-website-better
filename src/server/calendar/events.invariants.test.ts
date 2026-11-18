import fc from "fast-check";
import { describe, expect, it } from "vitest";
import { buildEventCards, type CalendarEvent } from "./events";

const NOW = new Date("2026-01-01T00:00:00.000Z");
const FIRST_MS = Date.parse("2026-01-02T00:00:00.000Z");
const LAST_MS = Date.parse("2029-12-31T00:00:00.000Z");
const DAY_MS = 86_400_000;

const MONTH =
  "(?:January|February|March|April|May|June|July|August|September|October|November|December)";
const DAY = "[1-9]\\d?";
const SINGLE = `${DAY} ${MONTH}`;
const SAME_MONTH_RANGE = `${DAY}–${DAY} ${MONTH}`;
const TWO_DATES = `${SINGLE} – ${SINGLE}`;
const DATE_SHAPE = new RegExp(
  `^(?:${SINGLE}|${SAME_MONTH_RANGE}|${TWO_DATES})$`,
);

// A few titles, so that the events of one run merge into ranged cards.
const title = fc.constantFrom("Recital", "Concert", "Masterclass");

const timed = fc
  .record({
    title,
    startMs: fc.integer({ min: FIRST_MS, max: LAST_MS }),
    lengthMs: fc.integer({ min: 0, max: 3 * DAY_MS }),
  })
  .map(({ title: name, startMs, lengthMs }): CalendarEvent => ({
    title: name,
    start: new Date(startMs).toISOString(),
    end: new Date(startMs + lengthMs).toISOString(),
    allDay: false,
    location: null,
  }));

const allDay = fc
  .record({
    title,
    startMs: fc.integer({ min: FIRST_MS, max: LAST_MS }),
    days: fc.integer({ min: 1, max: 4 }),
  })
  .map(({ title: name, startMs, days }): CalendarEvent => ({
    title: name,
    start: new Date(startMs).toISOString().slice(0, 10),
    end: new Date(startMs + days * DAY_MS).toISOString().slice(0, 10),
    allDay: true,
    location: null,
  }));

describe("buildEventCards invariants", () => {
  it("gives every card a date that is a day and a full month name, a range of days in one month, or two such dates joined by a spaced en dash", () => {
    fc.assert(
      fc.property(
        fc.array(fc.oneof(timed, allDay), { maxLength: 12 }),
        (events) => {
          const dates = buildEventCards(events, NOW).map((card) => card.date);
          const misshapen = dates.filter((date) => !DATE_SHAPE.test(date));
          expect(misshapen).toEqual([]);
        },
      ),
      { numRuns: 200 },
    );
  });
});
