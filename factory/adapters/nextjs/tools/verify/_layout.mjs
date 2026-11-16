// The layout check, for the smoke step (_smoke_page.mjs), the contact sheet
// (_contact_sheet.mjs) and a designer's prototype: it measures a page against
// the layout contract below and says where it departs from it.
//   import { LAYOUT_WIDTHS, layoutOf, acrossRoutes } from "./_layout.mjs";
//   const layout = await layoutOf(page); // null: no [data-shell], not checked
//   layout.items  // [{ check, selector, measured, want }], gating and reported
//   layout.column // { selector, left, right }: main's column, for acrossRoutes
//   acrossRoutes([{ route, column }, ...]) // edges between routes, one width
//
// On its own, from the project root, against any server (`next dev`, say, with
// a design direction's cookie):
//   node tools/verify/_layout.mjs <origin> <seconds> [--cookie <name>=<value>] <route>...
// It loads each route in Chromium, Firefox and WebKit at once (Playwright, the
// project's @playwright/test), at each of LAYOUT_WIDTHS in turn, the window 900
// tall, light, with reduced motion, in a fresh browser context each (the cookie
// set in each), waits at most <seconds> for it to load and its network to go
// quiet, and measures it. A route whose page has no [data-shell] at 390 px is
// skipped there, in that engine, and loaded at no other width. stdout: the
// gating findings first, exactly as smoke prints them (smoke-layout, and
// smoke-load for a page that never loaded), sorted, each naming its engines
// and then its widths only when it isn't in all of those the check ran in
// (`smoke-layout /about outside ...` in every engine at all four widths,
// `smoke-layout /about firefox 390px lone ...` in one at one); then what it
// reports for the Verifier, as Chromium measured it, one line per check,
// route, width and selector, in the order measured:
//   reported: <route> <width>px <check> <selector>: <measured> (want <expected>)
// stderr: one line, `layout: <n> finding(s), <m> reported; checked <routes>;
// skipped (no [data-shell]) <routes>`, so a route left out by a missing
// attribute shows. Exits 0 when it got as far as judging the pages (findings or
// none), 1 when a browser didn't start (a browser-missing line, as smoke's), 2,
// with its usage on stderr, on arguments it can't read.
//
// The layout contract (the Next.js adapter's; a project's docs/design.md is
// one instance of it, with its own values for the tokens). A page opts in by
// carrying [data-shell]; a page without one is not checked, and a project
// that uses none of these is unaffected. The attributes:
//   data-shell        PageShell: the column, its content box (inside border and
//                     padding); one in the page's header, one in main, one in
//                     its footer (the header: the first `header` outside main;
//                     the footer: the last `footer` outside main; in each, the
//                     first [data-shell] not in [data-bleed], or the region
//                     itself when it carries data-shell)
//   data-section      Section: main's sections, stacked in main's shell
//   data-heading      SectionHeading
//   data-prose, data-lead, data-quote, data-form, data-list, data-rows,
//   data-center, data-events, data-switcher
//                     blocks (and a `p` directly in a [data-section])
//   data-switcher > * a Switcher half, a block's cell
//   data-sidebar-body, data-sidebar-aside
//                     the Sidebar's body and slot, each a block's cell; the slot
//                     is what sits beside a narrow [data-prose]
//   data-bleed        what may leave the column (a hero)
//   data-card-title   a card's title, a label for one-word
// and two tokens, custom properties set where main's shell inherits them:
//   --space-section   the gap between sections, and above the footer
//   --space-heading   the gap under every heading
// A token that isn't set is a finding of its check, naming it.
//
// The checks, on the page at one width (lengths in CSS px; each difference a
// check rules on, an edge's, a gap's or an offset's, is rounded to a whole px
// before it is compared, so a finding's numbers are its verdict's and the same
// from run to run). Gating, a finding in smoke:
//   edges     the content box of the header's and the footer's shell differs
//             from main's by more than 1px on either side, or one is missing;
//             and (acrossRoutes) main's differs from the first checked route's
//             at the same width, in the same engine
//   outside   a visible element's box reaches more than 1px past the column
//             (main's shell's content box), not inside [data-bleed]; exempt:
//             a shell and its ancestors, an element that is position: fixed or
//             in one, an element in a closed dialog or next dev's overlay
//             (nextjs-portal), one the page can't scroll to (wholly above
//             its top or left of its left edge, or wholly right of the window
//             when the page doesn't scroll sideways: no overflow, or html's
//             or body's overflow-x hides or clips it), one clipped by an
//             ancestor whose overflow-x isn't visible and whose box is inside
//             the column, and one whose parent is itself outside (one finding
//             for a box and what's in it)
//   sections  the gap between adjacent main [data-section]s (those in no other
//             section), or between the last one and the footer, differs from
//             --space-section by more than 1px
//   headings  for each visible main [data-heading]: at the nearest level, from
//             it up to its section, that has a following sibling, the first
//             following element under it (its top at or below the heading's
//             bottom, overlapping it sideways) is more than 1px nearer or
//             further than --space-heading; with none under it, the first
//             following element sits beside it, and its top is more than 1px
//             off the heading's. A heading with nothing after it isn't measured
//   prose     a [data-prose] narrower than 0.6 of the column with nothing beside
//             it: no leaf element in main, or [data-sidebar-aside], overlapping
//             it vertically and clear of it sideways
//   lone      a block in main, not in [data-bleed], that neither fills 0.9 of
//             its cell's content width nor sits centred in it within 2px (its
//             cell: the nearest enclosing Sidebar body or slot, Switcher half,
//             block or shell; a Switcher half itself fills its cell)
// Reported, not gating (the contact sheet's index lists them for the Verifier;
// Chromium's alone):
//   one-word  a line of one word: any line of a label of four words or more,
//             or the first line of a three-word label (labels: h1, h2, h3,
//             [data-card-title], button, [role=button], [data-quote]'s
//             blockquote and figcaption, the li of a [data-list] or [data-rows],
//             a footer's a and p, a header's a: its nav tabs and brand, the p
//             right after a [data-bleed]'s h1: the hero tagline); or the last
//             line of any other paragraph in main. Words are runs between
//             spaces, no-break spaces and U+200B, and the parts of a slashed
//             compound (a word broken at a hyphen counts on each of its
//             lines); text in an element under 2px either way (visually
//             hidden) is none
//   ragged    a [data-prose] p, not a Lead's, of three lines or more whose
//             longest line is under 0.9 of its content width
//   short     a p in [data-prose] or [data-lead] (or a p[data-lead]), not
//             text-align: center, of three lines or fewer whose longest line is
//             under 0.75 of its content width
// Each item is one per check and selector on the page (the first in the page's
// order). A <selector> is _axe.mjs's selectorOf: tag, id and classes, under its
// parent's, no position, so a list's items are one; a region with no element
// is named by its tag (`header`), a token by `html`.
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium, firefox, webkit } from "@playwright/test";
import { selectorOf } from "./_axe.mjs";

