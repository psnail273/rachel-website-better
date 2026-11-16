// The smoke step's browsers: loads each page route headless in three engines,
// Chromium, Firefox and WebKit (Safari's engine) (Playwright, the project's
// @playwright/test), in each of the views below, and prints what went wrong on
// it.
//   node tools/verify/_smoke_page.mjs <origin> <seconds> [--cookie <name>=<value>] <route>...
// The smoke step calls it on the app it built and started. It runs as well on
// its own, from the project root, against any server: `next dev`, say, with the
// cookie set in every browser context and on every link request (a design
// direction's, `--cookie design-direction=b`); it prints the same lines, and
// exits 2, with its usage on stderr, on arguments it can't read.
//
// It starts the three browsers at once, one each, and each loads the routes in
// turn, while the others do the same. For each route it opens <origin><route>
// in a fresh browser context for each view (VIEWS), in turn, the window 900 px
// tall, with reduced motion:
//   390 and 1280 px wide, light and dark  axe, the link reading
//   320 px wide, light                    the reflow check, the link reading
//   1280 px wide, light, forced colours   the forced-colours check, the link
//                                         reading
// and waits, at most <seconds> for each load, for the page to load and its
// network to go quiet (Playwright's networkidle: no request for 500 ms), so the
// requests its scripts make count too. On a page that loaded it then runs the
// view's page checks (CHECKS), each at most <seconds>:
//   axe          axe-core (_axe.mjs: WCAG 2.0, 2.1 and 2.2 A and AA, wcag2a,
//                wcag2aa, wcag21a, wcag21aa and wcag22aa, and axe's
//                best-practice rules);
//   reflow       at 320 px wide (1280 px at 400% zoom, WCAG 1.4.10) the page
//                must not scroll sideways: the root's scrollWidth no more than
//                1 px over its clientWidth, unless the page hides its
//                overflow (overflow-x hidden or clip on the root, or the body's
//                propagated to it);
//   forced colours (Playwright's forcedColors: 'active', Windows' high
//                contrast) each element a Tab reaches (tabIndex 0 or more, not
//                disabled, inert or hidden) is focused in turn and must show a
//                visible indicator: an outline of width over 0 and style not
//                none, or a change on focus to a drawn outline or border (one
//                whose style isn't none and width isn't 0), a box-shadow,
//                text-decoration (its line, style, thickness or offset), clip
//                or size, or, where forced-color-adjust is none, a background
//                or text colour, of it, the elements in it, its ancestors, or
//                its parent's other children nearest it (100 each side) and
//                the elements in them (nearest first, 50 from each, 200 in
//                all), their ::before and ::after too, transitions finished
//                first: the same elements for each item of a list, however
//                long. It runs only in an engine that forces the colours (a
//                box-shadow computes to none): Chromium and Firefox do;
//                WebKit's Playwright emulates the media query alone, so it
//                doesn't run there;
//   link reading the page's same-origin links.
// Once every engine has loaded every route, each link (its #hash left off,
// each once, a route already loaded left out) is requested once, with no
// browser (Playwright's request), with GET, redirects followed, at most
// <seconds> each. Off-site links aren't requested: the step runs offline.
//
// stdout: one finding a line, sorted, each once, the origin left out of every
// message, and its host and port alone written <host> (the server's port
// changes from run to run, and a finding must not):
//   package.json:1 smoke-console <route>[ <engines>][ <widths>]: console error: <text>
//   package.json:1 smoke-page-error <route>[ <engines>][ <widths>]: uncaught <name>: <message>
//   package.json:1 smoke-response <route>[ <engines>][ <widths>]: <request path> answered <status>
//   package.json:1 smoke-request-failed <route>[ <engines>][ <widths>]: <request path> failed: <reason>
//   package.json:1 smoke-load <route>[ <engines>][ <widths>]: <why the page never
//                  loaded, or a page check never finished on it>
//   package.json:1 smoke-a11y <route>[ <engines>][ <widths>] <light|dark> <axe rule id> <target>: <help>
//   package.json:1 smoke-reflow <route>[ <engines>]: scrolls horizontally at 320px
//                  (<scrollWidth>px wide[, widest <target>])
//   package.json:1 smoke-forced-colors <route>[ <engines>] <target>: no visible
//                  focus indicator in forced colours
//   package.json:1 smoke-link <from route> <href> <status, or failed: <reason>>
//   tools/verify/local.env:1 browser-missing <Engine> didn't start (<why>); ...
// A page finding names where it was found only when that is narrower than
// where its rule ran (the views and engines that run its check; every one for
// console, page-error, response, request-failed and load), as two tokens after
// the route, each left out when it would name them all:
//   <engines>  the engines that found it, chromium, firefox and webkit in that
//              order, joined by commas (`smoke-a11y /contact firefox,webkit
//              dark ...`);
//   <widths>   the window widths it was found at, smallest first, each with px,
//              joined by commas (`smoke-a11y / 390px dark color-contrast ...`).
// So a finding all three engines report at both of axe's widths reads as it did
// when smoke ran Chromium alone at one width, and a forced-colours finding
// both Chromium and Firefox report names none. A smoke-link, from the one
// request, names none. browser-missing is one line for each engine that didn't
// start, naming it; then no page is loaded.
// The page findings name no scheme but smoke-a11y: a fault in both schemes is
// one finding. A <target> is a selector for the element with no position in it
// (_axe.mjs's describe): its tag, id and classes, under its parent's
// (`li.card > p.title`), so the items of a list, however many the page's data
// makes, are one finding; an element axe finds inside a frame or a shadow root
// keeps axe's own selector, its parts joined by " >>> ". The reflow check's
// <target> is the element reaching furthest right that no ancestor clips (the
// first in the page's order on a tie), when there is one. A link's <from
// route> is the first route, in the order given, any engine found it on.
// A response is judged on its status: 2xx passes, and so does a redirect (3xx
// with a Location), whose target is judged in turn; any other fails. A link
// fails on a final status of 400 or more.
// Exits 0 when it got as far as judging the pages (findings or none), 1 when a
// browser didn't start, 2 on arguments it can't read.
import { chromium, firefox, request, webkit } from "@playwright/test";
import { axe, describe, selectorOf } from "./_axe.mjs";

