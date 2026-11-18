// Shared by the Scenarios of "Design system, shell and Home" (Spec #26,
// Feature 1). Declares no test.
import { expect, type Locator } from "@playwright/test";

export const phone = { width: 390, height: 844 };
export const desktop = { width: 1280, height: 900 };

// Every page of the site, as ARCHITECTURE.md's Routes table and the site's
// navigation (src/lib/navigation.ts) name them.
export const pages = [
  { name: "Home", path: "/" },
  { name: "About Me", path: "/therapy/about" },
  { name: "Services", path: "/therapy/services" },
  { name: "Education and Training", path: "/therapy/education-and-training" },
  { name: "Bio", path: "/performing/bio" },
  { name: "Media", path: "/performing/media" },
  { name: "Contact", path: "/contact" },
] as const;

export type Rgba = { r: number; g: number; b: number; a: number };

// parseColor: a computed CSS colour, as getComputedStyle gives it
// ("rgb(…)", "rgba(…)", "color(srgb …)" or "transparent"), as 0–255 channels
// and an alpha.
export function parseColor(value: string): Rgba {
  const text = value.trim();
  if (text === "transparent") return { r: 0, g: 0, b: 0, a: 0 };
  const rgb = /^rgba?\(([^)]+)\)$/.exec(text);
  if (rgb) {
    const parts = rgb[1].split(/[\s,/]+/).filter(Boolean).map(Number);
    return { r: parts[0], g: parts[1], b: parts[2], a: parts[3] ?? 1 };
  }
  const srgb = /^color\(srgb\s+([^)]+)\)$/.exec(text);
  if (srgb) {
    const parts = srgb[1].split(/[\s/]+/).filter(Boolean).map(Number);
    return {
      r: parts[0] * 255,
      g: parts[1] * 255,
      b: parts[2] * 255,
      a: parts[3] ?? 1,
    };
  }
  throw new Error(`a colour this helper can't read: ${value}`);
}

// luminance: WCAG's relative luminance of an opaque colour, 0 (black) to 1
// (white).
export function luminance({ r, g, b }: Rgba): number {
  const lin = (c: number) => {
    const s = c / 255;
    return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

// style: one computed style property of the element.
export function style(target: Locator, property: string): Promise<string> {
  return target.evaluate(
    (el, name) => getComputedStyle(el).getPropertyValue(name),
    property,
  );
}

// left: the element's left edge in the window, in CSS pixels.
export async function left(target: Locator): Promise<number> {
  await expect(target).toBeVisible();
  const box = await target.boundingBox();
  expect(box, "it has a box on the page").not.toBeNull();
  return box!.x;
}
