import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const css = readFileSync(join(import.meta.dirname, "globals.css"), "utf8");
const srcDir = join(import.meta.dirname, "..");
const appDir = import.meta.dirname;

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

function block(path: string[]): Record<string, string> | undefined {
  return allBlocks.find(
    (entry) =>
      entry.path.length === path.length &&
      entry.path.every((part, i) => part === path[i]),
  )?.decls;
}

function entriesOf(path: string[]): [string, string][] {
  return Object.entries(block(path) ?? {});
}

function sourceFiles(dir: string, extensions: string[]): string[] {
  return readdirSync(dir, { recursive: true, encoding: "utf8" })
    .filter(
      (name) =>
        extensions.some((ext) => name.endsWith(ext)) &&
        !name.includes(".test."),
    )
    .sort();
}

const COLOR_TOKENS = [
  "bg",
  "surface",
  "tint",
  "ink",
  "heading",
  "muted",
  "link",
  "accent",
  "error",
  "ornament",
  "line",
  "line-strong",
  "band",
  "on-band",
  "on-band-muted",
  "band-accent",
  "plum",
  "on-image",
  "poster",
];

const ROOT_COLORS: [string, string][] = [
  ["--bg", "light-dark(#f6e4e6, #24131c)"],
  ["--surface", "light-dark(#fbf3f3, #2f1b26)"],
  ["--tint", "light-dark(#eed3d7, #3d2431)"],
  ["--ink", "light-dark(#3b2530, #eadfd9)"],
  ["--heading", "light-dark(#2a1420, #f7eee9)"],
  ["--muted", "light-dark(#6a525d, #c6b3ba)"],
  ["--link", "light-dark(#75203f, #f7dce4)"],
  ["--accent", "light-dark(#853a62, #f2abbe)"],
  ["--error", "light-dark(#8f1836, #ffb4c0)"],
  ["--ornament", "light-dark(#c98aa6, #8b5a72)"],
  ["--line", "light-dark(#e3c9ce, #42293a)"],
  ["--line-strong", "light-dark(#8f7480, #a78895)"],
  ["--band", "light-dark(#47172f, #47172f)"],
  ["--on-band", "light-dark(#f8eee9, #f8eee9)"],
  ["--on-band-muted", "light-dark(#dcc5cd, #dcc5cd)"],
  ["--band-accent", "light-dark(#f2abbe, #f2abbe)"],
  ["--plum", "light-dark(#24121c, #24121c)"],
  ["--on-image", "light-dark(#f8eee9, #f8eee9)"],
  ["--poster", "light-dark(#47172f, #47172f)"],
];

const LAYOUT_TOKENS: [string, string][] = [
  ["--content-max", "78rem"],
  ["--gutter", "clamp(1.25rem, 0.5rem + 3.2vw, 3rem)"],
  ["--measure", "65ch"],
  ["--aside", "clamp(15rem, 34%, 24rem)"],
  ["--switch-min", "18rem"],
  ["--space-section", "clamp(4rem, 2.5rem + 6vw, 7.5rem)"],
  ["--space-block", "clamp(2rem, 1.5rem + 2.2vw, 3.5rem)"],
  ["--space-heading", "clamp(1.5rem, 1.25rem + 1vw, 2rem)"],
  ["--space-flow", "1.25rem"],
  ["--space-tight", "0.75rem"],
  ["--header", "4.5rem"],
  ["--radius", "1rem"],
  ["--radius-card", "0"],
];

const SPACE_NAMES = ["section", "block", "heading", "flow", "tight"];

// fg, bg, light ratio, dark ratio: copied from docs/design.md section 1.
const PAIRS: [string, string, number, number][] = [
  ["ink", "bg", 11.5, 13.5],
  ["ink", "surface", 12.9, 12.3],
  ["ink", "tint", 10.0, 10.7],
  ["heading", "bg", 14.1, 15.5],
  ["heading", "surface", 15.8, 14.1],
  ["heading", "tint", 12.2, 12.3],
  ["muted", "bg", 5.8, 8.9],
  ["muted", "surface", 6.5, 8.1],
  ["link", "bg", 8.4, 13.8],
  ["link", "surface", 9.4, 12.5],
  ["accent", "bg", 6.2, 9.6],
  ["accent", "surface", 6.9, 8.7],
  ["accent", "tint", 5.4, 7.6],
  ["error", "bg", 7.3, 10.6],
  ["error", "surface", 8.2, 9.6],
  ["bg", "heading", 14.1, 15.5],
  ["on-band", "band", 12.9, 12.9],
  ["on-band-muted", "band", 9.0, 9.0],
  ["band-accent", "band", 7.9, 7.9],
  ["on-image", "plum", 15.6, 15.6],
  ["line-strong", "bg", 3.4, 5.6],
  ["line-strong", "surface", 3.9, 5.1],
];