const USAGE =
  "usage: node tools/verify/_smoke_page.mjs <origin> <seconds> [--cookie <name>=<value>] <route>...";
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
const HEIGHT = 900;
// The engines, in the order a finding names them.
const ENGINES = [
  { name: "chromium", title: "Chromium", type: chromium },
  { name: "firefox", title: "Firefox", type: firefox },
  { name: "webkit", title: "WebKit", type: webkit },
];
// The views each route is loaded in, in each engine, in this order: a fresh
// browser context each, HEIGHT tall, with reduced motion, running the named
// CHECKS. To check another width, add a view.
const AXE_WIDTHS = [390, 1280];
const VIEWS = [
  ...AXE_WIDTHS.flatMap((width) =>
    ["light", "dark"].map((scheme) => ({
      width,
      scheme,
      checks: ["axe", "links"],
    })),
  ),
  { width: 320, scheme: "light", checks: ["reflow", "links"] },
  {
    width: 1280,
    scheme: "light",
    forcedColors: "active",
    checks: ["forced-colors", "links"],
  },
];
// The rules every view can find, whatever its checks.
const EVENT_RULES = [
  "smoke-console",
  "smoke-page-error",
  "smoke-response",
  "smoke-request-failed",
  "smoke-load",
];
const host = origin.replace(/^[a-z]+:\/\//, "");
const strip = (s) =>
  String(s)
    .split(origin)
    .join("")
    .split(host)
    .join("<host>")
    .replace(/\s+/g, " ")
    .trim();
const firstLine = (e) => String(e?.message ?? e).split("\n")[0];

// out: the findings that name no engine (smoke-link). pageFindings: each page
// finding, by its line with no engine or width named, with the engines and
// widths that found it. ran: by rule, the engines and widths it ran in.
const out = [];
const pageFindings = new Map();
const ran = new Map();
const line = (rule, message) =>
  out.push(`package.json:1 ${rule} ${strip(message)}`);
// pageFinding(engine, width, rule, route, rest): <engine> found <rule> on
// <route> at <width>; <rest> is the message after the route (": <text>", or
// " <scheme> ...").
const pageFinding = (engine, width, rule, route, rest) => {
  const key = `package.json:1 ${rule} ${strip(route + rest)}`;
  const known = pageFindings.get(key) ?? {
    rule,
    route,
    rest,
    engines: new Set(),
    widths: new Set(),
  };
  known.engines.add(engine.name);
  known.widths.add(width);
  pageFindings.set(key, known);
};
// didRun(rule, engine, width): <rule> ran in <engine> at <width>.
const didRun = (rule, engine, width) => {
  const where = ran.get(rule) ?? { engines: new Set(), widths: new Set() };
  where.engines.add(engine.name);
  where.widths.add(width);
  ran.set(rule, where);
};

// within(promise, what): the promise, or a rejection once the limit runs out.
const within = (promise, what) => {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timer = setTimeout(
        () => reject(new Error(`${what} didn't finish within ${seconds}s`)),
        limit,
      );
    }),
  ]).finally(() => clearTimeout(timer));
};

