// @vitest-environment happy-dom
import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { SiteFooter } from "./site-footer";

afterEach(() => {
  cleanup();
  vi.useRealTimers();
});

function column(el: Element | null | undefined) {
  const list = el?.children[1];
  return {
    tag: el?.tagName,
    label: [el?.children[0]?.tagName, el?.children[0]?.textContent],
    listTag: list?.tagName,
    links: Array.from(list?.children ?? []).map((item) => {
      const a = item.children.item(0);
      return [
        item.tagName,
        item.children.length,
        a?.tagName,
        a?.textContent,
        a?.getAttribute("href"),
        a?.getAttribute("target"),
        a?.getAttribute("rel"),
      ];
    }),
  };
}

describe("SiteFooter", () => {
  it("links to each Therapy and Performing page from navs labelled Therapy pages and Performing pages", async () => {
    render(await SiteFooter());
    const navs = Array.from(
      screen.getByRole("contentinfo").querySelectorAll("nav"),
    );

    expect(navs.map((nav) => nav.getAttribute("aria-label"))).toEqual([
      "Therapy pages",
      "Performing pages",
    ]);
    expect(navs.map((nav) => column(nav))).toEqual([
      {
        tag: "NAV",
        label: ["P", "Therapy"],
        listTag: "UL",
        links: [
          ["LI", 1, "A", "About Me", "/therapy/about", null, null],
          ["LI", 1, "A", "Services", "/therapy/services", null, null],
          [
            "LI",
            1,
            "A",
            "Education and Training",
            "/therapy/education-and-training",
            null,
            null,
          ],
        ],
      },
      {
        tag: "NAV",
        label: ["P", "Performing"],
        listTag: "UL",
        links: [
          ["LI", 1, "A", "Bio", "/performing/bio", null, null],
          ["LI", 1, "A", "Media", "/performing/media", null, null],
        ],
      },
    ]);
  });

  it("gives the Contact column Wellness Alliance in a new tab, Email and Contact page", async () => {
    render(await SiteFooter());
    const footer = screen.getByRole("contentinfo");
    const navs = Array.from(footer.querySelectorAll("nav"));
    const links = Array.from(footer.querySelectorAll("a")).map((a) => [
      a.textContent,
      a.getAttribute("href"),
      a.getAttribute("target"),
      a.getAttribute("rel"),
    ]);

    expect(links).toEqual([
      ["About Me", "/therapy/about", null, null],
      ["Services", "/therapy/services", null, null],
      ["Education and Training", "/therapy/education-and-training", null, null],
      ["Bio", "/performing/bio", null, null],
      ["Media", "/performing/media", null, null],
      [
        "Wellness Alliance",
        "https://wellnessalliancestl.com/rsiegel",
        "_blank",
        "noopener noreferrer",
      ],
      ["Email", "mailto:rachel@example.com", null, null],
      ["Contact page", "/contact", null, null],
    ]);
    expect(column(navs[1]?.nextElementSibling)).toEqual({
      tag: "DIV",
      label: ["P", "Contact"],
      listTag: "UL",
      links: [
        [
          "LI",
          1,
          "A",
          "Wellness Alliance",
          "https://wellnessalliancestl.com/rsiegel",
          "_blank",
          "noopener noreferrer",
        ],
        ["LI", 1, "A", "Email", "mailto:rachel@example.com", null, null],
        ["LI", 1, "A", "Contact page", "/contact", null, null],
      ],
    });
  });

  it("shows the brand, the tagline, St. Louis, MO and the copyright line for the current year", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2031-06-15T12:00:00Z"));
    render(await SiteFooter());
    const first = screen.queryAllByRole("contentinfo");

    expect(first).toHaveLength(1);
    expect(
      Array.from(first[0]?.querySelectorAll("p") ?? []).map(
        (p) => p.textContent,
      ),
    ).toEqual([
      "Rachel Siegel",
      "Licensed psychotherapist, clarinetist, recorder player",
      "St. Louis, MO",
      "Therapy",
      "Performing",
      "Contact",
      "© 2031 Rachel Siegel",
    ]);
    expect(first[0]?.textContent).toBe(
      "Rachel SiegelLicensed psychotherapist, clarinetist, recorder playerSt. Louis, MOTherapyAbout MeServicesEducation and TrainingPerformingBioMediaContactWellness AllianceEmailContact page© 2031 Rachel Siegel",
    );

    cleanup();
    vi.setSystemTime(new Date("2027-03-01T12:00:00Z"));
    render(await SiteFooter());
    const paragraphs = Array.from(
      screen.getByRole("contentinfo").querySelectorAll("p"),
    );

    expect(paragraphs.at(-1)?.textContent).toBe("© 2027 Rachel Siegel");
  });
});
