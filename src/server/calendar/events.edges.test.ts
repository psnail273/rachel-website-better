import { describe, expect, it } from "vitest";

import { buildEventCards, parseIcs, type CalendarEvent } from "./events";

function cal(...vevents: string[][]): string {
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
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

function allDay(title: string, start: string, end: string): CalendarEvent {
  return { title, start, end, allDay: true, location: null };
}

const NOW = new Date("2026-10-01T12:00:00.000Z");

describe("parseIcs edges", () => {
  it("reads a TZID in another zone, with minutes and seconds", () => {
    const text = cal([
      "DTSTART;TZID=America/New_York:20261016T183015",
      "DTEND;TZID=America/New_York:20261016T194500",
      "SUMMARY:East",
    ]);
    expect(parseIcs(text)).toEqual([
      timed("East", "2026-10-16T22:30:15.000Z", "2026-10-16T23:45:00.000Z"),
    ]);
  });

  it("leaves out a date-only DTSTART that is not a real date", () => {
    expect(
      parseIcs(cal(["DTSTART;VALUE=DATE:20260230", "SUMMARY:Bad"])),
    ).toEqual([]);
    expect(
      parseIcs(cal(["DTSTART;VALUE=DATE:20261301", "SUMMARY:Bad"])),
    ).toEqual([]);
    expect(
      parseIcs(cal(["DTSTART;VALUE=DATE:20261000", "SUMMARY:Bad"])),
    ).toEqual([]);
    expect(
      parseIcs(cal(["DTSTART;VALUE=DATE:20260228", "SUMMARY:Good"])),
    ).toEqual([
      {
        title: "Good",
        start: "2026-02-28",
        end: "2026-03-01",
        allDay: true,
        location: null,
      },
    ]);
  });

  it("matches parameter names ignoring case", () => {
    const text = cal([
      "DTSTART;tzid=America/New_York:20261122T130000",
      "DTEND;tzid=America/New_York:20261122T140000",
      "SUMMARY:Lower",
    ]);
    expect(parseIcs(text)).toEqual([
      timed("Lower", "2026-11-22T18:00:00.000Z", "2026-11-22T19:00:00.000Z"),
    ]);
  });

  it("reads an unknown TZID and a floating time as Chicago time", () => {
    const text = cal(
      [
        "DTSTART;TZID=Mars/Olympus:20261122T130000",
        "DTEND;TZID=Mars/Olympus:20261122T140000",
        "SUMMARY:Unknown",
      ],
      ["DTSTART:20261122T130000", "DTEND:20261122T140000", "SUMMARY:Floating"],
    );
    expect(parseIcs(text)).toEqual([
      timed("Unknown", "2026-11-22T19:00:00.000Z", "2026-11-22T20:00:00.000Z"),
      timed("Floating", "2026-11-22T19:00:00.000Z", "2026-11-22T20:00:00.000Z"),
    ]);
  });

  it("unescapes a capital N as a newline", () => {
    const text = cal([
      "SUMMARY:Line one\\NLine two",
      "DTSTART:20261004T190000Z",
      "DTEND:20261004T200000Z",
    ]);
    expect(parseIcs(text)).toEqual([
      timed(
        "Line one\nLine two",
        "2026-10-04T19:00:00.000Z",
        "2026-10-04T20:00:00.000Z",
      ),
    ]);
  });

  it("leaves out a DTSTART that is not a real date or time", () => {
    const bad = [
      "DTSTART:20261345T180000Z",
      "DTSTART:20260004T190000Z",
      "DTSTART:20261000T190000Z",
      "DTSTART:20260230T190000Z",
      "DTSTART:20261004T250000Z",
      "DTSTART:20261004T186000Z",
      "DTSTART:20261004T180060Z",
      "DTSTART:x20261004T190000Z",
      "DTSTART:20261004T190000Zx",
      "DTSTART;VALUE=DATE:20261004x",
    ];
    const results = bad.map((line) => parseIcs(cal([line, "SUMMARY:Bad"])));
    expect(results).toEqual(bad.map(() => []));
    expect(parseIcs(cal(["DTSTART:20261004T235959Z", "SUMMARY:Bad"]))).toEqual([
      expect.objectContaining({ start: "2026-10-04T23:59:59.000Z" }),
    ]);
  });

  it("reads only VEVENTs inside a VCALENDAR", () => {
    const loose = [
      "BEGIN:VEVENT",
      "DTSTART:20261004T190000Z",
      "SUMMARY:Loose",
      "END:VEVENT",
    ].join("\r\n");
    expect(parseIcs(loose + "\r\n")).toEqual([]);

    const after = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "BEGIN:VEVENT",
      "SUMMARY:Inside",
      "DTSTART:20261004T190000Z",
      "DTEND:20261004T200000Z",
      "END:VEVENT",
      "END:VCALENDAR",
      "BEGIN:VEVENT",
      "SUMMARY:After",
      "DTSTART:20261005T190000Z",
      "DTEND:20261005T200000Z",
      "END:VEVENT",
    ].join("\r\n");
    expect(parseIcs(after + "\r\n")).toEqual([
      timed("Inside", "2026-10-04T19:00:00.000Z", "2026-10-04T20:00:00.000Z"),
    ]);
  });

  it("reads a multi-day all-day DTEND", () => {
    const text = cal([
      "DTSTART;VALUE=DATE:20261016",
      "DTEND;VALUE=DATE:20261019",
      "SUMMARY:Festival",
    ]);
    expect(parseIcs(text)).toEqual([
      allDay("Festival", "2026-10-16", "2026-10-19"),
    ]);
  });
});