// noHash(url): the URL with its #hash left off.
const noHash = (url) => {
  const u = new URL(url);
  u.hash = "";
  return u.href;
};

// launch(engine): { browser } for the engine, or { missing: <its
// browser-missing line> } when it doesn't start.
const launch = async (engine) => {
  try {
    return { browser: await engine.type.launch({ headless: true }) };
  } catch (e) {
    const why =
      String(e?.message ?? e)
        .split("\n")
        .map((l) =>
          strip(
            l.replace(/[║╔╗╚╝═]/g, "").replace(/^\s*browserType\.launch:/, ""),
          ),
        )
        .find((l) => l !== "") ?? "unknown";
    return {
      missing: `tools/verify/local.env:1 browser-missing ${engine.title} didn't start (${why}); run bash tools/verify/bootstrap, which installs it into PLAYWRIGHT_BROWSERS_PATH (tools/verify/local.env), and if it names missing system libraries: pnpm exec playwright install-deps ${engine.name}`,
    };
  }
};

// links: each same-origin link, without its hash, and the index of the first
// route (in the order given) any engine found it on.
const links = new Map();
const loaded = new Set(routes.map((r) => noHash(origin + r)));

// reflowOf(): in the page, null when it doesn't scroll sideways, else its
// width and the element reaching furthest right that no ancestor clips (or
// null). It uses nothing outside itself.
const reflowOf = () => {
  const root = document.documentElement;
  if (root.scrollWidth <= root.clientWidth + 1) return null;
  const overflow = (e) => getComputedStyle(e).overflowX;
  const viewport =
    overflow(root) !== "visible"
      ? overflow(root)
      : document.body
        ? overflow(document.body)
        : "visible";
  if (viewport === "hidden" || viewport === "clip") return null;
  const clipped = (el) => {
    if (getComputedStyle(el).position === "fixed") return true;
    for (
      let a = el.parentElement;
      a && a !== document.body && a !== root;
      a = a.parentElement
    ) {
      const s = getComputedStyle(a);
      if (s.overflowX !== "visible" || s.position === "fixed") return true;
    }
    return false;
  };
  let widest = null;
  let right = root.clientWidth + 1;
  for (const el of document.body?.querySelectorAll("*") ?? []) {
    const r = Math.round(el.getBoundingClientRect().right + window.scrollX);
    if (r > right && !clipped(el)) {
      widest = el;
      right = r;
    }
  }
  return { width: root.scrollWidth, widest };
};

