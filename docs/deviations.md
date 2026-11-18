# Deviations

Every ruling on a Deviation, oldest first. This file is append-only: add an entry for each ruling and never edit or remove one.

Each entry records the issue, the commit, what deviated, the reason (or "undeclared"), the ruling (accept, reject or amend), the reasoning, and a link to the amend when there is one.

## #9 cd4f2cd: extra green round for four surviving mutants

- Issue: #9 (calendar feed parsed into upcoming event cards). Commit: cd4f2cd.
- What deviated: the second green Verifier check FAILed on four survivors that no test catches. They are `events.ts:90` (DST-adjacent TZID conversion), `events.ts:228` twice (a DTEND that won't parse makes parseIcs throw), and `events.ts:267` (a VEVENT closed only by END:VCALENDAR is read).
- Reason: missing tests. The code is right.
- Ruling: driver's call: extra round.
- Reasoning: every finding is inside the brief. The new tests pin behaviour the brief already states (TZID local time, never throwing, an unterminated VEVENT left out) and change no criterion. Green is at the cap of 2, so this is green round 3 of 4. A DTEND that won't parse is read like a missing one (end = start), which is what the code already does and what the brief's missing-DTEND rule gives.

## #6, 78d1af3: pnpm-lock.yaml re-resolved next's peer @babel/core

- **What deviated:** the brief's lockfile seam allowed the three test packages and nothing else. `pnpm add -D -E` also re-resolved next's optional peer `@babel/core` from 8.0.10 to 7.29.13 in next's and styled-jsx's lockfile entries.
- **Reason:** undeclared, a side effect of pnpm's peer resolution.
- **Ruling:** accept.
- **Reasoning:** both versions were already locked at the base (c6dd194), no package is added beyond the three named, and R8 holds (the Verifier passed it). Every gate step passes with it.

## #27 996ce90: green Verifier FAIL on the Measure and Board design lines; two class-constant survivors

- Issue: #27 (design tokens: blush and evergreen palettes, Fraunces type roles, space tokens). Commit: 996ce90.
- What deviated: the green Verifier FAILed two design lines. **Measure:** the /therapy/services body runs 83–90 characters a line at 1280 px, because `max-w-3xl` (services/page.tsx:58) is unchanged from base. **Board:** no page matches its Board layout (hero buttons, footer band, square Upcoming cards, photo frame, list panel, centred pull quote). Mutate also left two StringLiteral survivors: the `linkClass` constants at mobile-menu.tsx:14 and nav-dropdown.tsx:8, blanked to `""`.
- Reason: outside this brief. The brief's Constraints say "Class swaps, with no layout redesign" and name #53 for the layout. The survivors are class strings that no test reads, and the brief's Mutants constraint foresaw them.
- Ruling: Measure and Board: overruled. These lines belong to #53 (PageShell, Prose at `--measure`) and the Spec's page slices ("their own redesign is in the page slices"). The Verifier passed every criterion, test, rule and token line. Survivors: driver's call: out of reach.
- Reasoning: fixing either design line would add layout work that #53 and the page slices already own, so overruling them changes no criterion of this brief. The Services measure was already a follow-up noted at #51's close. A test that pinned the menu links' Tailwind class strings would pin presentation and not behaviour, and the dropdown and menu are redesigned in their own slices. The FAIL has every line overruled, so it counts as a PASS.

## #53 e313022: invariant property tests in a new file outside the brief's scope

- Issue: #53 (layout components: one column and shared building blocks for every page). Commit: e313022.
- What deviated: the Editor added `src/lib/tie.invariants.test.ts`, which holds the three fast-check properties for the brief's `invariants` lines. That file is not under any `scope` line.
- Reason: declared in the commit body. The brief's `invariants` lines need property tests, and `tie.test.ts` is locked from the red phase. The `Deviation:` line sat above the closing trailer paragraph, so the deviation step read it as undeclared.
- Ruling: accept. The brief gains `scope src/lib/tie.invariants.test.ts` and is resealed (64b1c58).
- Reasoning: the brief asked for the invariant tests but left them no unlocked file in scope, which is a gap in the brief and not scope creep. The new file tests only `src/lib/tie.ts`'s exported functions and adds no product code.

## #30 443630b: footer focus ring through an arbitrary variant that slips past the focus-ring test

- Issue: #30 (full footer: evergreen band with page links, contact paths and location). Commit: 443630b.
- What deviated: the footer links set their ring colour with `[&:focus-visible]:outline-on-image` in `src/app/_components/site-footer.tsx`. `src/app/globals.test.ts`'s "leaves the focus ring to the global rule in every component" fails on any `focus-visible:` utility, and the arbitrary variant gets past its regex.
- Reason: undeclared. The Editor flagged it in its final message. The brief asked for an `on-image` ring on the footer links' `:focus-visible`, which the test forbids components to set.
- Ruling: reject. A counted green fix round replaces it: the `footer` sets `[--accent:var(--on-image)]`, and the global `:focus-visible` rule draws the ring in `on-image` inside the band. The brief's Constraint is corrected and resealed.
- Reasoning: getting past a test's regex works around a gate, which the factory never allows. Re-scoping the token keeps design.md §5's `on-image` ring in the footer, and the ring still comes from the one global rule, as #27's test intends. The brief's wording caused the clash, so it is fixed with the round.

## #30 39f74d0: two surviving class-string mutants in the footer

- Issue: #30 (full footer). Commit: 39f74d0.
- What deviated: mutate left two StringLiteral survivors in `src/app/_components/site-footer.tsx`: `linkClass` (line 12) and `labelClass` (line 13), each blanked to `""`.
- Reason: no test reads Tailwind class strings. The green Verifier judged the footer's styling against design.md §6 and the Board instead, and passed it.
- Ruling: driver's call: out of reach.
- Reasoning: a test that pinned the class strings would pin presentation, not behaviour. This is the same ruling as #28's link-class survivors.
## #33 2537e9c: the two message-state tests share their assertions in a helper

- Issue: #33 (Upcoming cards with one-line dates and Previous/Next arrows). Commit: 2537e9c.
- What deviated: the deviation step found an assert-drop in `UpcomingStrip.says_none_are_scheduled_when_no_events_are_upcoming` and in `UpcomingStrip.shows_the_fallback_message_and_a_calendar_link_when_no_events_are_available`. Each went from 4 assertion calls at the base to 1 at HEAD.
- Reason: undeclared. Both tests now call one helper, `expectMessageState` (`upcoming-strip.test.tsx:166`). The helper holds 8 assertion calls: the section's children, the centred Prose, its two `p`s, the one calendar link, and no `ul`, `li`, `button` or region. The probe counts only the calls written in each test's own body.
- Ruling: driver's call: accept. The brief gains `asserts` lines for both tests (4 → 1) and is resealed.
- Reasoning: nothing was dropped. Every check from the base, and the ones the brief added, still runs in both states through the helper, and the brief's bullets for those tests are pinned in full. A fix round would only copy the helper's body into the two tests.

## #33 70a9811: 21 surviving mutants out of reach

- Issue: #33 (Upcoming cards with one-line dates and Previous/Next arrows). Commit: 70a9811.
- What deviated: the green gate's mutate step left 21 survivors.
  - Presentation (no test reads it): the class strings in `upcoming-strip.tsx` (ARROW_CLASS :23, LINKED_CARD_CLASS :28), the chevron direction and paths (:45–47), and the linked-card hover condition (:60).
  - Equivalent in `upcoming-strip.tsx`: the measure's null guards, its skip of an unchanged update, its effect dependencies and the `?.` on card offsets (:94, :104, :108, :116, :120, :123), since the arrows render only with a measured row of at least two cards.
  - Equivalent in `events.ts`: the `?? ""` fallbacks at :335 and :338, since a month index is always 0–11 and NaN dates are dropped first.
- Reason: declared in the Editor's final message for the `??` fallbacks. The green Verifier judged every survivor PASS.
- Ruling: driver's call: out of reach.
- Reasoning: tests that pinned class strings or SVG paths would pin presentation, not behaviour. The design check judges those against the Board. The other mutants change no observable behaviour.

## #33 ab3b877: one-word lines on pages this issue doesn't touch

- Issue: #33 (Upcoming cards with one-line dates and Previous/Next arrows). Commit: ab3b877.
- What deviated: the green Verifier passed design 8 (Layout), but the layout check lists real one-word lines. Bio's first paragraph ends with "experiences." alone at 390 px (performing-bio-390-light.png). The Services h2 and paragraphs at 390 px are listed as one-word too.
- Reason: pre-existing, on markup this diff doesn't change. The strip's own text is tied.
- Ruling: driver's call: out of reach. Accept the PASS. The follow-up belongs to the pages' own slices of Spec #26 (#36–#41), which tie and rebuild that copy.
- Reasoning: fixing those lines means editing page files outside this brief's scope that other slices own. The Upcoming strip's cards and copy show no one-word line.

## #28 1109ea5: the header's first render was not tested as unscrolled

- Issue: #28 (sticky header, current section, skip link, square dropdowns). Commit: 1109ea5.
- What deviated: mutate left `useState(false)` → `true` alive in `src/app/_components/site-header.tsx:21`. Effects don't run in a prerender, so with that mutant every page's static HTML would ship `<header data-scrolled="">`. That shows the scrolled ground at rest until hydration, and always without JS (criterion 2). No test reads the prerendered header. The locked header tests check only after mount, and the locked layout tests prerender but never read the header's attributes.
- Reason: a gap in the brief, not a wrong test. The brief named no test for the server render.
- Ruling: reject the survivor; the green Verifier's FAIL line stands. A counted green fix round adds `src/app/_components/site-header.prerender.test.tsx`, a new unlocked file, which prerenders `SiteHeader` and asserts the header's attributes are `[]`. The brief gains its `scope` line and is resealed.
- Reasoning: the mutant is in reach and the behaviour is criterion 2, so it isn't out of reach. The locked tests don't contradict the brief; they leave this case out, so a Lock lift doesn't fit. A new file in scope adds the missing test without touching the locked ones.

## #28 1109ea5: design check items 6 (Board) and 8 (Layout) on parts other slices rebuild

- Issue: #28. Commit: 1109ea5.
- What deviated: read strictly, the green Verifier's design items 6 and 8 would be no. The faults are the "St. / Louis" and "life." line breaks, on page parts this issue's diff doesn't touch, which other Feature 1 slices rebuild.
- Reason: those parts are outside #28's scope list and its diff (the header, the skip link and the dropdowns). The header itself matches the Board and wraps nowhere at 390, 768, 1280 or 1920 px.
- Ruling: driver's call: out of reach.
- Reasoning: fixing them would mean editing files another slice owns. It is the same scoping #33's design check used. They stay with the slices that rebuild those parts.
