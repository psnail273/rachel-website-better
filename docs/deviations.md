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
