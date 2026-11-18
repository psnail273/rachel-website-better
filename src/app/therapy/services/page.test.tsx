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
  return load();
}

async function renderPage(): Promise<Document> {
  const { default: ServicesPage } = await loadPage();
  const { prelude } = await prerender(<ServicesPage />);
  const html = await text(prelude);
  return new DOMParser().parseFromString(html, "text/html");
}

function texts(nodes: Iterable<Element>): string[] {
  return Array.from(nodes, (node) => node.textContent);
}

function sectionOf(doc: Document, index: number): Element | null {
  const h2 = doc.querySelectorAll("h2")[index];
  return h2.parentElement;
}

describe("ServicesPage", () => {
  it("shows the Services heading, the practice paragraph and the pull quote", async () => {
    const doc = await renderPage();

    expect(texts(doc.querySelectorAll("h1"))).toEqual(["Services"]);
    expect(doc.querySelector("p")?.textContent).toBe(
      "I provide individual therapy to adults and adolescents (aged 14 and up) through a group practice, Wellness Alliance Counseling and Psychotherapy. In-person therapy takes place at our office in Clayton, MO. For telehealth, clients must be in Missouri or Illinois.",
    );
    expect(doc.querySelectorAll("figure")).toHaveLength(1);
    expect(texts(doc.querySelectorAll("blockquote"))).toEqual([
      'And you may ask yourself, "Well, how did I get here?"',
    ]);
    expect(texts(doc.querySelectorAll("figcaption"))).toEqual([
      "— Talking Heads",
    ]);
  });

  it("lists what you might be struggling with and how therapy may help", async () => {
    const doc = await renderPage();

    expect(texts(doc.querySelectorAll("h2"))).toEqual([
      "You might be struggling with…",
      "Therapy may help you…",
      "A note on perfectionism…",
    ]);
    expect(doc.querySelectorAll("section")).toHaveLength(3);
    expect(doc.querySelectorAll("ul")).toHaveLength(3);
    expect(texts(sectionOf(doc, 0)?.querySelectorAll("ul > li") ?? [])).toEqual(
      [
        "Identity development",
        "Anxiety and stress management",
        "Maladaptive perfectionism",
        "Self-doubt and imposter syndrome",
        "Depression or burnout",
        "Disordered eating and body image concerns",
        "Work-life balance",
        "Relationship issues/setting boundaries",
      ],
    );
    expect(texts(sectionOf(doc, 1)?.querySelectorAll("ul > li") ?? [])).toEqual(
      [
        "Manage stress and anxiety",
        "Reframe unhelpful beliefs",
        "Develop greater self worth and self-confidence",
        "Cope with uncomfortable emotions and situations",
        "Increase compassion for yourself and others",
        "Develop self-care strategies",
        "Learn and set healthier boundaries in relationships and with work",
        "Move through creative or career blocks with clarity",
        "Explore identity outside of work/art/achievement",
        "Create work/performances that have meaning and purpose.",
      ],
    );
  });

  it("shows the note on perfectionism with its list", async () => {
    const doc = await renderPage();
    const section = sectionOf(doc, 2);
    const children = Array.from(section?.children ?? []);

    expect(children.map((child) => child.tagName)).toEqual([
      "H2",
      "P",
      "UL",
      "P",
    ]);
    expect(children[1]?.textContent).toBe(
      "Contrary to common belief, perfectionism usually doesn't help us achieve our goals. More often, it keeps us small, distracted by the fear of making a mistake or seeming messy. Perfectionism can cause:",
    );
    expect(texts(children[2]?.querySelectorAll("li") ?? [])).toEqual([
      "Procrastination",
      "Shame",
      "Shutting down when emotional",
      "Imposter syndrome",
      "Obsession with achievement",
      "Chronic stress and burnout",
      "Frequent and intense anxiety of being perceived negatively.",
    ]);
    expect(children[3]?.textContent).toBe(
      "What if you could let that all go, and still be successful, loved and accepted as you are?",
    );
  });

  it("has its own title and description and no prices or Upcoming strip", async () => {
    const { metadata } = await loadPage();
    const doc = await renderPage();
    const body = doc.body.textContent;

    expect(metadata).toStrictEqual({
      title: "Services",
      description:
        "Individual therapy for adults and adolescents in Clayton, MO, and by telehealth in Missouri and Illinois, with Rachel Siegel at Wellness Alliance Counseling and Psychotherapy.",
    });
    expect(body).not.toContain("$");
    expect(body).not.toMatch(/\bprices?\b/i);
    expect(body).not.toMatch(/\brates?\b/i);
    expect(body).not.toMatch(/\bfees?\b/i);
    expect(body).not.toMatch(/sliding scale/i);
    expect(body).not.toMatch(/insurance/i);
    expect(body).not.toMatch(/upcoming/i);
  });
});
