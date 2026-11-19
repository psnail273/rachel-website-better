// @vitest-environment happy-dom
import { text } from "node:stream/consumers";
import type { ReactElement } from "react";
import { prerender } from "react-dom/static";
import type { Metadata } from "next";
import { describe, expect, it } from "vitest";

type PageModule = { default: () => ReactElement; metadata: Metadata };

const pages = import.meta.glob<PageModule>("./page.tsx");

async function loadPage(): Promise<PageModule> {
  const load = pages["./page.tsx"];
  expect(load).toBeDefined();
  if (load === undefined) throw new Error("no ./page.tsx beside this test");
  return load();
}

async function renderPage(): Promise<Document> {
  const { default: AboutPage } = await loadPage();
  const { prelude } = await prerender(<AboutPage />);
  const html = await text(prelude);
  return new DOMParser().parseFromString(html, "text/html");
}

function texts(nodes: Iterable<Element>): string[] {
  return Array.from(nodes, (node) => node.textContent);
}

function child(
  el: Element | null | undefined,
  index: number,
): Element | undefined {
  return el?.children.item(index) ?? undefined;
}

function attrs(el: Element | null | undefined): Record<string, string> {
  return Object.fromEntries(
    Array.from(el?.attributes ?? []).map((attr) => [attr.name, attr.value]),
  );
}

function tags(el: Element | null | undefined): string[] {
  return Array.from(el?.children ?? [], (child) => child.tagName);
}

const LEAD =
  "I believe every person holds the power to transform their\u00a0life.";
const paragraphs = [
  "It is my honor to be a part of that journey, helping empower my clients with the tools they need to build a more connected, joyful, and meaningful\u00a0life.",
  "My background as a classical musician may, at first glance, appear to be unrelated to my work as a psychotherapist. But the insights I gained from this industry regarding self-inquiry, psychology, body awareness, and teamwork are highly applicable to therapeutic work and\u00a0growth.",
  "Because of this background, I am especially passionate about working with high-achieving adolescents and adults, especially those struggling with maladaptive perfectionism. I also specialize in several related concerns,\u00a0including:",
  "In my sessions, I combine a warm, empathetic approach with evidence-based strategies. I draw especially upon ACT (Acceptance & Commitment Therapy) and CFT (Compassion Focused Therapy), both of which can help you develop flexibility in the face of adversity and build an authentic, values-driven life. I believe compassion, vulnerability, and having a safe space to just \u201cbe\u201d are at the root of healing, and I look forward to providing that space for\u00a0you.",
];
const specialisations = [
  "Anxiety, chronic stress, and feeling constantly\u00a0\u201con\u201d",
  "Self-doubt and imposter\u00a0syndrome",
  "Identity development",
  "Depression\u00a0and burnout",
  "Work life balance/\u200brelationship\u00a0issues",
  "Eating and body image\u00a0concerns",
];

