import { readdirSync, readFileSync } from "node:fs";
import { join, relative, sep } from "node:path";
import { describe, expect, it } from "vitest";
import { parseContactConfig } from "./config";

const CONFIG = {
  apiKey: "re_test_key",
  to: "rachel@example.com",
  from: "Rachel Siegel website <website@example.com>",
};

const ENV = {
  RESEND_API_KEY: " re_test_key ",
  CONTACT_TO_EMAIL: "rachel@example.com",
  CONTACT_FROM_EMAIL: "Rachel Siegel website <website@example.com>",
  OTHER: "x",
};

const NAMES = ["RESEND_API_KEY", "CONTACT_TO_EMAIL", "CONTACT_FROM_EMAIL"];

function sourceFiles(folder: string): string[] {
  return readdirSync(folder, { withFileTypes: true }).flatMap((entry) => {
    const path = join(folder, entry.name);
    return entry.isDirectory() ? sourceFiles(path) : [path];
  });
}

describe("parseContactConfig", () => {
  it("reads the key and both addresses, trimmed, and ignores every other variable", () => {
    expect(parseContactConfig(ENV)).toStrictEqual(CONFIG);
  });

  it("is not configured when any of the three is missing, empty or only spaces", () => {
    const results: { name: string; value: string; config: unknown }[] = [];
    for (const name of NAMES) {
      for (const value of [undefined, "", "  "]) {
        const without = Object.fromEntries(
          Object.entries(ENV).filter(([key]) => key !== name),
        );
        const env: Record<string, string | undefined> =
          value === undefined ? without : { ...ENV, [name]: value };
        results.push({
          name,
          value: String(value),
          config: parseContactConfig(env),
        });
      }
    }

    expect(results).toEqual(
      NAMES.flatMap((name) =>
        ["undefined", "", "  "].map((value) => ({ name, value, config: null })),
      ),
    );
    expect(parseContactConfig({})).toBeNull();
    expect(parseContactConfig(ENV)).not.toBeNull();
  });

  it("is the only source file that names RESEND_API_KEY", () => {
    const root = join(import.meta.dirname, "..", "..", "..");
    const named = sourceFiles(join(root, "src"))
      .filter((file) => !file.includes(".test."))
      .filter((file) => readFileSync(file, "utf8").includes("RESEND_API_KEY"))
      .map((file) => relative(root, file).split(sep).join("/"))
      .sort();

    expect(named).toEqual(["src/server/contact/config.ts"]);
  });
});