// unfocusedOf(): in the page, null when the engine doesn't force the colours,
// else the elements a Tab reaches that show no visible indicator when focused
// (the header's forced-colours check). It uses nothing outside itself.
const unfocusedOf = () => {
  const root = document.documentElement;
  const probe = document.createElement("div");
  probe.style.boxShadow = "0 0 0 1px rgb(1, 2, 3)";
  probe.style.forcedColorAdjust = "auto";
  root.append(probe);
  const forced = getComputedStyle(probe).boxShadow === "none";
  probe.remove();
  if (!forced) return null;
  // drawn(s, line): the outline or a border side (`border-top`) of a computed
  // style as it shows: "none" when its style is none or its width 0, so a
  // colour change on a line that isn't drawn counts for nothing.
  const drawn = (s, line) => {
    const style = s.getPropertyValue(`${line}-style`);
    const width = s.getPropertyValue(`${line}-width`);
    return style === "none" || style === "hidden" || parseFloat(width) === 0
      ? "none"
      : `${style} ${width} ${s.getPropertyValue(`${line}-color`)}`;
  };
  const LINES = ["outline", "top", "right", "bottom", "left"].map((l) =>
    l === "outline" ? l : `border-${l}`,
  );
  const PROPS = [
    "box-shadow",
    "text-decoration-line",
    "text-decoration-style",
    "text-decoration-thickness",
    "text-underline-offset",
    "clip",
    "clip-path",
  ];
  // Colours forced colours leave alone, on an element that opts out.
  const OWN = ["background-color", "color"];
  const finish = () => {
    for (const a of document.getAnimations())
      try {
        a.finish();
      } catch {
        // an endless animation can't finish; it changes no focus style here
      }
  };
  // hood(el): el, the elements in it, its ancestors below body, and its
  // parent's other children nearest it, 100 on each side (none when the
  // parent is body), with the elements in them, nearest first, 50 at most from
  // each and 200 in all: so each item of a long list has the same hood, its
  // neighbours', and a long neighbour (a select's options) crowds out none.
  const hood = (el) => {
    const nodes = [...el.querySelectorAll("*")];
    for (let a = el; a && a !== document.body && a !== root; a = a.parentElement)
      nodes.push(a);
    const up = el.parentElement;
    if (!up || up === document.body || up === root) return nodes;
    const kids = [...up.children];
    const i = kids.indexOf(el);
    let budget = 200;
    for (let d = 1; d <= 100; d++)
      for (const k of [kids[i - d], kids[i + d]]) {
        if (!k) continue;
        nodes.push(k);
        const inside = [...k.querySelectorAll("*")].slice(0, Math.min(50, budget));
        nodes.push(...inside);
        budget -= inside.length;
      }
    return nodes;
  };
  const snap = (nodes, el) => {
    const r = el.getBoundingClientRect();
    const values = [Math.round(r.width), Math.round(r.height)];
    for (const n of nodes)
      for (const pseudo of [null, "::before", "::after"]) {
        const s = getComputedStyle(n, pseudo);
        for (const l of LINES) values.push(drawn(s, l));
        for (const p of PROPS) values.push(s.getPropertyValue(p));
        const own = s.getPropertyValue("forced-color-adjust") === "none";
        for (const p of OWN) values.push(own ? s.getPropertyValue(p) : "");
      }
    return values;
  };
  const FOCUSABLE =
    'a[href], area[href], button, input:not([type="hidden"]), select, textarea, summary, iframe, [tabindex], [contenteditable]:not([contenteditable="false"]), audio[controls], video[controls]';
  const unfocused = [];
  for (const el of document.querySelectorAll(FOCUSABLE)) {
    if (el.tabIndex < 0 || el.matches(":disabled") || el.closest("[inert]"))
      continue;
    if (el.getClientRects().length === 0) continue;
    if (getComputedStyle(el).visibility !== "visible") continue;
    document.activeElement?.blur?.();
    const nodes = hood(el);
    finish();
    const before = snap(nodes, el);
    el.focus({ preventScroll: true });
    if (document.activeElement !== el) continue;
    finish();
    const after = snap(nodes, el);
    const outline = drawn(getComputedStyle(el), "outline") !== "none";
    el.blur();
    if (!outline && before.every((v, i) => v === after[i]))
      unfocused.push(el);
  }
  return unfocused;
};

// The page checks, by name, that a view runs on each page that loaded, in each
// engine, each at most <seconds>. A check is { rule, what, run }: run({ page,
// route, at, view, finding }) judges the page, finding(rule, rest) reporting
// what it finds (rest as pageFinding has it), and returns false when it can't
// run in this engine; else it counts as <rule> having run there, at the view's
// width. A check that throws or runs out of time is a smoke-load finding,
// "<what> didn't run: <why>". Add a check here, and name it in a view.
const CHECKS = {
  axe: {
    rule: "smoke-a11y",
    what: "axe",
    run: async ({ page, view, finding }) => {
      const result = await axe(page);
      for (const v of result.violations)
        for (const node of v.nodes) {
          const target = await describe(page, node.target);
          finding("smoke-a11y", ` ${view.scheme} ${v.id} ${target}: ${v.help}`);
        }
    },
  },
  reflow: {
    rule: "smoke-reflow",
    what: "the reflow check",
    run: async ({ page, view, finding }) => {
      const handle = await page.evaluateHandle(reflowOf);
      try {
        const width = await handle.evaluate((r) => r?.width ?? null);
        if (width === null) return;
        const widest = (await handle.getProperty("widest")).asElement();
        const target = widest ? await widest.evaluate(selectorOf) : null;
        finding(
          "smoke-reflow",
          `: scrolls horizontally at ${view.width}px (${width}px wide${
            target ? `, widest ${target}` : ""
          })`,
        );
      } finally {
        await handle.dispose();
      }
    },
  },
  "forced-colors": {
    rule: "smoke-forced-colors",
    what: "the forced-colours check",
    run: async ({ page, finding }) => {
      const handle = await page.evaluateHandle(unfocusedOf);
      try {
        if (await handle.evaluate((u) => u === null)) return false;
        for (const property of (await handle.getProperties()).values()) {
          const el = property.asElement();
          if (el)
            finding(
              "smoke-forced-colors",
              ` ${await el.evaluate(selectorOf)}: no visible focus indicator in forced colours`,
            );
        }
      } finally {
        await handle.dispose();
      }
    },
  },
  links: {
    rule: null,
    what: "the link reading",
    run: async ({ page, at }) => {
      const hrefs = await page.$$eval("a[href]", (as) =>
        as.map((a) => a.href).filter((h) => typeof h === "string"),
      );
      for (const href of hrefs) {
        let url;
        try {
          url = new URL(href);
        } catch {
          continue;
        }
        if (url.origin !== origin) continue;
        const key = noHash(url.href);
        if (!loaded.has(key) && (links.get(key) ?? Infinity) > at)
          links.set(key, at);
      }
    },
  },
};

