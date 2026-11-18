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

const paragraph1 =
  "As a performer of modern and historical wind instruments, Rachel Siegel defies conventional classifications. Across 34 states and for more than two decades, she has played music that spans a millennium, from orchestral works to ancient folk songs, on various eras of clarinets and recorders—all reflecting her eclectic musical interests and experiences.";
const paragraph2 =
  'From 2013-2017, Rachel served as a clarinetist in "The President\'s Own" United States Marine Band in Washington, DC. In addition to her duties as a clarinetist and ceremonial musician, Rachel had the opportunity to perform Vivaldi\'s Recorder Concerto in C minor with "The President\'s Own" Chamber Orchestra. Since then, Rachel has performed (on clarinets of all sizes) with the St. Louis Symphony Orchestra, Washington National Opera Orchestra, Baltimore Symphony, and the Richmond Symphony. Additionally, since its debut in 2016, she has played recorder in the Harry Potter in Concert series with several orchestras, including the Philadelphia Orchestra and National Symphony Orchestra. Now based in her hometown of St. Louis, MO, Rachel is a regularly featured artist with Early Music Missouri and frequently collaborates with the Collegium Vocale of St. Louis and American Kantorei concert series.';
const paragraph3 =
  "An advocate for the psychological wellbeing of performers and pedagogues within the field of classical music, Rachel teaches workshops to musicians of all ages on performance psychology and audition preparation. In all, thousands of students have worked with Rachel throughout the United States, including at universities such as Texas A&M, West Virginia University, and University of Missouri - St. Louis; at advanced youth programs like the St. Louis Symphony Youth Orchestra; and at dozens of schools across the country.";
const paragraph4 =
  "Rachel received degrees in clarinet performance from the University of Minnesota, University of Southern California, and Rice University. Her primary teachers include Burt Hara, Yehuda Gilad and Tina Ward (clarinet), and Clea Galhano (recorder). Additionally, in 2020 she was awarded a Fulbright to study in Helsinki, Finland. In addition to performing, you can read about Rachel's work as a psychotherapist in the therapy section of this website.";

describe("BioPage", () => {
  it("shows the Bio heading and the four bio paragraphs", async () => {
    const doc = await renderPage();

    expect(texts(doc.querySelectorAll("h1"))).toEqual(["Bio"]);
    expect(texts(doc.querySelectorAll("p"))).toEqual([
      paragraph1,
      paragraph2,
      paragraph3,
      paragraph4,
    ]);
  });

  it("links the therapy section to About Me", async () => {
    const doc = await renderPage();
    const links = Array.from(doc.querySelectorAll("a"));

    expect(
      links.map((a) => ({ text: a.textContent, href: a.getAttribute("href") })),
    ).toEqual([
      { text: "the therapy section of this website", href: "/therapy/about" },
    ]);
    expect(links[0]?.parentElement?.tagName).toBe("P");
    expect(links[0]?.parentElement?.textContent).toBe(paragraph4);
  });

  it("renders the clarinet headshot as its only image", async () => {
    const doc = await renderPage();

    expect(
      Array.from(doc.querySelectorAll("img"), (img) => ({
        src: img.getAttribute("src"),
        alt: img.getAttribute("alt"),
        width: img.getAttribute("width"),
        height: img.getAttribute("height"),
      })),
    ).toEqual([
      {
        src: "/images/headshot-clarinet.svg",
        alt: "Rachel Siegel holding her clarinet among white blossoming trees",
        width: "768",
        height: "1024",
      },
    ]);
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

    expect(Array.from(doc.body.children, (el) => el.tagName)).toEqual([
      "DIV",
      "SECTION",
    ]);
    const page = doc.body.children[0];
    expect(texts(page.querySelectorAll("h1"))).toEqual(["Bio"]);
    expect(texts(doc.querySelectorAll("section h2"))).toEqual(["Upcoming"]);
    expect(texts(doc.querySelectorAll("section p"))).toEqual([
      "Events are unavailable right now.",
      "See the full calendar",
    ]);
  });
});
