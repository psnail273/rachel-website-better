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

const CHICAGO = "America/Chicago";
const DAY_MS = 86_400_000;
const MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

type Fields = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
};

type ParsedDate = { allDay: boolean; fields: Fields; utc: boolean };

type Prop = { name: string; params: Map<string, string>; value: string };

function isKnownZone(zone: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: zone });
    return true;
  } catch {
    return false;
  }
}

function wallClock(instantMs: number, zone: string): Fields {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: zone,
    hourCycle: "h23",
    year: "numeric",
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    minute: "numeric",
    second: "numeric",
  }).formatToParts(new Date(instantMs));
  const get = (type: string): number => {
    const part = parts.find((p) => p.type === type);
    return part === undefined ? 0 : Number(part.value);
  };
  return {
    year: get("year"),
    month: get("month"),
    day: get("day"),
    hour: get("hour"),
    minute: get("minute"),
    second: get("second"),
  };
}

function fieldsAsUtcMs(f: Fields): number {
  return Date.UTC(f.year, f.month - 1, f.day, f.hour, f.minute, f.second);
}

function localToUtcMs(f: Fields, zone: string): number {
  const guess = fieldsAsUtcMs(f);
  const offsetAt = (instant: number): number =>
    fieldsAsUtcMs(wallClock(instant, zone)) - instant;
  const first = guess - offsetAt(guess);
  return guess - offsetAt(first);
}

function unescapeText(value: string): string {
  return value.replace(/\\([\\,;nN])/g, (_m, ch: string) =>
    ch === "n" || ch === "N" ? "\n" : ch,
  );
}

function unfold(text: string): string[] {
  const lines: string[] = [];
  for (const raw of text.split(/\r\n|\n|\r/)) {
    if ((raw.startsWith(" ") || raw.startsWith("\t")) && lines.length > 0) {
      lines[lines.length - 1] += raw.slice(1);
    } else {
      lines.push(raw);
    }
  }
  return lines;
}

function parseProp(line: string): Prop | null {
  let inQuote = false;
  let colon = -1;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') inQuote = !inQuote;
    else if (ch === ":" && !inQuote) {
      colon = i;
      break;
    }
  }
  if (colon < 0) return null;
  const head = line.slice(0, colon);
  const value = line.slice(colon + 1);
  const segments = head.split(";");
  const name = (segments[0] ?? "").trim().toUpperCase();
  const params = new Map<string, string>();
  for (const seg of segments.slice(1)) {
    const eq = seg.indexOf("=");
    if (eq > 0) {
      params.set(
        seg.slice(0, eq).trim().toUpperCase(),
        seg.slice(eq + 1).replace(/^"|"$/g, ""),
      );
    }
  }
  return { name, params, value };
}

function validDate(year: number, month: number, day: number): boolean {
  if (month < 1 || month > 12 || day < 1) return false;
  return new Date(Date.UTC(year, month - 1, day)).getUTCDate() === day;
}

function parseDateValue(value: string): ParsedDate | null {
  const v = value.trim();
  const dateOnly = /^(\d{4})(\d{2})(\d{2})$/.exec(v);
  if (dateOnly) {
    const [year, month, day] = [
      Number(dateOnly[1]),
      Number(dateOnly[2]),
      Number(dateOnly[3]),
    ];
    if (!validDate(year, month, day)) return null;
    return {
      allDay: true,
      fields: { year, month, day, hour: 0, minute: 0, second: 0 },
      utc: false,
    };
  }
  const dt = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$/i.exec(v);
  if (!dt) return null;
  const fields: Fields = {
    year: Number(dt[1]),
    month: Number(dt[2]),
    day: Number(dt[3]),
    hour: Number(dt[4]),
    minute: Number(dt[5]),
    second: Number(dt[6]),
  };
  if (!validDate(fields.year, fields.month, fields.day)) return null;
  if (fields.hour > 23 || fields.minute > 59 || fields.second > 59) {
    return null;
  }
  return { allDay: false, fields, utc: dt[7] !== "" };
}

function dateString(f: Fields): string {
  const p = (n: number, w: number): string => String(n).padStart(w, "0");
  return `${p(f.year, 4)}-${p(f.month, 2)}-${p(f.day, 2)}`;
}

function nextDayString(f: Fields): string {
  return new Date(Date.UTC(f.year, f.month - 1, f.day + 1))
    .toISOString()
    .slice(0, 10);
}

function toInstantMs(prop: Prop, parsed: ParsedDate): number {
  if (parsed.utc) return fieldsAsUtcMs(parsed.fields);
  const tzid = prop.params.get("TZID");
  const zone = tzid !== undefined && isKnownZone(tzid) ? tzid : CHICAGO;
  return localToUtcMs(parsed.fields, zone);
}