// visit(engine, browser, route, at, view): load the route (routes[at]) in the
// view, judge it, and run the view's page checks on it.
const visit = async (engine, browser, route, at, view) => {
  const finding = (rule, rest) =>
    pageFinding(engine, view.width, rule, route, rest);
  for (const rule of EVENT_RULES) didRun(rule, engine, view.width);
  const context = await browser.newContext({
    viewport: { width: view.width, height: HEIGHT },
    colorScheme: view.scheme,
    reducedMotion: "reduce",
    forcedColors: view.forcedColors ?? "none",
  });
  try {
    if (cookie) await context.addCookies([{ ...cookie, url: origin }]);
    const page = await context.newPage();
    page.on("console", (m) => {
      if (m.type() === "error")
        finding("smoke-console", `: console error: ${m.text()}`);
    });
    page.on("pageerror", (e) =>
      finding("smoke-page-error", `: uncaught ${e.name}: ${e.message}`),
    );
    page.on("response", (r) => {
      const status = r.status();
      const redirect =
        status >= 300 && status < 400 && r.headers()["location"] !== undefined;
      if ((status < 200 || status >= 300) && !redirect)
        finding("smoke-response", `: ${r.url()} answered ${status}`);
    });
    page.on("requestfailed", (r) =>
      finding(
        "smoke-request-failed",
        `: ${r.url()} failed: ${r.failure()?.errorText ?? "unknown"}`,
      ),
    );
    try {
      await page.goto(origin + route, {
        waitUntil: "networkidle",
        timeout: limit,
      });
    } catch (e) {
      finding(
        "smoke-load",
        `: the page didn't load and go quiet within ${seconds}s: ${firstLine(e)}`,
      );
      return;
    }
    for (const name of view.checks) {
      const check = CHECKS[name];
      try {
        const done = await within(
          check.run({ page, route, at, view, finding }),
          check.what,
        );
        if (check.rule && done !== false)
          didRun(check.rule, engine, view.width);
      } catch (e) {
        finding("smoke-load", `: ${check.what} didn't run: ${firstLine(e)}`);
      }
    }
  } finally {
    await context.close();
  }
};

// The engines' browsers, started at once; none loads a page unless all three
// start.
const started = await Promise.all(ENGINES.map(launch));
const missing = started.filter((s) => s.missing).map((s) => s.missing);
try {
  if (missing.length === 0) {
    await Promise.all(
      ENGINES.map(async (engine, i) => {
        for (const [at, route] of routes.entries())
          for (const view of VIEWS)
            await visit(engine, started[i].browser, route, at, view);
      }),
    );
    const api = await request.newContext({
      extraHTTPHeaders: cookie
        ? { cookie: `${cookie.name}=${cookie.value}` }
        : {},
    });
    try {
      for (const [url, at] of links) {
        const from = routes[at];
        try {
          const r = await api.get(url, { timeout: limit, maxRedirects: 20 });
          if (r.status() >= 400)
            line("smoke-link", `${from} ${url} ${r.status()}`);
          await r.dispose();
        } catch (e) {
          line("smoke-link", `${from} ${url} failed: ${firstLine(e)}`);
        }
      }
    } finally {
      await api.dispose();
    }
  }
} finally {
  await Promise.all(started.map((s) => s.browser?.close()));
}
if (missing.length > 0) {
  process.stdout.write(missing.map((l) => l + "\n").join(""));
  process.exit(1);
}

// covers(found, where): <found> holds every one of <where>.
const covers = (found, where) => [...where].every((x) => found.has(x));
for (const [key, { rule, route, rest, engines, widths }] of pageFindings) {
  const where = ran.get(rule) ?? { engines: new Set(), widths: new Set() };
  const tokens = [];
  if (!covers(engines, where.engines))
    tokens.push(
      ENGINES.filter((e) => engines.has(e.name))
        .map((e) => e.name)
        .join(","),
    );
  if (!covers(widths, where.widths))
    tokens.push(
      [...widths]
        .sort((a, b) => a - b)
        .map((w) => `${w}px`)
        .join(","),
    );
  out.push(
    tokens.length === 0
      ? key
      : `package.json:1 ${rule} ${strip(`${route} ${tokens.join(" ")}${rest}`)}`,
  );
}
process.stdout.write(
  [...new Set(out)]
    .sort()
    .map((l) => l + "\n")
    .join(""),
);
