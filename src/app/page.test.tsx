// @vitest-environment happy-dom
import { text } from "node:stream/consumers";
import { prerender } from "react-dom/static";
import { describe, expect, it } from "vitest";
import Home, { metadata } from "./page";

async function renderHome(): Promise<Document> {
  const { prelude } = await prerender(<Home />);
  const html = await text(prelude);
  return new DOMParser().parseFromString(html, "text/html");
}

describe("Home", () => {
  it("shows the name as the only h1 with the tagline after it", async () => {
    const doc = await renderHome();
    const headings = [...doc.querySelectorAll("h1")].map((h) => h.textContent);
    expect(headings).toEqual(["Rachel Siegel"]);
    expect(doc.querySelector("h1 + p")?.textContent).toBe(
      "Licensed psychotherapist, clarinetist, recorder player",
    );
  });

  it("renders the hero-mountain-lake image as its only image", async () => {
    const doc = await renderHome();
    const imgs = [...doc.querySelectorAll("img")].map((img) => ({
      src: img.getAttribute("src"),
      alt: img.getAttribute("alt"),
      width: img.getAttribute("width"),
      height: img.getAttribute("height"),
    }));
    expect(imgs).toEqual([
      {
        src: "/images/hero-mountain-lake.svg",
        alt: "Snow-capped mountains glowing pink at sunset above a still lake",
        width: "1920",
        height: "1280",
      },
    ]);
  });

  it("has its own title and meta description", () => {
    expect(metadata).toStrictEqual({
      title: {
        absolute:
          "Rachel Siegel · Psychotherapist, clarinetist and recorder player",
      },
      description:
        "Rachel Siegel is a licensed psychotherapist, clarinetist and recorder player. Find her therapy practice, her performances and her upcoming concerts.",
    });
  });
});
