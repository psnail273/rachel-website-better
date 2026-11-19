import fc from "fast-check";
import { describe, expect, it } from "vitest";
import { validateContact } from "./contact";

const MESSAGE_LONG = "Keep your message under 5,000 characters.";

// Mostly letters, so a string of 5,001 or more survives a trim.
const long = fc
  .string({
    unit: fc.constantFrom("a", "b", "Z", "1", " ", "\n", "\u00e9"),
    minLength: 5001,
    maxLength: 5200,
  })
  .filter((text) => text.trim().length > 5000);

describe("validateContact invariants", () => {
  it("accepts no message longer than 5,000 characters once trimmed", () => {
    fc.assert(
      fc.property(long, (message) => {
        expect(validateContact({ email: "ada@example.com", message })).toEqual({
          message: MESSAGE_LONG,
        });
      }),
      { numRuns: 100 },
    );
  });
});
