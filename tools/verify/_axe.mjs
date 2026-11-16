// axe-core on a page, for the smoke step (_smoke_page.mjs) and the contact
// sheet (_contact_sheet.mjs): the same rules, and the same selector for an
// element, in both.
//   import { axe, describe } from "./_axe.mjs";
//   const { violations, incomplete } = await axe(page);
//   const target = await describe(page, node.target);
// axe(page) runs @axe-core/playwright (the project's) on the page with the
// rules of TAGS: WCAG 2.0, 2.1 and 2.2 A and AA, and axe's best practices,
// leaving out next dev's error overlay (nextjs-portal), which is no page's.
// describe(page, target) is a selector for the element axe's <target> names,
// with no position in it: its tag, id and classes, under its parent's
// (`li.card > p.title`), none under body, so the items of a list, however many
// the page's data makes, are one; axe's own selector, its parts joined by
// " >>> ", when the element is inside a frame or a shadow root, or isn't found.
import { AxeBuilder } from "@axe-core/playwright";

export const TAGS = [
  "wcag2a",
  "wcag2aa",
  "wcag21a",
  "wcag21aa",
  "wcag22aa",
  "best-practice",
];

export const axe = (page) =>
  new AxeBuilder({ page }).withTags(TAGS).exclude("nextjs-portal").analyze();

export const describe = async (page, target) => {
  const own = target
    .map((t) => (Array.isArray(t) ? t.join(" >>> ") : t))
    .join(" >>> ");
  if (target.length !== 1 || typeof target[0] !== "string") return own;
  try {
    return await page.$eval(target[0], selectorOf);
  } catch {
    return own;
  }
};

// selectorOf(el): describe's selector for an element, run in the page (a
// page.$eval or page.$$eval callback; it uses nothing outside itself).
export const selectorOf = (el) => {
  const part = (e) =>
    e.tagName.toLowerCase() +
    (e.id ? "#" + CSS.escape(e.id) : "") +
    [...e.classList].map((c) => "." + CSS.escape(c)).join("");
  const up = el.parentElement;
  return up && up !== document.body && up !== document.documentElement
    ? `${part(up)} > ${part(el)}`
    : part(el);
};