export const LAYOUT_WIDTHS = [390, 768, 1280, 1920];
export const GATING = [
  "edges",
  "outside",
  "sections",
  "headings",
  "prose",
  "lone",
];
export const REPORTED = ["one-word", "ragged", "short"];

// measureLayout(selectorOf): in the page, null when it has no [data-shell],
// else { column, items } (the header's checks). It uses nothing outside itself
// but its argument, so layoutOf passes it as source.
function measureLayout(selectorOf) {
  if (!document.querySelector("[data-shell]")) return null;
  const R = Math.round;
  const items = [];
  const seen = new Set();
  const add = (check, el, measured, want) => {
    const selector = typeof el === "string" ? el : selectorOf(el);
    if (seen.has(`${check} ${selector}`)) return;
    seen.add(`${check} ${selector}`);
    items.push({ check, selector, measured, want });
  };
  const signed = (n) => `${n > 0 ? "+" : ""}${n}px`;
  const visible = (el) => {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    return (
      r.width > 0 &&
      r.height > 0 &&
      s.visibility !== "hidden" &&
      s.visibility !== "collapse" &&
      !el.closest("dialog:not([open]), nextjs-portal")
    );
  };
  // box(el): its content box, inside border and padding.
  const box = (el) => {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    return {
      left: r.left + parseFloat(s.borderLeftWidth) + parseFloat(s.paddingLeft),
      right:
        r.right - parseFloat(s.borderRightWidth) - parseFloat(s.paddingRight),
    };
  };
  const main = document.querySelector("main");
  const outsideMain = (tag) =>
    [...document.querySelectorAll(tag)].filter((e) => !e.closest("main"));
  const header = outsideMain("header")[0] ?? null;
  const footer = outsideMain("footer").at(-1) ?? null;
  const shellOf = (region) =>
    !region
      ? null
      : region.matches("[data-shell]")
        ? region
        : ([...region.querySelectorAll("[data-shell]")].find(
            (s) => !s.closest("[data-bleed]"),
          ) ?? null);
  const mainShell = shellOf(main);
  if (!mainShell) {
    add("edges", "main", "no [data-shell]", "one, its content box the column");
    return { column: null, items };
  }
  const col = box(mainShell);
  const colWidth = col.right - col.left;

  // 1. edges, in the page.
  for (const [name, region] of [
    ["header", header],
    ["footer", footer],
  ]) {
    const shell = shellOf(region);
    if (!shell) {
      add("edges", region ?? name, "no [data-shell]", "one, on main's column");
      continue;
    }
    const b = box(shell);
    const dl = R(b.left - col.left);
    const dr = R(b.right - col.right);
    if (Math.abs(dl) > 1 || Math.abs(dr) > 1)
      add(
        "edges",
        shell,
        `content box left ${signed(dl)}, right ${signed(dr)} from main's`,
        "main's, ±1px",
      );
  }

  // token(name): the custom property's computed length, or null when it isn't
  // set (a finding of <check>).
  const token = (name, check) => {
    const probe = document.createElement("div");
    probe.style.cssText = `position:absolute;visibility:hidden;inline-size:0;block-size:var(${name})`;
    mainShell.append(probe);
    const set = getComputedStyle(probe).getPropertyValue(name).trim() !== "";
    const h = probe.getBoundingClientRect().height;
    probe.remove();
    if (set) return h;
    add(check, "html", `${name} isn't set`, "the layout contract's token");
    return null;
  };

  // 2. outside.
  const exempt = new Set();
  for (const s of document.querySelectorAll("[data-shell]"))
    for (let a = s; a; a = a.parentElement) exempt.add(a);
  const fixed = new Map();
  const isFixed = (el) => {
    if (!el) return false;
    if (!fixed.has(el))
      fixed.set(
        el,
        getComputedStyle(el).position === "fixed" || isFixed(el.parentElement),
      );
    return fixed.get(el);
  };
  const clipped = (el) => {
    for (
      let a = el.parentElement;
      a && a !== document.body;
      a = a.parentElement
    ) {
      if (getComputedStyle(a).overflowX === "visible") continue;
      const r = a.getBoundingClientRect();
      if (R(r.left - col.left) >= -1 && R(col.right - r.right) >= -1)
        return true;
    }
    return false;
  };
  const viewport = document.documentElement.clientWidth;
  // The page scrolls sideways when it overflows and the viewport's overflow-x
  // (html's, or body's when html's is visible) doesn't hide or clip it.
  const rootOverflow = getComputedStyle(document.documentElement).overflowX;
  const viewportOverflow =
    rootOverflow === "visible"
      ? getComputedStyle(document.body).overflowX
      : rootOverflow;
  const sideways =
    document.documentElement.scrollWidth > viewport &&
    viewportOverflow !== "hidden" &&
    viewportOverflow !== "clip";
  const out = new Set();
  for (const el of document.body.querySelectorAll("*")) {
    if (exempt.has(el) || el.closest("[data-bleed]") || !visible(el)) continue;
    if (isFixed(el)) continue;
    const r = el.getBoundingClientRect();
    // Exempt only a box no scrolling brings into view (a skip link above the
    // window, a panel parked off-screen in a page that doesn't scroll sideways).
    const top = r.bottom + window.scrollY;
    const leftEdge = r.right + window.scrollX;
    if (top <= 0 || leftEdge <= 0 || (!sideways && r.left >= viewport))
      continue;
    const left = R(col.left - r.left);
    const right = R(r.right - col.right);
    if (left <= 1 && right <= 1) continue;
    if (clipped(el)) continue;
    out.add(el);
    if (out.has(el.parentElement)) continue;
    const past = [
      left > 1 ? `${left}px past the column's left edge` : null,
      right > 1 ? `${right}px past the column's right edge` : null,
    ].filter(Boolean);
    add(
      "outside",
      el,
      `reaches ${past.join(", ")}`,
      "inside the column, or in [data-bleed]",
    );
  }

  // 3. sections.
  const section = token("--space-section", "sections");
  const sections = [...main.querySelectorAll("[data-section]")].filter(
    (s) => !s.parentElement.closest("[data-section]") && visible(s),
  );
  if (section !== null) {
    const gaps = sections.map((s, i) => [s, i === 0 ? null : sections[i - 1]]);
    if (sections.length && footer) gaps.push([footer, sections.at(-1)]);
    for (const [below, above] of gaps) {
      if (!above) continue;
      const off = R(
        below.getBoundingClientRect().top -
          above.getBoundingClientRect().bottom -
          section,
      );
      if (Math.abs(off) > 1)
        add(
          "sections",
          below,
          `gap above is --space-section ${signed(off)}`,
          "--space-section, ±1px",
        );
    }
  }

  // 4. headings.
  const heading = token("--space-heading", "headings");
  if (heading !== null)
    for (const h of main.querySelectorAll("[data-heading]")) {
      if (!visible(h)) continue;
      const hr = h.getBoundingClientRect();
      const stop = h.closest("[data-section]") ?? main;
      const after = [];
      for (
        let el = h;
        el && el !== stop && !after.length;
        el = el.parentElement
      )
        for (let sib = el.nextElementSibling; sib; sib = sib.nextElementSibling)
          if (visible(sib)) after.push(sib);
      if (!after.length) continue;
      const under = after.find((el) => {
        const r = el.getBoundingClientRect();
        return (
          R(r.top - hr.bottom) >= -1 &&
          R(Math.min(r.right, hr.right) - Math.max(r.left, hr.left)) > 1
        );
      });
      if (under) {
        const off = R(under.getBoundingClientRect().top - hr.bottom - heading);
        if (Math.abs(off) > 1)
          add(
            "headings",
            h,
            `gap below is --space-heading ${signed(off)}`,
            "--space-heading, ±1px",
          );
      } else {
        const off = R(after[0].getBoundingClientRect().top - hr.top);
        if (Math.abs(off) > 1)
          add(
            "headings",
            h,
            `the content beside it ${signed(off)} from its top`,
            "level with it, ±1px",
          );
      }
    }

  // 5. prose.
  const leaves = [...main.querySelectorAll("*")].filter(
    (el) => el.children.length === 0 || el.matches("[data-sidebar-aside]"),
  );
  for (const p of document.querySelectorAll("[data-prose]")) {
    if (!visible(p)) continue;
    const pr = p.getBoundingClientRect();
    if (pr.width >= 0.6 * colWidth) continue;
    const beside = leaves.some((el) => {
      if (el.contains(p) || p.contains(el) || !visible(el)) return false;
      const r = el.getBoundingClientRect();
      return (
        r.top < pr.bottom &&
        r.bottom > pr.top &&
        (R(r.left - pr.right) >= -1 || R(pr.left - r.right) >= -1)
      );
    });
    if (!beside)
      add(
        "prose",
        p,
        `${R(pr.width)}px wide, nothing beside it`,
        "0.6 of the column or more, or something beside it",
      );
  }

  // 8. lone.
  const BLOCKS =
    "[data-prose], [data-lead], [data-quote], [data-form], [data-list], [data-rows], [data-center], [data-events], [data-switcher], [data-section] > p";
  const CELLS = `[data-sidebar-body], [data-sidebar-aside], [data-switcher] > *, [data-shell], ${BLOCKS}`;
  for (const el of main.querySelectorAll(`:is(${BLOCKS})`)) {
    if (!visible(el) || el.closest("[data-bleed]")) continue;
    if (el.parentElement.matches("[data-switcher]")) continue;
    const cell = el.parentElement.closest(CELLS);
    const c = cell && main.contains(cell) ? box(cell) : col;
    const cw = c.right - c.left;
    const r = el.getBoundingClientRect();
    const gl = r.left - c.left;
    const gr = c.right - r.right;
    if (r.width >= 0.9 * cw || Math.abs(R(gl - gr)) <= 2) continue;
    add(
      "lone",
      el,
      `${R(r.width)}px wide in a ${R(cw)}px cell, ${R(gl)}px | ${R(gr)}px either side`,
      "0.9 of it, or centred, ±2px",
    );
  }

  // The reported checks. linesOf(el): its lines, top to bottom, each { words,
  // left, right }, from the boxes of its words.
  const linesOf = (el) => {
    const lines = [];
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const parent = node.parentElement;
      if (!parent || parent.closest("script, style")) continue;
      const pr = parent.getBoundingClientRect();
      if (pr.width < 2 || pr.height < 2) continue;
      for (const m of node.textContent.matchAll(/[^\s\u200b/]+\/?/g)) {
        const range = document.createRange();
        range.setStart(node, m.index);
        range.setEnd(node, m.index + m[0].length);
        // A word broken across lines (at a hyphen) counts on each line it
        // shows on.
        const touched = new Set();
        for (const r of range.getClientRects()) {
          if (r.width === 0) continue;
          let line = lines.find((l) => Math.abs(l.top - r.top) < r.height / 2);
          if (!line) {
            line = { top: r.top, words: 0, left: r.left, right: r.right };
            lines.push(line);
          }
          touched.add(line);
          line.left = Math.min(line.left, r.left);
          line.right = Math.max(line.right, r.right);
        }
        for (const line of touched) line.words++;
      }
    }
    return lines.sort((a, b) => a.top - b.top);
  };
  const quote = (el) => {
    const t = el.innerText.replace(/\s+/g, " ").trim();
    return `"${t.length > 40 ? t.slice(0, 40) + "…" : t}"`;
  };
  const LABELS =
    "h1, h2, h3, [data-card-title], button, [role='button'], [data-quote] blockquote, [data-quote] figcaption, [data-list] li, [data-rows] li, footer a, footer p, header a, [data-bleed] h1 + p";
  for (const el of document.querySelectorAll(LABELS)) {
    if (!visible(el)) continue;
    const lines = linesOf(el);
    if (lines.length < 2) continue;
    const counts = lines.map((l) => l.words);
    const words = counts.reduce((a, b) => a + b, 0);
    if (words >= 4 ? counts.includes(1) : words === 3 && counts[0] === 1)
      add(
        "one-word",
        el,
        `${quote(el)} breaks ${counts.join("/")} words a line`,
        words >= 4 ? "no line of one word" : "no first line of one word",
      );
  }
  for (const el of main.querySelectorAll("p")) {
    if (!visible(el) || el.matches(LABELS)) continue;
    const lines = linesOf(el);
    if (lines.length > 1 && lines.at(-1).words === 1)
      add(
        "one-word",
        el,
        `${quote(el)} ends on a line of one word`,
        "a last line of two words or more",
      );
  }
  const reach = (el) => {
    const lines = linesOf(el);
    const b = box(el);
    return {
      lines: lines.length,
      longest: R(Math.max(0, ...lines.map((l) => l.right - l.left))),
      width: R(b.right - b.left),
    };
  };
  for (const el of document.querySelectorAll("[data-prose] p")) {
    if (!visible(el) || el.closest("[data-lead]")) continue;
    const m = reach(el);
    if (m.lines >= 3 && m.longest < 0.9 * m.width)
      add(
        "ragged",
        el,
        `${quote(el)} ${m.lines} lines, the longest ${m.longest}px of ${m.width}px`,
        `${Math.ceil(0.9 * m.width)}px (0.9 of its box)`,
      );
  }
  for (const el of document.querySelectorAll(
    ":is([data-prose], [data-lead]) p, p[data-lead]",
  )) {
    if (!visible(el) || getComputedStyle(el).textAlign === "center") continue;
    const m = reach(el);
    if (m.lines >= 1 && m.lines <= 3 && m.longest < 0.75 * m.width)
      add(
        "short",
        el,
        `${quote(el)} ${m.lines} line${m.lines > 1 ? "s" : ""}, the longest ${m.longest}px of ${m.width}px`,
        `${Math.ceil(0.75 * m.width)}px (0.75 of its box)`,
      );
  }

  const order = [
    "edges",
    "outside",
    "sections",
    "headings",
    "prose",
    "lone",
    "one-word",
    "ragged",
    "short",
  ];
  items.sort((a, b) => order.indexOf(a.check) - order.indexOf(b.check));
  return {
    column: {
      selector: selectorOf(mainShell),
      left: col.left,
      right: col.right,
    },
    items,
  };
}

