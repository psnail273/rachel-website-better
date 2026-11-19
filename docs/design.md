# Design reference

The design of Spec #26, "Blossom, one layout", with the palette, italics and separator the human chose in Playtest #62 ("Mauve and wine"): chosen by the human from live prototypes, built by the Editor, and checked by the Verifier. Each Build Brief cites the sections its slice builds, and its values are exact. A slice that needs a value this file doesn't give asks the Driver, who adds it here, rather than inventing one. The Board in `docs/design/board/` shows Home and About Me at 390 and 1280 px, light and dark.

Principles, in order:

1. **One layout.** Every page is built only from the layout contract (§3): one column, five spacing values, a fixed set of components. No page sets a margin, a padding or a gap of its own. Text never shifts sideways between pages.
2. **Nothing sits in half a page alone.** The human's rule: "No reason to only be half the page if there isn't another half of the page." A block with nothing beside it fills its column or is centred.
3. **Readable.** WCAG 2.2 AA in both palettes, a 65ch measure, no one-word lines in labels.
4. **Soft type, quiet surfaces.** Fraunces alone, soft, italic only for the name, the leads and the pull quote; one wine band (the footer); cards that "stand out, but don't pop too much".
5. **Honest.** No decoration that carries no information: no eyebrows, no arrows on links, no scroll reveals.

## 1. Colour tokens

CSS custom properties on `:root`, each written with `light-dark(<light>, <dark>)` and `color-scheme: light dark`, so the system setting picks the palette with no script and no flash. Tailwind's `@theme inline` exposes each as `--color-<name>`.

| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#f6e4e6` | `#24131c` | page background |
| `surface` | `#fbf3f3` | `#2f1b26` | Upcoming cards, pull quote, dropdown panel, form fields |
| `tint` | `#eed3d7` | `#3d2431` | list panel, hover fill of cards and dropdown items |
| `ink` | `#3b2530` | `#eadfd9` | body text |
| `heading` | `#2a1420` | `#f7eee9` | headings, leads, the page-ground button |
| `muted` | `#6a525d` | `#c6b3ba` | captions, "Coming soon", "(required)" |
| `link` | `#75203f` | `#f7dce4` | links in copy |
| `accent` | `#853a62` | `#f2abbe` | current-nav underline, focus ring (outside the hero and the footer), list bullets, mobile-menu group labels |
| `error` | `#8f1836` | `#ffb4c0` | form error text and invalid-field border |
| `ornament` | `#c98aa6` | `#8b5a72` | the hairline under a lead, the photo frame's line (decorative, never text) |
| `line` | `#e3c9ce` | `#42293a` | hairlines: rows, the scrolled header's edge (decorative) |
| `line-strong` | `#8f7480` | `#a78895` | outlines of controls: form fields, dropdown panel (needs 3:1) |
| `band` | `#47172f` | `#47172f` | the footer band: wine, the same in both schemes |
| `on-band` | `#f8eee9` | `#f8eee9` | text on `band`, and the focus ring in the footer |
| `on-band-muted` | `#dcc5cd` | `#dcc5cd` | secondary text on `band` |
| `band-accent` | `#f2abbe` | `#f2abbe` | footer column labels |
| `plum` | `#24121c` | `#24121c` | the hero's ground and scrim colour, hover text of hero buttons |
| `on-image` | `#f8eee9` | `#f8eee9` | text and outlines over the hero image and video stills |
| `poster` | `#47172f` | `#47172f` | ground behind a video still while it loads |

Measured WCAG 2.x ratios (each must stay at or above "Needs"):

| Pair | Light | Dark | Needs |
|---|---|---|---|
| `ink` on `bg` / `surface` / `tint` | 11.5 / 12.9 / 10.0 | 13.5 / 12.3 / 10.7 | 4.5 |
| `heading` on `bg` / `surface` / `tint` | 14.1 / 15.8 / 12.2 | 15.5 / 14.1 / 12.3 | 4.5 |
| `muted` on `bg` / `surface` | 5.8 / 6.5 | 8.9 / 8.1 | 4.5 |
| `link` on `bg` / `surface` | 8.4 / 9.4 | 13.8 / 12.5 | 4.5 |
| `accent` on `bg` / `surface` / `tint` | 6.2 / 6.9 / 5.4 | 9.6 / 8.7 / 7.6 | 4.5 (text), 3 (ring, bullets) |
| `error` on `bg` / `surface` | 7.3 / 8.2 | 10.6 / 9.6 | 4.5 |
| `bg` on `heading` (button hover, carousel arrows) | 14.1 | 15.5 | 4.5 |
| `on-band` / `on-band-muted` / `band-accent` on `band` | 12.9 / 9.0 / 7.9 | 12.9 / 9.0 / 7.9 | 4.5 |
| `on-image` on `plum` | 15.6 | 15.6 | 4.5 |
| `line-strong` on `bg` / `surface` | 3.4 / 3.9 | 5.6 / 5.1 | 3 |

