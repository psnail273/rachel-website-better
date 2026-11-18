import { expect, test } from "@playwright/test";
import { revalidate, serveFeed } from "../rachels-new-site/support";
import { phone } from "./support";

test.use({ viewport: phone });

// Six future all-day events, next year, a month apart and each titled on its
// own, so the strip shows six cards: more than a 390px row holds.
function manyEvents(now = new Date()): { ics: string; titles: string[] } {
  const next =
    Number(
      new Intl.DateTimeFormat("en-US", {
        timeZone: "America/Chicago",
        year: "numeric",
      }).format(now),
    ) + 1;
  const day = (m: number, d: number) =>
    `${next}${String(m).padStart(2, "0")}${String(d).padStart(2, "0")}`;
  const titles = [
    "Winter Recorder Consort",
    "Clarinet Quintet Evening",
    "Baroque Sonatas at Noon",
    "Early Music Missouri Festival",
    "Summer Pops on the Lawn",
    "Brahms Quintet with Friends",
  ];
  const events = titles.map((title, i) =>
    [
      "BEGIN:VEVENT",
      `UID:strip-${i}@scenario.fixture`,
      `DTSTAMP:${day(i + 2, 10)}T000000Z`,
      `DTSTART;VALUE=DATE:${day(i + 2, 10)}`,
      `DTEND;VALUE=DATE:${day(i + 2, 11)}`,
      `SUMMARY:${title}`,
      `LOCATION:Sheldon Concert Hall\\, St. Louis`,
      "END:VEVENT",
    ].join("\r\n"),
  );
  const ics = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Scenarios//Design system, shell and Home//EN",
    ...events,
    "END:VCALENDAR",
    "",
  ].join("\r\n");
  return { ics, titles };
}

test("on a phone, with more events than the row holds, Next events scrolls a later card into view and enables Previous events", async ({
  page,
  request,
}) => {
  const feed = manyEvents();
  await serveFeed(request, feed.ics);
  await revalidate(request);

  await page.goto("/");
  const row = page.getByRole("list", { name: "Upcoming events" });
  const cards = row.getByRole("listitem");
  await expect(cards.getByRole("heading", { level: 3 })).toHaveText(
    feed.titles,
  );
  await row.scrollIntoViewIfNeeded();

  const next = page.getByRole("button", { name: "Next events" });
  const previous = page.getByRole("button", { name: "Previous events" });
  await expect(next, "the cards overflow the row").toBeEnabled();
  await expect(previous).toBeDisabled();
  const later = cards.nth(1);
  await expect(later, "the second card starts out of view").not.toBeInViewport(
    { ratio: 0.9 },
  );

  await next.click();
  await expect(later, "the second card scrolls into view").toBeInViewport({
    ratio: 0.9,
  });
  await expect(previous).toBeEnabled();
});