// layoutOf(page): the page measured (once its fonts are ready), or null when
// it has no [data-shell] (decided first, from the page as loaded).
export const layoutOf = async (page) => {
  if (!(await page.evaluate(() => !!document.querySelector("[data-shell]"))))
    return null;
  await page.evaluate(() => document.fonts.ready.then(() => true));
  return page.evaluate(`(${measureLayout})(${selectorOf})`);
};

// acrossRoutes(pages): the edges items between routes at one width in one
// engine: <pages> is [{ route, column }] in the routes' order, each a page
// layoutOf measured; each column more than 1px off the first's, either side,
// is an item of its route.
export const acrossRoutes = (pages) => {
  const measured = pages.filter((p) => p.column);
  const [first] = measured;
  const signed = (n) => `${n > 0 ? "+" : ""}${n}px`;
  return measured.slice(1).flatMap(({ route, column }) => {
    const dl = Math.round(column.left - first.column.left);
    const dr = Math.round(column.right - first.column.right);
    return Math.abs(dl) > 1 || Math.abs(dr) > 1
      ? [
          {
            route,
            check: "edges",
            selector: column.selector,
            measured: `content box left ${signed(dl)}, right ${signed(dr)} from ${first.route}'s`,
            want: `${first.route}'s, ±1px`,
          },
        ]
      : [];
  });
};

