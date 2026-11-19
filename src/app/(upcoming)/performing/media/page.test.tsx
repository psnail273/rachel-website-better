// @vitest-environment happy-dom
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { text } from "node:stream/consumers";
import type { ReactElement } from "react";
import { prerender } from "react-dom/static";
import type { Metadata } from "next";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { siteConfig } from "@/lib/site-config";
import UpcomingLayout from "../../layout";

vi.mock("next/cache", () => ({ cacheLife: vi.fn() }));

type PageModule = { default: () => ReactElement; metadata: Metadata };

const pages = import.meta.glob<PageModule>("./page.tsx");
const importPage = pages["./page.tsx"];
if (importPage === undefined) throw new Error("no ./page.tsx beside this test");
const page = await importPage();

const ALLOW =
  "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share";
const PASSACAILLE = "\u201cPassacaille\u201d by Jacques-Martin Hotteterre";
const BERGAMASCA = "\u201cAria sopra La Bergamasca\u201d by Marco Uccellini";
const PASSACAILLE_TIED =
  "\u201cPassacaille\u201d by Jacques-\u2060Martin\u00a0Hotteterre";
const BERGAMASCA_TIED =
  "\u201cAria sopra La Bergamasca\u201d by Marco\u00a0Uccellini";
const IDS = ["VdwOjCyVsSE", "DZA9Wi6KzWY"];

let folder = "";

beforeEach(() => {
  folder = mkdtempSync(join(tmpdir(), "media-"));
  vi.stubEnv("EVENTS_CACHE_PATH", join(folder, "events.sqlite"));
  vi.stubEnv("CALENDAR_FEED_URL", "https://feed.test/calendar.ics");
  vi.stubGlobal(
    "fetch",
    vi.fn(() => Promise.reject(new TypeError("fetch failed"))),
  );
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
  rmSync(folder, { recursive: true, force: true });
});

function loadPage(): Promise<PageModule> {
  expect(page).toBeDefined();
  return Promise.resolve(page);
}

async function toDoc(element: ReactElement): Promise<Document> {
  const { prelude } = await prerender(element);
  const html = await text(prelude);
  return new DOMParser().parseFromString(html, "text/html");
}

async function renderPage(): Promise<Document> {
  const { default: MediaPage } = await loadPage();
  return toDoc(<MediaPage />);
}

function texts(nodes: Iterable<Element>): string[] {
  return Array.from(nodes, (node) => node.textContent);
}

function attrs(el: Element | null | undefined): Record<string, string> {
  return Object.fromEntries(
    Array.from(el?.attributes ?? [], (a) => [a.name, a.value]),
  );
}

function tags(el: Element | null | undefined): string[] {
  return Array.from(el?.children ?? [], (c) => c.tagName);
}

function iframesOf(): {
  src: string | null;
  title: string | null;
  allow: string | null;
  allowFullScreen: boolean;
}[] {
  return Array.from(document.querySelectorAll("iframe"), (f) => ({
    src: f.getAttribute("src"),
    title: f.getAttribute("title"),
    allow: f.getAttribute("allow"),
    allowFullScreen: f.hasAttribute("allowfullscreen"),
  }));
}

