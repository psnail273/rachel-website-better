// @vitest-environment happy-dom
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { text } from "node:stream/consumers";
import type { ReactElement } from "react";
import { prerender } from "react-dom/static";
import type { Metadata } from "next";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import UpcomingLayout from "../../layout";

vi.mock("next/cache", () => ({ cacheLife: vi.fn() }));

type PageModule = { default: () => ReactElement; metadata: Metadata };

const pages = import.meta.glob<PageModule>("./page.tsx");
const page = await pages["./page.tsx"]();

let folder = "";

beforeEach(() => {
  folder = mkdtempSync(join(tmpdir(), "bio-"));
  vi.stubEnv("EVENTS_CACHE_PATH", join(folder, "events.sqlite"));
  vi.stubEnv("CALENDAR_FEED_URL", "https://feed.test/calendar.ics");
  vi.stubGlobal(
    "fetch",
    vi.fn(() => Promise.reject(new TypeError("fetch failed"))),
  );
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
  rmSync(folder, { recursive: true, force: true });
});

function loadPage(): PageModule {
  expect(page).toBeDefined();
  return page;
}

async function toDoc(element: ReactElement): Promise<Document> {
  const { prelude } = await prerender(element);
  const html = await text(prelude);
  return new DOMParser().parseFromString(html, "text/html");
}

function renderPage(): Promise<Document> {
  const { default: BioPage } = loadPage();
  return toDoc(<BioPage />);
}

function texts(nodes: Iterable<Element>): string[] {
  return Array.from(nodes, (node) => node.textContent);
}

function attributes(el: Element | null | undefined): Record<string, string> {
  return Object.fromEntries(
    Array.from(el?.attributes ?? [], (a) => [a.name, a.value]),
  );
}

const paragraph1 =
  "As a performer of modern and historical wind instruments, Rachel Siegel defies conventional classifications. Across 34 states and for more than two decades, she has played music that spans a millennium, from orchestral works to ancient folk songs, on various eras of clarinets and recorders—all reflecting her eclectic musical interests and\u00a0experiences.";
const paragraph2 =
  "From 2013-2017, Rachel served as a clarinetist in \u201cThe President\u2019s Own\u201d United States Marine Band in Washington, DC. In addition to her duties as a clarinetist and ceremonial musician, Rachel had the opportunity to perform Vivaldi\u2019s Recorder Concerto in C minor with \u201cThe President\u2019s Own\u201d Chamber Orchestra. Since then, Rachel has performed (on clarinets of all sizes) with the St. Louis Symphony Orchestra, Washington National Opera Orchestra, Baltimore Symphony, and the Richmond Symphony. Additionally, since its debut in 2016, she has played recorder in the Harry Potter in Concert series with several orchestras, including the Philadelphia Orchestra and National Symphony Orchestra. Now based in her hometown of St. Louis, MO, Rachel is a regularly featured artist with Early Music Missouri and frequently collaborates with the Collegium Vocale of St. Louis and American Kantorei concert\u00a0series.";
const paragraph3 =
  "An advocate for the psychological wellbeing of performers and pedagogues within the field of classical music, Rachel teaches workshops to musicians of all ages on performance psychology and audition preparation. In all, thousands of students have worked with Rachel throughout the United States, including at universities such as Texas A&M, West Virginia University, and University of Missouri - St. Louis; at advanced youth programs like the St. Louis Symphony Youth Orchestra; and at dozens of schools across the\u00a0country.";
const paragraph4Before =
  "Rachel received degrees in clarinet performance from the University of Minnesota, University of Southern California, and Rice University. Her primary teachers include Burt Hara, Yehuda Gilad and Tina Ward (clarinet), and Clea Galhano (recorder). Additionally, in 2020 she was awarded a Fulbright to study in Helsinki, Finland. In addition to performing, you can read about Rachel\u2019s work as a psychotherapist in ";
const linkText = "the therapy section of this\u00a0website";

