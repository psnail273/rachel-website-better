import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import type { CalendarEvent } from "./events";

export type EventsCache = {
  read(feed: string): CalendarEvent[];
  replace(feed: string, events: readonly CalendarEvent[]): void;
  close(): void;
};

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}

export function openEventsCache(dbPath: string): EventsCache {
  if (dbPath !== ":memory:") {
    fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  }
  const db = new DatabaseSync(dbPath);
  db.exec(
    `CREATE TABLE IF NOT EXISTS calendar_events (
      feed TEXT NOT NULL,
      position INTEGER NOT NULL,
      title TEXT NOT NULL,
      start TEXT NOT NULL,
      "end" TEXT NOT NULL,
      all_day INTEGER NOT NULL,
      location TEXT
    )`,
  );
  return {
    read(feed) {
      const rows = db
        .prepare(
          `SELECT title, start, "end", all_day, location FROM calendar_events
           WHERE feed = ? ORDER BY position`,
        )
        .all(feed);
      return rows.map((row) => ({
        title: text(row.title),
        start: text(row.start),
        end: text(row.end),
        allDay: row.all_day === 1,
        location: typeof row.location === "string" ? row.location : null,
      }));
    },
    replace(feed, events) {
      db.exec("BEGIN");
      try {
        db.prepare("DELETE FROM calendar_events WHERE feed = ?").run(feed);
        const insert = db.prepare(
          `INSERT INTO calendar_events (feed, position, title, start, "end", all_day, location)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
        );
        events.forEach((e, i) => {
          insert.run(
            feed,
            i,
            e.title,
            e.start,
            e.end,
            e.allDay ? 1 : 0,
            e.location,
          );
        });
        db.exec("COMMIT");
      } catch (error) {
        db.exec("ROLLBACK");
        throw error;
      }
    },
    close() {
      db.close();
    },
  };
}

export function eventsCachePath(
  env: Readonly<Record<string, string | undefined>>,
): string {
  const value = env.EVENTS_CACHE_PATH;
  return value !== undefined && value !== "" ? value : "data/events.sqlite";
}
