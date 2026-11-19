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
        src: "/images/hero-mountain-lake.jpg",
        alt: "Snow-capped mountains glowing pink at sunset above a still lake",
        width: 2600,
        height: 1736,
      },
      "headshot-therapist": {
        src: "/images/headshot-therapist.jpg",
        alt: "Rachel Siegel in glasses and a navy tee, seated outdoors",
        width: 874,
        height: 1184,
      },
      "headshot-clarinet": {
        src: "/images/headshot-clarinet.jpg",
        alt: "Rachel Siegel holding her clarinet among white blossoming trees",
        width: 684,
        height: 922,
      },
      "headshot-recorder": {
        src: "/images/headshot-recorder.jpg",
        alt: "Rachel Siegel holding a wooden recorder among pink cherry blossoms",
        width: 716,
        height: 998,
      },
    });
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

  it("gives each image the pixel size of its JPEG", () => {
    const actual = keys.map((key) => {
      const bytes = readFileSync(
        join(import.meta.dirname, "..", "..", "public", images[key].src),
      );
      let at = 2;
      while (at < bytes.length) {
        const marker = bytes.readUInt8(at + 1);
        if (marker >= 0xc0 && marker <= 0xc2) break;
        at += 2 + bytes.readUInt16BE(at + 2);
      }
      return {
        key,
        width: bytes.readUInt16BE(at + 7),
        height: bytes.readUInt16BE(at + 5),
      };
    });
    expect(actual).toEqual([
      { key: "hero-mountain-lake", width: 2600, height: 1736 },
      { key: "headshot-therapist", width: 874, height: 1184 },
      { key: "headshot-clarinet", width: 684, height: 922 },
      { key: "headshot-recorder", width: 716, height: 998 },
    ]);
  });
});
