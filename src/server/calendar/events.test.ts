import { describe, expect, it } from "vitest";

import { buildEventCards, parseIcs, type CalendarEvent } from "./events";

function cal(...vevents: string[][]): string {
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Test//EN",
    "X-WR-TIMEZONE:America/Chicago",
    ...vevents.flatMap((v) => ["BEGIN:VEVENT", ...v, "END:VEVENT"]),
    "END:VCALENDAR",
  ];
  return lines.join("\r\n") + "\r\n";
}

function timed(
  title: string,
  start: string,
  end: string,
  location: string | null = null,
): CalendarEvent {
  return { title, start, end, allDay: false, location };
}

function allDay(
  title: string,
  start: string,
  end: string,
  location: string | null = null,
): CalendarEvent {
  return { title, start, end, allDay: true, location };
}

describe("parseIcs", () => {
  it("reads a VEVENT's title, start, end and location", () => {
    const text = cal([
      "UID:abc123@google.com",
      "DTSTART:20261122T190000Z",
      "DTEND:20261122T200000Z",
      "LOCATION:https://american-kantorei.org/",
      "SUMMARY:American Kantorei Performance",
    ]);
    expect(parseIcs(text)).toEqual([
      {
        title: "American Kantorei Performance",
        start: "2026-11-22T19:00:00.000Z",
        end: "2026-11-22T20:00:00.000Z",
        allDay: false,
        location: "https://american-kantorei.org/",
      },
    ]);
  });

  it("unfolds folded lines and unescapes commas, semicolons and newlines", () => {
    const text = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "BEGIN:VEVENT",
      "DTSTART:20261004T190000Z",
      "DTEND:20261004T200000Z",
      "SUMMARY:Early Music\\, Missouri\\; Fall Concert",
      "LOCATION:St Peter's Episcopal Church\\, 110 N Warson Rd\\; St. Lo",
      " uis\\nMO 631",
      "\t24",
      "END:VEVENT",
      "END:VCALENDAR",
      "",
    ].join("\n");
    expect(parseIcs(text)).toEqual([
      {
        title: "Early Music, Missouri; Fall Concert",
        start: "2026-10-04T19:00:00.000Z",
        end: "2026-10-04T20:00:00.000Z",
        allDay: false,
        location:
          "St Peter's Episcopal Church, 110 N Warson Rd; St. Louis\nMO 63124",
      },
    ]);
  });

  it("reads a date-only DTSTART as an all-day event", () => {
    const text = cal([
      "DTSTART;VALUE=DATE:20261122",
      "DTEND;VALUE=DATE:20261123",
      "SUMMARY:Open Rehearsal",
    ]);
    expect(parseIcs(text)).toEqual([
      {
        title: "Open Rehearsal",
        start: "2026-11-22",
        end: "2026-11-23",
        allDay: true,
        location: null,
      },
    ]);
  });

  it("reads a TZID start as local time in that zone", () => {
    const text = cal(
      [
        "DTSTART;TZID=America/Chicago:20261016T180000",
        "DTEND;TZID=America/Chicago:20261016T200000",
        "SUMMARY:Summer",
      ],
      [
        "DTSTART;TZID=America/Chicago:20261122T130000",
        "DTEND;TZID=America/Chicago:20261122T140000",
        "SUMMARY:Winter",
      ],
    );
    expect(parseIcs(text)).toEqual([
      {
        title: "Summer",
        start: "2026-10-16T23:00:00.000Z",
        end: "2026-10-17T01:00:00.000Z",
        allDay: false,
        location: null,
      },
      {
        title: "Winter",
        start: "2026-11-22T19:00:00.000Z",
        end: "2026-11-22T20:00:00.000Z",
        allDay: false,
        location: null,
      },
    ]);
  });

  it("fills a missing DTEND", () => {
    const text = cal(
      ["DTSTART:20261004T190000Z", "SUMMARY:Timed"],
      ["DTSTART;VALUE=DATE:20261005", "SUMMARY:Day"],
    );
    expect(parseIcs(text)).toEqual([
      {
        title: "Timed",
        start: "2026-10-04T19:00:00.000Z",
        end: "2026-10-04T19:00:00.000Z",
        allDay: false,
        location: null,
      },
      {
        title: "Day",
        start: "2026-10-05",
        end: "2026-10-06",
        allDay: true,
        location: null,
      },
    ]);
  });

  it("does not expand RRULE", () => {
    const text = cal([
      "DTSTART:20261004T190000Z",
      "DTEND:20261004T200000Z",
      "RRULE:FREQ=WEEKLY;COUNT=4",
      "SUMMARY:Weekly Lesson",
    ]);
    expect(parseIcs(text)).toEqual([
      {
        title: "Weekly Lesson",
        start: "2026-10-04T19:00:00.000Z",
        end: "2026-10-04T20:00:00.000Z",
        allDay: false,
        location: null,
      },
    ]);
  });

  it("returns no events for empty or malformed text", () => {
    const noStart = cal(["SUMMARY:No start"]);
    const badStart = cal(["DTSTART:2026-13-45", "SUMMARY:Bad start"]);
    const noSummary = cal(["DTSTART:20261004T190000Z"]);
    const cutOff =
      "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART:20261004T190000Z\r\nSUMMARY:Cut off";
    const control = cal(["DTSTART:20261004T190000Z", "SUMMARY:Control"]);
    expect(parseIcs("")).toEqual([]);
    expect(parseIcs("hello world")).toEqual([]);
    expect(parseIcs("<html><body>Not found</body></html>")).toEqual([]);
    expect(parseIcs(noStart)).toEqual([]);
    expect(parseIcs(badStart)).toEqual([]);
    expect(parseIcs(noSummary)).toEqual([]);
    expect(parseIcs(cutOff)).toEqual([]);
    // A well-formed event still parses, so the empty results above are not a stub's.
    expect(parseIcs(control)).toHaveLength(1);
  });
});

