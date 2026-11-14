import { describe, expect, it } from "vitest";
import { siteConfig } from "./site-config";

describe("siteConfig", () => {
  it("holds Rachel's email, the Wellness Alliance URL, the calendar feeds and the public calendar link", () => {
    expect(siteConfig).toEqual({
      email: "rachel@example.com",
      wellnessAllianceUrl: "https://wellnessalliancestl.com/rsiegel",
      calendarFeeds: [
        {
          name: "Rachel's public calendar",
          icsUrl:
            "https://calendar.google.com/calendar/ical/f93593a9aa8efdef9b296cd13ae5518c085ad3e1b69bb609278e09df2dc88ee4%40group.calendar.google.com/public/basic.ics",
        },
      ],
      publicCalendarUrl:
        "https://calendar.google.com/calendar/embed?src=f93593a9aa8efdef9b296cd13ae5518c085ad3e1b69bb609278e09df2dc88ee4%40group.calendar.google.com&ctz=America%2FChicago",
    });
  });
});
