// @vitest-environment happy-dom
import { text } from "node:stream/consumers";
import { prerender } from "react-dom/static";
import { describe, expect, it } from "vitest";
import Home, { metadata } from "./page";

const NBSP = "\u00a0";

async function renderHome(): Promise<Document> {
  const { prelude } = await prerender(<Home />);
  const html = await text(prelude);
  return new DOMParser().parseFromString(html, "text/html");
}

function find(doc: Document, selector: string): Element | null {
  return doc.querySelector(selector);
}

function attrs(el: Element | null | undefined): Record<string, string> {
  return Object.fromEntries(
    Array.from(el?.attributes ?? []).map((attr) => [attr.name, attr.value]),
  );
}

function kids(el: Element | null | undefined): Element[] {
  return Array.from(el?.children ?? []);
}

function nth(
  el: Element | null | undefined,
  index: number,
): Element | undefined {
  return kids(el).at(index);
}

describe("Home", () => {
  it("shows the name as the only h1 with the tagline after it", async () => {
    const doc = await renderHome();
    const headings = [...doc.querySelectorAll("h1")].map((h) => h.textContent);
    expect(headings).toEqual(["Rachel Siegel"]);
    expect(doc.querySelector("h1 + p")?.textContent).toBe(
      `Licensed psychotherapist, clarinetist, recorder${NBSP}player`,
    );
  });

  it("holds only the hero's name, tagline and two buttons, with nothing before the name", async () => {
    const doc = await renderHome();
    expect(doc.body.textContent).toBe(
      `Rachel SiegelLicensed psychotherapist, clarinetist, recorder${NBSP}playerTherapyPerforming`,
    );
  });

  it("builds the hero as a bleeding Section of image, scrim and PageShell", async () => {
    const doc = await renderHome();
    const sections = [...doc.querySelectorAll("section")];
    const section = sections[0];
    const scrim = nth(section, 1);
    const shell = nth(section, 2);
    const heading = nth(shell, 0);
    const tagline = nth(shell, 1);

    expect(sections).toHaveLength(1);
    expect(attrs(section)).toEqual({
      "data-section": "",
      "data-bleed": "",
      "aria-labelledby": "hero-heading",
    });
    expect(kids(section).map((el) => el.tagName)).toEqual([
      "IMG",
      "DIV",
      "DIV",
    ]);
    expect(attrs(scrim)).toEqual({
      "data-hero-scrim": "",
      "aria-hidden": "true",
    });
    expect(kids(scrim)).toHaveLength(0);
    expect(attrs(shell)).toEqual({ "data-shell": "" });
    expect(kids(shell).map((el) => el.tagName)).toEqual(["H1", "P", "DIV"]);
    expect(attrs(heading)).toEqual({
      id: "hero-heading",
      class: "type-display",
    });
    expect(attrs(tagline)).toEqual({ class: "type-hero-tag" });
  });

  it("links Therapy and Performing as hero buttons in a centred Cluster", async () => {
    const doc = await renderHome();
    const cluster = nth(nth(find(doc, "section"), 2), 2);
    const buttons = kids(cluster).map((el) => ({
      tag: el.tagName,
      attrs: attrs(el),
      text: el.textContent,
    }));

    expect(attrs(cluster)).toEqual({ "data-cluster": "center" });
    expect(buttons).toEqual([
      {
        tag: "A",
        attrs: {
          "data-hero-button": "",
          class: "type-button",
          href: "/therapy/about",
        },
        text: "Therapy",
      },
      {
        tag: "A",
        attrs: {
          "data-hero-button": "",
          class: "type-button",
          href: "/performing/bio",
        },
        text: "Performing",
      },
    ]);
  });

  it("shows the hero image unblurred with its alt text and preloads it", async () => {
    const doc = await renderHome();
    const img = find(doc, "section img");
    const links = [...doc.querySelectorAll("link")].map((link) => ({
      rel: link.getAttribute("rel"),
      as: link.getAttribute("as"),
      imagesrcset: link.getAttribute("imagesrcset"),
    }));

    expect(attrs(img)).toEqual({
      alt: "Snow-capped mountains glowing pink at sunset above a still lake",
      width: "2600",
      height: "1736",
      decoding: "async",
      "data-nimg": "1",
      style: "color:transparent",
      src: "/_next/image?url=%2Fimages%2Fhero-mountain-lake.jpg&w=3840&q=75",
      srcset:
        "/_next/image?url=%2Fimages%2Fhero-mountain-lake.jpg&w=3840&q=75 1x",
    });
    expect(links).toEqual([
      {
        rel: "preload",
        as: "image",
        imagesrcset:
          "/_next/image?url=%2Fimages%2Fhero-mountain-lake.jpg&w=3840&q=75 1x",
      },
    ]);
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
        src: "/_next/image?url=%2Fimages%2Fhero-mountain-lake.jpg&w=3840&q=75",
        alt: "Snow-capped mountains glowing pink at sunset above a still lake",
        width: "2600",
        height: "1736",
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
