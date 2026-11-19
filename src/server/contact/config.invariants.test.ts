import fc from "fast-check";
import { describe, expect, it } from "vitest";
import { parseContactConfig } from "./config";

const NAMES = ["RESEND_API_KEY", "CONTACT_TO_EMAIL", "CONTACT_FROM_EMAIL"];

const GOOD: Record<string, string> = {
  RESEND_API_KEY: "re_test_key",
  CONTACT_TO_EMAIL: "rachel@example.com",
  CONTACT_FROM_EMAIL: "Rachel Siegel website <website@example.com>",
};

const blank = fc.oneof(
  fc.constant(undefined),
  fc.string({ unit: fc.constantFrom(" ", "\t", "\n", "\u00a0") }),
);

describe("parseContactConfig invariants", () => {
  it("never throws on any record of strings and undefined", () => {
    fc.assert(
      fc.property(
        fc.dictionary(
          fc.oneof(fc.constantFrom(...NAMES), fc.string()),
          fc.option(fc.string(), { nil: undefined }),
        ),
        (env) => {
          expect(() => parseContactConfig(env)).not.toThrow();
        },
      ),
      { numRuns: 200 },
    );
  });

  it("is not configured whenever any of the three values is missing or blank", () => {
    fc.assert(
      fc.property(fc.constantFrom(...NAMES), blank, (name, value) => {
        const env: Record<string, string | undefined> = {
          ...GOOD,
          [name]: value,
        };
        expect(parseContactConfig(env)).toBeNull();
      }),
      { numRuns: 100 },
    );
  });
});
