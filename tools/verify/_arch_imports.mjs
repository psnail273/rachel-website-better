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
//   input-zod       a function that takes input from outside parses none of it
//                   with zod. Such a function is a route handler (a GET, HEAD,
//                   POST, PUT, PATCH, DELETE or OPTIONS a file app/**/route.*
//                   exports as a function or a const bound to one) that reads
//                   its request's body as data (request.json(), .formData(),
//                   .text(); a raw body, a stream or bytes, is not counted), the
//                   search params of its URL (request.nextUrl.searchParams, new
//                   URL(request.url).searchParams, and through a const made from
//                   the request), or its second argument (the route params); or
//                   a server
//                   action that uses a parameter: an async function a
//                   "use server" file exports, or a function whose body starts
//                   with "use server". It parses with zod when it holds a call
//                   <x>.parse(), .safeParse(), .parseAsync() or
//                   .safeParseAsync() (<x> not JSON, Date, URL, Number or
//                   BigInt), or zod's own parse() and the rest imported from
//                   zod, or calls a function that does: a top-level function
//                   of its file, or one a project file exports that it imports
//                   (by any name, through re-exports too), on down. Writing to
//                   search params (.set, .append, .delete, .sort: a redirect's
//                   copy of the URL) reads none. It checks no more than that, so it misses
//                   a parse of other data beside the input, a handler wrapped
//                   in another function's call (export const POST = withAuth(...)),
//                   one exported as `export { f as POST }`, a validator called
//                   as a method, and a server action built by a library; review
//                   catches those. Tests are exempt.
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

// source(file): the file's syntax tree, once a file.
const sources = new Map();
function source(file) {
  if (sources.has(file)) return sources.get(file);
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
  sources.set(file, sf);
  return sf;
}

