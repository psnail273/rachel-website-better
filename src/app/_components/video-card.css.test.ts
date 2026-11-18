import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const videoFile = join(import.meta.dirname, "video-card.css");
const css = existsSync(videoFile) ? readFileSync(videoFile, "utf8") : "";
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

const EASE = "150ms cubic-bezier(0.2, 0.7, 0.2, 1)";

function rule(selector: string, decls: Record<string, string>): Block {
  return { path: [selector], decls };
}

const EXPECTED_RULES: Block[] = [
  rule("[data-video-frame]", {
    position: "relative",
    display: "grid",
    "place-items": "center",
    "inline-size": "100%",
    "aspect-ratio": "16 / 9",
    padding: "0",
    border: "0",
    "border-radius": "var(--radius)",
    overflow: "hidden",
    background: "var(--poster)",
    cursor: "pointer",
  }),
  rule("[data-video-frame] > img", {
    position: "absolute",
    inset: "0",
    "inline-size": "100%",
    "block-size": "100%",
    "object-fit": "cover",
  }),
  rule("[data-play]", {
    position: "relative",
    "inline-size": "3.5rem",
    "block-size": "3.5rem",
    transition: `transform ${EASE}`,
  }),
  rule("[data-video-frame]:hover [data-play]", { transform: "scale(1.08)" }),
  rule("[data-play] circle", { fill: "rgb(36 18 28 / 0.72)" }),
  rule("[data-play] path", { fill: "var(--on-image)" }),
  rule("[data-video] figcaption", {
    "margin-block-start": "var(--space-tight)",
    color: "var(--heading)",
    "text-wrap": "balance",
    "overflow-wrap": "anywhere",
  }),
];

// Key order is part of the contract, so compare decls as ordered entries.
function ordered(entry: Block): { path: string[]; decls: [string, string][] } {
  return { path: entry.path, decls: Object.entries(entry.decls) };
}

describe("video card styles", () => {
  it("holds exactly the video card rules, in order", () => {
    expect(withDecls.map(ordered)).toEqual(EXPECTED_RULES.map(ordered));
    expect(withDecls).toHaveLength(7);
    expect(css).not.toContain("@layer");
  });

  it("is imported into Tailwind's components layer after the hero styles", () => {
    expect(globalsCss.split("\n").slice(0, 5)).toEqual([
      '@import "tailwindcss";',
      '@import "./_components/layout/styles.css" layer(components);',
      '@import "./_components/site-header.css" layer(components);',
      '@import "./_components/hero.css" layer(components);',
      '@import "./_components/video-card.css" layer(components);',
    ]);
  });
});