type Mode = "light" | "dark";

function palette(token: string): { light: string; dark: string } | null {
  const value = block([":root"])?.[`--${token}`];
  const match = /^light-dark\((#[0-9a-f]{6}), (#[0-9a-f]{6})\)$/i.exec(
    value ?? "",
  );
  const light = match?.[1];
  const dark = match?.[2];
  if (light === undefined || dark === undefined) return null;
  return { light, dark };
}

function luminance(hex: string): number {
  const channel = (start: number): number => {
    const c = parseInt(hex.slice(start, start + 2), 16) / 255;
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5);
}

function ratio(fg: string, bg: string, mode: Mode): number | null {
  const front = palette(fg)?.[mode];
  const back = palette(bg)?.[mode];
  if (front === undefined || back === undefined) return null;
  const [a, b] = [luminance(front), luminance(back)];
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

function hue(hex: string): number | null {
  const [r, g, b] = [1, 3, 5].map(
    (i) => parseInt(hex.slice(i, i + 2), 16) / 255,
  );
  if (r === undefined || g === undefined || b === undefined) return null;
  const max = Math.max(r, g, b);
  const d = max - Math.min(r, g, b);
  if (d === 0) return null;
  let h: number;
  if (max === r) h = ((g - b) / d) % 6;
  else if (max === g) h = (b - r) / d + 2;
  else h = (r - g) / d + 4;
  return (h * 60 + 360) % 360;
}

function round1(value: number | null): number | null {
  return value === null ? null : Math.round(value * 10) / 10;
}

type Role = {
  name: string;
  size: string;
  style: string;
  weight: string;
  axes: string;
  line: string;
  tracking: string;
  extra?: [string, string];
};

const BODY_SIZE = "clamp(1.0625rem, 1rem + 0.3vw, 1.1875rem)";
const SOFT_100 = '"SOFT" 100';
const SOFT_60 = '"SOFT" 60';

const ROLES: Role[] = [
  {
    name: "display",
    size: "clamp(3.75rem, 1.5rem + 9.4vw, 9.5rem)",
    style: "italic",
    weight: "380",
    axes: '"SOFT" 0, "WONK" 0',
    line: "0.92",
    tracking: "-0.035em",
  },
  {
    name: "h1",
    size: "clamp(3rem, 1.7rem + 5.4vw, 6rem)",
    style: "normal",
    weight: "300",
    axes: '"SOFT" 100, "WONK" 1',
    line: "1",
    tracking: "-0.03em",
  },
  {
    name: "h2",
    size: "clamp(1.75rem, 1.3rem + 1.9vw, 2.5rem)",
    style: "normal",
    weight: "350",
    axes: '"SOFT" 0, "WONK" 0',
    line: "1.1",
    tracking: "-0.02em",
  },
  {
    name: "lead",
    size: "clamp(1.375rem, 1.15rem + 1vw, 2rem)",
    style: "italic",
    weight: "380",
    axes: '"SOFT" 0, "WONK" 0',
    line: "1.3",
    tracking: "0",
  },
  {
    name: "quote",
    size: "clamp(1.5rem, 1.1rem + 3.2cqi, 3rem)",
    style: "italic",
    weight: "380",
    axes: '"SOFT" 0, "WONK" 0',
    line: "1.14",
    tracking: "-0.02em",
  },
  {
    name: "body",
    size: BODY_SIZE,
    style: "normal",
    weight: "400",
    axes: SOFT_60,
    line: "1.7",
    tracking: "0",
  },
  {
    name: "list",
    size: BODY_SIZE,
    style: "normal",
    weight: "400",
    axes: SOFT_60,
    line: "1.4",
    tracking: "0",
  },
  {
    name: "card-title",
    size: "1.25rem",
    style: "normal",
    weight: "500",
    axes: SOFT_60,
    line: "1.25",
    tracking: "0",
  },
  {
    name: "event-date",
    size: "1.875rem",
    style: "normal",
    weight: "300",
    axes: SOFT_100,
    line: "1.1",
    tracking: "0",
    extra: ["font-variant-numeric", "lining-nums"],
  },
  {
    name: "hero-tag",
    size: "clamp(1.1875rem, 1.05rem + 0.6vw, 1.5rem)",
    style: "normal",
    weight: "400",
    axes: SOFT_60,
    line: "1.4",
    tracking: "0",
  },
  {
    name: "button",
    size: "1.25rem",
    style: "normal",
    weight: "500",
    axes: SOFT_60,
    line: "1",
    tracking: "0",
  },
  {
    name: "brand",
    size: "1.375rem",
    style: "italic",
    weight: "500",
    axes: '"SOFT" 0, "WONK" 0',
    line: "1",
    tracking: "0",
  },
  {
    name: "nav",
    size: "1rem",
    style: "normal",
    weight: "500",
    axes: SOFT_60,
    line: "1",
    tracking: "0",
  },
  {
    name: "nav-item",
    size: "1rem",
    style: "normal",
    weight: "400",
    axes: SOFT_60,
    line: "1",
    tracking: "0",
  },
  {
    name: "sheet-link",
    size: "2rem",
    style: "normal",
    weight: "300",
    axes: SOFT_100,
    line: "1.1",
    tracking: "0",
  },
  {
    name: "label",
    size: "1.0625rem",
    style: "normal",
    weight: "500",
    axes: '"SOFT" 60, "WONK" 0',
    line: "1.3",
    tracking: "0",
  },
  {
    name: "footer-name",
    size: "clamp(2.5rem, 1.8rem + 3vw, 4rem)",
    style: "italic",
    weight: "380",
    axes: '"SOFT" 0, "WONK" 0',
    line: "1",
    tracking: "-0.03em",
  },
  {
    name: "small",
    size: "1rem",
    style: "normal",
    weight: "400",
    axes: SOFT_60,
    line: "1.4",
    tracking: "0",
  },
];

function roleEntries(role: Role): [string, string][] {
  const base: [string, string][] = [
    ["font-size", role.size],
    ["font-style", role.style],
    ["font-weight", role.weight],
    ["font-variation-settings", role.axes],
    ["line-height", role.line],
    ["letter-spacing", role.tracking],
  ];
  return role.extra === undefined ? base : [...base, role.extra];
}

const FAMILY = "var(--font-fraunces), Georgia, serif";

describe("design tokens", () => {
  it("meets each ratio-table minimum in both palettes", () => {
    const measured = PAIRS.map(([fg, bg]) => ({
      pair: `${fg} on ${bg}`,
      light: round1(ratio(fg, bg, "light")),
      dark: round1(ratio(fg, bg, "dark")),
    }));
    const expected = PAIRS.map(([fg, bg, light, dark]) => ({
      pair: `${fg} on ${bg}`,
      light,
      dark,
    }));

    const belowMinimum = PAIRS.flatMap(([fg, bg]) =>
      (["light", "dark"] as const).flatMap((mode) => {
        const minimum = fg === "line-strong" ? 3 : 4.5;
        const value = ratio(fg, bg, mode);
        return value === null || value < minimum
          ? [
              `${fg} on ${bg} (${mode}): ${String(value)} under ${String(minimum)}`,
            ]
          : [];
      }),
    );

    expect(measured).toEqual(expected);
    expect(belowMinimum).toEqual([]);
  });

  it("defines every colour token with its light and dark value", () => {
    const rootColors = entriesOf([":root"]).filter(([, value]) =>
      value.startsWith("light-dark("),
    );
    const themeColors = entriesOf(["@theme inline"]).filter(([name]) =>
      name.startsWith("--color-"),
    );
    const expectedTheme = COLOR_TOKENS.map((token): [string, string] => [
      `--color-${token}`,
      `var(--${token})`,
    ]);

    expect(Object.fromEntries(rootColors)).toEqual(
      Object.fromEntries(ROOT_COLORS),
    );
    expect(rootColors).toEqual(ROOT_COLORS);
    expect(themeColors).toEqual(expectedTheme);
  });

  it("resolves no colour token to a green hue", () => {
    const greens = COLOR_TOKENS.flatMap((token) => {
      const colors = palette(token);
      if (colors === null) return [`${token}: does not parse`];
      return (["light", "dark"] as const).flatMap((mode) => {
        const h = hue(colors[mode]);
        return h !== null && h >= 60 && h <= 180
          ? [`${token} (${mode}): ${String(Math.round(h))} degrees`]
          : [];
      });
    });
    const oldValues = [
      "#1f4a3a",
      "#2b6044",
      "#1f3a30",
      "#17302a",
      "#1e3b33",
      "#27483f",
      "#5e8a6f",
      "#c5d3c9",
      "#0f231d",
      "#2c4a41",
      "#7fa091",
      "#b9c4bc",
    ].filter((value) => css.toLowerCase().includes(value));

    expect(greens).toEqual([]);
    expect(oldValues).toEqual([]);
  });

  it("uses no colour token that no longer exists", () => {
    const removed =
      /[a-z]+-(?:background|foreground|accent-soft|accent-text)\b/g;
    const matches = sourceFiles(srcDir, [".ts", ".tsx"]).flatMap((file) =>
      Array.from(
        readFileSync(join(srcDir, file), "utf8").matchAll(removed),
        (match) => ({ file, match: match[0] }),
      ),
    );
    const removedNames = allBlocks.flatMap((entry) =>
      Object.keys(entry.decls).filter((name) =>
        [
          "--background",
          "--foreground",
          "--accent-soft",
          "--accent-text",
        ].includes(name),
      ),
    );

    expect(matches).toEqual([]);
    expect(removedNames).toEqual([]);
  });

  it("picks the palette from the system setting with no script", () => {
    const layout = readFileSync(join(appDir, "layout.tsx"), "utf8");

    expect(block([":root"])?.["color-scheme"]).toBe("light dark");
    expect(block(["@layer base", "body"])?.background).toBe("var(--bg)");
    expect(block(["@layer base", "body"])?.color).toBe("var(--ink)");
    expect(css.includes("prefers-color-scheme")).toBe(false);
    expect(css.includes("data-theme")).toBe(false);
    expect(css.includes(".dark")).toBe(false);
    expect(/<script/i.test(layout)).toBe(false);
    expect(/next\/script/.test(layout)).toBe(false);
  });

  it("sets all type in Fraunces with Georgia as the fallback", () => {
    const sourceSans = sourceFiles(srcDir, [".ts", ".tsx", ".css"]).filter(
      (file) => /source-?sans/i.test(readFileSync(join(srcDir, file), "utf8")),
    );
    const fontFacePaths = allBlocks
      .filter((entry) => entry.path.some((part) => part.includes("@font-face")))
      .map((entry) => entry.path);

    expect(entriesOf(["@layer base", "body"])).toEqual([
      ["background", "var(--bg)"],
      ["color", "var(--ink)"],
      ["font-family", FAMILY],
      ["font-optical-sizing", "auto"],
      ["font-size", BODY_SIZE],
      ["font-weight", "400"],
      ["font-variation-settings", '"SOFT" 60'],
      ["line-height", "1.7"],
    ]);
    expect(block(["@theme inline"])?.["--font-sans"]).toBe(FAMILY);
    expect(block(["@theme inline"])?.["--font-serif"]).toBe(FAMILY);
    expect(fontFacePaths).toEqual([]);
    expect(sourceSans).toEqual([]);
  });

  it("defines each type role as a utility with its exact values", () => {
    const actual = ROLES.map((role) => ({
      name: role.name,
      entries: entriesOf([`@utility type-${role.name}`]),
    }));
    const expected = ROLES.map((role) => ({
      name: role.name,
      entries: roleEntries(role),
    }));
    const utilityPaths = allBlocks
      .map((entry) => entry.path)
      .filter((path) => path.length === 1 && path[0]?.startsWith("@utility "));

    expect(actual).toEqual(expected);
    expect(utilityPaths).toEqual(
      ROLES.map((role) => [`@utility type-${role.name}`]),
    );
  });

  it('sets "WONK" 0 on every italic type role', () => {
    const italics = allBlocks
      .filter(
        (entry) =>
          entry.path.length === 1 &&
          entry.path[0]?.startsWith("@utility type-") &&
          entry.decls["font-style"] === "italic",
      )
      .map((entry) => [
        entry.path[0]?.replace("@utility type-", ""),
        entry.decls["font-variation-settings"],
      ]);

    expect(italics).toEqual([
      ["display", '"SOFT" 0, "WONK" 0'],
      ["lead", '"SOFT" 0, "WONK" 0'],
      ["quote", '"SOFT" 0, "WONK" 0'],
      ["brand", '"SOFT" 0, "WONK" 0'],
      ["footer-name", '"SOFT" 0, "WONK" 0'],
    ]);
  });

  it("defines the layout and space tokens and no other spacing scale", () => {
    const rootLayout = entriesOf([":root"]).filter(
      ([name, value]) =>
        name !== "color-scheme" && !value.startsWith("light-dark("),
    );
    const theme = entriesOf(["@theme inline"]);
    const expectedSpacing = SPACE_NAMES.map((name): [string, string] => [
      `--spacing-${name}`,
      `var(--space-${name})`,
    ]);
    const expectedThemeNames = [
      ...COLOR_TOKENS.map((token) => `--color-${token}`),
      "--font-sans",
      "--font-serif",
      ...expectedSpacing.map(([name]) => name),
    ];
    const spaceDecls = allBlocks.flatMap((entry) =>
      Object.keys(entry.decls)
        .filter((name) => name.startsWith("--space"))
        .map((name) => `${entry.path.join(" > ")} > ${name}`),
    );

    expect(rootLayout).toEqual(LAYOUT_TOKENS);
    expect(block(["@media (min-width: 48rem)", ":root"])).toEqual({
      "--header": "6rem",
    });
    expect(block(["@layer base", "html"])).toEqual({
      "scrollbar-gutter": "stable",
    });
    expect(theme.filter(([name]) => name.startsWith("--spacing"))).toEqual(
      expectedSpacing,
    );
    expect(theme.map(([name]) => name)).toEqual(expectedThemeNames);
    expect(spaceDecls).toEqual(
      SPACE_NAMES.map((name) => `:root > --space-${name}`),
    );
  });

  it("styles links in copy", () => {
    expect(entriesOf(["@layer base", "main :where(p, li) a"])).toEqual([
      ["color", "var(--link)"],
      ["font-weight", "500"],
      ["text-decoration", "underline"],
      ["text-decoration-thickness", "1px"],
      ["text-underline-offset", "0.3em"],
    ]);
    expect(block(["@layer base", "main :where(p, li) a:hover"])).toEqual({
      "text-decoration-thickness": "2px",
    });
  });

  it("draws a 2px accent ring at 3px offset on focus-visible", () => {
    expect(entriesOf(["@layer base", ":focus-visible"])).toEqual([
      ["outline", "2px solid var(--accent)"],
      ["outline-offset", "3px"],
    ]);
  });

  it("leaves the focus ring to the global rule in every component", () => {
    const matches = sourceFiles(appDir, [".ts", ".tsx"]).flatMap((file) =>
      Array.from(
        readFileSync(join(appDir, file), "utf8").matchAll(
          /focus-visible:[^\s"'`]*/g,
        ),
        (match) => ({ file, match: match[0] }),
      ),
    );

    expect(matches).toEqual([]);
  });

  it("holds exactly the planned rules and nothing else", () => {
    const paths = allBlocks
      .filter((entry) => Object.keys(entry.decls).length > 0)
      .map((entry) => entry.path);
    const expected = [
      [":root"],
      ["@media (min-width: 48rem)", ":root"],
      ["@theme inline"],
      ["@layer base", "html"],
      ["@layer base", "body"],
      ["@layer base", "h1, h2, h3"],
      ["@layer base", "main :where(p, li) a"],
      ["@layer base", "main :where(p, li) a:hover"],
      ["@layer base", ":focus-visible"],
      ...ROLES.map((role) => [`@utility type-${role.name}`]),
      ["@media (prefers-reduced-motion: reduce)", "*, *::before, *::after"],
    ];

    expect(paths).toEqual(expected);
    expect(paths).toHaveLength(28);
    expect(block(["@layer base", "h1, h2, h3"])).toEqual({
      color: "var(--heading)",
    });
  });

  it("turns animations and transitions off under reduced motion", () => {
    expect(
      entriesOf([
        "@media (prefers-reduced-motion: reduce)",
        "*, *::before, *::after",
      ]),
    ).toEqual([
      ["animation", "none !important"],
      ["transition", "none !important"],
      ["scroll-behavior", "auto !important"],
    ]);
  });
});
