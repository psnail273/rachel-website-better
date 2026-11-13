// The arch step's import checks, over dependency-cruiser's module graph:
//   node tools/verify/_arch_imports.mjs <graph.json> <scope> <tests>
// <graph.json> is `depcruise --output-type json` on the scoped files, which
// resolves each import (tsconfig.json's paths, extensions, index files) and
// reads each file as TypeScript compiles it: an import the compiler erases, as
// it brings in only types, isn't in the graph, so it counts as none. <scope>
// lists the scoped code files and <tests> the test files among them, one path
// a line. Each file's imports are read again with TypeScript's parser, for the
// line of each import a finding names; one marked as types alone (import type,
// export type, every name marked type) is never named.
//
// Prints one line per finding, `<check>\t<file>:<line> <message>`:
//   client-server   client code imports a server-only module. Client code is
//                   each "use client" file and every file it imports, and they
//                   import, on down. A server-only module is the server-only
//                   package, a file that imports it, a file under server/ or
//                   src/server/, and a route handler (app/**/route.*). A
//                   "use server" file (server actions) is neither: the client
//                   gets a reference to each action, not the file.
//   next-in-app     a file outside Next's routers, app/ and pages/ (or under
//                   src/), imports Next's runtime, next or next/*. Tests are
//                   exempt, and so are the files Next wants at the root:
//                   middleware, proxy, instrumentation, instrumentation-client
//                   and next.config.
//   fonts-local     a file imports next/font/google, which next build fetches.
// Only scoped files get findings. Exits 2 when the graph isn't depcruise's.
import { existsSync, readFileSync } from "node:fs";

const [graphFile, scopeFile, testsFile] = process.argv.slice(2);
const list = (f) =>
  new Set(
    readFileSync(f, "utf8")
      .split("\n")
      .map((l) => l.replace(/\r$/, ""))
      .filter(Boolean),
  );

let graph;
try {
  graph = JSON.parse(readFileSync(graphFile, "utf8"));
  if (!Array.isArray(graph.modules)) throw new Error("no modules");
} catch (e) {
  process.stderr.write(
    `_arch_imports: ${graphFile} isn't dependency-cruiser's JSON: ${e.message}\n`,
  );
  process.exit(2);
}
// The project's TypeScript, found from here (tools/verify/ in the project).
const ts = (await import("typescript")).default;
const scope = list(scopeFile);
const tests = list(testsFile);

// What each file imports once compiled, as `<file>\0<specifier>`; and where each
// leads, to the project file it resolves to, for the local ones.
const kept = new Set();
const resolved = new Map();
for (const m of graph.modules) {
  for (const d of m.dependencies ?? []) {
    if ((d.dependencyTypes ?? []).includes("type-only")) continue;
    kept.add(`${m.source}\0${d.module}`);
    const local =
      !d.couldNotResolve &&
      !d.coreModule &&
      (d.dependencyTypes ?? []).includes("local");
    if (local) resolved.set(`${m.source}\0${d.module}`, d.resolved);
  }
}
const isProjectFile = (f) =>
  typeof f === "string" && !/(^|\/)node_modules\//.test(f) && existsSync(f);