function buildEvent(props: Prop[]): CalendarEvent | null {
  const find = (name: string): Prop | undefined =>
    props.find((p) => p.name === name);
  const summary = find("SUMMARY");
  const startProp = find("DTSTART");
  if (summary === undefined || startProp === undefined) return null;
  const title = unescapeText(summary.value);
  if (title.trim() === "") return null;
  const start = parseDateValue(startProp.value);
  if (start === null) return null;
  const endProp = find("DTEND");
  const endParsed = endProp ? parseDateValue(endProp.value) : null;
  const locProp = find("LOCATION");
  const locText = locProp ? unescapeText(locProp.value) : "";
  const location = locText.trim() === "" ? null : locText;

  if (start.allDay) {
    const end =
      endParsed !== null && endParsed.allDay
        ? dateString(endParsed.fields)
        : nextDayString(start.fields);
    return {
      title,
      start: dateString(start.fields),
      end,
      allDay: true,
      location,
    };
  }
  const startMs = toInstantMs(startProp, start);
  const endMs =
    endProp !== undefined && endParsed !== null && !endParsed.allDay
      ? toInstantMs(endProp, endParsed)
      : startMs;
  return {
    title,
    start: new Date(startMs).toISOString(),
    end: new Date(endMs).toISOString(),
    allDay: false,
    location,
  };
}

export function parseIcs(text: string): CalendarEvent[] {
  const events: CalendarEvent[] = [];
  let inCalendar = false;
  let current: Prop[] | null = null;
  let depth = 0;
  for (const line of unfold(text)) {
    const prop = parseProp(line);
    if (prop === null) continue;
    const isBegin = prop.name === "BEGIN";
    const isEnd = prop.name === "END";
    const kind = prop.value.trim().toUpperCase();
    if (current === null) {
      if (isBegin && kind === "VCALENDAR") inCalendar = true;
      else if (isEnd && kind === "VCALENDAR") inCalendar = false;
      else if (isBegin && kind === "VEVENT" && inCalendar) {
        current = [];
        depth = 0;
      }
      continue;
    }
    if (isBegin) {
      if (kind === "VEVENT") {
        current = [];
        depth = 0;
      } else depth++;
    } else if (isEnd) {
      if (depth > 0) depth--;
      else if (kind === "VEVENT") {
        const event = buildEvent(current);
        if (event !== null) events.push(event);
        current = null;
      }
    } else if (depth === 0) {
      current.push(prop);
    }
  }
  return events;
}

function dayNumber(f: Fields): number {
  return Math.floor(Date.UTC(f.year, f.month - 1, f.day) / DAY_MS);
}

function parseDay(day: string): Fields {
  return {
    year: Number(day.slice(0, 4)),
    month: Number(day.slice(5, 7)),
    day: Number(day.slice(8, 10)),
    hour: 0,
    minute: 0,
    second: 0,
  };
}

type Prepared = {
  event: CalendarEvent;
  startMs: number;
  endMs: number;
  firstDay: number;
  lastDay: number;
};

function prepare(event: CalendarEvent): Prepared | null {
  if (event.allDay) {
    const s = parseDay(event.start);
    const e = parseDay(event.end);
    const firstDay = dayNumber(s);
    const endDay = dayNumber(e);
    if (Number.isNaN(firstDay) || Number.isNaN(endDay)) return null;
    return {
      event,
      startMs: localToUtcMs(s, CHICAGO),
      endMs: localToUtcMs(e, CHICAGO),
      firstDay,
      lastDay: Math.max(firstDay, endDay - 1),
    };
  }
  const startMs = Date.parse(event.start);
  const endMs = Date.parse(event.end);
  if (Number.isNaN(startMs) || Number.isNaN(endMs)) return null;
  const day = dayNumber(wallClock(startMs, CHICAGO));
  return { event, startMs, endMs, firstDay: day, lastDay: day };
}

function formatDay(day: number): { month: number; d: number; year: number } {
  const date = new Date(day * DAY_MS);
  return {
    month: date.getUTCMonth(),
    d: date.getUTCDate(),
    year: date.getUTCFullYear(),
  };
}

function formatRange(first: number, last: number): string {
  const a = formatDay(first);
  const startText = `${MONTHS[a.month] ?? ""} ${String(a.d)}`;
  if (last <= first) return startText;
  const b = formatDay(last);
  if (a.month === b.month && a.year === b.year) {
    return `${startText}–${String(b.d)}`;
  }
  return `${startText}–${MONTHS[b.month] ?? ""} ${String(b.d)}`;
}

function toCardLocation(location: string | null): CardLocation | null {
  if (location === null || location === "") return null;
  const trimmed = location.trim();
  if (/^https?:\/\/\S*$/i.test(trimmed)) {
    return { kind: "link", href: trimmed };
  }
  return { kind: "text", text: location };
}

export function buildEventCards(
  events: readonly CalendarEvent[],
  now: Date,
): EventCard[] {
  const nowMs = now.getTime();
  const upcoming: Prepared[] = [];
  for (const event of events) {
    const p = prepare(event);
    if (p !== null && p.endMs > nowMs) upcoming.push(p);
  }
  upcoming.sort((a, b) => a.startMs - b.startMs);

  type Card = {
    title: string;
    location: string | null;
    first: number;
    last: number;
  };
  const cards: Card[] = [];
  for (const p of upcoming) {
    const key = p.event.title.toLowerCase();
    const match = cards.find(
      (c) => c.title.toLowerCase() === key && c.last >= p.firstDay - 1,
    );
    if (match) match.last = Math.max(match.last, p.lastDay);
    else {
      cards.push({
        title: p.event.title,
        location: p.event.location,
        first: p.firstDay,
        last: p.lastDay,
      });
    }
  }
  return cards.map((c) => ({
    date: formatRange(c.first, c.last),
    title: c.title,
    location: toCardLocation(c.location),
  }));
}