// imports(file): { directive, list: [{ spec, line, typeOnly }] }, once a file.
const parsed = new Map();
function imports(file) {
  if (parsed.has(file)) return parsed.get(file);
  const sf = source(file);
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

// --- input-zod ----------------------------------------------------------------------

const isFunctionLike = (n) =>
  !!n &&
  (ts.isFunctionDeclaration(n) ||
    ts.isFunctionExpression(n) ||
    ts.isArrowFunction(n) ||
    ts.isMethodDeclaration(n));
const hasModifier = (n, kind) =>
  (ts.canHaveModifiers(n) ? (ts.getModifiers(n) ?? []) : []).some(
    (m) => m.kind === kind,
  );
const isAsync = (fn) => hasModifier(fn, ts.SyntaxKind.AsyncKeyword);

// Does a function's body start with the "use server" directive?
function inlineServer(fn) {
  if (!fn.body || !ts.isBlock(fn.body)) return false;
  for (const st of fn.body.statements) {
    if (!ts.isExpressionStatement(st) || !ts.isStringLiteral(st.expression))
      return false;
    if (st.expression.text === "use server") return true;
  }
  return false;
}

// The names a parameter binds: its own, or those its destructuring binds.
function boundNames(name, into = []) {
  if (ts.isIdentifier(name)) into.push(name.text);
  else
    for (const e of name.elements)
      if (!ts.isOmittedExpression(e)) boundNames(e.name, into);
  return into;
}

// Is the identifier a reference to a value (not a property's or key's name)?
function isReference(id) {
  const p = id.parent;
  if (!p) return true;
  if (ts.isPropertyAccessExpression(p) && p.name === id) return false;
  if (ts.isPropertyAssignment(p) && p.name === id) return false;
  if (ts.isBindingElement(p) && p.propertyName === id) return false;
  if (ts.isParameter(p) || ts.isVariableDeclaration(p)) return p.name !== id;
  if (ts.isBindingElement(p)) return p.name !== id;
  if (ts.isJsxAttribute(p) || ts.isTypeReferenceNode(p)) return false;
  if (ts.isQualifiedName(p)) return false;
  return true;
}

// The names among `names` the node refers to, in order of first use.
function referenced(node, names) {
  const wanted = new Set(names);
  const seen = [];
  const visit = (n) => {
    if (ts.isIdentifier(n) && wanted.has(n.text) && isReference(n)) {
      if (!seen.includes(n.text)) seen.push(n.text);
    }
    ts.forEachChild(n, visit);
  };
  if (node) visit(node);
  return seen;
}

const PARSE = new Set(["parse", "safeParse", "parseAsync", "safeParseAsync"]);
const NOT_ZOD = new Set(["JSON", "Date", "URL", "Number", "BigInt"]);
// Is the call a zod parse: <x>.parse(...), .safeParse, .parseAsync or
// .safeParseAsync, on anything but JSON, Date, URL, Number or BigInt; or zod's
// own parse(schema, data) and the rest, imported from zod (or zod/<path>)?
function isParseCall(file, n) {
  if (!ts.isCallExpression(n)) return false;
  let callee = n.expression;
  if (ts.isNonNullExpression(callee)) callee = callee.expression;
  if (ts.isIdentifier(callee)) {
    const from = topFunctions(file).imported.get(callee.text);
    return (
      !!from && /^zod(\/|$)/.test(from.spec) && PARSE.has(from.name)
    );
  }
  if (!ts.isPropertyAccessExpression(callee) || !PARSE.has(callee.name.text))
    return false;
  return !(
    ts.isIdentifier(callee.expression) && NOT_ZOD.has(callee.expression.text)
  );
}

// topFunctions(file): the file's top-level functions by name (function
// declarations, and consts bound to a function), with `default` for its
// default export; the names each local name was imported as, from where; and
// its exports by another name (`export default f`, `export { f as g }`) or from
// another file (`export { g } from "./x"`, `export * from "./x"`).
const tops = new Map();
function topFunctions(file) {
  if (tops.has(file)) return tops.get(file);
  const sf = source(file);
  const fns = new Map();
  const imported = new Map();
  const exports = new Map(); // exported name -> { local } or { spec, name }
  const star = []; // the specifiers of export * from
  for (const st of sf.statements) {
    if (
      ts.isExportAssignment(st) &&
      !st.isExportEquals &&
      ts.isIdentifier(st.expression)
    ) {
      exports.set("default", { local: st.expression.text });
      continue;
    }
    if (ts.isExportDeclaration(st) && !st.isTypeOnly) {
      const spec =
        st.moduleSpecifier && ts.isStringLiteral(st.moduleSpecifier)
          ? st.moduleSpecifier.text
          : null;
      if (!st.exportClause) {
        if (spec) star.push(spec);
      } else if (ts.isNamedExports(st.exportClause)) {
        for (const e of st.exportClause.elements) {
          if (e.isTypeOnly) continue;
          const name = (e.propertyName ?? e.name).text;
          exports.set(e.name.text, spec ? { spec, name } : { local: name });
        }
      }
      continue;
    }
    if (ts.isFunctionDeclaration(st) && st.body) {
      if (st.name) fns.set(st.name.text, st);
      if (
        hasModifier(st, ts.SyntaxKind.ExportKeyword) &&
        hasModifier(st, ts.SyntaxKind.DefaultKeyword)
      )
        fns.set("default", st);
    } else if (ts.isVariableStatement(st)) {
      for (const d of st.declarationList.declarations) {
        if (ts.isIdentifier(d.name) && isFunctionLike(d.initializer))
          fns.set(d.name.text, d.initializer);
      }
    } else if (
      ts.isExportAssignment(st) &&
      !st.isExportEquals &&
      isFunctionLike(st.expression)
    ) {
      fns.set("default", st.expression);
    } else if (
      ts.isImportDeclaration(st) &&
      ts.isStringLiteral(st.moduleSpecifier) &&
      st.importClause &&
      !st.importClause.isTypeOnly
    ) {
      const spec = st.moduleSpecifier.text;
      const c = st.importClause;
      if (c.name) imported.set(c.name.text, { spec, name: "default" });
      if (c.namedBindings && ts.isNamedImports(c.namedBindings)) {
        for (const e of c.namedBindings.elements) {
          imported.set(e.name.text, {
            spec,
            name: (e.propertyName ?? e.name).text,
          });
        }
      }
    }
  }
  const out = { fns, imported, exports, star };
  tops.set(file, out);
  return out;
}

// localFunction(file, name): the function a name in the file stands for, its
// own or one it imports from a project file; else null. exportedFunction(file,
// name): the function the file exports as that name, through re-exports. One
// lookup visits each file and name once (`seen`), so a cycle of re-exports ends.
function localFunction(file, name, seen = new Set()) {
  const { fns, imported } = topFunctions(file);
  if (fns.has(name)) return { file, fn: fns.get(name) };
  const from = imported.get(name);
  return from ? exportedFrom(file, from.spec, from.name, seen) : null;
}
function exportedFrom(file, spec, name, seen) {
  const target = resolved.get(`${file}\0${spec}`);
  return isProjectFile(target) ? exportedFunction(target, name, seen) : null;
}
function exportedFunction(file, name, seen) {
  const key = `${file}\0${name}`;
  if (seen.has(key)) return null;
  seen.add(key);
  const { fns, exports, star } = topFunctions(file);
  const e = exports.get(name);
  if (e)
    return e.spec
      ? exportedFrom(file, e.spec, e.name, seen)
      : localFunction(file, e.local, seen);
  if (fns.has(name)) return { file, fn: fns.get(name) };
  for (const spec of star) {
    const found = exportedFrom(file, spec, name, seen);
    if (found) return found;
  }
  return null;
}

// The function a call's callee names: one of this file's top-level functions,
// or one a project file exports (by any name, or through a re-export) that this
// file imports; else null.
function calledFunction(file, call) {
  const callee = call.expression;
  return ts.isIdentifier(callee) ? localFunction(file, callee.text) : null;
}

// Does the function parse with zod: a parse call in it, or a call to a function
// (of this file, or imported from a project file) that does, on down?
const validating = new Map();
function validates(file, fn) {
  if (validating.has(fn)) return validating.get(fn);
  validating.set(fn, false); // a cycle validates nothing by itself
  let yes = false;
  const visit = (n) => {
    if (yes) return;
    if (isParseCall(file, n)) {
      yes = true;
      return;
    }
    if (ts.isCallExpression(n)) {
      const called = calledFunction(file, n);
      if (called && validates(called.file, called.fn)) {
        yes = true;
        return;
      }
    }
    ts.forEachChild(n, visit);
  };
  visit(fn);
  validating.set(fn, yes);
  return yes;
}

const BODY = new Set(["json", "formData", "text"]);
const WRITES = new Set(["set", "append", "delete", "sort"]);
// Is the search params access only written to: <it>.set(...), .append, .delete
// or .sort (as a redirect to a copy of the request's URL does)?
function writesTo(n) {
  const p = n.parent;
  return (
    ts.isPropertyAccessExpression(p) &&
    p.expression === n &&
    WRITES.has(p.name.text) &&
    ts.isCallExpression(p.parent) &&
    p.parent.expression === p
  );
}
// What a route handler reads of its input: the request's body as data
// (request.json(), .formData(), .text()), the search params of the request's URL
// (request.nextUrl.searchParams, new URL(request.url).searchParams), or the
// context's params. A value made from the request (const url = new
// URL(request.url)) counts as the request.
function handlerReads(fn) {
  const reads = [];
  const [request, context] = fn.parameters;
  const fromRequest = new Set(request ? boundNames(request.name) : []);
  // Is the expression the request, or made from it: a property, a method's
  // result, or a URL built from it?
  const refers = (e) => {
    if (!e) return false;
    if (ts.isIdentifier(e)) return fromRequest.has(e.text);
    if (
      ts.isPropertyAccessExpression(e) ||
      ts.isParenthesizedExpression(e) ||
      ts.isAwaitExpression(e) ||
      ts.isNonNullExpression(e) ||
      ts.isAsExpression(e)
    )
      return refers(e.expression);
    if (ts.isCallExpression(e)) return refers(e.expression);
    if (ts.isNewExpression(e))
      return (
        ts.isIdentifier(e.expression) &&
        e.expression.text === "URL" &&
        refers(e.arguments?.[0])
      );
    return false;
  };
  const read = (what) => {
    if (!reads.includes(what)) reads.push(what);
  };
  const visit = (n) => {
    if (ts.isVariableDeclaration(n) && n.initializer && refers(n.initializer)) {
      if (ts.isIdentifier(n.name)) fromRequest.add(n.name.text);
      else if (ts.isObjectBindingPattern(n.name))
        for (const e of n.name.elements) {
          const key = (e.propertyName ?? e.name).getText();
          if (key === "searchParams") read("search params");
          if (ts.isIdentifier(e.name)) fromRequest.add(e.name.text);
        }
    }
    if (ts.isPropertyAccessExpression(n) && refers(n.expression)) {
      if (BODY.has(n.name.text)) read("its body");
      if (n.name.text === "searchParams" && !writesTo(n)) read("search params");
    }
    ts.forEachChild(n, visit);
  };
  if (fn.body) visit(fn.body);
  if (context && referenced(fn.body, boundNames(context.name)).length > 0)
    read("route params");
  return reads;
}

// The functions to check, `{ fn, line, what, reads }` for each that reads input.
const METHODS = new Set(["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]);
const routeFile = /^(src\/)?app\/(.*\/)?route\.[cm]?[jt]sx?$/;
function inputFunctions(file) {
  const sf = source(file);
  const found = [];
  const lineOf = (node) =>
    sf.getLineAndCharacterOfPosition(node.getStart(sf)).line + 1;
  const exported = []; // [name, fn, node to point at]
  for (const st of sf.statements) {
    const isExported = hasModifier(st, ts.SyntaxKind.ExportKeyword);
    if (!isExported) continue;
    if (ts.isFunctionDeclaration(st) && st.body)
      exported.push([st.name?.text ?? "default", st, st.name ?? st]);
    else if (ts.isVariableStatement(st))
      for (const d of st.declarationList.declarations)
        if (ts.isIdentifier(d.name) && isFunctionLike(d.initializer))
          exported.push([d.name.text, d.initializer, d.name]);
  }
  for (const st of sf.statements)
    if (ts.isExportAssignment(st) && !st.isExportEquals && isFunctionLike(st.expression))
      exported.push(["default", st.expression, st]);

  const serverFile = imports(file).directive === "server";
  const seen = new Set();
  const action = (name, fn, at) => {
    if (seen.has(fn)) return;
    seen.add(fn);
    const names = fn.parameters.flatMap((p) => boundNames(p.name));
    const used = referenced(fn.body, names);
    if (used.length > 0)
      found.push({
        fn,
        line: lineOf(at),
        what: `server action ${name}`,
        reads: `its argument${used.length > 1 ? "s" : ""} ${used.join(", ")}`,
      });
  };
  if (routeFile.test(file)) {
    for (const [name, fn, at] of exported) {
      if (!METHODS.has(name)) continue;
      const reads = handlerReads(fn);
      if (reads.length > 0)
        found.push({
          fn,
          line: lineOf(at),
          what: `route handler ${name}`,
          reads: reads.join(", "),
        });
    }
  }
  if (serverFile)
    for (const [name, fn, at] of exported) if (isAsync(fn)) action(name, fn, at);
  const visit = (n) => {
    if (isFunctionLike(n) && inlineServer(n)) {
      let name = n.name?.text;
      if (!name && n.parent && ts.isVariableDeclaration(n.parent) && ts.isIdentifier(n.parent.name))
        name = n.parent.name.text;
      action(name ?? "(inline)", n, n.name ?? n);
    }
    ts.forEachChild(n, visit);
  };
  visit(sf);
  return found;
}

for (const f of [...scope].filter(isProjectFile).sort()) {
  if (tests.has(f)) continue;
  for (const { fn, line, what, reads } of inputFunctions(f)) {
    if (validates(f, fn)) continue;
    finding(
      "input-zod",
      f,
      line,
      `${what} reads ${reads} and parses none of it with zod; pass its input through a schema's .parse or .safeParse (here, or in a function this one calls) before using it`,
    );
  }
}

process.stdout.write(out.length > 0 ? out.join("\n") + "\n" : "");
