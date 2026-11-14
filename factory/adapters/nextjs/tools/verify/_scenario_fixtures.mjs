// The Scenario driver's fixture server (tools/verify/scenarios): what the app
// fetches during the Scenarios, a Scenario sets. The driver starts it when
// tools/verify/scenario-env names {fixtures}:
//   node tools/verify/_scenario_fixtures.mjs <port> <folder>
// It listens on 127.0.0.1:<port> and prints `listening on
// http://127.0.0.1:<port>` once it does; when it can't (the port taken), it
// prints why on stderr and exits 1. Each request target (path and query) is one
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
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { createServer } from "node:http";
import { join } from "node:path";

const [port, folder] = process.argv.slice(2);
if (!/^\d+$/.test(port ?? "") || !folder) {
  console.error("usage: node _scenario_fixtures.mjs <port> <folder>");
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
      mkdirSync(folder, { recursive: true });
      // The body first, then its type, each renamed into place whole: a GET
      // finds both or answers 404.
      writeFileSync(f.staged, Buffer.concat(chunks));
      renameSync(f.staged, f.body);
      writeFileSync(
        f.staged,
        request.headers["content-type"] ?? "application/octet-stream",
      );
      renameSync(f.staged, f.type);
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
