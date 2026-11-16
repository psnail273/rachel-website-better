// The Scenario driver's fixture server (tools/verify/scenarios): what the app
// fetches during the Scenarios, a Scenario sets. The driver starts it when
// tools/verify/scenario-env names {fixtures}, and smoke and the contact sheet
// when tools/verify/smoke-env does (_server.sh's nx_step_env):
//   node tools/verify/_scenario_fixtures.mjs <port> <folder> [<seed>]
// It listens on 127.0.0.1:<port> (0: a port the OS picks free) and prints
// `listening on http://127.0.0.1:<port>`, the port it got, once it does; when it
// can't (the port taken, a seed file it can't read), it prints why on stderr and
// exits 1. With <seed>, a folder, it first serves each file in it, at any depth,
// as a PUT would: <seed>/<path> at the target /<path>, its Content-Type by its
// extension (.ics text/calendar, .json application/json, .html text/html, .xml
// application/xml, .txt text/plain, else application/octet-stream); a <seed>
// that isn't there is no seed. Each request target (path and query) is one
// fixture:
//   PUT <target>      from now on GET <target> answers 200 with this request's
//                     body and Content-Type; answers 204
//   DELETE <target>   from now on GET <target> answers 404; answers 204
//   GET, HEAD         the body put there, or 404 when none is
// Any other method answers 405. A fixture lives in <folder> as two files named
// by its target, the body (b<target, URI-encoded>) and its type (t<...>),
// each staged in n<...> by a PUT first, so the driver empties the folder
// between Scenario files and each starts with nothing served. It runs until
// TERM.
import {
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { createServer } from "node:http";
import { extname, join } from "node:path";

const [port, folder, seed] = process.argv.slice(2);
if (!/^\d+$/.test(port ?? "") || !folder) {
  console.error("usage: node _scenario_fixtures.mjs <port> <folder> [<seed>]");
  process.exit(2);
}

const files = (target) => {
  const name = encodeURIComponent(target);
  return {
    body: join(folder, `b${name}`),
    type: join(folder, `t${name}`),
    // Staged here first: n is no fixture's first letter.
    staged: join(folder, `n${name}`),
  };
};
const answer = (response, status, headers = {}, body = undefined) => {
  response.writeHead(status, headers);
  response.end(body);
};

// put <target> <body> <type>: from now on GET <target> answers the body.
const put = (target, body, type) => {
  const f = files(target);
  mkdirSync(folder, { recursive: true });
  // The body first, then its type, each renamed into place whole: a GET finds
  // both or answers 404.
  writeFileSync(f.staged, body);
  renameSync(f.staged, f.body);
  writeFileSync(f.staged, type);
  renameSync(f.staged, f.type);
};

const TYPES = {
  ".ics": "text/calendar",
  ".json": "application/json",
  ".html": "text/html",
  ".xml": "application/xml",
  ".txt": "text/plain",
};
// sow <dir> <target>: each file under <dir> put at <target>/<its name>.
const sow = (dir, target) => {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const at = join(dir, entry.name);
    const to = `${target}/${entry.name}`;
    if (entry.isDirectory()) sow(at, to);
    else
      put(
        to,
        readFileSync(at),
        TYPES[extname(entry.name).toLowerCase()] ?? "application/octet-stream",
      );
  }
};
if (seed) {
  try {
    sow(seed, "");
  } catch (error) {
    if (error.code !== "ENOENT" || error.path !== seed) {
      console.error(`fixtures: seed: ${error.message}`);
      process.exit(1);
    }
  }
}

const server = createServer((request, response) => {
  const target = request.url ?? "/";
  if (encodeURIComponent(target).length > 200) {
    answer(response, 414);
    return;
  }
  const f = files(target);
  if (request.method === "GET" || request.method === "HEAD") {
    let body;
    let type;
    try {
      body = readFileSync(f.body);
      type = readFileSync(f.type, "utf8");
    } catch {
      answer(response, 404);
      return;
    }
    answer(
      response,
      200,
      { "content-type": type, "content-length": body.length },
      request.method === "GET" ? body : undefined,
    );
  } else if (request.method === "PUT") {
    const chunks = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => {
      put(
        target,
        Buffer.concat(chunks),
        request.headers["content-type"] ?? "application/octet-stream",
      );
      answer(response, 204);
    });
  } else if (request.method === "DELETE") {
    rmSync(f.type, { force: true });
    rmSync(f.body, { force: true });
    answer(response, 204);
  } else {
    answer(response, 405, { allow: "GET, HEAD, PUT, DELETE" });
  }
});
server.on("error", (error) => {
  console.error(`fixtures: ${error.message}`);
  process.exit(1);
});
server.listen(Number(port), "127.0.0.1", () => {
  console.log(`listening on http://127.0.0.1:${server.address().port}`);
});
process.on("SIGTERM", () => process.exit(0));
