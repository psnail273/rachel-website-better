# Design reference

The design of Spec #26, "editorial calm": written by Opus, built by the Editor, and checked by the Verifier. Each Build Brief cites the sections its slice builds, and its values are exact. A slice that needs a value this file doesn't give asks the Driver, who adds it here, rather than inventing one.

Principles, in order: **readable** (WCAG 2.2 AA in both palettes, a 65ch measure); **calm** (whitespace over boxes, one accent, no loud shadows); **editorial** (large Fraunces display type, asymmetric two-column sections, eyebrow labels); **fast** (no JavaScript for looks or motion where CSS can do it; no layout shift); **honest** (motion and decoration never hide content).

## 1. Colour tokens

CSS custom properties on `:root`, each written with `light-dark(<light>, <dark>)` and `color-scheme: light dark`, so the system setting picks the palette with no script and no flash. Tailwind's `@theme inline` exposes each as `--color-<name>`. Contrast is WCAG 2.x, computed from these exact OKLCH values (the hex column is their sRGB rendering, for reference only).

| Token | Light | Hex | Dark | Hex | Use |
|---|---|---|---|---|---|
| `bg` | `oklch(0.975 0.008 70)` | #faf6f1 | `oklch(0.19 0.04 290)` | #141024 | page background |
| `surface` | `oklch(0.995 0.004 70)` | #fffdfb | `oklch(0.235 0.045 290)` | #1e1a32 | cards, dropdown panels |
| `tint` | `oklch(0.945 0.022 20)` | #fbe7e7 | `oklch(0.27 0.05 320)` | #311e36 | callouts, hover fill |
| `ink` | `oklch(0.30 0.075 300)` | #34244d | `oklch(0.92 0.015 60)` | #ece2db | body text |
| `heading` | `oklch(0.27 0.07 280)` | #202148 | `oklch(0.96 0.012 60)` | #f8f0ea | headings |
| `muted` | `oklch(0.48 0.045 300)` | #615874 | `oklch(0.76 0.03 300)` | #b4adc2 | secondary text, captions, "Coming soon" |
| `accent` | `oklch(0.50 0.14 15)` | #a33949 | `oklch(0.80 0.10 30)` | #f7a597 | eyebrows, links, date months, focus ring |
| `accent-strong` | `oklch(0.42 0.12 330)` | #70306c | `oklch(0.80 0.10 30)` | #f7a597 | primary button fill |
| `on-accent` | `oklch(0.985 0.005 70)` | #fcfaf7 | `oklch(0.22 0.06 295)` | #1d1333 | text on `accent-strong` |
| `border` | `oklch(0.89 0.015 300)` | #dcd9e3 | `oklch(0.33 0.04 290)` | #353249 | hairlines (decorative) |
| `border-strong` | `oklch(0.62 0.04 300)` | #8a819b | `oklch(0.55 0.04 290)` | #716e88 | outlines of controls (≥3:1) |
| `night` | `oklch(0.24 0.065 295)` | #22173a | `oklch(0.15 0.035 290)` | #0b0819 | footer, hero scrim, video posters |
| `on-night` | `oklch(0.95 0.012 60)` | #f5ede7 | same | | text on `night` |
| `on-night-muted` | `oklch(0.80 0.03 300)` | #c0bacf | same | | secondary text on `night` |
| `coral` | `oklch(0.80 0.10 30)` | #f7a597 | same | | accent on `night` (text ok there), ornaments elsewhere |

Measured ratios (both palettes pass; the lowest of each pair is shown):

| Pair | Light | Dark | Needs |
|---|---|---|---|
| `ink` on `bg` / `surface` / `tint` | 13.0 / 13.8 / 11.8 | 14.6 / 13.3 / 12.1 | 4.5 |
| `heading` on `bg` / `surface` | 14.2 / 15.1 | 16.5 / 15.0 | 4.5 |
| `muted` on `bg` / `surface` / `tint` | 6.2 / 6.6 / 5.6 | 8.6 / 7.8 / 7.1 | 4.5 |
| `accent` on `bg` / `surface` / `tint` | 6.0 / 6.4 / 5.5 | 9.6 / 8.7 / 7.9 | 4.5 |
| `on-accent` on `accent-strong` | 8.7 | 9.1 | 4.5 |
| `on-night` / `on-night-muted` / `coral` on `night` | 14.4 / 8.9 / 8.6 | 17.0 / 10.5 / 10.2 | 4.5 |
| `border-strong` on `bg` | 3.4 | 3.8 | 3 |