// findingText(item): an item as smoke's finding has it after the route (and its
// engines and widths): ` <check> <selector>: <measured> (want <expected>)`.
export const findingText = ({ check, selector, measured, want }) =>
  ` ${check} ${selector}: ${measured} (want ${want})`;

// dimensions(found, ran, order): the tokens a finding names after its route
// (smoke's rule): its engines, in <order>, when they aren't all <ran.engines>;
// then its widths, smallest first, each with px, when they aren't all
// <ran.widths>. <found> and <ran> are { engines, widths }, each a Set.
export const dimensions = (found, ran, order) => {
  const covers = (a, b) => [...b].every((x) => a.has(x));
  const tokens = [];
  if (!covers(found.engines, ran.engines))
    tokens.push(order.filter((e) => found.engines.has(e)).join(","));
  if (!covers(found.widths, ran.widths))
    tokens.push(
      [...found.widths]
        .sort((a, b) => a - b)
        .map((w) => `${w}px`)
        .join(","),
    );
  return tokens;
};

// The call on its own (the header's).
const standalone = async () => {
  const USAGE =
    "usage: node tools/verify/_layout.mjs <origin> <seconds> [--cookie <name>=<value>] <route>...";
  const args = [];
  let cookie = null;
  for (let i = 2; i < process.argv.length; i++) {
    const arg = process.argv[i];
    const value = arg === "--cookie" ? process.argv[++i] : null;
    if (value === null) {
      args.push(arg);
      continue;
    }
    const eq = (value ?? "").indexOf("=");
    if (eq < 1) {
      process.stderr.write(
        `--cookie takes <name>=<value>, not '${value ?? ""}'\n${USAGE}\n`,
      );
      process.exit(2);
    }
    cookie = { name: value.slice(0, eq), value: value.slice(eq + 1) };
  }
  const origin = (args[0] ?? "").replace(/\/$/, "");
  const [, seconds, ...routes] = args;
  if (
    routes.length === 0 ||
    !/^https?:\/\/[^/]+$/.test(origin) ||
    !(Number(seconds) >= 1)
  ) {
    process.stderr.write(USAGE + "\n");
    process.exit(2);
  }
  const limit = Number(seconds) * 1000;
  const host = origin.replace(/^[a-z]+:\/\//, "");
  const strip = (s) =>
    String(s)
      .split(origin)
      .join("")
      .split(host)
      .join("<host>")
      .replace(/\s+/g, " ")
      .trim();
  const ENGINES = [
    { name: "chromium", title: "Chromium", type: chromium },
    { name: "firefox", title: "Firefox", type: firefox },
    { name: "webkit", title: "WebKit", type: webkit },
  ];
  const started = await Promise.all(
    ENGINES.map(async (engine) => {
      try {
        return { browser: await engine.type.launch({ headless: true }) };
      } catch (e) {
        const why =
          String(e?.message ?? e)
            .split("\n")
            .map((l) =>
              strip(
                l
                  .replace(/[║╔╗╚╝═]/g, "")
                  .replace(/^\s*browserType\.launch:/, ""),
              ),
            )
            .find((l) => l !== "") ?? "unknown";
        return {
          missing: `tools/verify/local.env:1 browser-missing ${engine.title} didn't start (${why}); run bash tools/verify/bootstrap, which installs it into PLAYWRIGHT_BROWSERS_PATH (tools/verify/local.env), and if it names missing system libraries: pnpm exec playwright install-deps ${engine.name}`,
        };
      }
    }),
  );
  const missing = started.filter((s) => s.missing).map((s) => s.missing);
  // found: each finding's line after the route, with where it was found;
  // ran: where each rule ran; reported: Chromium's reported lines.
  const found = new Map();
  const ran = new Map();
  const reported = [];
  const checked = new Set();
  const skipped = new Set();
  const note = (rule, engine, width) => {
    const where = ran.get(rule) ?? { engines: new Set(), widths: new Set() };
    where.engines.add(engine.name);
    where.widths.add(width);
    ran.set(rule, where);
  };
  const finding = (rule, engine, width, route, text) => {
    const key = `${rule}\n${route}\n${text}`;
    const known = found.get(key) ?? {
      rule,
      route,
      text,
      engines: new Set(),
      widths: new Set(),
    };
    known.engines.add(engine.name);
    known.widths.add(width);
    found.set(key, known);
  };
  try {
    if (missing.length === 0)
      await Promise.all(
        ENGINES.map(async (engine, i) => {
          const browser = started[i].browser;
          const columns = new Map(LAYOUT_WIDTHS.map((w) => [w, []]));
          for (const route of routes)
            for (const width of LAYOUT_WIDTHS) {
              if (
                width !== LAYOUT_WIDTHS[0] &&
                !columns.get(LAYOUT_WIDTHS[0]).some((c) => c.route === route)
              )
                break;
              // smoke counts its layout-only widths (768, 1920) out of where
              // smoke-load ran; so does this, with 390 the one width every
              // route is loaded at, so a page that never loads reads as smoke's.
              if (width === LAYOUT_WIDTHS[0]) note("smoke-load", engine, width);
              const context = await browser.newContext({
                viewport: { width, height: 900 },
                colorScheme: "light",
                reducedMotion: "reduce",
              });
              try {
                if (cookie)
                  await context.addCookies([{ ...cookie, url: origin }]);
                const page = await context.newPage();
                const firstLine = (e) => String(e?.message ?? e).split("\n")[0];
                let layout;
                try {
                  await page.goto(origin + route, {
                    waitUntil: "networkidle",
                    timeout: limit,
                  });
                } catch (e) {
                  finding(
                    "smoke-load",
                    engine,
                    width,
                    route,
                    `: the page didn't load and go quiet within ${seconds}s: ${firstLine(e)}`,
                  );
                  continue;
                }
                try {
                  layout = await layoutOf(page);
                } catch (e) {
                  finding(
                    "smoke-load",
                    engine,
                    width,
                    route,
                    `: the layout check didn't run: ${firstLine(e)}`,
                  );
                  continue;
                }
                if (!layout) {
                  if (engine.name === "chromium" && width === LAYOUT_WIDTHS[0])
                    skipped.add(route);
                  continue;
                }
                if (engine.name === "chromium") checked.add(route);
                note("smoke-layout", engine, width);
                columns.get(width).push({ route, column: layout.column });
                for (const item of layout.items)
                  if (GATING.includes(item.check))
                    finding(
                      "smoke-layout",
                      engine,
                      width,
                      route,
                      findingText(item),
                    );
                  else if (engine.name === "chromium")
                    reported.push(
                      `reported: ${route} ${width}px${findingText(item)}`,
                    );
              } finally {
                await context.close();
              }
            }
          for (const [width, pages] of columns)
            for (const item of acrossRoutes(pages))
              finding(
                "smoke-layout",
                engine,
                width,
                item.route,
                findingText(item),
              );
        }),
      );
  } finally {
    await Promise.all(started.map((s) => s.browser?.close()));
  }
  if (missing.length > 0) {
    process.stdout.write(missing.map((l) => l + "\n").join(""));
    process.exit(1);
  }
  const order = ENGINES.map((e) => e.name);
  const lines = [...found.values()].map(
    ({ rule, route, text, engines, widths }) => {
      const tokens = dimensions({ engines, widths }, ran.get(rule), order);
      return `package.json:1 ${rule} ${strip(`${route}${tokens.map((t) => " " + t).join("")}${text}`)}`;
    },
  );
  const findings = [...new Set(lines)].sort();
  process.stdout.write(
    [...findings, ...reported.map(strip)].map((l) => l + "\n").join(""),
  );
  const list = (s) => (s.size ? [...s].join(" ") : "none");
  process.stderr.write(
    `layout: ${findings.length} finding(s), ${reported.length} reported; checked ${list(checked)}; skipped (no [data-shell]) ${list(skipped)}\n`,
  );
};

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
)
  await standalone();
