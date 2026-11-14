import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import ts from "typescript";
import { afterEach, describe, expect, it } from "vitest";

let folder = "";

afterEach(async () => {
  if (folder !== "") {
    await rm(folder, { recursive: true, force: true });
    folder = "";
  }
});

describe("tsconfig.json", () => {
  it("tsc leaves out the root Scenario folder and compiles the rest", async () => {
    folder = await mkdtemp(join(tmpdir(), "tsconfig-test-"));
    const config = await readFile(
      join(import.meta.dirname, "..", "tsconfig.json"),
      "utf8",
    );
    await writeFile(join(folder, "tsconfig.json"), config);
    const files = [
      "scenarios/rachels-new-site/play.ts",
      "scenarios/b.tsx",
      "src/page.ts",
      "src/scenarios/c.ts",
    ];
    for (const file of files) {
      await mkdir(dirname(join(folder, file)), { recursive: true });
      await writeFile(join(folder, file), "export {};\n");
    }
    const fatal: ts.Diagnostic[] = [];

    const parsed = ts.getParsedCommandLineOfConfigFile(
      join(folder, "tsconfig.json"),
      {},
      {
        ...ts.sys,
        onUnRecoverableConfigFileDiagnostic: (d) => {
          fatal.push(d);
        },
      },
    );

    expect(fatal).toEqual([]);
    expect(parsed?.errors).toEqual([]);
    expect(parsed?.fileNames.map((f) => relative(folder, f))).toEqual([
      "src/page.ts",
      "src/scenarios/c.ts",
    ]);
  });
});
