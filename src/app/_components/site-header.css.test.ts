import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const css = readFileSync(join(import.meta.dirname, "site-header.css"), "utf8");
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

const WIDE = "@media (width >= 48rem)";
const EASE = "200ms cubic-bezier(0.2, 0.7, 0.2, 1)";
const HERO_HEADER =
  "body:has(> main [data-bleed]) > header:not([data-scrolled])";

function rule(selector: string, decls: Record<string, string>): Block {
  return { path: [selector], decls };
}

const EXPECTED_RULES: Block[] = [
  rule("[data-skip-link]", {
    position: "fixed",
    top: "1rem",
    left: "1rem",
    "z-index": "60",
    display: "flex",
    "align-items": "center",
    "block-size": "3rem",
    "padding-inline": "var(--space-flow)",
    background: "var(--heading)",
    color: "var(--bg)",
    "font-size": "1rem",
    "font-weight": "500",
    "line-height": "1",
  }),
  rule("[data-skip-link]:not(:focus)", { translate: "0 -5rem" }),
  rule("body > header", {
    position: "sticky",
    top: "0",
    "z-index": "50",
    display: "flex",
    "align-items": "center",
    "block-size": "var(--header)",
    color: "var(--heading)",
    transition: `background-color ${EASE}, color ${EASE}`,
  }),
  rule("body > header[data-scrolled]", {
    background: "rgb(from var(--bg) r g b / 0.92)",
    "backdrop-filter": "blur(12px)",
    "box-shadow": "0 1px 0 var(--line)",
  }),
  rule(HERO_HEADER, { color: "var(--on-image)" }),
  rule(`${HERO_HEADER} :is([data-brand], [data-nav-tab])`, {
    "--accent": "var(--on-image)",
  }),
  rule("body > header > [data-shell]", {
    display: "flex",
    "align-items": "center",
    "justify-content": "space-between",
  }),
  rule("[data-nav]", { display: "none" }),
  {
    path: [WIDE, "[data-nav]"],
    decls: {
      display: "flex",
      "align-items": "center",
      gap: "var(--space-heading)",
    },
  },
  rule("[data-dropdown]", { position: "relative" }),
  rule("[data-nav-tab]", {
    display: "flex",
    "align-items": "center",
    gap: "0.375rem",
    "min-block-size": "2.75rem",
    cursor: "pointer",
  }),
  rule("[data-nav-label]", { "text-underline-offset": "0.3rem" }),
  rule("[data-nav-tab]:hover [data-nav-label]", {
    "text-decoration": "underline 1px currentColor",
  }),
  rule("[data-nav-tab][aria-current] [data-nav-label]", {
    "text-decoration": "underline 2px var(--accent)",
  }),
  rule("[data-chevron]", { opacity: "0.8" }),
  rule("[data-dropdown-panel]", {
    position: "absolute",
    top: "100%",
    right: "0",
    "z-index": "10",
    "inline-size": "15rem",
    padding: "0",
    border: "1px solid var(--line-strong)",
    background: "var(--surface)",
  }),
  rule("[data-dropdown-panel] a", {
    display: "flex",
    "align-items": "center",
    "block-size": "2.75rem",
    "padding-inline": "var(--space-flow)",
    color: "var(--ink)",
    "white-space": "nowrap",
  }),
  rule("[data-dropdown-panel] a:hover", {
    background: "var(--tint)",
    color: "var(--heading)",
  }),
  rule('[data-dropdown-panel] a[aria-current="page"]', {
    color: "var(--heading)",
    "text-decoration": "underline 2px var(--accent)",
    "text-underline-offset": "0.35em",
  }),
  rule("[data-dropdown-panel] a:focus-visible", { "outline-offset": "-3px" }),
];

// Key order is part of the contract, so compare decls as ordered entries.
function ordered(entry: Block): { path: string[]; decls: [string, string][] } {
  return { path: entry.path, decls: Object.entries(entry.decls) };
}

describe("header styles", () => {
  it("holds exactly the header rules, in order", () => {
    expect(withDecls.map(ordered)).toEqual(EXPECTED_RULES.map(ordered));
    expect(withDecls).toHaveLength(20);
    expect(css).not.toContain("@layer");
  });

  it("is imported into Tailwind's components layer after the layout styles", () => {
    expect(globalsCss.split("\n").slice(0, 3)).toEqual([
      '@import "tailwindcss";',
      '@import "./_components/layout/styles.css" layer(components);',
      '@import "./_components/site-header.css" layer(components);',
    ]);
  });
});
