import { describe, expect, it } from "vitest";

import { onDemandRevalidation } from "./revalidation";

describe("onDemandRevalidation", () => {
  it("is true when the flag is exactly 1", () => {
    expect(onDemandRevalidation({ ON_DEMAND_REVALIDATION: "1" })).toBe(true);
  });

  it("is false when the flag is unset", () => {
    expect(onDemandRevalidation({})).toBe(false);
  });

  it("is false when the flag is undefined", () => {
    expect(onDemandRevalidation({ ON_DEMAND_REVALIDATION: undefined })).toBe(
      false,
    );
  });

  it.each(["", "0", "true", " 1", "1 "])(
    "is false when the flag is %j",
    (value) => {
      expect(onDemandRevalidation({ ON_DEMAND_REVALIDATION: value })).toBe(
        false,
      );
    },
  );
});
