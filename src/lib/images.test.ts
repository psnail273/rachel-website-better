// @vitest-environment happy-dom
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { images, type ImageKey } from "./images";

const keys: ImageKey[] = [
  "hero-mountain-lake",
  "headshot-therapist",
  "headshot-clarinet",
  "headshot-recorder",
];

describe("images", () => {
  it("lists the four site images with their src, alt and size", () => {
    expect(images).toStrictEqual({
      "hero-mountain-lake": {
        src: "/images/hero-mountain-lake.svg",
        alt: "Snow-capped mountains glowing pink at sunset above a still lake",
        width: 1920,
        height: 1280,
      },
      "headshot-therapist": {
        src: "/images/headshot-therapist.svg",
        alt: "Rachel Siegel in glasses and a navy tee, seated outdoors",
        width: 874,
        height: 1184,
      },
      "headshot-clarinet": {
        src: "/images/headshot-clarinet.svg",
        alt: "Rachel Siegel holding her clarinet among white blossoming trees",
        width: 768,
        height: 1024,
      },
      "headshot-recorder": {
        src: "/images/headshot-recorder.svg",
        alt: "Rachel Siegel holding a wooden recorder among pink cherry blossoms",
        width: 1471,
        height: 2048,
      },
    });
  });

  it("draws the hero placeholder as the design's dusk-lake illustration", () => {
    const root = join(import.meta.dirname, "..", "..");
    const publicFile = join(root, "public", "images", "hero-mountain-lake.svg");
    const design = readFileSync(
      join(root, "docs", "design", "hero-dusk-lake.svg"),
      "utf-8",
    );
    const placeholder = existsSync(publicFile)
      ? readFileSync(publicFile, "utf-8")
      : "";
    expect(placeholder).toBe(design);
  });

  it("points every src at a file in public", () => {
    const missing = keys.filter(
      (key) =>
        !existsSync(
          join(import.meta.dirname, "..", "..", "public", images[key].src),
        ),
    );
    expect(missing).toEqual([]);
  });

  it("sizes each placeholder SVG to its slot", () => {
    const expected = (
      [
        ["hero-mountain-lake", "1920", "1280"],
        ["headshot-therapist", "874", "1184"],
        ["headshot-clarinet", "768", "1024"],
        ["headshot-recorder", "1471", "2048"],
      ] as const
    ).map(([key, w, h]) => ({
      key,
      tagName: "svg",
      width: w,
      height: h,
      viewBox: `0 0 ${w} ${h}`,
    }));
    const actual = keys.map((key) => {
      const file = join(
        import.meta.dirname,
        "..",
        "..",
        "public",
        "images",
        `${key}.svg`,
      );
      const source = existsSync(file) ? readFileSync(file, "utf-8") : "";
      const root = new DOMParser().parseFromString(
        source,
        "image/svg+xml",
      ).documentElement;
      return {
        key,
        tagName: root.tagName,
        width: root.getAttribute("width"),
        height: root.getAttribute("height"),
        viewBox: root.getAttribute("viewBox"),
      };
    });
    expect(actual).toEqual(expected);
  });
});
