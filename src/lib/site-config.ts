export type CalendarFeed = {
  name: string;
  icsUrl: string;
};

export type SiteConfig = {
  email: string;
  wellnessAllianceUrl: string;
  calendarFeeds: CalendarFeed[];
  publicCalendarUrl: string;
};

export const siteConfig: SiteConfig = {
  email: "",
  wellnessAllianceUrl: "",
  calendarFeeds: [],
  publicCalendarUrl: "",
};
