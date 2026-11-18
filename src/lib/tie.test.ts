import { describe, expect, it } from "vitest";
import { tieItem, tieLabel, tieLast } from "./tie";

const NBSP = " ";
const ZWSP = "​";

describe("tie", () => {
  it("ties the last two words of a paragraph", () => {
    expect(tieLast("a b c d e")).toBe(`a b c d${NBSP}e`);
    expect(tieLast("two words")).toBe(`two${NBSP}words`);
    expect(tieLast("one")).toBe("one");
    expect(tieLast("")).toBe("");
  });

  it("ties a three-word label after its first word and a longer one before its last", () => {
    expect(tieLabel("American Kantorei Performance")).toBe(
      `American${NBSP}Kantorei Performance`,
    );
    expect(tieLabel("Education and Training")).toBe(
      `Education${NBSP}and Training`,
    );
    expect(tieLabel("Let everything happen to you")).toBe(
      `Let everything happen to${NBSP}you`,
    );
    expect(tieLabel("Upcoming events")).toBe("Upcoming events");
    expect(tieLabel("Media")).toBe("Media");
  });

  it("breaks a list item after a slash between words", () => {
    expect(tieItem("balance/relationship")).toBe(`balance/${ZWSP}relationship`);
    expect(tieItem("Work life balance/relationship issues")).toBe(
      `Work life balance/${ZWSP}relationship${NBSP}issues`,
    );
    expect(tieItem("Eating/body image")).toBe("Eating/body image");
    expect(tieItem("Identity development")).toBe("Identity development");
    expect(tieItem("Self-doubt and imposter syndrome")).toBe(
      `Self-doubt and imposter${NBSP}syndrome`,
    );
  });

  it("puts a word joiner after each hyphen of a tied pair, and only there, in tieLast, tieLabel and tieItem", () => {
    expect(tieItem("Develop greater self worth and self-confidence")).toBe(
      "Develop greater self worth and\u00a0self-\u2060confidence",
    );
    expect(tieItem("Develop self-care strategies")).toBe(
      "Develop\u00a0self-\u2060care strategies",
    );
    expect(tieItem("Certification Training in DBT (Alexa Mulee, C-DBT)")).toBe(
      "Certification Training in DBT (Alexa Mulee,\u00a0C-\u2060DBT)",
    );
    expect(tieItem("self-care/self-worth tips")).toBe(
      "self-\u2060care/self-\u2060worth tips",
    );
    expect(tieLabel("Family-Based Treatment works")).toBe(
      "Family-\u2060Based\u00a0Treatment works",
    );
    expect(tieLabel("Re-entry made simple-ish")).toBe(
      "Re-\u2060entry\u00a0made simple-ish",
    );
    expect(tieLast("Build an authentic, values-driven life")).toBe(
      "Build an authentic, values-\u2060driven\u00a0life",
    );
    expect(tieLast("a well-known self-starter")).toBe(
      "a well-\u2060known\u00a0self-\u2060starter",
    );
    expect(tieLast("my mother-in-law")).toBe(
      "my\u00a0mother-\u2060in-\u2060law",
    );
    expect(tieItem("Work-life balance")).toBe("Work-life balance");
    expect(tieItem("Self-doubt and imposter syndrome")).toBe(
      "Self-doubt and imposter\u00a0syndrome",
    );
    expect(tieLabel("Self-doubt and imposter syndrome")).toBe(
      "Self-doubt and imposter\u00a0syndrome",
    );
    expect(tieLabel("Well-being matters")).toBe("Well-being matters");
    expect(tieLast("self-confidence")).toBe("self-confidence");
    expect(tieLast("a self-made plan today")).toBe(
      "a self-made plan\u00a0today",
    );
    expect(tieItem("Open 4\u20135 December")).toBe(
      "Open\u00a04\u20135 December",
    );
    expect(tieItem("Care for musicians, self\u2010worth")).toBe(
      "Care for musicians,\u00a0self\u2010worth",
    );
    expect(tieLabel("Tour dates 4\u20135 December")).toBe(
      "Tour dates 4\u20135\u00a0December",
    );
    expect(tieLabel("Short notes on self\u2010worth")).toBe(
      "Short notes on\u00a0self\u2010worth",
    );
  });

  it("keeps a tied pair's real hyphen and words, with only word joiners added", () => {
    const tied = tieItem("Develop greater self worth and self-confidence");
    expect(tied).toBe(
      "Develop greater self worth and\u00a0self-\u2060confidence",
    );
    expect(tied.replaceAll("\u2060", "").replaceAll("\u00a0", " ")).toBe(
      "Develop greater self worth and self-confidence",
    );
    expect(tied.includes("\u2011")).toBe(false);
  });
});
