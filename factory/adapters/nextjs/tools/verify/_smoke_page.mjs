// The smoke step's browser: loads each page route headless in Chromium
// (Playwright, the project's @playwright/test), in a light and a dark colour
// scheme, and prints what went wrong on it.
//   node tools/verify/_smoke_page.mjs <origin> <seconds> <route>...
// It opens <origin><route> in a fresh browser context for each scheme, and waits,
// at most <seconds> for each load, for the page to load and its network to go
// quiet (Playwright's networkidle: no request for 500 ms), so the requests its
// scripts make count too. On a page that loaded it then runs axe-core
// (@axe-core/playwright: the wcag2a, wcag2aa and wcag22aa rules), at most
// <seconds> too, and gathers its same-origin links. Once every route is loaded,
// each link (its #hash left off, each once, a route already loaded left out)
// is requested with GET, redirects followed, at most <seconds> each. Off-site
// links aren't requested: the step runs offline.
//
// stdout: one finding a line, sorted, each once, the origin left out of every
// message, and its host and port alone written <host> (the server's port
// changes from run to run, and a finding must not):
//   package.json:1 smoke-console <route>: console error: <text>
//   package.json:1 smoke-page-error <route>: uncaught <name>: <message>
//   package.json:1 smoke-response <route>: <request path> answered <status>
//   package.json:1 smoke-request-failed <route>: <request path> failed: <reason>
//   package.json:1 smoke-load <route>: <why the page never loaded, or axe or the
//                  link reading never finished on it>
//   package.json:1 smoke-a11y <route> <light|dark> <axe rule id> <target>: <help>
//   package.json:1 smoke-link <from route> <href> <status, or failed: <reason>>
//   tools/verify/local.env:1 browser-missing <why Chromium didn't start>
// The first five name no scheme: a fault in both schemes is one finding. An
// axe <target> is a selector for the element with no position in it: its tag,
// id and classes, under its parent's (`li.card > p.title`), so the items of a
// list, however many the page's data makes, are one finding; an element axe
// finds inside a frame or a shadow root keeps axe's own selector, its parts
// joined by " >>> ". A link's <from route> is the first route it was found on.
// A response is judged on its status: 2xx passes, and so does a redirect (3xx
// with a Location), whose target is judged in turn; any other fails. A link
// fails on a final status of 400 or more.
// Exits 0 when it got as far as judging the pages (findings or none), 1 when
// Chromium didn't start.
import { AxeBuilder } from "@axe-core/playwright";
import { chromium, request } from "@playwright/test";

const [origin, seconds, ...routes] = process.argv.slice(2);
const limit = Number(seconds) * 1000;
const TAGS = ["wcag2a", "wcag2aa", "wcag22aa"];
const SCHEMES = ["light", "dark"];
const out = [];
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
const line = (rule, message) =>
  out.push(`package.json:1 ${rule} ${strip(message)}`);

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

// describe(page, target): a selector for the element axe's <target> names,
// with no position in it: its tag, id and classes, under its parent's (none
// under body). Axe's own selector, its parts joined by " >>> ", when the
// element is inside a frame or a shadow root, or isn't found.
const describe = async (page, target) => {
  const own = target
    .map((t) => (Array.isArray(t) ? t.join(" >>> ") : t))
    .join(" >>> ");
  if (target.length !== 1 || typeof target[0] !== "string") return own;
  try {
    return await page.$eval(target[0], (el) => {
      const part = (e) =>
        e.tagName.toLowerCase() +
        (e.id ? "#" + CSS.escape(e.id) : "") +
        [...e.classList].map((c) => "." + CSS.escape(c)).join("");
      const up = el.parentElement;
      return up && up !== document.body && up !== document.documentElement
        ? `${part(up)} > ${part(el)}`
        : part(el);
    });
  } catch {
    return own;
  }
};

let browser;
try {
  browser = await chromium.launch({ headless: true });
} catch (e) {
  const first = strip(
    String(e?.message ?? e)
      .split("\n")
      .find((l) => l.trim() !== "") ?? "unknown",
  );
  console.log(
    `tools/verify/local.env:1 browser-missing Chromium didn't start (${first}); run bash tools/verify/bootstrap, which installs it into PLAYWRIGHT_BROWSERS_PATH (tools/verify/local.env), and if it names missing system libraries: pnpm exec playwright install-deps chromium`,
  );
  process.exit(1);
}

// links: each same-origin link, without its hash, and the route it was first
// found on.
const links = new Map();
const loaded = new Set(routes.map((r) => noHash(origin + r)));

// visit(route, scheme): load the route in the scheme, judge it, run axe on it
// and gather its links.
const visit = async (route, scheme) => {
  const finding = (rule, message) => line(rule, `${route}: ${message}`);
  const context = await browser.newContext({ colorScheme: scheme });
  try {
    const page = await context.newPage();
    page.on("console", (m) => {
      if (m.type() === "error")
        finding("smoke-console", `console error: ${m.text()}`);
    });
    page.on("pageerror", (e) =>
      finding("smoke-page-error", `uncaught ${e.name}: ${e.message}`),
    );
    page.on("response", (r) => {
      const status = r.status();
      const redirect =
        status >= 300 && status < 400 && r.headers()["location"] !== undefined;
      if ((status < 200 || status >= 300) && !redirect)
        finding("smoke-response", `${r.url()} answered ${status}`);
    });
    page.on("requestfailed", (r) =>
      finding(
        "smoke-request-failed",
        `${r.url()} failed: ${r.failure()?.errorText ?? "unknown"}`,
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
        `the page didn't load and go quiet within ${seconds}s: ${firstLine(e)}`,
      );
      return;
    }
    try {
      const result = await within(
        new AxeBuilder({ page }).withTags(TAGS).analyze(),
        "axe",
      );
      for (const v of result.violations)
        for (const node of v.nodes) {
          const target = await describe(page, node.target);
          line("smoke-a11y", `${route} ${scheme} ${v.id} ${target}: ${v.help}`);
        }
    } catch (e) {
      finding("smoke-load", `axe didn't run: ${firstLine(e)}`);
    }
    let hrefs = [];
    try {
      hrefs = await page.$$eval("a[href]", (as) =>
        as.map((a) => a.href).filter((h) => typeof h === "string"),
      );
    } catch (e) {
      finding("smoke-load", `its links weren't read: ${firstLine(e)}`);
    }
    for (const href of hrefs) {
      let url;
      try {
        url = new URL(href);
      } catch {
        continue;
      }
      if (url.origin !== origin) continue;
      const key = noHash(url.href);
      if (!loaded.has(key) && !links.has(key)) links.set(key, route);
    }
  } finally {
    await context.close();
  }
};

try {
  for (const route of routes)
    for (const scheme of SCHEMES) await visit(route, scheme);
  const api = await request.newContext();
  try {
    for (const [url, from] of links) {
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
} finally {
  await browser.close();
}
process.stdout.write(
  [...new Set(out)]
    .sort()
    .map((l) => l + "\n")
    .join(""),
);
