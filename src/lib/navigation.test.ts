import { describe, expect, it } from "vitest";
import { currentSection } from "./navigation";

describe("currentSection", () => {
  it("names the section a pathname belongs to", () => {
    const pathnames = [
      "/",
      "/therapy",
      "/therapy/about",
      "/therapy/education-and-training",
      "/therapyx",
      "/performing",
      "/performing/bio",
      "/performing-arts",
      "/contact",
      "/contacts",
      "/about/therapy",
      null,
    ];

    expect(pathnames.map((pathname) => currentSection(pathname))).toEqual([
      null,
      "therapy",
      "therapy",
      "therapy",
      null,
      "performing",
      "performing",
      null,
      "contact",
      null,
      null,
      null,
    ]);
  });
});
