import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { eventsCachePath, openEventsCache } from "./cache";
import type { CalendarEvent } from "./events";

const A = "https://calendar.example/a.ics";
const B = "https://calendar.example/b.ics";

const CACHED: CalendarEvent[] = [
  {
    title: "Harry Potter with the Nashville Symphony",
    start: "2026-11-08T00:30:00.000Z",
    end: "2026-11-08T03:00:00.000Z",
    allDay: false,
    location: "Schermerhorn Symphony Center, Nashville",
  },
];

const EVENTS_B: CalendarEvent[] = [
  {
    title: "Collegium Vocale of St. Louis Concert",
    start: "2026-10-25T19:00:00.000Z",
    end: "2026-10-25T20:30:00.000Z",
    allDay: false,
    location: "Second Presbyterian Church",
  },
];

const STORED: CalendarEvent[] = [
  {
    title: "Open Rehearsal",
    start: "2026-11-22",
    end: "2026-11-23",
    allDay: true,
    location: null,
  },
  {
    title: "Recital",
    start: "2026-12-05T01:00:00.000Z",
    end: "2026-12-05T02:30:00.000Z",
    allDay: false,
    location: "St Peter's Episcopal Church, St. Louis",
  },
  {
    title: "American Kantorei Performance",
    start: "2026-11-22T19:00:00.000Z",
    end: "2026-11-22T20:00:00.000Z",
    allDay: false,
    location: "https://american-kantorei.org/",
  },
];

describe("openEventsCache", () => {
  let tmp = "";

  beforeEach(() => {
    tmp = fs.mkdtempSync(path.join(os.tmpdir(), "events-cache-"));
  });

  afterEach(() => {
    fs.rmSync(tmp, { recursive: true, force: true });
  });

  it("reads back a feed's events as they were stored", () => {
    const cache = openEventsCache(":memory:");
    cache.replace(A, STORED);
    expect(cache.read(A)).toEqual(STORED);
    cache.close();
  });

  it("replaces a feed's earlier events instead of appending", () => {
    const cache = openEventsCache(":memory:");
    cache.replace(A, STORED);
    cache.replace(A, CACHED);
    expect(cache.read(A)).toEqual(CACHED);
    cache.replace(A, []);
    expect(cache.read(A)).toEqual([]);
    cache.close();
  });

  it("keeps each feed's events apart and reads an unknown feed as empty", () => {
    const cache = openEventsCache(":memory:");
    expect(cache.read(A)).toEqual([]);
    cache.replace(A, STORED);
    cache.replace(B, CACHED);
    cache.replace(B, EVENTS_B);
    expect(cache.read(A)).toEqual(STORED);
    expect(cache.read(B)).toEqual(EVENTS_B);
    expect(cache.read("https://calendar.example/none.ics")).toEqual([]);
    cache.close();
  });

  it("creates the database file and its folders when missing", () => {
    const file = path.join(tmp, "nested", "deeper", "events.sqlite");
    const before = fs.existsSync(file);
    const cache = openEventsCache(file);
    const after = fs.existsSync(file);
    const empty = cache.read(A);
    cache.replace(A, CACHED);
    const stored = cache.read(A);
    cache.close();
    expect(before).toBe(false);
    expect(after).toBe(true);
    expect(empty).toEqual([]);
    expect(stored).toEqual(CACHED);
  });

  it("keeps stored events when the database is opened again", () => {
    const file = path.join(tmp, "events.sqlite");
    const first = openEventsCache(file);
    first.replace(A, STORED);
    first.close();
    const second = openEventsCache(file);
    expect(second.read(A)).toEqual(STORED);
    second.close();
  });

  it("adds its table to an existing database that lacks it", () => {
    const file = path.join(tmp, "events.sqlite");
    const db = new DatabaseSync(file);
    db.exec("CREATE TABLE other (x INTEGER)");
    db.close();
    const cache = openEventsCache(file);
    const empty = cache.read(A);
    cache.replace(A, CACHED);
    const stored = cache.read(A);
    cache.close();
    expect(empty).toEqual([]);
    expect(stored).toEqual(CACHED);
  });

  it("closes its database", () => {
    const cache = openEventsCache(":memory:");
    cache.close();
    expect(() => cache.read(A)).toThrow("database is not open");
  });
});

describe("eventsCachePath", () => {
  it("reads the path from EVENTS_CACHE_PATH", () => {
    expect(
      eventsCachePath({ EVENTS_CACHE_PATH: "/var/cache/rachel/events.sqlite" }),
    ).toBe("/var/cache/rachel/events.sqlite");
  });

  it("defaults to data/events.sqlite when EVENTS_CACHE_PATH is unset or empty", () => {
    expect(eventsCachePath({})).toBe("data/events.sqlite");
    expect(eventsCachePath({ EVENTS_CACHE_PATH: "" })).toBe(
      "data/events.sqlite",
    );
  });
});
