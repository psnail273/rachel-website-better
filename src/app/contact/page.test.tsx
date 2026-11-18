// @vitest-environment happy-dom
import { text } from "node:stream/consumers";
import type { ReactElement } from "react";
import { prerender } from "react-dom/static";
import type { Metadata } from "next";
import { describe, expect, it } from "vitest";
import { siteConfig } from "@/lib/site-config";

type PageModule = { default: () => ReactElement; metadata: Metadata };

const pages = import.meta.glob<PageModule>("./page.tsx");

async function loadPage(): Promise<PageModule> {
  const load = pages["./page.tsx"];
  expect(load).toBeDefined();
  return load();
}

async function renderPage(): Promise<Document> {
  const { default: ContactPage } = await loadPage();
  const { prelude } = await prerender(<ContactPage />);
  const html = await text(prelude);
  return new DOMParser().parseFromString(html, "text/html");
}

function texts(nodes: Iterable<Element>): string[] {
  return Array.from(nodes, (node) => node.textContent);
}

describe("ContactPage", () => {
  it("shows the Contact heading and the two ways to get in touch", async () => {
    const doc = await renderPage();

    expect(texts(doc.querySelectorAll("h1"))).toEqual(["Contact"]);
    expect(texts(doc.querySelectorAll("p"))).toEqual([
      "For therapy, please reach out through Wellness Alliance.",
      "For performances, workshops or anything else, email me directly.",
    ]);
  });

  it("links Wellness Alliance in a new tab and the email as a mailto link", async () => {
    const doc = await renderPage();
    const links = Array.from(doc.querySelectorAll("a"));
    const paragraphs = Array.from(doc.querySelectorAll("p"));

    expect(
      links.map((a) => ({
        text: a.textContent,
        href: a.getAttribute("href"),
        target: a.getAttribute("target"),
        rel: a.getAttribute("rel"),
      })),
    ).toEqual([
      {
        text: "Wellness Alliance",
        href: "https://wellnessalliancestl.com/rsiegel",
        target: "_blank",
        rel: "noopener noreferrer",
      },
      {
        text: "email me directly",
        href: "mailto:rachel@example.com",
        target: null,
        rel: null,
      },
    ]);
    expect(paragraphs[0]?.contains(links[0] ?? null)).toBe(true);
    expect(paragraphs[1]?.contains(links[1] ?? null)).toBe(true);
    expect(links[0]?.getAttribute("href")).toBe(siteConfig.wellnessAllianceUrl);
    expect(links[1]?.getAttribute("href")).toBe(`mailto:${siteConfig.email}`);
  });

  it("has its own title and description, and no Upcoming strip", async () => {
    const { metadata } = await loadPage();
    const doc = await renderPage();

    expect(metadata).toStrictEqual({
      title: "Contact",
      description:
        "How to reach Rachel Siegel: therapy inquiries through Wellness Alliance, and email for performances, workshops and anything else.",
    });
    expect(doc.querySelectorAll("section, h2")).toHaveLength(0);
    expect(doc.body.textContent).not.toMatch(/upcoming/i);
  });
});