describe("MediaPage", () => {
  it("shows the Media heading first in the photo page, with the recorder headshot beside it", async () => {
    const doc = await renderPage();
    const section = doc.body.firstElementChild;
    const lead = section?.firstElementChild;
    const h1s = Array.from(doc.querySelectorAll("h1"));
    const img = doc.querySelector("[data-sidebar-aside] img");

    expect(tags(doc.body)).toEqual(["SECTION"]);
    expect(attrs(section)).toEqual({
      "data-section": "",
      "aria-labelledby": "media-heading",
    });
    expect(tags(section)).toEqual(["DIV"]);
    expect(attrs(lead)).toEqual({ "data-sidebar": "lead" });
    expect(tags(lead)).toEqual(["DIV", "DIV", "DIV"]);
    expect(
      Array.from(lead?.children ?? [], (c) => Object.keys(attrs(c))),
    ).toEqual([
      ["data-sidebar-head"],
      ["data-sidebar-aside"],
      ["data-sidebar-body"],
    ]);
    expect(texts(h1s)).toEqual(["Media"]);
    expect(attrs(h1s[0])).toEqual({
      "data-heading": "1",
      id: "media-heading",
      class: "type-h1",
    });
    expect(tags(doc.querySelector("[data-sidebar-head]"))).toEqual(["H1"]);
    expect(tags(doc.querySelector("[data-sidebar-aside]"))).toEqual(["FIGURE"]);
    expect(attrs(doc.querySelector("[data-sidebar-aside] > figure"))).toEqual({
      "data-photo": "",
    });
    expect(tags(doc.querySelector("[data-sidebar-aside] > figure"))).toEqual([
      "IMG",
    ]);
    expect(img?.getAttribute("src")).toBe("/images/headshot-recorder.svg");
    expect(img?.getAttribute("alt")).toBe(
      "Rachel Siegel holding a wooden recorder among pink cherry blossoms",
    );
    expect(img?.getAttribute("width")).toBe("1471");
    expect(img?.getAttribute("height")).toBe("2048");
    expect(img?.getAttribute("sizes")).toBeNull();
    expect(
      Array.from(doc.querySelectorAll("[class]")).filter((el) =>
        /self-center|max-w-|mx-auto/.test(el.getAttribute("class") ?? ""),
      ),
    ).toEqual([]);
  });

  it("sets the Video and Audio blocks in one block Stack", async () => {
    const doc = await renderPage();
    const body = doc.querySelector("[data-sidebar-body]");
    const stack = body?.firstElementChild;
    const [video, audio] = Array.from(stack?.children ?? []);

    expect(tags(body)).toEqual(["DIV"]);
    expect(attrs(stack)).toEqual({ "data-stack": "block" });
    expect(tags(stack)).toEqual(["DIV", "DIV"]);
    expect(attrs(video)).toEqual({});
    expect(attrs(audio)).toEqual({});
    expect(tags(video)).toEqual(["H2", "DIV"]);
    expect(video?.children[0]?.textContent).toBe("Video");
    expect(attrs(video?.children[0])).toEqual({
      "data-heading": "2",
      class: "type-h2",
    });
    expect(attrs(video?.children[1])).toEqual({ "data-switcher": "pair" });
    expect(tags(audio)).toEqual(["H2", "DIV"]);
    expect(audio?.children[0]?.textContent).toBe("Audio");
    expect(attrs(audio?.children[0])).toEqual({
      "data-heading": "2",
      class: "type-h2",
    });
    expect(attrs(audio?.children[1])).toEqual({ "data-prose": "start" });
    expect(texts(doc.querySelectorAll("h2"))).toEqual(["Video", "Audio"]);
  });

  it("shows each video's YouTube still and play mark in its card", async () => {
    const doc = await renderPage();
    const switchers = Array.from(doc.querySelectorAll("[data-switcher]"));
    const cells = Array.from(switchers[0]?.children ?? []);
    const figures = Array.from(doc.querySelectorAll("figure[data-video]"));
    const titles = [PASSACAILLE, BERGAMASCA];
    const tied = [PASSACAILLE_TIED, BERGAMASCA_TIED];

    expect(switchers).toHaveLength(1);
    expect(tags(switchers[0])).toEqual(["DIV", "DIV"]);
    expect(cells.map(attrs)).toEqual([{}, {}]);
    expect(cells.map(tags)).toEqual([["FIGURE"], ["FIGURE"]]);
    expect(cells.map((c) => attrs(c.firstElementChild))).toEqual([
      { "data-video": "" },
      { "data-video": "" },
    ]);
    expect(figures).toHaveLength(2);
    expect(figures.map(tags)).toEqual([
      ["BUTTON", "FIGCAPTION"],
      ["BUTTON", "FIGCAPTION"],
    ]);
    expect(figures.map((f) => attrs(f.children[0]))).toEqual(
      titles.map((t) => ({
        "data-video-frame": "",
        type: "button",
        "aria-label": `Play ${t}`,
      })),
    );
    expect(figures.map((f) => tags(f.children[0]))).toEqual([
      ["IMG", "svg"],
      ["IMG", "svg"],
    ]);
    expect(figures.map((f) => attrs(f.querySelector("img")))).toEqual(
      titles.map((t, i) => ({
        alt: `Still from the video of ${t}`,
        loading: "lazy",
        width: "480",
        height: "360",
        decoding: "async",
        "data-nimg": "1",
        style: "color:transparent",
        src: `https://i.ytimg.com/vi/${IDS[i] ?? ""}/hqdefault.jpg`,
      })),
    );
    expect(figures.map((f) => attrs(f.querySelector("svg")))).toEqual([
      {
        "data-play": "",
        "aria-hidden": "true",
        width: "56",
        height: "56",
        viewBox: "0 0 56 56",
      },
      {
        "data-play": "",
        "aria-hidden": "true",
        width: "56",
        height: "56",
        viewBox: "0 0 56 56",
      },
    ]);
    expect(figures.map((f) => tags(f.querySelector("svg")))).toEqual([
      ["circle", "path"],
      ["circle", "path"],
    ]);
    expect(figures.map((f) => attrs(f.querySelector("svg circle")))).toEqual([
      { cx: "28", cy: "28", r: "28" },
      { cx: "28", cy: "28", r: "28" },
    ]);
    expect(figures.map((f) => attrs(f.querySelector("svg path")))).toEqual([
      { d: "M22 17v22l18-11z" },
      { d: "M22 17v22l18-11z" },
    ]);
    expect(figures.map((f) => attrs(f.children[1]))).toEqual([
      { "data-card-title": "", class: "type-card-title" },
      { "data-card-title": "", class: "type-card-title" },
    ]);
    expect(figures.map((f) => f.children[1]?.textContent)).toEqual(tied);
    expect(figures.map((f) => f.children[1]?.children.length)).toEqual([0, 0]);
    expect(
      Array.from(doc.querySelectorAll("img"), (i) => i.getAttribute("src")),
    ).toEqual([
      "/images/headshot-recorder.svg",
      "https://i.ytimg.com/vi/VdwOjCyVsSE/hqdefault.jpg",
      "https://i.ytimg.com/vi/DZA9Wi6KzWY/hqdefault.jpg",
    ]);
    expect(doc.querySelectorAll("iframe")).toHaveLength(0);
    expect(
      doc.querySelectorAll(
        '[src*="youtube.com"], [src*="youtube-nocookie.com"]',
      ),
    ).toHaveLength(0);
  });

  it("swaps only the clicked card's frame for its player, above the same caption", async () => {
    const { default: MediaPage } = await loadPage();
    render(<MediaPage />);
    const figures = (): Element[] =>
      Array.from(document.querySelectorAll("figure[data-video]"));
    const iframeAttrs = (
      id: string,
      title: string,
    ): Record<string, string> => ({
      "data-video-frame": "",
      src: `https://www.youtube-nocookie.com/embed/${id}?autoplay=1`,
      title,
      allow: ALLOW,
      allowfullscreen: "",
    });

    fireEvent.click(
      screen.getByRole("button", { name: `Play ${PASSACAILLE}` }),
    );
    const first = figures()[0];
    expect(tags(first)).toEqual(["IFRAME", "FIGCAPTION"]);
    expect(attrs(first?.children[0])).toEqual(
      iframeAttrs(IDS[0] ?? "", PASSACAILLE),
    );
    expect(tags(figures()[1])).toEqual(["BUTTON", "FIGCAPTION"]);
    expect(figures()[1]?.children[0]?.getAttribute("aria-label")).toBe(
      `Play ${BERGAMASCA}`,
    );
    expect(document.querySelectorAll("iframe")).toHaveLength(1);

    fireEvent.click(screen.getByRole("button", { name: `Play ${BERGAMASCA}` }));
    expect(tags(figures()[1])).toEqual(["IFRAME", "FIGCAPTION"]);
    expect(attrs(figures()[1]?.children[0])).toEqual(
      iframeAttrs(IDS[1] ?? "", BERGAMASCA),
    );
    expect(attrs(figures()[0]?.children[0])).toEqual(
      iframeAttrs(IDS[0] ?? "", PASSACAILLE),
    );
    expect(document.querySelectorAll("iframe")).toHaveLength(2);
    expect(document.querySelectorAll("figure[data-video] button")).toHaveLength(
      0,
    );
    expect(figures().map((f) => f.children[1]?.textContent)).toEqual([
      PASSACAILLE_TIED,
      BERGAMASCA_TIED,
    ]);
  });

  it("shows a named play button per video and no player before a click", async () => {
    const { default: MediaPage } = await loadPage();
    render(<MediaPage />);

    expect(document.querySelectorAll("iframe")).toHaveLength(0);
    expect(document.querySelectorAll('[src*="youtube"]')).toHaveLength(0);
    expect(screen.queryAllByRole("button")).toHaveLength(2);
    expect(
      screen.queryAllByRole("button", { name: `Play ${PASSACAILLE}` }),
    ).toHaveLength(1);
    expect(
      screen.queryAllByRole("button", { name: `Play ${BERGAMASCA}` }),
    ).toHaveLength(1);
  });

  it("clicking a play button swaps that card for its youtube-nocookie player", async () => {
    const { default: MediaPage } = await loadPage();
    render(<MediaPage />);

    const passacaille = {
      src: "https://www.youtube-nocookie.com/embed/VdwOjCyVsSE?autoplay=1",
      title: PASSACAILLE,
      allow: ALLOW,
      allowFullScreen: true,
    };
    fireEvent.click(
      screen.getByRole("button", { name: `Play ${PASSACAILLE}` }),
    );
    expect(iframesOf()).toEqual([passacaille]);
    expect(screen.queryAllByRole("button")).toHaveLength(1);
    expect(
      screen.queryAllByRole("button", { name: `Play ${BERGAMASCA}` }),
    ).toHaveLength(1);

    fireEvent.click(screen.getByRole("button", { name: `Play ${BERGAMASCA}` }));
    expect(iframesOf()).toEqual([
      passacaille,
      {
        src: "https://www.youtube-nocookie.com/embed/DZA9Wi6KzWY?autoplay=1",
        title: BERGAMASCA,
        allow: ALLOW,
        allowFullScreen: true,
      },
    ]);
    expect(screen.queryAllByRole("button")).toHaveLength(0);
  });

  it("lists the three recordings as plain Coming soon rows", async () => {
    const doc = await renderPage();
    const prose = doc.querySelector('[data-prose="start"]');
    const ul = prose?.children[0];
    const items = Array.from(ul?.children ?? []);

    expect(tags(prose)).toEqual(["UL", "P"]);
    expect(attrs(ul)).toEqual({ "data-rows": "", class: "type-list" });
    expect(tags(ul)).toEqual(["LI", "LI", "LI"]);
    expect(items.map(tags)).toEqual([
      ["SPAN", "SPAN"],
      ["SPAN", "SPAN"],
      ["SPAN", "SPAN"],
    ]);
    expect(items.map((li) => attrs(li.children[0]))).toEqual([{}, {}, {}]);
    expect(items.map((li) => li.children[0]?.textContent)).toEqual([
      "Brahms Clarinet Quintet, mvmt.\u00A03",
      "Brahms Clarinet Quintet, mvmt.\u00A04",
      "Chamber Music St. Louis radio broadcast, September\u00A02025",
    ]);
    expect(items.map((li) => attrs(li.children[1]))).toEqual([
      { "data-status": "" },
      { "data-status": "" },
      { "data-status": "" },
    ]);
    expect(items.map((li) => li.children[1]?.textContent)).toEqual([
      "Coming soon",
      "Coming soon",
      "Coming soon",
    ]);
    expect(items.map((li) => li.children[1]?.children.length)).toEqual([
      0, 0, 0,
    ]);
    expect(doc.body.textContent.split("Coming soon")).toHaveLength(4);
    expect(doc.querySelectorAll("audio")).toHaveLength(0);
  });

  it("links email in the Brahms line to Rachel's address", async () => {
    const doc = await renderPage();
    const p = doc.querySelector('[data-prose="start"]')?.children[1];
    const links = Array.from(doc.querySelectorAll("a"));

    expect(p?.tagName).toBe("P");
    expect(attrs(p)).toEqual({});
    expect(p?.textContent).toBe(
      "For access to the full Brahms Quintet performance, contact Rachel via\u00A0email.",
    );
    expect(tags(p)).toEqual(["A"]);
    expect(links).toHaveLength(1);
    expect(attrs(links[0])).toEqual({ href: "mailto:rachel@example.com" });
    expect(links[0]?.getAttribute("href")).toBe(`mailto:${siteConfig.email}`);
    expect(links[0]?.textContent).toBe("email");
    expect(links[0]?.parentElement).toBe(p);
    expect(links[0]?.nextSibling?.textContent).toBe(".");
  });

  it("has its own title and meta description", async () => {
    const { metadata } = await loadPage();

    expect(metadata).toStrictEqual({
      title: "Media",
      description:
        "Videos and recordings of Rachel Siegel's performances on recorder and clarinet, with her upcoming concerts.",
    });
  });

  it("shows the Upcoming strip below the media in its group's layout", async () => {
    const { default: MediaPage } = await loadPage();
    const doc = await toDoc(await UpcomingLayout({ children: <MediaPage /> }));
    const [media, strip] = Array.from(doc.body.children);

    expect(tags(doc.body)).toEqual(["SECTION", "SECTION"]);
    expect(attrs(media)).toEqual({
      "data-section": "",
      "aria-labelledby": "media-heading",
    });
    expect(attrs(strip)).toEqual({
      "data-section": "",
      "aria-labelledby": "upcoming-heading",
    });
    if (media === undefined || strip === undefined) {
      throw new Error("the layout rendered fewer than two sections");
    }
    expect(texts(media.querySelectorAll("h1"))).toEqual(["Media"]);
    expect(texts(media.querySelectorAll("h2"))).toEqual(["Video", "Audio"]);
    expect(texts(strip.querySelectorAll("h2"))).toEqual(["Upcoming"]);
    expect(texts(strip.querySelectorAll("p"))).toEqual([
      "Events are unavailable right now.",
      "See the full calendar",
    ]);
  });
});
