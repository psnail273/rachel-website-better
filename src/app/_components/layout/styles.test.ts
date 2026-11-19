import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const css = readFileSync(join(import.meta.dirname, "styles.css"), "utf8");
const globalsCss = readFileSync(
  join(import.meta.dirname, "..", "..", "globals.css"),
  "utf8",
);
const appDir = join(import.meta.dirname, "..", "..");

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

const allBlocks = blocks(css);
const withDecls = allBlocks.filter(
  (entry) => Object.keys(entry.decls).length > 0,
);

const NARROW = "@media (width < 40rem)";
const WIDE = "@media (width >= 40rem)";

function rule(selector: string, decls: Record<string, string>): Block {
  return { path: [selector], decls };
}

function inMedia(
  media: string,
  selector: string,
  decls: Record<string, string>,
): Block {
  return { path: [media, selector], decls };
}

const EXPECTED_RULES: Block[] = [
  rule("[data-shell]", {
    "inline-size": "100%",
    "max-inline-size": "var(--content-max)",
    "margin-inline": "auto",
    "padding-inline": "var(--gutter)",
  }),
  rule("main", {
    "container-type": "inline-size",
    "padding-block-start": "var(--space-heading)",
    "padding-block-end": "var(--space-section)",
    flex: "none",
  }),
  rule("body:has(> header[data-over-hero]) > main", {
    "padding-block-start": "0",
  }),
  rule("main > [data-shell]", {
    display: "flex",
    "flex-direction": "column",
    gap: "var(--space-section)",
  }),
  rule("body > footer", { flex: "1 0 auto" }),
  rule("[data-heading]", {
    "margin-block-end": "var(--space-heading)",
    "text-wrap": "balance",
    "overflow-wrap": "anywhere",
  }),
  rule("[data-stack]", { display: "flex", "flex-direction": "column" }),
  rule('[data-stack="block"]', { gap: "var(--space-block)" }),
  rule('[data-stack="heading"]', { gap: "var(--space-heading)" }),
  rule('[data-stack="flow"]', { gap: "var(--space-flow)" }),
  rule('[data-stack="tight"]', { gap: "var(--space-tight)" }),
  rule("[data-cluster]", {
    display: "flex",
    "flex-wrap": "wrap",
    gap: "var(--space-flow)",
  }),
  rule('[data-cluster="center"]', { "justify-content": "center" }),
  inMedia(NARROW, '[data-sidebar="lead"] > [data-sidebar-aside]', {
    "margin-block-end": "var(--space-heading)",
  }),
  inMedia(NARROW, '[data-sidebar="trail"] > [data-sidebar-aside]', {
    "margin-block-start": "var(--space-block)",
  }),
  inMedia(WIDE, "[data-sidebar]", {
    display: "grid",
    "grid-template-columns": "minmax(0, 1fr) var(--aside)",
    "grid-template-rows": "auto 1fr",
    "column-gap": "var(--space-block)",
  }),
  inMedia(WIDE, "[data-sidebar-head]", {
    "grid-column": "1",
    "grid-row": "1",
  }),
  inMedia(WIDE, "[data-sidebar-body]", {
    "grid-column": "1",
    "grid-row": "2",
  }),
  inMedia(WIDE, "[data-sidebar-aside]", {
    "grid-column": "2",
    "grid-row": "1 / span 2",
  }),
  inMedia(WIDE, "[data-sidebar-aside] > *", {
    position: "sticky",
    top: "calc(var(--header) + var(--space-flow))",
  }),
  rule("[data-switcher]", {
    display: "grid",
    "grid-template-columns":
      "repeat(auto-fit, minmax(min(100%, var(--switch-min)), 1fr))",
    "column-gap": "var(--space-block)",
  }),
  rule('[data-switcher="pair"]', { "row-gap": "var(--space-block)" }),
  rule('[data-switcher="run"]', { "row-gap": "var(--space-flow)" }),
  rule("[data-center]", {
    "inline-size": "100%",
    "max-inline-size": "var(--measure)",
    "margin-inline": "auto",
    "text-align": "center",
  }),
  rule("[data-prose]", { "max-inline-size": "var(--measure)" }),
  rule("[data-prose] > * + *", { "margin-block-start": "var(--space-flow)" }),
  rule("[data-prose] p", { "text-wrap": "wrap" }),
  rule('[data-prose="center"]', {
    "inline-size": "100%",
    "margin-inline": "auto",
    "text-align": "center",
  }),
  rule("[data-lead]", { color: "var(--heading)", "text-wrap": "wrap" }),
  rule("[data-lead] a", { "font-weight": "inherit", "white-space": "nowrap" }),
  rule("[data-rule]", {
    display: "block",
    "inline-size": "3.5rem",
    "block-size": "1px",
    "margin-block-start": "var(--space-flow)",
    background: "var(--ornament)",
  }),
  rule("[data-quote]", {
    "container-type": "inline-size",
    background: "var(--surface)",
    "border-radius": "var(--radius)",
    padding: "var(--space-block) var(--space-heading)",
    "text-align": "center",
  }),
  rule("[data-quote] blockquote", {
    "max-inline-size": "22ch",
    "margin-inline": "auto",
    color: "var(--heading)",
    "text-wrap": "balance",
    "overflow-wrap": "anywhere",
  }),
  rule("[data-quote] figcaption", {
    "margin-block-start": "var(--space-flow)",
    color: "var(--muted)",
    "text-wrap": "balance",
  }),
  rule("[data-quote] cite", {
    "font-style": "italic",
    "font-variation-settings": '"SOFT" 60, "WONK" 0',
  }),
  rule("[data-photo]", {
    padding: "var(--space-tight)",
    border: "1.5px solid var(--ornament)",
    "border-radius": "calc(var(--radius) + var(--space-tight))",
  }),
  rule("[data-photo] img", {
    "inline-size": "100%",
    "aspect-ratio": "3 / 4",
    "object-fit": "cover",
    "object-position": "50% 20%",
    "border-radius": "var(--radius)",
  }),
  rule("[data-list]", { display: "grid", gap: "var(--space-tight)" }),
  rule("[data-list] li", {
    position: "relative",
    "padding-inline-start": "var(--space-flow)",
    "text-wrap": "wrap",
    "overflow-wrap": "anywhere",
  }),
  rule("[data-list] li::before", {
    content: '""',
    position: "absolute",
    "inset-inline-start": "0",
    "inset-block-start": "0.42em",
    "inline-size": "0.625rem",
    "block-size": "0.625rem",
    border: "1.5px solid var(--accent)",
    "border-radius": "50%",
  }),
  rule('[data-list="panel"]', {
    background: "var(--tint)",
    padding: "var(--space-heading)",
    "border-radius": "var(--radius)",
    color: "var(--heading)",
  }),
  rule("[data-rows] li", {
    display: "flex",
    "flex-wrap": "wrap",
    "justify-content": "space-between",
    "column-gap": "var(--space-flow)",
    "padding-block": "var(--space-tight)",
    "border-block-start": "1px solid var(--line)",
    "text-wrap": "balance",
    "overflow-wrap": "anywhere",
  }),
  rule("[data-rows] li:last-child", {
    "border-block-end": "1px solid var(--line)",
  }),
  rule("[data-rows] [data-status]", {
    color: "var(--muted)",
    "white-space": "nowrap",
  }),
];

