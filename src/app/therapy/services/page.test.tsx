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

function texts(nodes: Iterable<Element> | undefined): string[] {
  return Array.from(nodes ?? [], (node) => node.textContent);
}

const NBSP = "\u00a0";
const ZWSP = "\u200b";
const WJ = "\u2060";
const EVERY = "[class], :not([class])";

function attrs(node: Element | null | undefined): Record<string, string> {
  return Object.fromEntries(
    Array.from(node?.attributes ?? [], (a) => [a.name, a.value]),
  );
}

function tags(nodes: Iterable<Element> | undefined): string[] {
  return Array.from(nodes ?? [], (node) => node.tagName);
}

function at(list: Element[], index: number): Element | undefined {
  return list.at(index);
}

function kid(node: Element | undefined, index: number): Element | undefined {
  return node ? Array.from(node.children).at(index) : undefined;
}

function section(doc: Document, index: number): Element | undefined {
  return kid(doc.body, index);
}

describe("ServicesPage", () => {
  it("shows the Services heading, the practice paragraph and the pull quote", async () => {
    const doc = await renderPage();
    const first = section(doc, 0);
    const sidebar = first?.children[0];
    const [head, body, slot] = Array.from(sidebar?.children ?? []);
    const h1 = kid(head, 0);
    const prose = kid(body, 0);
    const figure = kid(slot, 0);

    expect(tags(doc.body.children)).toEqual(["SECTION", "SECTION", "SECTION"]);
    expect(attrs(first)).toEqual({
      "data-section": "",
      "aria-labelledby": "services-heading",
    });
    expect(tags(first?.children ?? [])).toEqual(["DIV"]);
    expect(attrs(sidebar)).toEqual({ "data-sidebar": "trail" });
    expect(sidebar?.children).toHaveLength(3);
    expect(attrs(head)).toEqual({ "data-sidebar-head": "" });
    expect(attrs(body)).toEqual({ "data-sidebar-body": "" });
    expect(attrs(slot)).toEqual({ "data-sidebar-aside": "" });
    expect(head.children).toHaveLength(1);
    expect(h1?.tagName).toBe("H1");
    expect(attrs(h1)).toEqual({
      "data-heading": "1",
      id: "services-heading",
      class: "type-h1",
    });
    expect(h1?.textContent).toBe("Services");
    expect(doc.querySelectorAll("h1")).toHaveLength(1);
    expect(body.children).toHaveLength(1);
    expect(prose?.tagName).toBe("DIV");
    expect(attrs(prose)).toEqual({ "data-prose": "start" });
    expect(tags(prose?.children)).toEqual(["P"]);
    expect(kid(prose, 0)?.textContent).toBe(
      `I provide individual therapy to adults and adolescents (aged 14 and up) through a group practice, Wellness Alliance Counseling and Psychotherapy. In-person therapy takes place at our office in Clayton, MO. For telehealth, clients must be in Missouri or${NBSP}Illinois.`,
    );
    expect(slot.children).toHaveLength(1);
    expect(figure?.tagName).toBe("FIGURE");
    expect(attrs(figure)).toEqual({ "data-quote": "" });
    expect(tags(figure?.children)).toEqual(["BLOCKQUOTE", "FIGCAPTION"]);
    expect(attrs(kid(figure, 0))).toEqual({ class: "type-quote" });
    expect(kid(figure, 0)?.textContent).toBe(
      `And you may ask yourself, \u201cWell, how did I get${NBSP}here?\u201d`,
    );
    expect(attrs(kid(figure, 1))).toEqual({ class: "type-small" });
    expect(kid(figure, 1)?.textContent).toBe("Talking Heads");
    expect(doc.querySelectorAll("figure")).toHaveLength(1);
    expect(doc.querySelectorAll("blockquote")).toHaveLength(1);
  });

  it("lists what you might be struggling with and how therapy may help", async () => {
    const doc = await renderPage();
    const second = section(doc, 1);
    const pair = second?.children[0];
    const halves = Array.from(pair?.children ?? []);

    expect(texts(doc.querySelectorAll("h2"))).toEqual([
      `You might be struggling${NBSP}with…`,
      `Therapy may help${NBSP}you…`,
      `A note on${NBSP}perfectionism…`,
    ]);
    expect(attrs(second)).toEqual({
      "data-section": "",
      "aria-label": "What therapy can help with",
    });
    expect(tags(second?.children ?? [])).toEqual(["DIV"]);
    expect(attrs(pair)).toEqual({ "data-switcher": "pair" });
    expect(tags(halves)).toEqual(["DIV", "DIV"]);
    expect(halves.map((half) => attrs(half))).toEqual([{}, {}]);
    expect(halves.map((half) => tags(half.children))).toEqual([
      ["H2", "UL"],
      ["H2", "UL"],
    ]);
    expect(halves.map((half) => attrs(kid(half, 0)))).toEqual([
      { "data-heading": "2", class: "type-h2" },
      { "data-heading": "2", class: "type-h2" },
    ]);
    expect(halves.map((half) => attrs(kid(half, 1)))).toEqual([
      { "data-list": "plain", class: "type-list" },
      { "data-list": "plain", class: "type-list" },
    ]);
    expect(at(halves, 0)?.children[0]?.textContent).toBe(
      `You might be struggling${NBSP}with…`,
    );
    expect(texts(at(halves, 0)?.querySelectorAll("li") ?? [])).toEqual([
      `Identity development`,
      `Anxiety and stress${NBSP}management`,
      `Maladaptive perfectionism`,
      `Self-doubt and imposter${NBSP}syndrome`,
      `Depression${NBSP}or burnout`,
      `Disordered eating and body image${NBSP}concerns`,
      `Work-life balance`,
      `Relationship issues/${ZWSP}setting${NBSP}boundaries`,
    ]);
    expect(at(halves, 1)?.children[0]?.textContent).toBe(
      `Therapy may help${NBSP}you…`,
    );
    expect(texts(at(halves, 1)?.querySelectorAll("li") ?? [])).toEqual([
      `Manage stress and${NBSP}anxiety`,
      `Reframe${NBSP}unhelpful beliefs`,
      `Develop greater self worth and${NBSP}self-${WJ}confidence`,
      `Cope with uncomfortable emotions and${NBSP}situations`,
      `Increase compassion for yourself and${NBSP}others`,
      `Develop${NBSP}self-${WJ}care strategies`,
      `Learn and set healthier boundaries in relationships and with${NBSP}work`,
      `Move through creative or career blocks with${NBSP}clarity`,
      `Explore identity outside of work/${ZWSP}art/achievement`,
      `Create work/${ZWSP}performances that have meaning and${NBSP}purpose.`,
    ]);
  });

  it("shows the note on perfectionism with its list", async () => {
    const doc = await renderPage();
    const third = section(doc, 2);
    const h2 = kid(third, 0);
    const stack = kid(third, 1);
    const run = kid(stack, 0);
    const center = kid(stack, 1);
    const halves = Array.from(run?.children ?? []);
    const prose = at(halves, 0)?.children[0];
    const list = at(halves, 1)?.children[0];
    const lead = kid(center, 0);

    expect(attrs(third)).toEqual({
      "data-section": "",
      "aria-labelledby": "perfectionism-heading",
    });
    expect(tags(third?.children ?? [])).toEqual(["H2", "DIV"]);
    expect(attrs(h2)).toEqual({
      "data-heading": "2",
      id: "perfectionism-heading",
      class: "type-h2",
    });
    expect(h2?.textContent).toBe(`A note on${NBSP}perfectionism…`);
    expect(attrs(stack)).toEqual({ "data-stack": "block" });
    expect(tags(stack?.children)).toEqual(["DIV", "DIV"]);
    expect(attrs(run)).toEqual({ "data-switcher": "run" });
    expect(attrs(center)).toEqual({ "data-prose": "center" });
    expect(tags(halves)).toEqual(["DIV", "DIV"]);
    expect(halves.map((half) => attrs(half))).toEqual([{}, {}]);
    expect(at(halves, 0)?.children).toHaveLength(1);
    expect(attrs(prose)).toEqual({ "data-prose": "start" });
    expect(tags(prose?.children)).toEqual(["P"]);
    expect(kid(prose, 0)?.textContent).toBe(
      `Contrary to common belief, perfectionism usually doesn\u2019t help us achieve our goals. More often, it keeps us small, distracted by the fear of making a mistake or seeming messy. Perfectionism can${NBSP}cause:`,
    );
    expect(at(halves, 1)?.children).toHaveLength(1);
    expect(list?.tagName).toBe("UL");
    expect(attrs(list)).toEqual({ "data-list": "plain", class: "type-list" });
    expect(texts(list?.querySelectorAll("li"))).toEqual([
      `Procrastination`,
      `Shame`,
      `Shutting down when${NBSP}emotional`,
      `Imposter syndrome`,
      `Obsession${NBSP}with achievement`,
      `Chronic stress and${NBSP}burnout`,
      `Frequent and intense anxiety of being perceived${NBSP}negatively.`,
    ]);
    expect(center?.children).toHaveLength(1);
    expect(attrs(lead)).toEqual({ "data-lead": "", class: "type-lead" });
    expect(lead?.textContent).toBe(
      `What if you could let that all go, and still be successful, loved and accepted as you${NBSP}are?`,
    );
    expect(lead?.querySelector("svg")).toBeNull();
  });

  it("styles nothing as a callout box", async () => {
    const doc = await renderPage();
    const all = Array.from(doc.body.querySelectorAll(EVERY));
    const classes = new Set(all.flatMap((el) => Array.from(el.classList)));
    const aside = section(doc, 0)?.querySelector("[data-sidebar-aside]");

    expect(Array.from(classes).sort()).toEqual([
      "type-h1",
      "type-h2",
      "type-lead",
      "type-list",
      "type-quote",
      "type-small",
    ]);
    expect(doc.body.querySelectorAll("[style]")).toHaveLength(0);
    expect(doc.querySelectorAll('[data-list="panel"]')).toHaveLength(0);
    expect(doc.querySelectorAll("[data-quote]")).toHaveLength(1);
    expect(aside?.querySelectorAll("[data-quote]")).toHaveLength(1);
  });

  it("centres the closing question in its column", async () => {
    const doc = await renderPage();
    const leads = doc.querySelectorAll("[data-lead]");
    const lead = at(Array.from(leads), 0);
    const parent = lead?.parentElement;
    const stack = section(doc, 2)?.querySelector('[data-stack="block"]');
    const inSection = Array.from(
      section(doc, 2)?.querySelectorAll(EVERY) ?? [],
    );

    expect(leads).toHaveLength(1);
    expect(attrs(parent)).toEqual({ "data-prose": "center" });
    expect(stack?.lastElementChild).toBe(parent);
    expect(inSection.at(-1)).toBe(lead);
    expect(lead?.textContent).toBe(
      `What if you could let that all go, and still be successful, loved and accepted as you${NBSP}are?`,
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
