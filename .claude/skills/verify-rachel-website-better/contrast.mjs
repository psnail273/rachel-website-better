// A text box's contrast, read from screenshots once its transitions have
// settled. The verify skill's generator (factory/adapters/nextjs/verify-skill.sh)
// copies it into the skill's folder; app.sh's `contrast` runs it on the app it
// started. Run from the project root:
//   node .claude/skills/verify-<project>/contrast.mjs <url> <selector> [--width <px>] [--scheme light|dark] [--cookie <name>=<value>] [--save <prefix>] [--seconds <n>]
// One headless Chromium (the project's @playwright/test, found from the working
// directory; PLAYWRIGHT_BROWSERS_PATH says where) opens <url> at <width> px
// (default 1280; the window 900 tall, one CSS px a pixel) in <scheme> (default
// light), waits for the page to load
// and its network to go quiet, for the fonts, and scrolls the first element
// <selector> matches into view. Then it settles the page: every running
// animation and transition is finished (an infinite one cancelled), until none
// runs, and transitions and animations are turned off from then on, so no colour
// is read mid-way (a scroll-triggered fade included). It takes the element's box
// twice: as it is, and with the text inside it made transparent. The pixels that
// differ are the text's; the rest is what is behind it.
//
// stdout, one `<key> <value>` a line:
//   contrast <ratio>:1        the text colour against the background colour
//   text #rrggbb              the text's colour: the most frequent colour of
//                             its tenth of pixels that stand out most from
//                             what is under them (a glyph's core, not its
//                             anti-aliased edge)
//   background #rrggbb <n>%   the commonest colour behind the text, and how
//                             much of the box it fills
//   worst <ratio>:1 #rrggbb   the text colour against the background pixel
//                             right under the text it contrasts least with
//                             (the same as contrast on a flat background)
//   matched <n>               how many elements the selector matched (the
//                             first is read)
//   saved <file>              with --save: <prefix>-text.png and
//                             <prefix>-background.png, the two screenshots
// A ratio is WCAG 2's, (L1 + 0.05) / (L2 + 0.05) from sRGB relative luminance,
// cut (not rounded) to two decimals, so 4.499 reads 4.49, short of 4.5.
// Exits 0 with a reading, 1 when there is none (no element, no text pixels,
// Chromium didn't start; the reason on stderr), 2 on a usage error.
import { writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { inflateSync } from "node:zlib";

// channel <0..255>: the sRGB channel, linear.
const channel = (c) => {
  const s = c / 255;
  return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
};

// luminance [r, g, b]: WCAG's relative luminance.
export const luminance = ([r, g, b]) =>
  0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);

// ratio <a> <b>: WCAG's contrast ratio of two colours, uncut.
export const ratio = (a, b) => {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
};

// cut <ratio>: two decimals, cut down.
export const cut = (r) => (Math.floor(r * 100 + 1e-9) / 100).toFixed(2);

export const hex = ([r, g, b]) =>
  "#" + [r, g, b].map((c) => c.toString(16).padStart(2, "0")).join("");

