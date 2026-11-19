import { describe, expect, it } from "vitest";
import { validateContact } from "./contact";

const EMAIL_EMPTY = "Enter your email address.";
const EMAIL_BAD = "Enter an email address like name@example.com.";
const MESSAGE_EMPTY = "Write a message.";
const MESSAGE_LONG = "Keep your message under 5,000 characters.";

describe("validateContact", () => {
  it("accepts a whole email and a message once trimmed, up to 254 and 5,000 characters", () => {
    const accepted = [
      { email: "ada@example.com", message: "Hello" },
      { email: "  ada@example.com  ", message: "  Hello  " },
      { email: "r@e.co", message: "a".repeat(5000) },
      { email: "a".repeat(242) + "@example.com", message: "Hello" },
      { email: "ada@example.com", message: "  " + "a".repeat(5000) + "  " },
    ];

    const results = accepted.map((fields) => validateContact(fields));

    expect(results).toEqual([{}, {}, {}, {}, {}]);
    expect(("a".repeat(242) + "@example.com").length).toBe(254);
    expect(
      validateContact({
        email: "a".repeat(243) + "@example.com",
        message: "a".repeat(5001),
      }),
    ).toEqual({ email: EMAIL_BAD, message: MESSAGE_LONG });
  });

  it("asks for an email and for a whole address of at most 254 characters", () => {
    const cases: [string, string][] = [
      ["", EMAIL_EMPTY],
      ["   ", EMAIL_EMPTY],
      ["rachel@", EMAIL_BAD],
      ["rachel@example", EMAIL_BAD],
      ["x y@z.co", EMAIL_BAD],
      ["a@b.co c", EMAIL_BAD],
      ["a".repeat(243) + "@example.com", EMAIL_BAD],
    ];

    const results = cases.map(([email]) =>
      validateContact({ email, message: "Hello" }),
    );

    expect(results).toEqual(cases.map(([, email]) => ({ email })));
    expect(("a".repeat(243) + "@example.com").length).toBe(255);
  });

  it("asks for a message of at most 5,000 characters once trimmed", () => {
    const email = "ada@example.com";

    expect(validateContact({ email, message: "" })).toEqual({
      message: MESSAGE_EMPTY,
    });
    expect(validateContact({ email, message: "   " })).toEqual({
      message: MESSAGE_EMPTY,
    });
    expect(validateContact({ email, message: "a".repeat(5001) })).toEqual({
      message: MESSAGE_LONG,
    });
    expect(validateContact({ email, message: " " + "a".repeat(5001) })).toEqual(
      { message: MESSAGE_LONG },
    );
    expect(validateContact({ email: "", message: "" })).toEqual({
      email: EMAIL_EMPTY,
      message: MESSAGE_EMPTY,
    });
  });
});