Rules:
- Text uses only `ink`, `heading`, `muted`, `link`, `accent` or `error` on `bg`, `surface` or `tint`; `on-band`, `on-band-muted` or `band-accent` on `band`; `on-image` over the hero and video stills. No other pairing, and no opacity on text.
- `ornament` and `line` are decorative only (`ornament` on `bg` is 2.2:1 in light, 3.2:1 in dark): never text, never the only sign of a state.
- **Hero scrim.** Two layers over the image, both in `plum` (`rgb(36 18 28)`): `radial-gradient(ellipse 75% 55% at 50% 52%, rgb(36 18 28 / 0.42), transparent 100%)` above `linear-gradient(to bottom, rgb(36 18 28 / 0.6) 0%, rgb(36 18 28 / 0.3) 24%, rgb(36 18 28 / 0.3) 100%)`. Every piece of text and every control over the image (brand, nav labels, menu button, name, tagline, both buttons) must reach 4.5:1 against the lightest pixel behind its box, scrim included, at 390×844, 768×1024, 1280×900 and 1920×1080. Measured on the placeholder: lowest 5.49 (a nav label at 1920), the name 7.89–8.58, the tagline 7.48–13.87, the buttons 7.03–8.22. A new hero photo is re-measured; if it fails, the scrim darkens, the text does not change.
- The token test (#27) computes every pair above from the CSS and fails under its minimum.

## 2. Typography

One family: **Fraunces**, variable on `opsz`, `wght`, `SOFT` (0–100) and `WONK`, upright and italic, from `src/app/fonts`. `font-optical-sizing: auto` (no `opsz` set by hand). Copy is set at `"SOFT" 60`; upright display type (`h1`, `event-date`, `sheet-link`) at `"SOFT" 100`; the italic roles and `h2` at `"SOFT" 0, "WONK" 0`. Every italic sets `"WONK" 0`, so none shows the font's swashed forms (the curled "h"). Italic is kept for the name (`display`, `brand`, `footer-name`), the lead, the pull quote and a `cite`; nothing else is italic. Source Sans 3 is not used. Fallback stack: `Georgia, serif`.

| Role | Size | Style, weight, axes | Line height | Tracking | Colour |
|---|---|---|---|---|---|
| `display` (Home `h1`) | `clamp(3.75rem, 1.5rem + 9.4vw, 9.5rem)` | italic 380, `"SOFT" 0, "WONK" 0` | 0.92 | -0.035em | `on-image` |
| `h1` (page title) | `clamp(3rem, 1.7rem + 5.4vw, 6rem)` | upright 300, `"SOFT" 100, "WONK" 1` | 1 | -0.03em | `heading` |
| `h2` (section heading) | `clamp(1.75rem, 1.3rem + 1.9vw, 2.5rem)` | upright 350, `"SOFT" 0, "WONK" 0` | 1.1 | -0.02em | `heading` |
| `lead` (statement) | `clamp(1.375rem, 1.15rem + 1vw, 2rem)` | italic 380, `"SOFT" 0, "WONK" 0` | 1.3 | 0 | `heading` |
| `quote` (pull quote) | `clamp(1.5rem, 1.1rem + 3.2cqi, 3rem)`, `cqi` of the quote's own box | italic 380, `"SOFT" 0, "WONK" 0` | 1.14 | -0.02em | `heading` |
| `body` | `clamp(1.0625rem, 1rem + 0.3vw, 1.1875rem)` | upright 400, `"SOFT" 60` | 1.7 | 0 | `ink` |
| `list`, `rows` | body size | upright 400, `"SOFT" 60` | 1.4 | 0 | `ink` (`heading` in the panel) |
| `card-title` (event and video titles) | `1.25rem` | upright 500, `"SOFT" 60` | 1.25 | 0 | `ink` in an event card, `heading` under a video |
| `event-date` | `1.875rem` | upright 300, `"SOFT" 100`, `font-variant-numeric: lining-nums` | 1.1 | 0 | `heading` |
| `hero-tag` | `clamp(1.1875rem, 1.05rem + 0.6vw, 1.5rem)` | upright 400, `"SOFT" 60` | 1.4 | 0 | `on-image` |
| `button` (hero buttons, Send) | `1.25rem` | upright 500, `"SOFT" 60` | 1 | 0 | see §5 |
| `brand` (header) | `1.375rem` | italic 500, `"SOFT" 0, "WONK" 0` | 1 | 0 | `heading`, `on-image` over the hero |
| `nav` (tabs), dropdown items | `1rem` | upright 500 (tabs), 400 (items), `"SOFT" 60` | 1 | 0 | `heading` (tabs), `ink` (items) |
| `sheet-link` (mobile menu) | `2rem` | upright 300, `"SOFT" 100` | 1.1 | 0 | `heading` |
| `label` (footer column, mobile-menu group) | `1.0625rem` | upright 500, `"SOFT" 60, "WONK" 0` | 1.3 | 0 | `band-accent` in the footer, `accent` in the menu |
| `footer-name` | `clamp(2.5rem, 1.8rem + 3vw, 4rem)` | italic 380, `"SOFT" 0, "WONK" 0` | 1 | -0.03em | `on-band` |
| `small` (footer text, captions, event place, error text, Details link) | `1rem` | upright 400 (error text 500) | 1.4 | 0 | per context |

Links in copy: `link` colour, weight 500, `text-decoration: underline; text-decoration-thickness: 1px; text-underline-offset: 0.3em`; hover thickness 2px. A link inside a lead keeps the lead's weight (380).

**Wrapping rules** (the human called wrapping out; each is checked, §3):

- `text-wrap: balance` only on headings (`display`, `h1`, `h2`, card titles, the hero tagline, the footer's tagline lines), on rows, and on the pull quote and its caption, which sit in a centred box. Nothing else is balanced.
- Body paragraphs are `text-wrap: wrap`. **No `text-wrap: pretty`**: it re-breaks a whole short paragraph narrower to rescue its last line, so its right edge parts from its neighbours'.
- Leads are `text-wrap: wrap`: a statement fills its measure. Balancing made "email me directly" wrap at half width.
- **Tie the last two words.** Every paragraph and lead ends with its last two words joined by a no-break space (U+00A0), through a trailing link if it ends on one, so no paragraph ends on a line of one word.
- **Labels** (headings, card titles, quotes, list items, rows): four words or more keep their last two words together with a no-break space. **Three words** keep their *first* two together, so the break falls after the second ("American Kantorei / Performance", "Education and / Training"): two lines of three words must leave one word alone, and it goes last. Two-word labels are left alone, so they can still break on a phone. Tied labels carry `overflow-wrap: anywhere`, so they break rather than overflow a column narrower than they are.
- **No one-word line in a label**, in any position, when it has four words or more; no one-word first line when it has three.
- In list items a slash between words is a break opportunity (U+200B after the `/`), and the parts of a slashed compound count as words for the two rules above ("Work life balance/ / relationship issues").
- **A link in a lead never splits across lines** (`white-space: nowrap`). Footer links, nav tabs, dropdown items and the brand never wrap (`white-space: nowrap`).
- Copy uses typographic quotes and apostrophes.

## 3. Space, layout, shape

### Tokens

These are the only layout and spacing values. Every margin, padding and gap in the site is one of the five `space` tokens.

| Token | Value | Use |
|---|---|---|
| `--content-max` | `78rem` | the shell's max width, gutters included: a 72rem column |
| `--gutter` | `clamp(1.25rem, 0.5rem + 3.2vw, 3rem)` | the shell's side padding |
| `--measure` | `65ch` (of body type) | the widest copy, the form, the centred column |
| `--aside` | `clamp(15rem, 34%, 24rem)` | the Sidebar's slot |
| `--switch-min` | `18rem` | a Switcher half narrower than this stacks |
| `--space-section` | `clamp(4rem, 2.5rem + 6vw, 7.5rem)` | between sections; hero → Upcoming; last section → footer |
| `--space-block` | `clamp(2rem, 1.5rem + 2.2vw, 3.5rem)` | between blocks in a section; column gaps; footer padding |
| `--space-heading` | `clamp(1.5rem, 1.25rem + 1vw, 2rem)` | under every heading; card and panel padding; nav gap |
| `--space-flow` | `1.25rem` | between paragraphs; card gaps; form field gaps |
| `--space-tight` | `0.75rem` | list item gaps; row padding; label → field; photo frame padding |
| `--header` | `4.5rem`; `6rem` from 48rem (768 px) | header height |
| `--radius` | `1rem` | photo, panel, pull quote, video |
| `--radius-card` | `0` | Upcoming cards, buttons, form fields, dropdown panel |

`html` has `scrollbar-gutter: stable`, so the column does not move between a page that scrolls and one that doesn't.

### The column

- **One column edge.** The header's content, `main`'s content and the footer's content each sit in a PageShell, so their left and right edges are identical on every route at a given width. Measured content edges: 20.5–354.5 at 390; 32.6–720.4 at 768; 56.5–1208.5 at 1280; 376.5–1528.5 at 1920.
- **Only the hero bleeds.** The Home hero (`data-bleed`) is the one element whose box leaves the column. Photos, quotes, cards and panels all end at the column's right edge, never at the window's.
- `main` is `container-type: inline-size`; its padding is `var(--space-heading)` at the top (`0` when it holds the hero) and `var(--space-section)` at the bottom. `main` does not grow (`flex: none`); the footer does (`flex: 1 0 auto`), so on a short page the band fills the window and the gap above it stays `--space-section`.

### Components

Every page is built only from these. Each carries its data attribute, which the checks select on.

| Component | Attribute | Rules |
|---|---|---|
| **PageShell** | `data-shell` | `inline-size: 100%; max-inline-size: var(--content-max); margin-inline: auto; padding-inline: var(--gutter)`. One in the header, one in `main`, one in the footer (and one inside the hero, for its text). `main`'s shell is `display: flex; flex-direction: column; gap: var(--space-section)`: that gap is the only vertical space between sections. |
| **Section** | `data-section` | A `section`, a direct child of `main`'s shell. No margin or padding of its own. Named with `aria-labelledby` its heading, or `aria-label`. |
| **SectionHeading** | `data-heading="1"` / `"2"` | The `h1` or `h2` in its type role, `margin-block-end: var(--space-heading)`, `text-wrap: balance`, its text tied (§2). The same space follows every heading on every page. |
| **Stack** | `data-stack="block"` / `"heading"` / `"flow"` / `"tight"` | `display: flex; flex-direction: column; gap` the named token. |
| **Cluster** | `data-cluster="start"` / `"center"` | `display: flex; flex-wrap: wrap; gap: var(--space-flow)`; `center` adds `justify-content: center`. |
| **Sidebar** | `data-sidebar="lead"` / `"trail"`, children `data-sidebar-head`, `data-sidebar-body`, `data-sidebar-aside` | Copy with a fixed slot beside it. From 40rem (640 px): `grid-template-columns: minmax(0, 1fr) var(--aside)`, `grid-template-rows: auto 1fr`, `column-gap: var(--space-block)`; head at row 1 col 1, body at row 2 col 1, the slot in col 2 spanning both rows, so its top is on the heading's top. The slot's content is `position: sticky; top: calc(var(--header) + var(--space-flow))`. Below 40rem it is one column: `lead` puts the slot between head and body (DOM order head, slot, body), with `margin-block-end: var(--space-heading)`; `trail` puts it after the body, with `margin-block-start: var(--space-block)`. |
| **Switcher** | `data-switcher="pair"` / `"label"` / `"run"` | Exactly two children, each in a `div`: `display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, var(--switch-min)), 1fr)); column-gap: var(--space-block)`. Two equal halves or one column, never a half-empty row. `pair`: two blocks, `row-gap: var(--space-block)` when stacked. `label`: a SectionHeading beside its content, no row gap (stacked, the heading's own space is the gap). `run`: one passage of copy in two halves, `row-gap: var(--space-flow)` when stacked. |
| **Center** | `data-center` | One centred column: `inline-size: 100%; max-inline-size: var(--measure); margin-inline: auto; text-align: center`. For a page with nothing to set beside its copy. |
| **Prose** | `data-prose="start"` / `"center"` | Running copy: `max-inline-size: var(--measure)`; children separated by `margin-block-start: var(--space-flow)`; paragraphs `text-wrap: wrap`, last two words tied. `center` adds `inline-size: 100%; margin-inline: auto; text-align: center`, for copy with nothing beside it. |
| **Lead** | `data-lead` | A statement in `lead` type, last two words tied; optionally the hairline under it (§5). |
| **PullQuote** | `data-quote` | The site's one quote style (§5). |
| **Photo** | `data-photo` | The one photo slot (§5). It fills the Sidebar's slot and stays inside the column. |
| **List** | `data-list="plain"` / `"panel"` | Bulleted list (§5). |
| **Rows** | `data-rows` | Ruled rows (§5). |

Two templates are compositions of these: **PhotoPage** (About Me, Bio, Media) is `Section > Sidebar lead`, with the `h1` as head, a Photo as the slot and the page's copy as body.

### Layout rules

- **The lone-block rule**, in the human's words: "No reason to only be half the page if there isn't another half of the page." A block with nothing beside it is centred in its cell or fills it; it is never left-aligned with empty space to its right. A block's cell is the Sidebar's body or slot, a Switcher half, an enclosing block, or else the column.
- **The short-line rule.** Left-aligned copy of three lines or fewer reaches at least 0.75 of its box with its longest line. Statements fill their measure.
- A two-up layout collapses to one column cleanly (Switcher); nothing leaves a half-empty row.
- **Shape.** Upcoming cards, buttons, form fields and the dropdown panel are square (`--radius-card: 0`). The photo frame, the list panel, the pull quote and video stills are rounded (`--radius: 1rem`); the photo's outer frame is `calc(var(--radius) + var(--space-tight))`. Carousel arrows are circles. No shadows anywhere. No grain.
- **Targets.** Every control is at least 24×24 px; nav tabs, dropdown items, icon buttons are 44 px (2.75rem) tall; footer links 36 px (2.25rem); buttons 3.5rem.

### The checks

`layout-check.mjs` (design round, to be ported into the gate) loads every route (`/`, `/therapy/about`, `/therapy/services`, `/therapy/education-and-training`, `/performing/bio`, `/performing/media`, `/contact`) at 390, 768, 1280 and 1920 px wide, 900 px tall, reduced motion on, and fails on any of:

1. **edges:** the content box (inside its padding) of the `[data-shell]` in `header`, `main` and `footer` differs between the three, or between routes at one width, by more than 1px on either side.
2. **outside:** a visible element's box extends more than 1px beyond the column and is not inside `[data-bleed]`. Exempt: ancestors of a shell, `position: fixed` elements, closed dialogs, and elements clipped by an `overflow-x` ancestor that is itself inside the column (the event cards).
3. **sections:** the gap between each pair of adjacent `main [data-section]`s, or between the last one and the `footer`, differs from the computed `--space-section` by more than 1px.
4. **headings:** for each `main [data-heading]`, the gap to the first following element that sits under it (at the nearest ancestor level that has following siblings) differs from the computed `--space-heading` by more than 1px; or, when its content sits beside it instead, the content's top is more than 1px off the heading's top.
5. **prose:** a `[data-prose]` narrower than 0.6 of the column with nothing beside it (a leaf element, or the Sidebar's slot, overlapping it vertically).
6. **1-word:** a line of one word: anywhere in a label of four words or more, or the first line of a three-word label (labels: `h1`–`h3`, `[data-card-title]`, buttons, the quote and its caption, list items, rows, footer links and lines, nav tabs, the brand, the hero tagline); or the last line of any paragraph in `main`. Words are runs between spaces, no-break spaces and U+200B, and the parts of a slashed compound.
7. **ragged:** a `[data-prose]` paragraph (not a Lead) of three lines or more whose longest line reaches less than 0.9 of its box.
8. **lone:** a block (`[data-prose]`, `[data-lead]`, `[data-quote]`, `[data-form]`, `[data-list]`, `[data-rows]`, `[data-center]`, `[data-events]`, `[data-switcher]`, or a `p` directly in a section) that neither fills 0.9 of its cell's content width nor sits centred in it within 2px.
9. **short:** a paragraph in `[data-prose]` or `[data-lead]`, not centred, of three lines or fewer, whose longest line reaches less than 0.75 of its box.

Alongside it: axe (WCAG 2.0/2.1/2.2 A and AA) on every route and a not-found URL, 390 and 1280 px, light and dark, with 0 violations, also with the contact form in its error state, in its success state, and with a dropdown open; and the hero contrast measure of §1.

## 4. Motion

There is very little, and none of it is triggered by scrolling into view.

- **No scroll reveals, no entrance animations, no page transitions.**
- **Header ground.** Past 24 px of scroll the header takes its ground (§6); `transition: background-color 200ms, color 200ms`, easing `cubic-bezier(0.2, 0.7, 0.2, 1)`.
- **Hover**, all `150ms` with the same easing: hero and Send buttons swap fill and text colour; an Upcoming card that holds a link takes `tint`; a video's play button scales to 1.08; link underlines thicken (no transition).
- **Mobile menu** fades in: opacity 0 → 1 over `200ms`.
- **Carousel arrows** scroll the row by one card, `behavior: smooth`.
- **Reduced motion.** `@media (prefers-reduced-motion: reduce)` sets `animation: none; transition: none; scroll-behavior: auto` on everything, and the carousel scrolls with `behavior: auto`.

## 5. Components

**Focus ring.** `outline: 2px solid var(--accent); outline-offset: 3px`, on `:focus-visible` only. Over the hero (including the header while it is transparent) the ring is `on-image`; in the footer it is `on-band`. Inside the dropdown panel it is `accent` with `outline-offset: -3px`, so it is never clipped and never overlaps the next item; on the Upcoming row, `outline-offset: -2px`.

**Buttons.** Square, `1px` outline, transparent fill, `button` type, `block-size: 3.5rem`, text centred, no padding (fixed width).
- *Hero button* (on the image): outline and text `on-image`; hover fills `on-image` with `plum` text. Width: `flex: 0 0 12.5rem` from 30rem (480 px); below, `flex: 1 1 0; max-inline-size: 12.5rem`, so the two share the row.
- *Page button* (the form's Send): outline and text `heading`; hover fills `heading` with `bg` text. `inline-size: 12.5rem; max-inline-size: 100%`.
- *Icon button* (menu, close): `2.75rem` square, no outline, a 20 px icon stroked `1.5` in `currentColor`, the glyph at the button's right edge so it sits on the column's edge with no negative margin. `aria-label` names the action.
- *Carousel arrow:* see §8.
- No "→" or "↗" on any link or button.

**Lead and the hairline.** A `p` in `lead` type. With the hairline (About Me only): under the text, `margin-block-start: var(--space-flow)`, one `aria-hidden` block `3.5rem` wide and `1px` tall, filled `ornament`, square ends. Left-aligned with the text. It is a separator and nothing else: no dots, no motif.

**Pull quote.** A `figure`, `container-type: inline-size`, `surface` fill, `--radius`, `padding: var(--space-block) var(--space-heading)`, `text-align: center`. The `blockquote` is in `quote` type, `max-inline-size: 22ch`, centred, balanced, its last two words tied. The `figcaption` follows at `margin-block-start: var(--space-flow)`: `small`, `muted`, balanced; a work's title is in `cite`, italic, `"SOFT" 60, "WONK" 0`. No quotation-mark ornament, no dash before the name. It is one component at two widths: across the column (About Me) or in the Sidebar's slot (Services).

**Photo.** A `figure`: `padding: var(--space-tight)`, `border: 1.5px solid var(--ornament)`, `border-radius: calc(var(--radius) + var(--space-tight))`. The image inside: `inline-size: 100%`, `aspect-ratio: 3 / 4`, `object-fit: cover`, `object-position: 50% 20%`, `border-radius: var(--radius)`. One ratio and one focal point for every portrait, so swapping a photo is swapping a file; nothing in the design depends on a photo's colours or crop. `sizes="(min-width: 640px) 24rem, 100vw"`.

**List.** A `ul`, `display: grid; gap: var(--space-tight)`. Each `li`: `padding-inline-start: var(--space-flow)`, `list` type, `text-wrap: wrap`, and a bullet drawn as `::before`: an open ring `0.625rem` across, `border: 1.5px solid var(--accent)`, at `inset-block-start: 0.42em`. *Panel* (About Me's specialisations): the same list on `tint`, `padding: var(--space-heading)`, `--radius`, text in `heading`, **one column at every width**.

**Rows.** A `ul`; each `li` has `padding-block: var(--space-tight)`, `border-block-start: 1px solid var(--line)` (the last also a bottom border), `list` type, `text-wrap: balance`, and is `display: flex; flex-wrap: wrap; justify-content: space-between; column-gap: var(--space-flow)` so a status ("Coming soon", `muted`, plain text, `white-space: nowrap`) sits at the right.

**Event card.** See §8.

**Video card.** A `figure`. First a `button` (`aria-label="Play <title>"`), `aspect-ratio: 16 / 9`, `--radius`, `overflow: hidden`, `poster` ground, holding: a plain `img` of YouTube's own still, `https://i.ytimg.com/vi/<id>/hqdefault.jpg`, `width="480" height="360"`, `loading="lazy"`, `alt="Still from the video of <title>"`, `object-fit: cover` (the 4:3 still is cropped to 16:9); and, centred over it, a 56 px play mark: a disc `rgb(36 18 28 / 0.72)` with an `on-image` triangle. A click replaces the button, in the same frame, with an `iframe` of `https://www.youtube-nocookie.com/embed/<id>?autoplay=1`, `title` the video's title, `allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"`, `allowFullScreen`. Nothing is loaded from YouTube's player before the click. Under the frame, at `margin-block-start: var(--space-tight)`, the `figcaption` in `card-title` type, tied. The ids: `VdwOjCyVsSE` (“Passacaille” by Jacques-Martin Hotteterre), `DZA9Wi6KzWY` (“Aria sopra La Bergamasca” by Marco Uccellini).

**Contact form.** `data-form`: `display: grid; gap: var(--space-flow); max-inline-size: var(--measure); margin-inline: auto; text-align: start`, `novalidate`, named by the "Send a message" heading (`aria-labelledby`).
- Fields, in order, each a `div` with `display: grid; gap: var(--space-tight)`:

  | Field | Control | Label | `autocomplete` | Required |
  |---|---|---|---|---|
  | Name | `input type="text"` | "Name" | `name` | no |
  | Email | `input type="email"` | "Email (required)" | `email` | yes |
  | Message | `textarea rows="6"`, `resize: vertical` | "Message (required)" | none | yes |

- Labels are visible `label`s, weight 500, `heading`; "(required)" is text in the label, `muted`, weight 400: the marking is not colour alone.
- Controls: `inline-size: 100%`, `padding: var(--space-tight)`, `border: 1px solid var(--line-strong)`, square, `surface` fill, `heading` text, body type, line height 1.4. Focus: the focus ring.
- Validation runs on submit, in the browser. Email empty: "Enter your email address." Email not matching `^[^\s@]+@[^\s@]+\.[^\s@]+$`: "Enter an email address like name@example.com." Message empty: "Write a message."
- Error state: the message is a `p` under its field, `small`, weight 500, `error`; the control gets `aria-invalid="true"`, `aria-describedby` the message's id, a border in `error` doubled by `box-shadow: inset 0 0 0 1px var(--error)`. Focus moves to the first invalid field.
- Success state: the form is replaced by a Lead with `role="status"`, "Thanks — Rachel will get back to you." (last two words tied), and focus moves to it (`tabindex="-1"`, no outline).
- The Send button is a page button, `justify-self: center`.
- **Sending is not designed here.** The prototype sends nothing. Where the message goes, spam protection, the pending and failure states and the server's own validation are #54 (Resend, a honeypot and a per-IP rate limit; config in `.env.example`).

**Placeholders.** The headshot placeholders are the existing generated SVGs at the image list's keys. The hero placeholder is the dusk-lake illustration drawn in the design round (`docs/design/hero-dusk-lake.svg`, 1920 × 1280; the slice copies it into `public/`): a sky from `#221f4a` through `#96607f` to `#f3b790`, alpenglow peaks, a lake mirroring them; it replaces the art at the key `hero-mountain-lake`. Real photos are not in yet: nothing committed contains the stand-in photos.

## 6. Shell

The page is `skip link, header, main, footer` in a flex column of `min-height: 100vh`.

**Skip link.** The first element. Hidden above the window until focused, then fixed at top-left `1rem`, above the header: `block-size: 3rem`, `padding-inline: var(--space-flow)`, `heading` fill, `bg` text, Fraunces 500 `1rem`. It targets `#main` (`tabindex="-1"` on `main`).

**Header.** `position: sticky; top: 0; z-index: 50`, `block-size: var(--header)`. Its PageShell is a flex row, `align-items: center; justify-content: space-between`: the brand "Rachel Siegel" (a link to `/`, `brand` type) at left, the nav at right.
- At rest it has **no ground**: plain text on the page, in `heading`.
- Scrolled past 24 px (`data-scrolled`): `background: rgb(from var(--bg) r g b / 0.92)`, `backdrop-filter: blur(12px)`, `box-shadow: 0 1px 0 var(--line)`.
- On Home, until scrolled, it sits over the hero and its text is `on-image`.

**Nav** (from 48rem). `Therapy` and `Performing` are buttons that open a dropdown; `Contact` is a link. Tabs: `nav` type, `min-height: 2.75rem`, `gap: var(--space-heading)` between them. The label carries the underline, `0.3rem` below the text: `1px` in `currentColor` on hover, `2px` in `accent` on the current tab (`aria-current="true"` on a section's button, `"page"` on Contact).
- **Chevron** after each dropdown label, `0.375rem` away: a `10px` SVG, stroke `1.5`, `opacity: 0.8`, `aria-hidden`.
- **Dropdown.** Opens on click (`aria-expanded`), closes on Escape, on a click outside, and on choosing a link. The panel sits directly under its tab, right-aligned to it: `inline-size: 15rem`, `border: 1px solid var(--line-strong)`, `surface` fill, square, **no vertical padding**: the box is exactly its links. Each link is `2.75rem` tall, `padding-inline: var(--space-flow)`, `ink`; hover `tint` fill and `heading` text; the current page (`aria-current="page"`) is `heading` with a `2px` `accent` underline, offset `0.35em`. No shadow, no animation.

**Mobile menu** (below 48rem). The nav is replaced by an icon button, "Menu" (two horizontal lines). It opens a modal `dialog` filling the window, `bg` fill: a head row the header's height holding the brand and a "Close" icon button, then the links. Both rows sit on the same column as the page (`max-inline-size: var(--content-max); padding-inline: var(--gutter)`); the links block has `padding-block: var(--space-heading) var(--space-block)`. Links, left-aligned, `sheet-link` type, `min-height: 3.5rem`: Home; a group "Therapy" (About Me, Services, Education and Training); a group "Performing" (Bio, Media); Contact. Group names are `label` type in `accent`, groups have `margin-block: var(--space-flow)`. The current page is underlined `2px` in `accent`, offset `0.2em`. Choosing a link closes it; the page behind does not scroll; focus stays in the dialog.

**Footer.** The one wine band: `band` fill, `on-band` text, `small` type, `padding-block: var(--space-block)`. In its PageShell, a grid with `gap: var(--space-block)`:
- **Brand:** "Rachel Siegel" in `footer-name`; the tagline "Licensed psychotherapist, clarinetist, recorder player" `var(--space-tight)` below; then "St. Louis, MO" in `on-band-muted`, directly under. Both lines balanced.
- **Three columns**, each a label in `label` type and `band-accent`, then a plain vertical list of links:
  - Therapy: About Me, Services, Education and Training
  - Performing: Bio, Media
  - Contact: "Wellness Alliance" (the Wellness Alliance page, new tab), "Email" (`mailto:`), "Contact page" (`/contact`)
- Links: `on-band`, `min-block-size: 2.25rem`, never wrapping, underlined `1px` on hover. Labels are short on purpose: a label never breaks.
- **Bottom line:** "© <year> Rachel Siegel" in `on-band-muted`.
- Layout: below 40rem everything is one column (brand, Therapy, Performing, Contact, bottom line). From 40rem the three columns are `repeat(3, minmax(0, 1fr))` with `column-gap: var(--space-flow)`. From 64rem (1024 px) the brand and the columns sit side by side, `minmax(0, 5fr) minmax(0, 7fr)`, the bottom line across both.
- Therapy and Performing are `nav`s labelled "Therapy pages" and "Performing pages".

**Not-found.** See §9.

## 7. Home

Three things, top to bottom: the hero, Upcoming (§8), the footer. **No path cards**, no eyebrow, nothing else.

**Hero.** A `section` with `data-section data-bleed`: `inline-size: 100cqi; margin-inline-start: calc(50% - 50cqi)` (the window's width, out of the column), `min-block-size: max(100svh, 34rem)`, pulled under the header with `margin-block-start: calc(-1 * var(--header)); padding-block-start: var(--header)`, `plum` ground, `overflow: hidden`.
- The image (key `hero-mountain-lake`) fills it: `object-fit: cover; object-position: 50% 55%`, no blur. The scrim of §1 lies over it.
- Its text sits in a PageShell, a flex column centred both ways, `padding-block: var(--space-block)`, `text-align: center`, all `on-image`:
  - `h1` "Rachel Siegel" in `display`;
  - the tagline "Licensed psychotherapist, clarinetist, recorder player" in `hero-tag`, `margin-block-start: var(--space-flow)`;
  - a centred Cluster of two hero buttons, "Therapy" → `/therapy/about` and "Performing" → `/performing/bio`, `margin-block-start: var(--space-heading)`.
- Hero → Upcoming is `--space-section`; "Upcoming" → its cards is `--space-heading`; cards → footer is `--space-section`.

## 8. Upcoming

A Section (`aria-labelledby` its heading) on Home, Bio and Media, always the last section. A SectionHeading `h2` "Upcoming", with no eyebrow; then a Stack (`heading`) of the row and, when the row overflows, the arrows.

**The row.** A `ul` (`data-events`, `aria-label="Upcoming events"`, `tabindex="0"`): `display: flex; gap: var(--space-flow); overflow-x: auto; scroll-snap-type: x mandatory; scrollbar-width: none`. No edge fade.

**Card.** An `li` (`data-event`): `flex: 1 0 15.5rem; max-inline-size: 28rem; min-block-size: 12rem`, `padding: var(--space-heading)`, `surface` fill, square, no border, no shadow, `scroll-snap-align: start`, a flex column aligned left. Below 40rem: `flex: 0 0 calc(100% - 2 * var(--space-flow))`, one card and a sliver of the next. So three events fill the column in three equal cards at 1280.
- The date in `event-date`, **day before month, month in full**: "22 November"; a range in one month "16–18 October"; across months "30 October – 2 November".
- The title, an `h3` in `card-title`, `ink`, `margin-block-start: var(--space-tight)`, balanced and tied.
- A place given as text: `small`, `muted`, `margin-block-start: var(--space-tight)`.
- A place given as a link: a link "Details" (visually hidden suffix " about <title>"), link style, `small`, pushed to the card's foot (`margin-block-start: auto; padding-block-start: var(--space-flow)`), opening in a new tab. Its `::after { inset: 0 }` makes the whole card the target; a card that holds a link takes `tint` on hover.

**Arrows.** Shown only when the row overflows, under it, in a centred Cluster: "Previous events" and "Next events", `3.25rem` circles, `heading` fill with a `bg` chevron (20 px, stroke 1.5), `1px` `heading` border. Disabled at its end of the row: transparent fill, `heading` chevron, `opacity: 0.3`. Each scrolls by one card's width plus the gap.

**Empty and unavailable.** In place of the row, a centred Prose: "No upcoming events are scheduled right now." or "Events are unavailable right now.", then a link "See the full calendar" (new tab).

## 9. Pages

**No eyebrows anywhere**: no small label above any `h1` or `h2`. Each inner page starts with its `h1` as a SectionHeading, `--space-heading` under the header. `h1`s are left-aligned, except Contact's.

- **About Me** (`/therapy/about`). Two Sections.
  1. PhotoPage: `h1` "About Me"; Photo of the therapist headshot; body a Stack (`heading`) of: a Lead **with the hairline**, "I believe every person holds the power to transform their life."; then a Prose of the three paragraphs before the list, the specialisations as a List *panel* (six items, one column), and the closing paragraph. The lead is not repeated in the body.
  2. A Section (`aria-label="A line from Rilke"`) holding the PullQuote across the column, its text set without quotation marks: Let everything happen to you: beauty and terror. Just keep going. No feeling is final. Caption: Rainer Maria Rilke, *Letters to a Young Poet*.
- **Services** (`/therapy/services`). Three Sections.
  1. Sidebar `trail`: head the `h1` "Services"; body a Prose with the services paragraph, at body size; slot the PullQuote, whose text is: And you may ask yourself, “Well, how did I get here?” (only the inner question is in quotation marks), caption "Talking Heads". On a phone the quote follows the paragraph.
  2. A Section (`aria-label="What therapy can help with"`) holding a Switcher `pair`: each half an `h2` SectionHeading and a plain List: "You might be struggling with…" (eight items) and "Therapy may help you…" (ten items).
  3. "A note on perfectionism…": the `h2` SectionHeading above, full width, like the two before it; then a Stack (`block`) of a Switcher `run` (left a Prose with the paragraph that ends "Perfectionism can cause:", right the plain List of seven items, top edges aligned) and, below both, a Prose `center` holding a Lead without the rule: "What if you could let that all go, and still be successful, loved and accepted as you are?" On a phone: paragraph, list, question.
- **Education and Training** (`/therapy/education-and-training`). One Section: the `h1`, then a Stack (`block`) of two Switchers `label`: the `h2` "Education & Credentials" beside Rows of the four credentials, and the `h2` "Specialized Training" beside Rows of the ten trainings. Each item is one line of text as in the copy; no links, no cards.
- **Bio** (`/performing/bio`). PhotoPage: `h1` "Bio"; Photo of the clarinet headshot; body a Prose of the four paragraphs, **all plain and the same size, exactly as in Rachel's PDF**: no lead, no enlarged first sentence. The therapy link is an inline link. Then Upcoming.
- **Media** (`/performing/media`). PhotoPage: `h1` "Media"; Photo of the recorder headshot; body a Stack (`block`) of two blocks: the `h2` "Video" above a Switcher `pair` of the two video cards (§5); the `h2` "Audio" above a Prose holding Rows of the three recordings, each with "Coming soon" at right, and the line "For access to the full Brahms Quintet performance, contact Rachel via email." with "email" a `mailto:` link. Then Upcoming.
- **Contact** (`/contact`). One Section holding one **Center**: a centred single column at the measure. The `h1` "Contact", centred (the only centred `h1`); a Stack (`block`) of: a Stack (`flow`) of two Leads, "For therapy, please reach out through Wellness Alliance." (link, new tab) and "For performances, workshops or anything else, email me directly." (`mailto:` link); then the `h2` "Send a message" above the contact form (§5). Headings and statements are centred; the form's labels, fields and errors are left-aligned inside it; Send is centred.
- **Not-found.** On the contract like Contact: one Section holding a Center with the `h1` "This page wandered off", then a Stack (`heading`) of a Lead "The page you're looking for isn't here." and a page button "Back to Home" → `/`, centred. No "404" eyebrow. (Specified here; the design round did not prototype it.)

## Changes from the previous design.md

**Principles.** "Editorial calm" (asymmetric 12-column sections, eyebrow labels, reveals) is replaced by "Blossom, one layout".

**§1 Colour tokens.**
- New palette: blush ground and evergreen in light, evergreen ground in dark; values are hex, not OKLCH.
- Removed: `accent-strong`, `on-accent`, `border`, `border-strong`, `night`, `on-night`, `on-night-muted`, `coral`.
- Added: `link`, `error`, `ornament`, `line`, `line-strong`, `band`, `on-band`, `on-band-muted`, `band-accent`, `plum`, `on-image`, `poster`.
- `accent` no longer colours links or eyebrows: it is the current-nav underline, the focus ring and list bullets.
- The hero scrim is new (radial plus top-down, in `plum`), and the contrast rule is now measured on every text box over the image at four viewports.

**§2 Typography.**
- Fraunces only; Source Sans 3 is no longer used anywhere.
- Every role's size, weight and axes changed; display, `h2`, lead and quote are italic 300 at `"SOFT" 100`; the page `h1` adds `"WONK" 1`.
- Removed roles: `eyebrow`, `h3` as a general heading. Added: `card-title`, `event-date`, `hero-tag`, `brand`, `sheet-link`, `label`, `footer-name`.
- `text-wrap: pretty` is dropped from paragraphs; `balance` is limited to headings, rows and the quote.
- New wrapping rules: tied last words, the three-word rule, no one-word lines in labels, unsplit links, slash breaks in list items.

**§3 Space, layout, shape.**
- The spacing scale of ten steps is replaced by five named tokens; the 12-column grid and the 7 + 4 asymmetric split are gone.
- Container: `76rem` with a `44rem` inner text column becomes one `72rem` column (`--content-max: 78rem` with gutters) and a `65ch` measure.
- New: the layout contract and its fourteen components, the one-column-edge rule, the lone-block rule, the short-line rule, and the list of checks.
- Radius: one `1rem` radius for photo, panel, quote and video; cards, buttons and fields are square; no pills.
- Shadows and grain are removed.

**§4 Motion.**
- Scroll reveals, view transitions, card lift and arrow nudge are removed.
- What remains: the header's ground on scroll, colour hovers, the mobile menu's fade, the carousel's smooth scroll.

**§5 Components.**
- Buttons: pill primary and blurred on-image buttons become square 1px-outline buttons; arrow links are removed.
- Removed: Eyebrow, Page header, Callout, Card (generic), the quote's opening mark and dash.
- Pull quote: now a centred `surface` panel, one style at two widths.
- Lists: open-ring bullets; the panel variant replaces the Callout's two-column list and is one column.
- Photo: a framed 3/4 slot up to 24rem in the Sidebar, replacing the 20rem/14rem image frame.
- New: Lead with the dotted rule, Rows with a plain-text status ("Coming soon" is no longer a pill), the video card with YouTube's still, the contact form.
- Placeholders: the hero art is the dusk-lake illustration.

**§6 Shell.**
- Header: no ground at rest (was a blurred bar with a hairline); ground only once scrolled; `6rem` tall from 768 px.
- Dropdown: square, no radius, no shadow, no padding, no opening animation; chevrons are 10 px at 80% opacity.
- Mobile menu: left-aligned on the page's column; group labels are italic, not eyebrows.
- Footer: brand with a large italic name and the tagline, three short-label columns; Contact's links are "Wellness Alliance", "Email", "Contact page" (were "Therapy, through Wellness Alliance ↗" and "Email Rachel"); no hairline above the bottom line; the band grows on short pages.
- Not-found moved to §9 and lost its "404" eyebrow.

**§7 Home.**
- Hero: full first screen, text centred (was bottom-left, 88svh); no eyebrow; no image blur; buttons are square outlines.
- The Paths section (two cards) is removed. Home is hero, Upcoming, footer.

**§8 Upcoming.**
- Heading without the "On stage" eyebrow.
- Cards: flexible width filling the column (were 15rem), square, no hairline, date as one line "22 November" (was a month eyebrow over a large day).
- Arrows moved under the row, centred, filled circles; the edge fade is removed.
- "Details" has no arrow; empty states are centred copy, not a dashed box.

**§9 Pages.**
- No eyebrows; the eyebrow/lead table is removed.
- About Me: lead with the dotted rule; photo in the Sidebar slot at up to 24rem; specialisations in a one-column panel; Rilke quote as a centred panel.
- Services: the Talking Heads quote sits beside the intro; the perfectionism note is a heading over paragraph-and-list halves with a centred closing question, not a Callout.
- Education and Training: heading beside rows in equal halves; degree/school and title/presenter are no longer styled apart; no sticky headings.
- Bio: no lead; all paragraphs plain.
- Media: "Video" (was "Videos") with real YouTube stills; the photo is in the Sidebar slot beside both blocks; "Coming soon" is plain text.
- Contact: a centred single column with two statements and a new contact form (was two cards). The form's sending needs its own slice.

## Changes in the Playtest #62 tuning

The human kept the layout and asked for a new palette, calmer italics and a plainer separator; they chose "Mauve and wine" from three live directions. No layout, spacing, size or content value changed. The section above is the history of Spec #26 and still names the evergreen palette it introduced; this section replaces it.

**Principles.** Principle 4: "partly italic; one evergreen band" is now "italic only for the name, the leads and the pull quote; one wine band".

**§1 Colour tokens.**
- No green is left. Changed in light: `link` (`#1f4a3a` → `#75203f`), `accent` (`#2b6044` → `#853a62`), `ornament` (`#d98fa3` → `#c98aa6`), `band` (`#1f3a30` → `#47172f`), `on-band-muted` (`#c5d3c9` → `#dcc5cd`), `poster` (`#1f3a30` → `#47172f`).
- The dark scheme is a wine dusk, not forest green: `bg`, `surface`, `tint`, `muted`, `link`, `ornament`, `line`, `line-strong`, `band`, `on-band-muted` and `poster` all changed; `ink`, `heading`, `accent`, `error`, `on-band`, `band-accent`, `plum` and `on-image` did not.
- `link` in dark is its own value (`#f7dce4`), no longer the same as `heading`.
- `band` is one value in both schemes; in dark it sits a little lighter than `bg` (1.2:1), a raised band rather than a darker one.
- The footer's focus ring is `on-band` (was `on-image`; the two hold the same value today).
- Every pair in the contrast table was re-measured.

**§2 Typography.**
- Every italic sets `"WONK" 0`.
- `display` and `footer-name`: italic 380, `"SOFT" 0` (were 300, `"SOFT" 100`). `brand`: italic 500, `"SOFT" 0` (was `"SOFT" 100`).
- `lead` and `quote`: italic 380, `"SOFT" 0` (were 300, `"SOFT" 100`). A link in a lead is 380.
- `h2`: upright 350, `"SOFT" 0, "WONK" 0` (was italic 300, `"SOFT" 100`).
- `label`: upright 500 (was italic 500).
- A `cite` stays italic, at `"SOFT" 60, "WONK" 0`.
- Unchanged: `h1` (upright 300, `"SOFT" 100, "WONK" 1`) and every other upright role.

**§5 Components.**
- The dotted rule under About Me's lead (five large and four small dots) is replaced by a hairline, `3.5rem` by `1px`, in `ornament`.

**§6 Shell.**
- Footer and mobile-menu group labels are upright; the footer band is wine.
