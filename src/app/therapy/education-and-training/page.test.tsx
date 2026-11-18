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
  const { default: EducationPage } = await loadPage();
  const { prelude } = await prerender(<EducationPage />);
  const html = await text(prelude);
  return new DOMParser().parseFromString(html, "text/html");
}

function texts(nodes: Iterable<Element>): string[] {
  return Array.from(nodes, (node) => node.textContent);
}

describe("EducationPage", () => {
  it("shows the Education and Training heading and the two list headings", async () => {
    const doc = await renderPage();
    const h2s = Array.from(doc.querySelectorAll("h2"));
    const uls = Array.from(doc.querySelectorAll("ul"));

    expect(texts(doc.querySelectorAll("h1"))).toEqual([
      "Education and Training",
    ]);
    expect(texts(h2s)).toEqual([
      "Education & Credentials",
      "Specialized Training",
    ]);
    expect(uls).toHaveLength(2);
    expect(doc.querySelectorAll("ol")).toHaveLength(0);
    expect(h2s[0]?.nextElementSibling).toBe(uls[0]);
    expect(h2s[1]?.nextElementSibling).toBe(uls[1]);
    expect(h2s[0]?.nextElementSibling?.tagName).toBe("UL");
    expect(h2s[1]?.nextElementSibling?.tagName).toBe("UL");
  });

  it("lists the four education entries", async () => {
    const doc = await renderPage();
    const list = doc.querySelectorAll("ul")[0];

    expect(list).toBeDefined();
    expect(texts(list.querySelectorAll("li"))).toEqual([
      "MSW, Master of Social Work — Saint Louis University",
      "MM, Music Performance — University of Southern California",
      "BM, Music Performance — University of Minnesota – Twin Cities",
      "Clarinet Performance, Rice University",
    ]);
  });

  it("lists the ten specialized trainings", async () => {
    const doc = await renderPage();
    const list = doc.querySelectorAll("ul")[1];

    expect(list).toBeDefined();
    expect(texts(list.querySelectorAll("li"))).toEqual([
      "RO-DBT (Radically Open Dialectical Behavioral Therapy) Level 1",
      "Compassion Focused Therapy (Drs. Dennis Church and Paul Gilbert, Psychwire)",
      "Treating Adult ADHD (Margaret Dawson)",
      "Body Perfectionism: Innovative Tools from DBT, CBT, ACT ERP and More to Improve Self-Worth (Deanna Smith, PESI)",
      "Certification Training in DBT (Alexa Mulee, C-DBT)",
      "Understanding Adolescent Eating Disorders: Foundations in Family-Based Treatment (Washington University, St. Louis)",
      "Shamelessly Imperfect: A guide to Help Your Clients Break Free from Perfectionism (Milly Feliz, PESI)",
      "ACT 2-Day Intensive (Dr. DJ Moran)",
      "Mindfulness Certification Course, 2-Day Intensive (Dr. Debra Premashakti Alvis)",
      "Food and Mood: A Therapist's Guide to the Role of Nutrition in Mental Health (Kathleen Zamperini)",
    ]);
  });

  it("has no links, its own title and description, and no Upcoming strip", async () => {
    const { metadata } = await loadPage();
    const doc = await renderPage();
    const items = Array.from(doc.querySelectorAll("li"));

    expect(doc.querySelectorAll("a, button")).toHaveLength(0);
    expect(items).toHaveLength(14);
    expect(items.map((li) => li.children.length)).toEqual(items.map(() => 0));
    expect(items.map((li) => li.hasAttribute("class"))).toEqual(
      items.map(() => false),
    );
    expect(metadata).toStrictEqual({
      title: "Education and Training",
      description:
        "Rachel Siegel's education and training: a Master of Social Work from Saint Louis University, degrees in music performance, and specialized training in ACT, Compassion Focused Therapy, DBT and more.",
    });
    expect(doc.body.textContent).not.toMatch(/upcoming/i);
  });
});
