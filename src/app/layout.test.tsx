// @vitest-environment happy-dom
import { existsSync, readdirSync } from "node:fs";
import { text } from "node:stream/consumers";
import { join } from "node:path";
import localFont from "next/font/local";
import { prerender } from "react-dom/static";
import { afterEach, describe, expect, it, vi } from "vitest";
import RootLayout, { metadata } from "./layout";

vi.mock("next/font/local", () => ({
  default: vi.fn((options: { variable: string }) => ({
    className: "font-class",
    variable: `mock-${options.variable}`,
    style: { fontFamily: "mock" },
  })),
}));

// Vitest clears mock calls before each test, so keep what the layout passed
// to localFont when it was imported.
const fontOptions = vi.mocked(localFont).mock.calls.map(([options]) => options);

afterEach(() => {
  vi.useRealTimers();
});

async function renderPage(): Promise<Document> {
  const { prelude } = await prerender(
    <RootLayout params={Promise.resolve({})}>
      <p>page body</p>
    </RootLayout>,
  );
  const html = await text(prelude);
  return new DOMParser().parseFromString(html, "text/html");
}

describe("RootLayout", () => {
  it("wraps every page in the header and the footer", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2031-06-15T12:00:00Z"));

    const doc = await renderPage();

    expect(Array.from(doc.body.children).map((el) => el.tagName)).toEqual([
      "HEADER",
      "MAIN",
      "FOOTER",
    ]);
    const homeLinks = Array.from(doc.querySelectorAll("header a")).filter(
      (a) => a.textContent === "Rachel Siegel",
    );
    expect(homeLinks.map((a) => a.getAttribute("href"))).toEqual(["/"]);
    expect(doc.querySelector("main")?.textContent).toBe("page body");
    expect(doc.querySelector("footer")?.textContent).toBe(
      "© 2031 Rachel Siegel",
    );
  });

  it("loads only Fraunces from the local font files", async () => {
    expect(fontOptions).toStrictEqual([
      {
        src: [
          { path: "./fonts/Fraunces-Variable.ttf", style: "normal" },
          { path: "./fonts/Fraunces-Italic-Variable.ttf", style: "italic" },
        ],
        weight: "100 900",
        variable: "--font-fraunces",
        fallback: ["Georgia", "serif"],
        adjustFontFallback: "Times New Roman",
      },
    ]);

    const doc = await renderPage();

    expect(doc.documentElement.getAttribute("lang")).toBe("en");
    expect(doc.documentElement.getAttribute("class")).toBe(
      "mock---font-fraunces antialiased",
    );
  });

  it("leaves no Geist font file in src/app/fonts", () => {
    const fontsDir = join(import.meta.dirname, "fonts");

    expect(readdirSync(fontsDir).sort()).toEqual([
      "Fraunces-Italic-Variable.ttf",
      "Fraunces-OFL.txt",
      "Fraunces-Variable.ttf",
      "SourceSans3-Italic-Variable.ttf",
      "SourceSans3-OFL.txt",
      "SourceSans3-Variable.ttf",
    ]);
  });

  it("sets the title template and the description", () => {
    expect(metadata).toEqual({
      title: { default: "Rachel Siegel", template: "%s · Rachel Siegel" },
      description:
        "Rachel Siegel, licensed psychotherapist, clarinetist and recorder player.",
    });
  });

  it("leaves none of the scaffold's images in public", () => {
    const names = [
      "file.svg",
      "globe.svg",
      "next.svg",
      "vercel.svg",
      "window.svg",
    ];

    const remaining = names.filter((name) =>
      existsSync(join(import.meta.dirname, "..", "..", "public", name)),
    );

    expect(remaining).toEqual([]);
  });
});