// Key order is part of the contract, so compare decls as ordered entries.
function ordered(entry: Block): { path: string[]; decls: [string, string][] } {
  return { path: entry.path, decls: Object.entries(entry.decls) };
}

function declsOf(selector: string): Record<string, string> | undefined {
  return allBlocks.find(
    (entry) => entry.path.length === 1 && entry.path[0] === selector,
  )?.decls;
}

function pageFiles(): string[] {
  return readdirSync(appDir, { recursive: true, encoding: "utf8" })
    .map((name) => name.replaceAll("\\", "/"))
    .filter(
      (name) =>
        name.endsWith(".tsx") &&
        !name.includes(".test.") &&
        !name.startsWith("_components/"),
    )
    .sort();
}

const SPACING_UTILITY =
  /(?<![\w-])!?-?(?:[mp](?:bs|be|[trblxyse])?|gap(?:-[xy])?|space-[xy])-[^\s"'`}]+/g;
const ARBITRARY_PROPERTY =
  /\[(?:margin|padding|gap|row-gap|column-gap)[\w-]*:/g;
const STYLE_PROPERTY =
  /\b(?:margin|padding|gap|rowGap|columnGap)(?:[A-Z]\w*)?\s*:/g;

describe("layout styles", () => {
  it("holds exactly the layout rules, in order", () => {
    expect(withDecls.map(ordered)).toEqual(EXPECTED_RULES.map(ordered));
    expect(withDecls).toHaveLength(44);
    expect(css).not.toContain("@layer");
  });

  it("is imported into Tailwind's components layer", () => {
    expect(globalsCss.split("\n").slice(0, 2)).toEqual([
      '@import "tailwindcss";',
      '@import "./_components/layout/styles.css" layer(components);',
    ]);
  });

  it("spaces main's sections with the section gap alone", () => {
    const sectionSelectors = allBlocks
      .filter((entry) => entry.path.join(" ").includes("data-section"))
      .map((entry) => entry.path.at(-1));

    expect(declsOf("main > [data-shell]")).toEqual({
      display: "flex",
      "flex-direction": "column",
      gap: "var(--space-section)",
    });
    expect(sectionSelectors).toEqual([]);
  });

  it("collapses Switcher to one column below --switch-min per half", () => {
    const switcher = declsOf("[data-switcher]");

    expect(switcher?.["grid-template-columns"]).toBe(
      "repeat(auto-fit, minmax(min(100%, var(--switch-min)), 1fr))",
    );
    expect(switcher?.["column-gap"]).toBe("var(--space-block)");
    expect(declsOf('[data-switcher="label"]')).toBeUndefined();
  });

  it("leaves every page's margins, paddings and gaps to the layout components", () => {
    const files = pageFiles();
    const found: { file: string; match: string }[] = [];
    for (const file of files) {
      const source = readFileSync(join(appDir, file), "utf8");
      for (const pattern of [
        SPACING_UTILITY,
        ARBITRARY_PROPERTY,
        STYLE_PROPERTY,
      ]) {
        for (const match of source.matchAll(pattern)) {
          found.push({ file, match: match[0] });
        }
      }
    }
    const spacing = [
      "mt-4",
      "md:mbe-2",
      "pbs-flow",
      "-mx-6",
      "gap-x-3",
      "space-y-8",
    ];
    const notSpacing = ["max-w-3xl", "items-center", "snap-x", "top-full"];

    expect(files).toEqual([
      "(upcoming)/layout.tsx",
      "(upcoming)/page.tsx",
      "(upcoming)/performing/bio/page.tsx",
      "(upcoming)/performing/media/page.tsx",
      "(upcoming)/performing/media/video-card.tsx",
      "contact/page.tsx",
      "layout.tsx",
      "not-found.tsx",
      "therapy/about/page.tsx",
      "therapy/education-and-training/page.tsx",
      "therapy/services/page.tsx",
    ]);
    expect(found).toEqual([]);
    expect(
      spacing.filter((sample) => sample.match(SPACING_UTILITY) === null),
    ).toEqual([]);
    expect(
      notSpacing.filter((sample) => sample.match(SPACING_UTILITY) !== null),
    ).toEqual([]);
    expect("[margin-top:1rem]".match(ARBITRARY_PROPERTY)).not.toBeNull();
    expect("paddingInline: 4".match(STYLE_PROPERTY)).not.toBeNull();
  });
});