describe("parseIcs structure edges", () => {
  it("reads January and December dates and rejects month 13", () => {
    const jan = cal(["DTSTART;VALUE=DATE:20270101", "SUMMARY:Jan"]);
    const dec = cal(["DTSTART;VALUE=DATE:20261231", "SUMMARY:Dec"]);
    const bad = cal(["DTSTART:20261305T190000Z", "SUMMARY:Bad"]);
    const prefixed = cal(["DTSTART;VALUE=DATE:x20261004", "SUMMARY:Bad"]);
    expect(parseIcs(jan).map((e) => e.start)).toEqual(["2027-01-01"]);
    expect(parseIcs(dec).map((e) => e.start)).toEqual(["2026-12-31"]);
    expect(parseIcs(bad)).toEqual([]);
    expect(parseIcs(prefixed)).toEqual([]);
  });

  it("skips nested components and keeps reading after them", () => {
    const text = [
      "BEGIN:VCALENDAR",
      "BEGIN:VEVENT",
      "BEGIN:VALARM",
      "SUMMARY:Alarm",
      "END:VALARM",
      "SUMMARY:Real",
      "DTSTART:20261004T190000Z",
      "DTEND:20261004T200000Z",
      "END:VEVENT",
      "END:VCALENDAR",
    ].join("\r\n");
    expect(parseIcs(text + "\r\n")).toEqual([
      timed("Real", "2026-10-04T19:00:00.000Z", "2026-10-04T20:00:00.000Z"),
    ]);
  });

  it("restarts at a VEVENT begun inside a VEVENT", () => {
    const text = [
      "BEGIN:VCALENDAR",
      "BEGIN:VEVENT",
      "SUMMARY:Lost",
      "BEGIN:VEVENT",
      "SUMMARY:Kept",
      "DTSTART:20261004T190000Z",
      "DTEND:20261004T200000Z",
      "END:VEVENT",
      "END:VCALENDAR",
    ].join("\r\n");
    expect(parseIcs(text + "\r\n")).toEqual([
      timed("Kept", "2026-10-04T19:00:00.000Z", "2026-10-04T20:00:00.000Z"),
    ]);
  });

  it("ignores stray components outside a VEVENT", () => {
    const text = [
      "BEGIN:VCALENDAR",
      "END:VEVENT",
      "BEGIN:VTODO",
      "END:VTODO",
      "BEGIN:VEVENT",
      "SUMMARY:Found",
      "DTSTART:20261004T190000Z",
      "DTEND:20261004T200000Z",
      "END:VEVENT",
      "END:VCALENDAR",
    ].join("\r\n");
    expect(parseIcs(text + "\r\n")).toEqual([
      timed("Found", "2026-10-04T19:00:00.000Z", "2026-10-04T20:00:00.000Z"),
    ]);
  });

  it("reads a TZID time next to a daylight-saving change", () => {
    const text = cal(
      [
        "SUMMARY:Fall",
        "DTSTART;TZID=America/Chicago:20261101T030000",
        "DTEND;TZID=America/Chicago:20261101T040000",
      ],
      [
        "SUMMARY:Spring",
        "DTSTART;TZID=America/Chicago:20270314T030000",
        "DTEND;TZID=America/Chicago:20270314T040000",
      ],
    );
    expect(parseIcs(text)).toEqual([
      timed("Fall", "2026-11-01T09:00:00.000Z", "2026-11-01T10:00:00.000Z"),
      timed("Spring", "2027-03-14T08:00:00.000Z", "2027-03-14T09:00:00.000Z"),
    ]);
  });

  it("reads a DTEND that is not a date as a missing one", () => {
    const text = cal([
      "DTSTART:20261004T190000Z",
      "DTEND:garbage",
      "SUMMARY:BadEnd",
    ]);
    expect(parseIcs(text)).toEqual([
      timed("BadEnd", "2026-10-04T19:00:00.000Z", "2026-10-04T19:00:00.000Z"),
    ]);
  });

  it("leaves out a VEVENT that the calendar's end closes", () => {
    const text = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "BEGIN:VEVENT",
      "DTSTART:20261004T190000Z",
      "SUMMARY:Unclosed",
      "END:VCALENDAR",
    ].join("\r\n");
    expect(parseIcs(text + "\r\n")).toEqual([]);
  });
});