describe("AboutPage", () => {
  it("shows the About Me heading first in the photo page, with no label above it", async () => {
    const doc = await renderPage();
    const first = child(doc.body, 0);
    const lead = child(first, 0);
    const head = child(lead, 0);

    expect(doc.body.children).toHaveLength(2);
    expect(Array.from(doc.body.children, (c) => c.tagName)).toEqual([
      "SECTION",
      "SECTION",
    ]);
    expect(
      Array.from(doc.body.children, (c) => c.hasAttribute("data-section")),
    ).toEqual([true, true]);
    expect(doc.querySelectorAll("h1")).toHaveLength(1);
    const h1 = doc.querySelector("h1");
    expect(h1?.textContent).toBe("About Me");
    expect(attrs(h1)).toEqual({
      "data-heading": "1",
      id: "about-heading",
      class: "type-h1",
    });
    expect(attrs(first)).toEqual({
      "data-section": "",
      "aria-labelledby": "about-heading",
    });
    expect(first?.children).toHaveLength(1);
    expect(lead?.tagName).toBe("DIV");
    expect(lead?.getAttribute("data-sidebar")).toBe("lead");
    expect(head?.tagName).toBe("DIV");
    expect(head?.hasAttribute("data-sidebar-head")).toBe(true);
    expect(head?.children).toHaveLength(1);
    expect(child(head, 0)).toBe(h1);
    const offenders = Array.from(doc.querySelectorAll("[class]"))
      .filter((el) => /self-center|max-w-|mx-auto/.test(el.className))
      .map((el) => el.tagName);
    expect(offenders).toEqual([]);
  });

  it("shows the lead once, followed by the hairline", async () => {
    const doc = await renderPage();
    const body = doc.querySelector("[data-sidebar-body]");
    const stack = child(body, 0);
    const leadBox = child(stack, 0);
    const rule = child(leadBox, 1);

    expect(doc.querySelectorAll("[data-lead]")).toHaveLength(1);
    const lead = doc.querySelector("[data-lead]");
    expect(lead?.tagName).toBe("P");
    expect(lead?.getAttribute("class")).toBe("type-lead");
    expect(lead?.textContent).toBe(LEAD);
    expect(doc.body.textContent.split("I believe every person")).toHaveLength(
      2,
    );
    expect(body?.children).toHaveLength(1);
    expect(stack?.tagName).toBe("DIV");
    expect(attrs(stack)).toEqual({ "data-stack": "heading" });
    expect(stack?.children).toHaveLength(2);
    expect(leadBox?.tagName).toBe("DIV");
    expect(attrs(leadBox)).toEqual({});
    expect(leadBox?.children).toHaveLength(2);
    expect(child(leadBox, 0)).toBe(lead);
    expect(child(stack, 1)?.tagName).toBe("DIV");
    expect(attrs(child(stack, 1))).toEqual({ "data-prose": "start" });
    expect(rule?.tagName).toBe("DIV");
    expect(attrs(rule)).toEqual({ "data-rule": "", "aria-hidden": "true" });
    expect(rule?.children).toHaveLength(0);
    expect(doc.querySelectorAll("[data-rule]")).toHaveLength(1);
    expect(doc.querySelectorAll("svg circle")).toHaveLength(0);
  });

  it("sets the three paragraphs, the specialisations panel and the closing paragraph in one Prose", async () => {
    const doc = await renderPage();
    const prose = doc.querySelector('[data-prose="start"]');
    const children = Array.from(prose?.children ?? []);
    const list = doc.querySelector("ul");

    expect(tags(prose)).toEqual(["P", "P", "P", "UL", "P"]);
    expect(texts(children.filter((c) => c.tagName === "P"))).toEqual(
      paragraphs,
    );
    expect(doc.querySelectorAll("ul")).toHaveLength(1);
    expect(list?.parentElement).toBe(prose);
    expect(attrs(list)).toEqual({ "data-list": "panel", class: "type-list" });
    expect(texts(doc.querySelectorAll("li"))).toEqual(specialisations);
    expect(texts(doc.querySelectorAll("p"))).toEqual([LEAD, ...paragraphs]);
    expect(
      children.filter((c) => c.tagName === "P").map((c) => attrs(c)),
    ).toEqual([{}, {}, {}, {}]);
    expect(attrs(prose)).toEqual({ "data-prose": "start" });
    expect(attrs(doc.querySelector('[data-stack="heading"]'))).toEqual({
      "data-stack": "heading",
    });
  });

  it("sets the Rilke quote in a panel across the column", async () => {
    const doc = await renderPage();
    const section = child(doc.body, 1);
    const figure = child(section, 0);
    const caption = child(figure, 1);

    expect(attrs(section)).toEqual({
      "data-section": "",
      "aria-label": "A line from Rilke",
    });
    expect(section?.children).toHaveLength(1);
    expect(figure?.tagName).toBe("FIGURE");
    expect(figure?.hasAttribute("data-quote")).toBe(true);
    expect(tags(figure)).toEqual(["BLOCKQUOTE", "FIGCAPTION"]);
    expect(child(figure, 0)?.getAttribute("class")).toBe("type-quote");
    expect(caption?.getAttribute("class")).toBe("type-small");
    expect(child(figure, 0)?.textContent).toBe(
      "Let everything happen to you: beauty and terror. Just keep going. No feeling is\u00a0final.",
    );
    expect(caption?.textContent).toBe(
      "Rainer Maria Rilke, Letters to a Young\u00a0Poet",
    );
    expect(caption?.children).toHaveLength(1);
    expect(child(caption, 0)?.tagName).toBe("CITE");
    expect(child(caption, 0)?.textContent).toBe("Letters to a Young\u00a0Poet");
    expect(doc.querySelectorAll("figure")).toHaveLength(2);
  });

  it("puts the therapist headshot in the photo slot between the heading and the lead", async () => {
    const doc = await renderPage();
    const lead = doc.querySelector('[data-sidebar="lead"]');
    const aside = doc.querySelector("[data-sidebar-aside]");
    const figure = child(aside, 0);
    const imgs = doc.querySelectorAll("img");

    expect(
      Array.from(lead?.children ?? [], (c) =>
        c.hasAttribute("data-sidebar-head")
          ? "head"
          : c.hasAttribute("data-sidebar-aside")
            ? "aside"
            : c.hasAttribute("data-sidebar-body")
              ? "body"
              : "other",
      ),
    ).toEqual(["head", "aside", "body"]);
    expect(aside?.children).toHaveLength(1);
    expect(figure?.tagName).toBe("FIGURE");
    expect(figure?.hasAttribute("data-photo")).toBe(true);
    expect(figure?.children).toHaveLength(1);
    expect(child(figure, 0)?.tagName).toBe("IMG");
    expect(imgs).toHaveLength(1);
    expect(imgs[0]?.getAttribute("src")).toBe("/images/headshot-therapist.svg");
    expect(imgs[0]?.getAttribute("alt")).toBe(
      "Rachel Siegel in glasses and a navy tee, seated outdoors",
    );
    expect(imgs[0]?.getAttribute("width")).toBe("874");
    expect(imgs[0]?.getAttribute("height")).toBe("1184");
  });

  it("has its own title and description and no Upcoming strip", async () => {
    const doc = await renderPage();
    const { metadata } = await loadPage();

    expect(metadata).toStrictEqual({
      title: "About Me",
      description:
        "Rachel Siegel is a psychotherapist who works with high-achieving adolescents and adults on perfectionism, anxiety, imposter syndrome, identity and burnout, drawing on ACT and Compassion Focused Therapy.",
    });
    expect(doc.body.textContent).not.toMatch(/upcoming/i);
  });
});
