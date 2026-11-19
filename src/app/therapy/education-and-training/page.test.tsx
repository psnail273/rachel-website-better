// @vitest-environment happy-dom
import { text } from "node:stream/consumers";
import { prerender } from "react-dom/static";
import { describe, expect, it } from "vitest";
import EducationPage, { metadata } from "./page";

const CREDENTIALS = [
  "MSW, Master of Social Work — Saint Louis University",
  "MM, Music Performance — University of Southern California",
  "BM, Music Performance — University of Minnesota – Twin Cities",
  "Clarinet Performance, Rice University",
];
const TRAININGS = [
  "RO-DBT (Radically Open Dialectical Behavioral Therapy) Level 1",
  "Compassion Focused Therapy (Drs. Dennis Church and Paul Gilbert, Psychwire)",
  "Treating Adult ADHD (Margaret Dawson)",
  "Body Perfectionism: Innovative Tools from DBT, CBT, ACT ERP and More to Improve Self-Worth (Deanna Smith, PESI)",
  "Certification Training in DBT (Alexa Mulee,\u00a0C-\u2060DBT)",
  "Understanding Adolescent Eating Disorders: Foundations in Family-Based Treatment (Washington University, St. Louis)",
  "Shamelessly Imperfect: A guide to Help Your Clients Break Free from Perfectionism (Milly Feliz, PESI)",
  "ACT 2-Day Intensive (Dr. DJ Moran)",
  "Mindfulness Certification Course, 2-Day Intensive (Dr. Debra Premashakti Alvis)",
  "Food and Mood: A Therapist's Guide to the Role of Nutrition in Mental Health (Kathleen Zamperini)",
];
const H1_TEXT = "Education and Training";
const H2_TEXTS = ["Education & Credentials", "Specialized Training"];

async function renderPage(): Promise<Document> {
  const { prelude } = await prerender(<EducationPage />);
  const html = await text(prelude);
  return new DOMParser().parseFromString(html, "text/html");
}

function texts(nodes: Iterable<Element>): string[] {
  return Array.from(nodes, (node) => node.textContent);
}

function attrs(el: Element | null | undefined): Record<string, string> {
  return Object.fromEntries(
    Array.from(el?.attributes ?? [], (a) => [a.name, a.value]),
  );
}

describe("EducationPage", () => {
  it("shows the Education and Training heading first, with no label above it", async () => {
    const doc = await renderPage();
    const section = doc.body.children.item(0);
    const [h1, stack] = Array.from(section?.children ?? []);
    const classes = Array.from(
      doc.querySelectorAll("[class]"),
      (el) => el.getAttribute("class") ?? "",
    );
    const offenders = classes.filter((c) =>
      /self-center|max-w-|mx-auto/.test(c),
    );

    expect(doc.body.children).toHaveLength(1);
    expect(section?.tagName).toBe("SECTION");
    expect(attrs(section)).toEqual({
      "data-section": "",
      "aria-labelledby": "education-heading",
    });
    expect(section?.children).toHaveLength(2);
    expect(h1?.tagName).toBe("H1");
    expect(attrs(h1)).toEqual({
      "data-heading": "1",
      id: "education-heading",
      class: "type-h1",
    });
    expect(h1?.textContent).toBe(H1_TEXT);
    expect(stack?.tagName).toBe("DIV");
    expect(attrs(stack)).toEqual({ "data-stack": "block" });
    expect(doc.querySelectorAll("h1")).toHaveLength(1);
    expect(offenders).toEqual([]);
  });

  it("sets each heading beside its rows in a label switcher", async () => {
    const doc = await renderPage();
    const stack = doc.querySelector('div[data-stack="block"]');
    const switchers = Array.from(stack?.children ?? []);

    expect(switchers).toHaveLength(2);
    for (const sw of switchers) {
      const halves = Array.from(sw.children);
      expect(sw.tagName).toBe("DIV");
      expect(attrs(sw)).toEqual({ "data-switcher": "label" });
      expect(halves.map((h) => h.tagName)).toEqual(["DIV", "DIV"]);
      expect(halves.map((h) => attrs(h))).toEqual([{}, {}]);
      expect(attrs(halves[0]?.children.item(0))).toEqual({
        "data-heading": "2",
        class: "type-h2",
      });
      expect(halves[0]?.children).toHaveLength(1);
      expect(halves[0]?.children.item(0)?.tagName).toBe("H2");
      expect(halves[1]?.children).toHaveLength(1);
      expect(halves[1]?.children.item(0)?.tagName).toBe("UL");
      expect(attrs(halves[1]?.children.item(0))).toEqual({
        "data-rows": "",
        class: "type-list",
      });
    }
    expect(texts(doc.querySelectorAll("h2"))).toEqual(H2_TEXTS);
    expect(doc.querySelectorAll("ul")).toHaveLength(2);
    expect(doc.querySelectorAll("ol")).toHaveLength(0);
  });

  it("lists the four credentials and the ten trainings as rows of plain text", async () => {
    const doc = await renderPage();
    const lists = Array.from(doc.querySelectorAll("ul"));
    const items = Array.from(doc.querySelectorAll("li"));
    const problems = items.flatMap((li, index) => {
      const span = li.children.item(0);
      const found: string[] = [];
      if (li.attributes.length !== 0)
        found.push(`li ${String(index)} has attributes`);
      if (li.children.length !== 1)
        found.push(`li ${String(index)} child count`);
      if (span?.tagName !== "SPAN")
        found.push(`li ${String(index)} child not span`);
      if (span && span.attributes.length !== 0)
        found.push(`li ${String(index)} span has attributes`);
      if (span && span.children.length !== 0)
        found.push(`li ${String(index)} span has children`);
      return found;
    });

    expect(lists).toHaveLength(2);
    expect(texts(lists.at(0)?.querySelectorAll("li") ?? [])).toEqual(
      CREDENTIALS,
    );
    expect(texts(lists.at(1)?.querySelectorAll("li") ?? [])).toEqual(TRAININGS);
    expect(items).toHaveLength(14);
    expect(problems).toEqual([]);
  });

  it("has no links or buttons, no styling of its own, its own title and description, and no Upcoming strip", async () => {
    const doc = await renderPage();
    const classes = Array.from(doc.querySelectorAll("[class]"), (el) =>
      el.getAttribute("class"),
    );

    expect(
      doc.querySelectorAll("a, button, [role], [tabindex], [onclick]"),
    ).toHaveLength(0);
    expect(classes).toEqual([
      "type-h1",
      "type-h2",
      "type-list",
      "type-h2",
      "type-list",
    ]);
    expect(metadata).toStrictEqual({
      title: "Education and Training",
      description:
        "Rachel Siegel's education and training: a Master of Social Work from Saint Louis University, degrees in music performance, and specialized training in ACT, Compassion Focused Therapy, DBT and more.",
    });
    expect(doc.body.textContent).not.toMatch(/upcoming/i);
  });
});