// decodePng <buffer>: { width, height, data } with data RGBA, 4 bytes a pixel;
// 8-bit truecolour (colour type 2) or truecolour with alpha (6), not interlaced:
// what Chromium writes.
export const decodePng = (buffer) => {
  const sig = "89504e470d0a1a0a";
  if (buffer.subarray(0, 8).toString("hex") !== sig)
    throw new Error("not a PNG");
  let at = 8;
  let width = 0;
  let height = 0;
  let type = 0;
  const idat = [];
  while (at < buffer.length) {
    const length = buffer.readUInt32BE(at);
    const name = buffer.toString("ascii", at + 4, at + 8);
    const body = buffer.subarray(at + 8, at + 8 + length);
    if (name === "IHDR") {
      width = body.readUInt32BE(0);
      height = body.readUInt32BE(4);
      type = body[9];
      if (body[8] !== 8 || (type !== 2 && type !== 6) || body[12] !== 0)
        throw new Error(
          `a PNG it can't read: depth ${body[8]}, colour type ${type}, interlace ${body[12]}`,
        );
    } else if (name === "IDAT") idat.push(body);
    else if (name === "IEND") break;
    at += 12 + length;
  }
  const bpp = type === 6 ? 4 : 3;
  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * bpp;
  const rows = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? rows[y * stride + x - bpp] : 0;
      const b = y > 0 ? rows[(y - 1) * stride + x] : 0;
      const c = x >= bpp && y > 0 ? rows[(y - 1) * stride + x - bpp] : 0;
      let v = line[x];
      if (filter === 1) v += a;
      else if (filter === 2) v += b;
      else if (filter === 3) v += (a + b) >> 1;
      else if (filter === 4) {
        const p = a + b - c;
        const pa = Math.abs(p - a);
        const pb = Math.abs(p - b);
        const pc = Math.abs(p - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      } else if (filter !== 0) throw new Error(`PNG filter ${filter}`);
      rows[y * stride + x] = v & 255;
    }
  }
  const data = new Uint8Array(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    data[i * 4] = rows[i * bpp];
    data[i * 4 + 1] = rows[i * bpp + 1];
    data[i * 4 + 2] = rows[i * bpp + 2];
    data[i * 4 + 3] = bpp === 4 ? rows[i * bpp + 3] : 255;
  }
  return { width, height, data };
};

const at = (data, i) => [data[i * 4], data[i * 4 + 1], data[i * 4 + 2]];
const key = (c) => (c[0] << 16) | (c[1] << 8) | c[2];
const fromKey = (k) => [(k >> 16) & 255, (k >> 8) & 255, k & 255];

// commonest <colours>: the most frequent colour and its count; ties go to the
// first seen.
const commonest = (colours) => {
  const counts = new Map();
  let best = -1;
  let most = 0;
  for (const c of colours) {
    const k = key(c);
    const n = (counts.get(k) ?? 0) + 1;
    counts.set(k, n);
    if (n > most) [best, most] = [k, n];
  }
  return [fromKey(best), most];
};

// measure <text> <background>: two RGBA pixel arrays of one box (with the
// text, and with it made transparent); the reading, or null when no pixel
// differs.
export const measure = (text, background) => {
  const n = text.length / 4;
  const [bg, filled] = commonest(
    Array.from({ length: n }, (_, i) => at(background, i)),
  );
  const glyph = [];
  for (let i = 0; i < n; i++) {
    const t = at(text, i);
    const b = at(background, i);
    if (key(t) !== key(b)) glyph.push({ t, b, r: ratio(t, b) });
  }
  if (glyph.length === 0) return null;
  glyph.sort((x, y) => y.r - x.r);
  const core = glyph.slice(0, Math.max(1, Math.ceil(glyph.length / 10)));
  const [colour] = commonest(core.map((g) => g.t));
  let worst = null;
  for (const { b } of glyph) {
    const r = ratio(colour, b);
    if (worst === null || r < worst.r) worst = { r, b };
  }
  return {
    contrast: ratio(colour, bg),
    text: colour,
    background: bg,
    share: Math.round((filled / n) * 100),
    worst: worst.r,
    worstBackground: worst.b,
  };
};

// The page settles: every animation and transition finished (an infinite one
// cancelled), until none runs, then both turned off from here on.
const SETTLE = async () => {
  const frame = () => new Promise((r) => requestAnimationFrame(() => r()));
  await document.fonts.ready;
  for (let round = 0; round < 20; round++) {
    await frame();
    const running = document
      .getAnimations()
      .filter((a) => a.playState !== "finished");
    if (running.length === 0) break;
    for (const a of running) {
      try {
        a.finish();
      } catch {
        a.cancel();
      }
    }
  }
  const style = document.createElement("style");
  style.textContent =
    "*, *::before, *::after { transition: none !important; animation-play-state: paused !important; caret-color: transparent !important; }";
  document.head.append(style);
  await frame();
  await frame();
};

const HIDE =
  "[data-contrast-probe], [data-contrast-probe] * { color: transparent !important; -webkit-text-fill-color: transparent !important; text-shadow: none !important; text-decoration-color: transparent !important; }";

