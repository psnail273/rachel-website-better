// The app's page routes, as ARCHITECTURE.md's `## Routes` table lists them: the
// smoke step loads each (tools/verify/smoke), and any other step that walks the
// pages reads them here too (contact-sheet, the Scenario driver's looks).
//   node tools/verify/_routes.mjs <architecture file> <rule>
// or, from a script: import { readRoutes, routeSlug } from "./_routes.mjs".
//
// The table is the first fenced block after the `## Routes` heading, before the
// next heading. A line of it is a page route when its first field is a path
// starting with `/` and its second field, the file, when there is one, isn't a
// route handler (route.ts, route.js and the like): a line naming a method first
// (`POST /api/...`), and `/api/health  app/api/health/route.ts`, are no pages. A
// path with a dynamic segment (`/blog/[slug]`) can't be loaded: it is left out,
// with a note. A path listed twice counts once; the order is the table's.
//
// stdout: one route a line; or, when the file lists none (no file, no heading,
// no fenced block under it, no page line in it), one finding,
//   <architecture file>:<line> <rule> <why>
// at the heading's line (1 without one), and exit 1. stderr: a line for each
// dynamic route left out. Exits 0 with routes, 1 without.
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const HANDLER = /(^|\/)route\.[cm]?[jt]sx?$/;

// readRoutes(text): { routes, dynamic, problem } for the text of an
// ARCHITECTURE.md: the page routes in table order, the dynamic ones left out,
// and, when there is no page route, { line, message } saying why (else null).
export function readRoutes(text) {
  const lines = String(text).split(/\r?\n/);
  const heading = lines.findIndex((l) => /^##\s+Routes\s*$/.test(l));
  if (heading < 0)
    return {
      routes: [],
      dynamic: [],
      problem: {
        line: 1,
        message:
          "no `## Routes` section: list the app's page routes there, in a fenced block, one `<path> <file> <what>` a line",
      },
    };
  const at = heading + 1;
  let open = -1;
  for (let i = heading + 1; i < lines.length; i++) {
    if (/^#{1,2}\s/.test(lines[i])) break;
    if (/^\s*(```|~~~)/.test(lines[i])) {
      open = i;
      break;
    }
  }
  if (open < 0)
    return {
      routes: [],
      dynamic: [],
      problem: {
        line: at,
        message:
          "the `## Routes` section has no fenced block: list the app's page routes in one, one `<path> <file> <what>` a line",
      },
    };
  const fence = lines[open].trim().slice(0, 3);
  const routes = [];
  const dynamic = [];
  for (let i = open + 1; i < lines.length; i++) {
    if (lines[i].trim().startsWith(fence)) break;
    const [path, file] = lines[i].trim().split(/\s+/);
    if (!path?.startsWith("/")) continue;
    if (file !== undefined && HANDLER.test(file)) continue;
    if (path.includes("[")) {
      if (!dynamic.includes(path)) dynamic.push(path);
      continue;
    }
    if (!routes.includes(path)) routes.push(path);
  }
  const problem =
    routes.length > 0
      ? null
      : {
          line: at,
          message:
            dynamic.length > 0
              ? `the \`## Routes\` table lists no page route without a dynamic segment (${dynamic.join(", ")}), so none can be loaded`
              : "the `## Routes` table lists no page route: a line whose first field is its path, `/` and on",
        };
  return { routes, dynamic, problem };
}

// routeSlug(route): the route's name in a screenshot's file name, as the Board
// names its files (factory/CONTEXT.md): `home` for `/`, else the path without
// its leading and trailing slashes, each other slash a dash (`/therapy/about`
// is `therapy-about`). A screenshot is `<slug>-<width>-<scheme>.png`.
export function routeSlug(route) {
  const path = String(route).replace(/^\/+|\/+$/g, "");
  return path === "" ? "home" : path.replace(/\//g, "-");
}

if (
  process.argv[1] !== undefined &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  const [file, rule] = process.argv.slice(2);
  let text;
  try {
    text = readFileSync(file, "utf8");
  } catch (e) {
    console.log(
      `${file}:1 ${rule} can't read ${file} (${e?.code ?? e}), whose \`## Routes\` table lists the page routes`,
    );
    process.exit(1);
  }
  const { routes, dynamic, problem } = readRoutes(text);
  for (const path of dynamic)
    console.error(
      `routes: left out ${path}: a dynamic segment can't be loaded without a value`,
    );
  if (problem) {
    console.log(`${file}:${problem.line} ${rule} ${problem.message}`);
    process.exit(1);
  }
  process.stdout.write(routes.map((r) => r + "\n").join(""));
}