Rules:
- Text uses only `ink`, `heading`, `muted` or `accent` on `bg`, `surface` or `tint`; `on-accent` on `accent-strong`; `on-night`, `on-night-muted` or `coral` on `night`. No other pairing, and no opacity on text.
- `coral` is never text on a light background (2.5:1). The old `#e8837a` and `#f6d3cc` are retired.
- The token test (#27) computes every pair above from the CSS and fails under its minimum.

## 2. Typography

Fonts are already in `src/app/fonts` (R10). Fraunces is variable on `opsz` (9–144), `wght`, `SOFT` (0–100) and `WONK`; set axes with `font-variation-settings` and `font-optical-sizing: auto`.

Fluid sizes interpolate from a 360 px to a 1280 px viewport:

| Role | Size | Font, settings | Line height | Tracking |
|---|---|---|---|---|
| `display` (Home `h1`) | `clamp(3.25rem, 1.9rem + 6vw, 7rem)` | Fraunces 360, `"SOFT" 50, "WONK" 1`, opsz auto | 0.95 | -0.025em |
| `h1` (page title) | `clamp(2.5rem, 1.75rem + 3.4vw, 4.5rem)` | Fraunces 380, `"SOFT" 50` | 1.02 | -0.02em |
| `h2` | `clamp(1.75rem, 1.4rem + 1.6vw, 2.75rem)` | Fraunces 400, `"SOFT" 30` | 1.1 | -0.015em |
| `h3` | `clamp(1.2rem, 1.1rem + 0.45vw, 1.5rem)` | Fraunces 500 | 1.25 | -0.01em |
| `quote` (pull quote) | `clamp(1.75rem, 1.2rem + 2.4vw, 3rem)` | Fraunces italic 340, `"SOFT" 100` | 1.2 | -0.015em |
| `lead` (intro) | `clamp(1.2rem, 1.05rem + 0.65vw, 1.5rem)` | Source Sans 3 400 | 1.5 | 0 |
| `body` | `clamp(1.0625rem, 1rem + 0.28vw, 1.1875rem)` | Source Sans 3 400 | 1.65 | 0 |
| `small` | `0.9375rem` | Source Sans 3 400 | 1.5 | 0 |
| `eyebrow` | `0.8125rem` | Source Sans 3 600, uppercase | 1.2 | 0.16em |
| `button`, nav | `1rem` | Source Sans 3 600 | 1 | 0.01em |

- Headings use `heading`; `lead` and `body` use `ink`; eyebrows use `accent` (`coral` on `night`).
- Body copy is capped at `65ch`; `lead` at `52ch`. `text-wrap: balance` on headings and pull quotes, `text-wrap: pretty` on paragraphs.
- Bold within body is Source Sans 600, never Fraunces.

## 3. Space, layout, shape

- **Spacing scale** (rem): 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8. Use only these.
- **Container:** `max-width: 76rem`, centred, side gutter `clamp(1.25rem, 4vw, 3rem)`. Text-only pages use a `44rem` inner column for copy.
- **Section rhythm:** vertical padding `clamp(4rem, 2.5rem + 6vw, 8rem)` between top-level sections; `2rem` between a heading and its content; `1.25em` between paragraphs.
- **Grid:** a 12-column grid with `gap: clamp(1.5rem, 3vw, 3rem)` from `md` (768 px) up; one column below. Two-column sections are asymmetric: text 7 columns, aside 4 columns starting at column 9.
- **Radius:** `0.5rem` small controls; `1rem` cards; `1.5rem` images and large cards; `999px` buttons and pills.
- **Shadow** (light only; none in dark): `--shadow-soft: 0 1px 2px oklch(0.27 0.07 300 / 0.06), 0 16px 40px -16px oklch(0.27 0.07 300 / 0.22)`. Cards rest flat with a `border` hairline and gain the shadow on hover.
- **Grain:** an inline SVG `feTurbulence` noise (`baseFrequency 0.8`, `numOctaves 3`) at 5% opacity, `mix-blend-mode: overlay`, on `night` areas only (hero scrim, footer, video posters). Decorative: `aria-hidden`, `pointer-events: none`.
- **Targets:** every control is at least 24×24 px; buttons, menu items and dropdown items are 44 px tall.

## 4. Motion

| Token | Value |
|---|---|
| `--ease-out` | `cubic-bezier(0.22, 1, 0.36, 1)` |
| `--dur-fast` | `150ms` (hover, press) |
| `--dur-mid` | `300ms` (menus, dropdowns) |
| `--dur-slow` | `700ms` (reveals) |

- **Reveal:** elements marked as a reveal section animate from `opacity: 0; translate: 0 1.5rem` to rest, `animation-timeline: view()`, `animation-range: entry 0% entry 60%`, `--ease-out`. All of it sits inside `@supports (animation-timeline: view())` and `@media (prefers-reduced-motion: no-preference)`, so content is visible by default. Above-the-fold content (the hero, page headers) never reveals.
- **Page transition:** React `<ViewTransition>` around the main content; the root crossfades over 250 ms with `--ease-out`. The header has its own `view-transition-name: site-header` and a `none` animation, so it holds still.
- **Hover:** links underline from `text-decoration-color: transparent` to `currentColor`; cards lift `translate: 0 -2px` and take `--shadow-soft`; arrow links move their arrow `0.25rem` right. All `--dur-fast`.
- **Reduced motion:** `@media (prefers-reduced-motion: reduce)` turns every transition and animation off, including view transitions (`::view-transition-group(*) { animation: none }`).

## 5. Components

**Focus ring.** `outline: 2px solid var(--accent); outline-offset: 3px; border-radius: inherit`, on `:focus-visible` only. On `night` areas the ring is `coral`.

**Buttons.**
- *Primary:* `accent-strong` fill, `on-accent` text, pill, `height: 3rem`, padding `0 1.5rem`, `button` type. Hover: lightness −0.04.
- *On-image:* used on the hero. `on-night` 1.5 px border, transparent fill with `backdrop-filter: blur(8px)`, `on-night` text; hover fills `on-night` at 12%.
- *Icon:* a 2.5rem circle with a `border-strong` outline and a 1.25rem chevron icon in `ink`; `aria-label` names the action. When disabled, it has 40% opacity and `cursor: default`.
- *Arrow link:* `accent` text, `button` type, a trailing "→" in a `span` with `aria-hidden`.

**Eyebrow.** A `p`, not a heading, above the heading it labels: `eyebrow` type in `accent`, with a 2rem × 1px rule in `accent` before it and a 0.75rem gap.

**Page header** (every page but Home). Eyebrow, then `h1`, then an optional `lead`. Top padding `clamp(3rem, 2rem + 4vw, 6rem)`, then the section rhythm. It is left-aligned in the container and doesn't reveal.

**Pull quote.** A `figure` holding a `blockquote` in `quote` type and `heading` colour, and a `figcaption` in `eyebrow` type and `muted` colour, starting with "—" (a work's title stays in italics). A decorative opening mark "“" in Fraunces 6rem `coral` (light palette: `accent`) is set above-left, `aria-hidden`. It's full-container width, with its text capped at `28ch` on desktop and centred, with section padding above and below.

**Lists.** Plain `ul`s with a custom marker: a 0.375rem circle in `accent`, aligned to the first line's x-height, with a 0.75rem gap. Items are spaced 0.5rem apart. The *Hairline list* (Education, audio rows) has no marker, `1rem` vertical padding per item and a `border` top hairline per item, plus one at the bottom.

**Callout.** A `tint` fill, `1.5rem` radius, padding `clamp(1.5rem, 4vw, 3rem)`, an `h2` at `h3` size, and its list in two columns from `md` up.

**Card.** A `surface` fill, a `border` hairline, `1rem` radius, `1.5rem` padding, hover as in Motion. A whole-card link uses one `a` stretched with `::after { inset: 0 }`, never nested links.

**Image frame.** `1.5rem` radius, `aspect-ratio` from the image list, `object-fit: cover`. The headshot is "small" as Rachel asked: `max-width: 20rem` on desktop and `14rem` on mobile, centred when stacked.

**Placeholders** (generated SVGs, at the image list's keys and sizes):
- *Hero, `hero-mountain-lake`:* a dusk sky gradient from `oklch(0.42 0.09 320)` at the top through `oklch(0.70 0.11 25)` at the horizon, three layered mountain silhouettes in `night` at 100%, 85% and 70% opacity, and a lake below mirroring the sky at 60%, with a grain filter. It shouldn't look like a blurred blob.
- *Headshots:* a soft radial gradient from `tint` to `oklch(0.80 0.06 320)`, with a centred, simplified head-and-shoulders silhouette in `night` at 18% opacity and grain. Each headshot has a different hue offset (therapist 0, clarinet +20, recorder −20).

## 6. Shell

**Header.** `position: sticky; top: 0`, height 4.5rem, `bg` at 78% with `backdrop-filter: blur(16px) saturate(1.4)` (solid `bg` inside `@supports not (backdrop-filter: …)`), and a `border` hairline at the bottom. On the left, "Rachel Siegel" in Fraunces 500 1.375rem `heading`. On the right, the tabs in `button` type `ink`, 2rem apart. The current tab gets `aria-current` (`page` on `/contact`, `true` on a section) and an `accent` 2px underline 0.375rem below its text. The dropdown panel is a `surface` card with a `1rem` radius and `--shadow-soft`, `0.5rem` padding and 15rem wide, 0.5rem below its tab. Its items are 2.75rem tall with `0.75rem` side padding, `0.5rem` radius and a `tint` hover. It opens with opacity and a 0.25rem rise over `--dur-mid`.

**Skip link.** The first element in `body`. It's visually hidden until focused, then shows at top-left 1rem in a primary-button style, above the header (`z-index` over it). It targets `#main` (`tabindex="-1"` on `main`).

**Mobile menu** (below `md`). The menu button is an icon button in the header with "Menu" as its accessible name. The sheet is `position: fixed; inset: 0`, `bg` fill, header row with the name and a "Close" icon button. Links are in Fraunces 400 2rem `heading`, 3.5rem tall, grouped under eyebrows "Therapy" and "Performing", then Contact on its own, and Home first. The current page carries `accent` text. It opens with a fade and a 0.5rem rise over `--dur-mid`; the body doesn't scroll while it's open, and focus stays in it.

**Footer.** A `night` fill with grain, `on-night` text, top padding `6rem` and bottom `2rem`. It's a 12-column grid: the brand (cols 1–4: "Rachel Siegel" in Fraunces 2rem, the tagline in `on-night-muted` `small`, then "St. Louis, MO"); Therapy (cols 6–7: an eyebrow in `coral` and the three links); Performing (cols 8–9: Bio, Media); Contact (cols 10–12: "Therapy, through Wellness Alliance ↗" and "Email Rachel"). Links are `on-night`, with an underline on hover. A bottom row sits below a hairline in `on-night` at 15%: "© <year> Rachel Siegel" in `on-night-muted` `small`. On mobile the columns stack, brand first, with `2.5rem` gaps.

**Not-found.** A page header with the eyebrow "404", the `h1` "This page wandered off", the lead "The page you're looking for isn't here." and a primary button "Back to Home". It uses `bg` and the normal shell.

## 7. Home

**Hero.** Full-bleed: it breaks out of the container, sits under the sticky header (its top padding clears it), and is `min-height: min(88svh, 56rem)`. The image is `object-fit: cover; object-position: 50% 40%` with `filter: blur(2px); scale: 1.03` and no more blur. The scrim is two layers: `linear-gradient(to top, oklch(from var(--night) l c h / 0.85) 0%, oklch(from var(--night) l c h / 0.72) 35%, transparent 70%)` and `linear-gradient(to right, oklch(from var(--night) l c h / 0.55), transparent 60%)`, plus grain. The text block sits bottom-left in the container, padding-bottom `clamp(3rem, 8vh, 6rem)`, max 40rem wide. It holds the eyebrow "Psychotherapist · Clarinetist · Recorder player" (`on-night`, `coral` rule), "Rachel Siegel" in `display` and `on-night`, the tagline in `lead` and `on-night`, and the two on-image buttons "Therapy" and "Performing", 0.75rem apart, `2rem` below. Text must sit where the scrim is at least 0.70 opacity: measured against a white pixel, `on-night` reaches 5.4:1 there. That's why the eyebrow is `on-night` and not `coral` in the hero.

**Paths.** A section after the hero, with section padding. It's two cards side by side from `md` (6 + 6 columns) and stacked below. Each card is `1.5rem` radius, padding `clamp(2rem, 4vw, 3.5rem)`, and `min-height: 18rem`, with its content pushed to the bottom. It holds the eyebrow ("Therapy" / "Performing"), the blurb as a `quote`-sized Fraunces italic in `heading` (Therapy: "I believe every person holds the power to transform their life."; Performing: the Bio's first sentence, at `h3`-plus size `clamp(1.25rem, 1rem + 1vw, 1.75rem)` since it's long), and an arrow link "About my practice" → `/therapy/about` / "About my music" → `/performing/bio`. The Therapy card is filled `tint`; the Performing card is filled `night` with grain and `on-night` text and `coral` eyebrow.

## 8. Upcoming

The section has the same container. The header row holds an eyebrow "On stage" (decorative label) above the `h2` "Upcoming" on the left, and the Previous/Next icon buttons ("Previous events" / "Next events") on the right, shown only when the row overflows. The row is a horizontal list with `scroll-snap-type: x mandatory`, `gap: 1rem` and `scroll-padding-inline` equal to the gutter. A `mask-image` fades the overflowing side or sides over 3rem; there's no fade at an end the row is scrolled to. The buttons scroll by one card width plus the gap (`scrollBy`, smooth unless reduced motion).

Each card is 15rem wide, a Card (§5) with no hover lift unless it holds a link. Its date block holds the month (or "Oct–Nov" across months) in `eyebrow` type and `accent`, and below it the day or range ("16–18") in Fraunces 400 `2.5rem` `heading`, with tabular numerals. A `border` hairline separates it from the title, which is in `h3` style. The location shows as `small` `muted` text, or as a "Details ↗" arrow link. The unavailable and "none scheduled" messages are `lead` `muted` text with the calendar arrow link, inside a dashed `border-strong` box with a `1rem` radius.

## 9. Pages

Each page starts with the page header (§5). Its eyebrow and intro:

| Page | Eyebrow | `h1` | Lead |
|---|---|---|---|
| About Me | Therapy | About Me | the copy's first sentence |
| Services | Therapy | Services | the services paragraph |
| Education and Training | Therapy | Education and Training | (none) |
| Bio | Performing | Bio | the bio's first sentence |
| Media | Performing | Media | (none) |
| Contact | Contact | Contact | (none) |

A lead taken from the copy isn't repeated in the body.

- **About Me:** text in cols 1–7. The headshot in cols 9–12 is `position: sticky; top: 7rem`. On mobile it comes after the lead, centred. The specialties are a List (§5). The Rilke pull quote comes after the copy.
- **Services:** the Talking Heads pull quote comes after the page header. Then the two lists, as `h2` + List, sit in cols 1–6 and 7–12. Then "A note on perfectionism…" as a Callout (§5), with its closing question set in Fraunces italic `h3` size.
- **Education and Training:** each section is a row, with the `h2` in cols 1–4 (sticky `top: 7rem` on desktop) and a Hairline list in cols 5–12. In "Education & Credentials", the degree is in Source Sans 600 `ink` and the school in `muted` on its own line. In "Specialized Training", the course title is `ink` and the parenthetical presenter is `muted`. There are no links, cards or hover effects.
- **Bio:** the copy in cols 1–7 and the clarinet headshot in cols 9–12, sticky as on About. The therapy link is an inline `accent` link.
- **Media:** an `h2` "Videos". Two posters in a 6 + 6 grid, each 16:9 with a `1.5rem` radius, filled `night` with grain and a soft `coral`-to-`accent-strong` radial glow at 25%. Each has a centred 4.5rem circular play button (`surface` fill, an `accent` triangle, `--shadow-soft`, scale 1.05 on hover) and the video's title below in `h3`. Then the recorder headshot (cols 9–12) beside an `h2` "Audio" with a Hairline list (cols 1–7): the title on the left and a "Coming soon" pill on the right (`border-strong` outline, `muted` text, `small`, pill radius). The Brahms email line comes below as `body`.
- **Contact:** two cards in 6 + 6 columns, the Paths style (§7): "For therapy, please reach out through Wellness Alliance" (`tint`, arrow link "Wellness Alliance ↗") and "For performances, workshops or anything else, email me directly" (`night`, arrow link "Email Rachel"). The copy is unchanged.
