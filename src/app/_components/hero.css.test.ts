import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const heroFile = join(import.meta.dirname, "hero.css");
const css = existsSync(heroFile) ? readFileSync(heroFile, "utf8") : "";
const globalsCss = readFileSync(
  join(import.meta.dirname, "..", "globals.css"),
  "utf8",
);

type Block = { path: string[]; decls: Record<string, string> };

function collapse(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

function blocks(source: string): Block[] {
  const text = source.replace(/\/\*[\s\S]*?\*\//g, "");
  const stack: { index: number; prelude: string }[] = [];
  const found: (Block | undefined)[] = [];
  const declsByIndex = new Map<number, Record<string, string>>();
  let buffer = "";

  function declare(): void {
    const top = stack.at(-1);
    const colon = buffer.indexOf(":");
    if (top !== undefined && colon !== -1) {
      const name = collapse(buffer.slice(0, colon));
      const value = collapse(buffer.slice(colon + 1));
      const decls = declsByIndex.get(top.index) ?? {};
      decls[name] = value;
      declsByIndex.set(top.index, decls);
    }
    buffer = "";
  }

  for (const char of text) {
    if (char === "{") {
      stack.push({ index: found.length, prelude: collapse(buffer) });
      found.push(undefined);
      buffer = "";
    } else if (char === ";") {
      declare();
    } else if (char === "}") {
      declare();
      const top = stack.pop();
      if (top !== undefined) {
        found[top.index] = {
          path: [...stack.map((entry) => entry.prelude), top.prelude],
          decls: declsByIndex.get(top.index) ?? {},
        };
      }
    } else {
      buffer += char;
    }
  }
  return found.filter((entry): entry is Block => entry !== undefined);
}

const withDecls = blocks(css).filter(
  (entry) => Object.keys(entry.decls).length > 0,
);

const WIDE = "@media (width >= 30rem)";
const EASE = "150ms cubic-bezier(0.2, 0.7, 0.2, 1)";

function rule(selector: string, decls: Record<string, string>): Block {
  return { path: [selector], decls };
}

const EXPECTED_RULES: Block[] = [
  rule("[data-bleed]", {
    position: "relative",
    display: "flex",
    "inline-size": "100cqi",
    "min-block-size": "max(100svh, 34rem)",
    "margin-block-start": "calc(-1 * var(--header))",
    "margin-inline-start": "calc(50% - 50cqi)",
    "padding-block-start": "var(--header)",
    overflow: "hidden",
    background: "var(--plum)",
    color: "var(--on-image)",
    "--accent": "var(--on-image)",
  }),
  rule("[data-bleed] > img", {
    position: "absolute",
    inset: "0",
    "inline-size": "100%",
    "block-size": "100%",
    "object-fit": "cover",
    "object-position": "50% 55%",
  }),
  rule("[data-hero-scrim]", {
    position: "absolute",
    inset: "0",
    background:
      "radial-gradient(ellipse 75% 55% at 50% 52%, rgb(36 18 28 / 0.42), transparent 100%), linear-gradient(to bottom, rgb(36 18 28 / 0.6) 0%, rgb(36 18 28 / 0.3) 24%, rgb(36 18 28 / 0.3) 100%)",
  }),
  rule("[data-bleed] > [data-shell]", {
    position: "relative",
    display: "flex",
    "flex-direction": "column",
    "align-items": "center",
    "justify-content": "center",
    "padding-block": "var(--space-block)",
    "text-align": "center",
  }),
  rule("[data-bleed] h1", {
    color: "var(--on-image)",
    "text-wrap": "balance",
  }),
  rule("[data-bleed] h1 + p", {
    "margin-block-start": "var(--space-flow)",
    "text-wrap": "balance",
  }),
  rule("[data-bleed] [data-cluster]", {
    "align-self": "stretch",
    "margin-block-start": "var(--space-heading)",
  }),
  rule("[data-hero-button]", {
    display: "flex",
    flex: "1 1 0",
    "align-items": "center",
    "justify-content": "center",
    "max-inline-size": "12.5rem",
    "block-size": "3.5rem",
    border: "1px solid var(--on-image)",
    color: "var(--on-image)",
    transition: `background-color ${EASE}, color ${EASE}`,
  }),
  rule("[data-hero-button]:hover", {
    background: "var(--on-image)",
    color: "var(--plum)",
  }),
  { path: [WIDE, "[data-hero-button]"], decls: { flex: "0 0 12.5rem" } },
];

// Key order is part of the contract, so compare decls as ordered entries.
function ordered(entry: Block): { path: string[]; decls: [string, string][] } {
  return { path: entry.path, decls: Object.entries(entry.decls) };
}

describe("hero styles", () => {
  it("holds exactly the hero rules, in order", () => {
    expect(withDecls.map(ordered)).toEqual(EXPECTED_RULES.map(ordered));
    expect(withDecls).toHaveLength(10);
    expect(css).not.toContain("@layer");
  });

  it("is imported into Tailwind's components layer after the header styles", () => {
    expect(globalsCss.split("\n").slice(0, 4)).toEqual([
      '@import "tailwindcss";',
      '@import "./_components/layout/styles.css" layer(components);',
      '@import "./_components/site-header.css" layer(components);',
      '@import "./_components/hero.css" layer(components);',
    ]);
  });
});