describe("BioPage", () => {
  it("shows the Bio heading first in the photo page, with no label above it", async () => {
    const doc = await renderPage();
    const section = doc.body.firstElementChild;
    const sidebar = section?.firstElementChild;
    const parts = Array.from(sidebar?.children ?? []);
    const head = parts[0];
    const aside = parts[1];
    const figure = aside?.firstElementChild;
    const heading = head?.firstElementChild;
    const image = figure?.firstElementChild;

    expect(doc.body.children).toHaveLength(1);
    expect(section?.tagName).toBe("SECTION");
    expect(attributes(section)).toEqual({
      "data-section": "",
      "aria-labelledby": "bio-heading",
    });
    expect(section?.children).toHaveLength(1);
    expect(sidebar?.tagName).toBe("DIV");
    expect(attributes(sidebar)).toEqual({ "data-sidebar": "lead" });
    expect(
      parts.map((part) => [part.tagName, ...Object.keys(attributes(part))]),
    ).toEqual([
      ["DIV", "data-sidebar-head"],
      ["DIV", "data-sidebar-aside"],
      ["DIV", "data-sidebar-body"],
    ]);
    expect(texts(doc.querySelectorAll("h1"))).toEqual(["Bio"]);
    expect(attributes(heading)).toEqual({
      "data-heading": "1",
      id: "bio-heading",
      class: "type-h1",
    });
    expect(head?.children).toHaveLength(1);
    expect(heading?.tagName).toBe("H1");
    expect(aside?.children).toHaveLength(1);
    expect(figure?.tagName).toBe("FIGURE");
    expect(figure?.hasAttribute("data-photo")).toBe(true);
    expect(figure?.children).toHaveLength(1);
    expect(image?.tagName).toBe("IMG");
    expect(doc.querySelectorAll("img")).toHaveLength(1);
    expect(image?.getAttribute("src")).toBe("/images/headshot-clarinet.svg");
    expect(image?.getAttribute("alt")).toBe(
      "Rachel Siegel holding her clarinet among white blossoming trees",
    );
    expect(image?.getAttribute("width")).toBe("768");
    expect(image?.getAttribute("height")).toBe("1024");
    expect(image?.getAttribute("sizes")).toBeNull();
    expect(
      Array.from(
        doc.querySelectorAll("[class]"),
        (el) => el.getAttribute("class") ?? "",
      ).filter((cls) => /self-center|max-w-|mx-auto/.test(cls)),
    ).toEqual([]);
  });

  it("sets the four bio paragraphs as one plain Prose", async () => {
    const doc = await renderPage();
    const body = doc.querySelector("[data-sidebar-body]");
    const prose = body?.firstElementChild;
    const paragraphs = Array.from(prose?.children ?? []);

    expect(body?.children).toHaveLength(1);
    expect(prose?.tagName).toBe("DIV");
    expect(attributes(prose)).toEqual({ "data-prose": "start" });
    expect(paragraphs.map((p) => p.tagName)).toEqual(["P", "P", "P", "P"]);
    expect(paragraphs.map((p) => attributes(p))).toEqual([{}, {}, {}, {}]);
    expect(texts(paragraphs)).toEqual([
      paragraph1,
      paragraph2,
      paragraph3,
      paragraph4Before + linkText + ".",
    ]);
    expect(texts(doc.querySelectorAll("p"))).toHaveLength(4);
    expect(doc.querySelectorAll("[data-lead], .type-lead")).toHaveLength(0);
    expect(doc.querySelectorAll("strong, em, b, span, small")).toHaveLength(0);
    expect(paragraphs.map((p) => p.children.length)).toEqual([0, 0, 0, 1]);
  });

  it("links the therapy section of this website to About Me", async () => {
    const doc = await renderPage();
    const links = Array.from(doc.querySelectorAll("a"));
    const link = links[0];
    const paragraphs = doc.querySelectorAll("[data-prose='start'] > p");

    expect(links).toHaveLength(1);
    expect(attributes(link)).toEqual({ href: "/therapy/about" });
    expect(link?.textContent).toBe(linkText);
    expect(link?.parentElement).toBe(paragraphs[3]);
    expect(link?.nextSibling?.textContent).toBe(".");
  });

  it("has its own title and meta description", () => {
    const { metadata } = loadPage();

    expect(metadata).toStrictEqual({
      title: "Bio",
      description:
        "Rachel Siegel is a clarinetist and recorder player on modern and historical instruments, a former member of the United States Marine Band, now based in St. Louis.",
    });
  });

  it("shows the Upcoming strip below the bio in its group's layout", async () => {
    const { default: BioPage } = loadPage();
    const doc = await toDoc(await UpcomingLayout({ children: <BioPage /> }));
    const [bio, upcoming] = Array.from(doc.body.children);

    expect(Array.from(doc.body.children, (el) => el.tagName)).toEqual([
      "SECTION",
      "SECTION",
    ]);
    expect(attributes(bio)).toEqual({
      "data-section": "",
      "aria-labelledby": "bio-heading",
    });
    expect(attributes(upcoming)).toEqual({
      "data-section": "",
      "aria-labelledby": "upcoming-heading",
    });
    expect(texts(bio?.querySelectorAll("h1") ?? [])).toEqual(["Bio"]);
    expect(texts(upcoming?.querySelectorAll("h2") ?? [])).toEqual(["Upcoming"]);
    expect(texts(upcoming?.querySelectorAll("p") ?? [])).toEqual([
      "Events are unavailable right now.",
      "See the full calendar",
    ]);
  });
});