describe("buildEventCards", () => {
  it("makes one card with the title, Chicago date and location of a future event", () => {
    const events = [
      timed(
        "Harry Potter with the Nashville Symphony",
        "2026-11-08T00:30:00.000Z",
        "2026-11-08T03:00:00.000Z",
        "Schermerhorn Symphony Center, Nashville",
      ),
    ];
    expect(
      buildEventCards(events, new Date("2026-11-01T12:00:00.000Z")),
    ).toEqual([
      {
        date: "7 November",
        title: "Harry Potter with the Nashville Symphony",
        location: {
          kind: "text",
          text: "Schermerhorn Symphony Center, Nashville",
        },
      },
    ]);
  });

  it("leaves out events that ended before now", () => {
    const events = [
      timed("Past", "2026-10-04T19:00:00.000Z", "2026-10-04T20:00:00.000Z"),
      timed("Ends now", "2026-10-10T11:00:00.000Z", "2026-10-10T12:00:00.000Z"),
      timed("Still on", "2026-10-10T11:00:00.000Z", "2026-10-10T12:01:00.000Z"),
    ];
    expect(
      buildEventCards(events, new Date("2026-10-10T12:00:00.000Z")),
    ).toEqual([{ date: "10 October", title: "Still on", location: null }]);
  });

  it("sorts cards soonest first", () => {
    const events = [
      timed("C", "2026-11-22T19:00:00.000Z", "2026-11-22T20:00:00.000Z"),
      timed("A", "2026-10-04T19:00:00.000Z", "2026-10-04T20:00:00.000Z"),
      allDay("B", "2026-10-25", "2026-10-26"),
    ];
    expect(
      buildEventCards(events, new Date("2026-10-01T12:00:00.000Z")),
    ).toEqual([
      { date: "4 October", title: "A", location: null },
      { date: "25 October", title: "B", location: null },
      { date: "22 November", title: "C", location: null },
    ]);
  });

  it("merges same-titled events on consecutive days into one ranged card", () => {
    const url =
      "https://philorch.ensembleartsphilly.org/tickets-and-events/2026-27";
    const events = [
      timed(
        "Harry Potter with the Philadelphia Orchestra",
        "2026-10-17T23:00:00.000Z",
        "2026-10-18T01:00:00.000Z",
        url,
      ),
      timed(
        "Collegium Vocale of St. Louis Concert",
        "2026-10-25T19:00:00.000Z",
        "2026-10-25T20:30:00.000Z",
      ),
      timed(
        "Harry Potter with the Philadelphia orchestra",
        "2026-10-16T23:00:00.000Z",
        "2026-10-17T01:00:00.000Z",
        url,
      ),
      timed(
        "Harry Potter with the Philadelphia Orchestra",
        "2026-10-18T18:00:00.000Z",
        "2026-10-18T21:10:00.000Z",
        url,
      ),
    ];
    expect(
      buildEventCards(events, new Date("2026-10-01T12:00:00.000Z")),
    ).toEqual([
      {
        date: "16–18 October",
        title: "Harry Potter with the Philadelphia orchestra",
        location: { kind: "link", href: url },
      },
      {
        date: "25 October",
        title: "Collegium Vocale of St. Louis Concert",
        location: null,
      },
    ]);
  });

  it("keeps same-titled events apart when a day falls between them", () => {
    const events = [
      timed("Concert", "2026-10-16T23:00:00.000Z", "2026-10-17T01:00:00.000Z"),
      timed("Concert", "2026-10-18T23:00:00.000Z", "2026-10-19T01:00:00.000Z"),
      timed("Recital", "2026-10-19T23:00:00.000Z", "2026-10-20T01:00:00.000Z"),
    ];
    expect(
      buildEventCards(events, new Date("2026-10-01T12:00:00.000Z")),
    ).toEqual([
      { date: "16 October", title: "Concert", location: null },
      { date: "18 October", title: "Concert", location: null },
      { date: "19 October", title: "Recital", location: null },
    ]);
  });

  it("merges same-titled events on the same day", () => {
    const events = [
      timed("Concert", "2026-10-16T19:00:00.000Z", "2026-10-16T21:00:00.000Z"),
      timed("CONCERT", "2026-10-17T00:00:00.000Z", "2026-10-17T02:00:00.000Z"),
    ];
    expect(
      buildEventCards(events, new Date("2026-10-01T12:00:00.000Z")),
    ).toEqual([{ date: "16 October", title: "Concert", location: null }]);
  });

  it("shows both months for a run that crosses months", () => {
    const events = [
      timed(
        "Halloween Pops",
        "2026-11-01T00:00:00.000Z",
        "2026-11-01T02:00:00.000Z",
      ),
      timed(
        "Halloween Pops",
        "2026-11-02T01:00:00.000Z",
        "2026-11-02T03:00:00.000Z",
      ),
    ];
    expect(
      buildEventCards(events, new Date("2026-10-01T12:00:00.000Z")),
    ).toEqual([
      {
        date: "31 October – 1 November",
        title: "Halloween Pops",
        location: null,
      },
    ]);
  });

  it("links a URL location and keeps any other location as text", () => {
    const events = [
      timed(
        "One",
        "2026-10-04T19:00:00.000Z",
        "2026-10-04T20:00:00.000Z",
        "https://conspirito.kirkwoodpres.org/",
      ),
      timed(
        "Two",
        "2026-10-05T19:00:00.000Z",
        "2026-10-05T20:00:00.000Z",
        "St Peter's Episcopal Church, St. Louis",
      ),
      timed(
        "Three",
        "2026-10-06T19:00:00.000Z",
        "2026-10-06T20:00:00.000Z",
        "www.example.org",
      ),
      timed(
        "Four",
        "2026-10-07T19:00:00.000Z",
        "2026-10-07T20:00:00.000Z",
        null,
      ),
    ];
    expect(
      buildEventCards(events, new Date("2026-10-01T12:00:00.000Z")),
    ).toEqual([
      {
        date: "4 October",
        title: "One",
        location: {
          kind: "link",
          href: "https://conspirito.kirkwoodpres.org/",
        },
      },
      {
        date: "5 October",
        title: "Two",
        location: {
          kind: "text",
          text: "St Peter's Episcopal Church, St. Louis",
        },
      },
      {
        date: "6 October",
        title: "Three",
        location: { kind: "text", text: "www.example.org" },
      },
      { date: "7 October", title: "Four", location: null },
    ]);
  });

  it("dates an all-day event by its own day", () => {
    const events = [allDay("Open Rehearsal", "2026-11-22", "2026-11-23")];
    const card = {
      date: "22 November",
      title: "Open Rehearsal",
      location: null,
    };
    expect(
      buildEventCards(events, new Date("2026-11-22T12:00:00.000Z")),
    ).toEqual([card]);
    expect(
      buildEventCards(events, new Date("2026-11-23T05:59:00.000Z")),
    ).toEqual([card]);
    expect(
      buildEventCards(events, new Date("2026-11-23T06:00:00.000Z")),
    ).toEqual([]);
  });

  it("spans a multi-day all-day event across its days", () => {
    const events = [allDay("Festival", "2026-10-16", "2026-10-19")];
    expect(
      buildEventCards(events, new Date("2026-10-01T12:00:00.000Z")),
    ).toEqual([{ date: "16–18 October", title: "Festival", location: null }]);
  });

  it("merges events from two feeds into one sorted list", () => {
    const feedA = cal(
      [
        "DTSTART:20261122T190000Z",
        "DTEND:20261122T200000Z",
        "SUMMARY:American Kantorei Performance",
      ],
      [
        "DTSTART:20261004T190000Z",
        "DTEND:20261004T200000Z",
        "SUMMARY:Early Music Missouri Concert",
      ],
    );
    const feedB = cal([
      "DTSTART:20261025T190000Z",
      "DTEND:20261025T203000Z",
      "SUMMARY:Collegium Vocale of St. Louis Concert",
    ]);
    const cards = buildEventCards(
      [...parseIcs(feedA), ...parseIcs(feedB)],
      new Date("2026-10-01T12:00:00.000Z"),
    );
    expect(cards).toEqual([
      {
        date: "4 October",
        title: "Early Music Missouri Concert",
        location: null,
      },
      {
        date: "25 October",
        title: "Collegium Vocale of St. Louis Concert",
        location: null,
      },
      {
        date: "22 November",
        title: "American Kantorei Performance",
        location: null,
      },
    ]);
  });

  it("yields no cards for malformed or empty text", () => {
    const now = new Date("2026-10-01T12:00:00.000Z");
    const control = cal(["DTSTART:20261004T190000Z", "SUMMARY:Control"]);
    expect(buildEventCards(parseIcs(""), now)).toEqual([]);
    expect(buildEventCards(parseIcs("hello world"), now)).toEqual([]);
    expect(buildEventCards([], now)).toEqual([]);
    // A well-formed future event still yields a card, so the empty results above are not a stub's.
    expect(buildEventCards(parseIcs(control), now)).toHaveLength(1);
  });
});