const usage = () => {
  console.error(
    "usage: node contrast.mjs <url> <selector> [--width <px>] [--scheme light|dark] [--cookie <name>=<value>] [--save <prefix>] [--seconds <n>]",
  );
  process.exit(2);
};

const main = async (argv) => {
  const [url, selector, ...rest] = argv;
  if (!url || !selector) usage();
  const opt = { width: 1280, scheme: "light", seconds: 60 };
  for (let i = 0; i < rest.length; i += 2) {
    const [name, value] = [rest[i], rest[i + 1]];
    if (value === undefined) usage();
    if (name === "--width") opt.width = Number(value);
    else if (name === "--scheme") opt.scheme = value;
    else if (name === "--cookie") opt.cookie = value;
    else if (name === "--save") opt.save = value;
    else if (name === "--seconds") opt.seconds = Number(value);
    else usage();
  }
  if (
    !(opt.width > 0) ||
    !(opt.seconds > 0) ||
    !["light", "dark"].includes(opt.scheme) ||
    (opt.cookie !== undefined && !opt.cookie.includes("="))
  )
    usage();
  // The project's Playwright, from the project root (the working directory),
  // wherever this file is.
  const { chromium } = createRequire(join(process.cwd(), "package.json"))(
    "@playwright/test",
  );
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
  } catch (e) {
    console.error(
      `contrast: Chromium didn't start (${String(e?.message ?? e).split("\n")[0]}); PLAYWRIGHT_BROWSERS_PATH is '${process.env.PLAYWRIGHT_BROWSERS_PATH ?? ""}'`,
    );
    return 1;
  }
  try {
    const context = await browser.newContext({
      viewport: { width: opt.width, height: 900 },
      deviceScaleFactor: 1,
      colorScheme: opt.scheme,
    });
    if (opt.cookie) {
      const i = opt.cookie.indexOf("=");
      await context.addCookies([
        {
          name: opt.cookie.slice(0, i),
          value: opt.cookie.slice(i + 1),
          url,
        },
      ]);
    }
    const page = await context.newPage();
    page.setDefaultTimeout(opt.seconds * 1000);
    await page.goto(url, { waitUntil: "networkidle" });
    const all = page.locator(selector);
    const matched = await all.count();
    if (matched === 0) {
      console.error(`contrast: no element matches ${selector} at ${url}`);
      return 1;
    }
    const box = all.first();
    await box.scrollIntoViewIfNeeded();
    await page.evaluate(SETTLE);
    const clip = await box.boundingBox();
    if (!clip || clip.width < 1 || clip.height < 1) {
      console.error(`contrast: ${selector} has no box to read`);
      return 1;
    }
    const shot = () => page.screenshot({ clip, animations: "disabled" });
    const withText = await shot();
    await box.evaluate((el) => el.setAttribute("data-contrast-probe", ""));
    await page.addStyleTag({ content: HIDE });
    await page.evaluate(SETTLE);
    const without = await shot();
    const reading = measure(decodePng(withText).data, decodePng(without).data);
    if (!reading) {
      console.error(
        `contrast: no text pixels in ${selector}'s box (no text in it, or the text is already transparent)`,
      );
      return 1;
    }
    console.log(`contrast ${cut(reading.contrast)}:1`);
    console.log(`text ${hex(reading.text)}`);
    console.log(`background ${hex(reading.background)} ${reading.share}%`);
    console.log(
      `worst ${cut(reading.worst)}:1 ${hex(reading.worstBackground)}`,
    );
    console.log(`matched ${matched}`);
    if (opt.save) {
      writeFileSync(`${opt.save}-text.png`, withText);
      writeFileSync(`${opt.save}-background.png`, without);
      console.log(`saved ${opt.save}-text.png`);
      console.log(`saved ${opt.save}-background.png`);
    }
    return 0;
  } catch (e) {
    console.error(`contrast: ${String(e?.message ?? e).split("\n")[0]}`);
    return 1;
  } finally {
    await browser.close();
  }
};

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href)
  process.exitCode = await main(process.argv.slice(2));
