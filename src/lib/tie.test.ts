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
});