// imports(file): { directive, list: [{ spec, line, typeOnly }] }, once a file.
const parsed = new Map();
function imports(file) {
  if (parsed.has(file)) return parsed.get(file);
  const text = readFileSync(file, "utf8");
  const kind = /\.tsx$/.test(file)
    ? ts.ScriptKind.TSX
    : /\.(jsx)$/.test(file)
      ? ts.ScriptKind.JSX
      : /\.(js|mjs|cjs)$/.test(file)
        ? ts.ScriptKind.JS
        : ts.ScriptKind.TS;
  const sf = ts.createSourceFile(
    file,
    text,
    ts.ScriptTarget.Latest,
    true,
    kind,
  );
  const lineOf = (node) =>
    sf.getLineAndCharacterOfPosition(node.getStart(sf)).line + 1;
  let directive = null;
  for (const s of sf.statements) {
    if (!ts.isExpressionStatement(s) || !ts.isStringLiteral(s.expression))
      break;
    if (s.expression.text === "use client") directive = "client";
    if (s.expression.text === "use server") directive = "server";
  }
  const found = [];
  const named = (elements) =>
    elements.length > 0 && elements.every((e) => e.isTypeOnly);
  const visit = (node) => {
    if (
      ts.isImportDeclaration(node) &&
      ts.isStringLiteral(node.moduleSpecifier)
    ) {
      const c = node.importClause;
      const typeOnly =
        !!c &&
        (c.isTypeOnly ||
          (!c.name &&
            !!c.namedBindings &&
            ts.isNamedImports(c.namedBindings) &&
            named(c.namedBindings.elements)));
      found.push({
        spec: node.moduleSpecifier.text,
        line: lineOf(node),
        typeOnly,
      });
    } else if (
      ts.isExportDeclaration(node) &&
      node.moduleSpecifier &&
      ts.isStringLiteral(node.moduleSpecifier)
    ) {
      const c = node.exportClause;
      const typeOnly =
        node.isTypeOnly || (!!c && ts.isNamedExports(c) && named(c.elements));
      found.push({
        spec: node.moduleSpecifier.text,
        line: lineOf(node),
        typeOnly,
      });
    } else if (
      ts.isImportEqualsDeclaration(node) &&
      ts.isExternalModuleReference(node.moduleReference) &&
      ts.isStringLiteral(node.moduleReference.expression)
    ) {
      found.push({
        spec: node.moduleReference.expression.text,
        line: lineOf(node),
        typeOnly: node.isTypeOnly,
      });
    } else if (
      ts.isCallExpression(node) &&
      node.arguments.length >= 1 &&
      ts.isStringLiteralLike(node.arguments[0])
    ) {
      const callee = node.expression;
      if (
        callee.kind === ts.SyntaxKind.ImportKeyword ||
        (ts.isIdentifier(callee) && callee.text === "require")
      ) {
        found.push({
          spec: node.arguments[0].text,
          line: lineOf(node),
          typeOnly: false,
        });
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(sf);
  const out = { directive, list: found };
  parsed.set(file, out);
  return out;
}

const out = [];
const finding = (check, file, line, message) =>
  out.push(`${check}\t${file}:${line} ${message}`);

// --- client-server ---------------------------------------------------------------

function serverOnly(file) {
  if (imports(file).directive === "server") return null;
  if (/^(src\/)?server\//.test(file)) return "under server/";
  if (/^(src\/)?app\/(.*\/)?route\.[cm]?[jt]sx?$/.test(file))
    return "a route handler";
  if (imports(file).list.some((i) => !i.typeOnly && i.spec === "server-only"))
    return 'it imports "server-only"';
  return null;
}

const files = new Set([...scope].filter(isProjectFile));
for (const m of graph.modules) if (isProjectFile(m.source)) files.add(m.source);

const root = new Map();
const queue = [];
for (const f of [...files].sort()) {
  if (imports(f).directive === "client") {
    root.set(f, f);
    queue.push(f);
  }
}
while (queue.length > 0) {
  const m = queue.shift();
  const client =
    root.get(m) === m
      ? '"use client"'
      : `reached from ${root.get(m)}, a "use client" file`;
  for (const i of imports(m).list) {
    if (i.typeOnly || !kept.has(`${m}\0${i.spec}`)) continue;
    let target = null;
    let why = null;
    if (i.spec === "server-only") {
      target = "server-only";
      why = "the server-only package";
    } else {
      target = resolved.get(`${m}\0${i.spec}`);
      if (!isProjectFile(target) || imports(target).directive === "server")
        continue;
      why = serverOnly(target);
      if (why === null) {
        if (!root.has(target)) {
          root.set(target, root.get(m));
          queue.push(target);
        }
        continue;
      }
      why = `${target}: ${why}`;
    }
    if (scope.has(m)) {
      finding(
        "client-server",
        m,
        i.line,
        `imports ${i.spec}, which is server-only (${why}), into client code (${m} is ${client}); keep it on the server and pass the client what it needs as props or through a server action`,
      );
    }
  }
}

// --- next-in-app and fonts-local ----------------------------------------------------

const nextRoot =
  /^((src\/)?(middleware|proxy|instrumentation|instrumentation-client)\.[cm]?[jt]sx?|next\.config\.[cm]?[jt]s)$/;
for (const f of [...scope].filter(isProjectFile).sort()) {
  for (const i of imports(f).list) {
    if (i.typeOnly || !kept.has(`${f}\0${i.spec}`)) continue;
    if (i.spec === "next/font/google") {
      finding(
        "fonts-local",
        f,
        i.line,
        "imports next/font/google, which next build downloads, and the gates run offline; use next/font/local with the font files in the repo",
      );
    }
    if (
      (i.spec === "next" || i.spec.startsWith("next/")) &&
      !/^(src\/)?(app|pages)\//.test(f) &&
      !tests.has(f) &&
      !nextRoot.test(f)
    ) {
      finding(
        "next-in-app",
        f,
        i.line,
        `imports ${i.spec} outside app/; only app/ (its pages, layouts and route handlers) uses Next's runtime: move this code into app/, or pass it what it needs from there`,
      );
    }
  }
}

process.stdout.write(out.length > 0 ? out.join("\n") + "\n" : "");
