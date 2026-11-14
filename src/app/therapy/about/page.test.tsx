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
  return load!();
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

const paragraph1 =
  "I believe every person holds the power to transform their life. It is my honor to be a part of that journey, helping empower my clients with the tools they need to build a more connected, joyful, and meaningful life.";
const paragraph2 =
  "My background as a classical musician may, at first glance, appear to be unrelated to my work as a psychotherapist. But the insights I gained from this industry regarding self-inquiry, psychology, body awareness, and teamwork are highly applicable to therapeutic work and growth.";
const paragraph3 =
  "Because of this background, I am especially passionate about working with high-achieving adolescents and adults, especially those struggling with maladaptive perfectionism. I also specialize in several related concerns, including:";
const paragraph4 =
  'In my sessions, I combine a warm, empathetic approach with evidence-based strategies. I draw especially upon ACT (Acceptance & Commitment Therapy) and CFT (Compassion Focused Therapy), both of which can help you develop flexibility in the face of adversity and build an authentic, values-driven life. I believe compassion, vulnerability, and having a safe space to just "be" are at the root of healing, and I look forward to providing that space for you.';

describe("AboutPage", () => {
  it("shows the About Me heading and the copy", async () => {
    const doc = await renderPage();

    expect(texts(doc.querySelectorAll("h1"))).toEqual(["About Me"]);
    expect(texts(doc.querySelectorAll("p"))).toEqual([
      paragraph1,
      paragraph2,
      paragraph3,
      paragraph4,
    ]);
  });

  it("lists the six specialties between the third and fourth paragraphs", async () => {
    const doc = await renderPage();
    const list = doc.querySelector("ul");

    expect(doc.querySelectorAll("ul")).toHaveLength(1);
    expect(texts(doc.querySelectorAll("li"))).toEqual([
      'Anxiety, chronic stress, and feeling constantly "on"',
      "Self-doubt and imposter syndrome",
      "Identity development",
      "Depression and burnout",
      "Work life balance/relationship issues",
      "Eating and body image concerns",
    ]);
    expect(list?.previousElementSibling?.tagName).toBe("P");
    expect(list?.previousElementSibling?.textContent).toBe(paragraph3);
    expect(list?.nextElementSibling?.tagName).toBe("P");
    expect(list?.nextElementSibling?.textContent).toBe(paragraph4);
  });

  it("shows the Rilke quote and the small headshot", async () => {
    const doc = await renderPage();
    const caption = doc.querySelector("figcaption");
    const imgs = doc.querySelectorAll("img");

    expect(doc.querySelectorAll("figure")).toHaveLength(1);
    expect(texts(doc.querySelectorAll("blockquote"))).toEqual([
      "Let everything happen to you: beauty and terror. Just keep going. No feeling is final.",
    ]);
    expect(texts(doc.querySelectorAll("figcaption"))).toEqual([
      "— Rainer Maria Rilke, Letters to a Young Poet",
    ]);
    expect(texts(doc.querySelectorAll("cite"))).toEqual([
      "Letters to a Young Poet",
    ]);
    expect(doc.querySelector("cite")?.parentElement).toBe(caption);
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
