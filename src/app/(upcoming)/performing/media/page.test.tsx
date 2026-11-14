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

const ALLOW =
  "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share";
const PASSACAILLE = "“Passacaille” by Jacques-Martin Hotteterre";
const BERGAMASCA = "“Aria sopra La Bergamasca” by Marco Uccellini";

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

async function loadPage(): Promise<PageModule> {
  const load = pages["./page.tsx"];
  expect(load).toBeDefined();
  return load!();
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
  it("shows the Media heading, the recorder headshot and the Video and Audio sections", async () => {
    const doc = await renderPage();
    const h2s = Array.from(doc.querySelectorAll("h2"));

    expect(texts(doc.querySelectorAll("h1"))).toEqual(["Media"]);
    expect(
      Array.from(doc.querySelectorAll("img"), (img) => ({
        src: img.getAttribute("src"),
        alt: img.getAttribute("alt"),
        width: img.getAttribute("width"),
        height: img.getAttribute("height"),
      })),
    ).toEqual([
      {
        src: "/images/headshot-recorder.svg",
        alt: "Rachel Siegel holding a wooden recorder among pink cherry blossoms",
        width: "1471",
        height: "2048",
      },
    ]);
    expect(texts(h2s)).toEqual(["Video", "Audio"]);
    expect(h2s.map((h) => h.parentElement?.tagName)).toEqual([
      "SECTION",
      "SECTION",
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

  it("lists the three recordings as coming soon", async () => {
    const doc = await renderPage();
    const audio = Array.from(doc.querySelectorAll("h2"))
      .find((h) => h.textContent === "Audio")
      ?.closest("section");

    expect(audio).toBeTruthy();
    expect(
      Array.from(audio!.querySelectorAll("li"), (li) =>
        texts(Array.from(li.children)),
      ),
    ).toEqual([
      ["Brahms Clarinet Quintet, mvmt. 3", "Coming soon"],
      ["Brahms Clarinet Quintet, mvmt. 4", "Coming soon"],
      [
        "Chamber Music St. Louis radio broadcast, September 2025",
        "Coming soon",
      ],
    ]);
    expect(doc.querySelectorAll("audio")).toHaveLength(0);
  });

  it("links email in the Brahms line to Rachel's address", async () => {
    const doc = await renderPage();
    const audio = Array.from(doc.querySelectorAll("h2"))
      .find((h) => h.textContent === "Audio")
      ?.closest("section");
    const paragraphs = Array.from(audio!.querySelectorAll("p"));
    const links = Array.from(doc.querySelectorAll("a"));

    expect(texts(paragraphs)).toEqual([
      "For access to the full Brahms Quintet performance, contact Rachel via email.",
    ]);
    expect(
      links.map((a) => ({
        text: a.textContent,
        href: a.getAttribute("href"),
      })),
    ).toEqual([{ text: "email", href: "mailto:rachel@example.com" }]);
    expect(links[0]?.getAttribute("href")).toBe(`mailto:${siteConfig.email}`);
    expect(links[0]?.parentElement).toBe(paragraphs[0]);
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
    const [page, strip] = Array.from(doc.body.children);

    expect(Array.from(doc.body.children, (el) => el.tagName)).toEqual([
      "DIV",
      "SECTION",
    ]);
    expect(texts(page!.querySelectorAll("h1"))).toEqual(["Media"]);
    expect(texts(strip!.querySelectorAll("h2"))).toEqual(["Upcoming"]);
    expect(texts(strip!.querySelectorAll("p"))).toEqual([
      "Events are unavailable right now.",
      "See the full calendar",
    ]);
  });
});
