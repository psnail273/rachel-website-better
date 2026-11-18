import fc from "fast-check";
import { describe, expect, it } from "vitest";
import { tieItem, tieLabel, tieLast } from "./tie";

const NBSP = " ";
const ZWSP = "​";

// A word that holds no space, NBSP or ZWSP, with slashes and hyphens common.
const word = fc.string({
  unit: fc.constantFrom("a", "b", "Z", "é", "/", "-", ".", "1"),
  minLength: 1,
  maxLength: 6,
});

function singleSpaced(maxWords: number): fc.Arbitrary<string> {
  return fc
    .array(word, { minLength: 1, maxLength: maxWords })
    .map((words) => words.join(" "));
}

describe("tie invariants", () => {
  it("gives back the input once tieItem's ZWSPs are removed and its NBSPs turned back into spaces", () => {
    fc.assert(
      fc.property(singleSpaced(8), (text) => {
        const tied = tieItem(text);
        expect(tied.replaceAll(ZWSP, "").replaceAll(NBSP, " ")).toBe(text);
      }),
      { numRuns: 200 },
    );
  });

  it("leaves a label of two words or fewer unchanged in tieLabel", () => {
    fc.assert(
      fc.property(singleSpaced(2), (text) => {
        expect(tieLabel(text)).toBe(text);
      }),
      { numRuns: 200 },
    );
  });

  it("never throws on any string in tieLast", () => {
    fc.assert(
      fc.property(
        fc.oneof(fc.string(), fc.string({ unit: "binary" })),
        (text) => {
          expect(() => tieLast(text)).not.toThrow();
        },
      ),
      { numRuns: 200 },
    );
  });
});