describe("buildEventCards edges", () => {
  it("names every month", () => {
    const events = Array.from({ length: 12 }, (_, i) => {
      const mm = String(i + 1).padStart(2, "0");
      return timed(
        `M${String(i + 1)}`,
        `2027-${mm}-05T18:00:00.000Z`,
        `2027-${mm}-05T19:00:00.000Z`,
      );
    });
    const dates = [
      "5 January",
      "5 February",
      "5 March",
      "5 April",
      "5 May",
      "5 June",
      "5 July",
      "5 August",
      "5 September",
      "5 October",
      "5 November",
      "5 December",
    ];
    expect(buildEventCards(events, NOW)).toEqual(
      dates.map((date, i) => ({
        date,
        title: `M${String(i + 1)}`,
        location: null,
      })),
    );
  });

  it("trims a URL location and links http as well as https", () => {
    const events = [
      timed(
        "One",
        "2026-10-04T19:00:00.000Z",
        "2026-10-04T20:00:00.000Z",
        "  https://example.org/tickets  ",
      ),
      timed(
        "Two",
        "2026-10-05T19:00:00.000Z",
        "2026-10-05T20:00:00.000Z",
        "http://example.org/",
      ),
      timed(
        "Three",
        "2026-10-06T19:00:00.000Z",
        "2026-10-06T20:00:00.000Z",
        "https://example.org/a b",
      ),
      timed(
        "Four",
        "2026-10-07T19:00:00.000Z",
        "2026-10-07T20:00:00.000Z",
        "see https://example.org/",
      ),
    ];
    expect(buildEventCards(events, NOW).map((c) => c.location)).toEqual([
      { kind: "link", href: "https://example.org/tickets" },
      { kind: "link", href: "http://example.org/" },
      { kind: "text", text: "https://example.org/a b" },
      { kind: "text", text: "see https://example.org/" },
    ]);
  });

  it("treats an empty location as none", () => {
    const events = [
      timed(
        "Empty",
        "2026-10-04T19:00:00.000Z",
        "2026-10-04T20:00:00.000Z",
        "",
      ),
    ];
    expect(buildEventCards(events, NOW)).toEqual([
      { date: "4 October", title: "Empty", location: null },
    ]);
  });

  it("shows both months for a run across years", () => {
    expect(
      buildEventCards([allDay("New Year", "2026-12-31", "2027-01-02")], NOW),
    ).toEqual([
      { date: "31 December – 1 January", title: "New Year", location: null },
    ]);
    expect(
      buildEventCards([allDay("Season", "2026-10-16", "2027-10-19")], NOW),
    ).toEqual([
      { date: "16 October – 18 October", title: "Season", location: null },
    ]);
  });
});
