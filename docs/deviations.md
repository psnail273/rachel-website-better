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

## #29 784e8c7: query helpers return stand-ins instead of throwing

- Issue: #29 (full-screen mobile menu). Commit: 784e8c7.
- What deviated: the brief's fixture asked for query helpers that throw when nothing is found. `only`, `childAt`, `dialogById` and `linkNamed` in `src/app/_components/mobile-menu.test.tsx` return a detached stand-in element (`div`, `dialog` or `a`) instead.
- Reason: the red gate refuses a test that fails with a thrown error (ERROR) rather than an assertion (FAILURE), so a throwing helper could never go red against the unchanged product.
- Ruling: driver's call: accepted.
- Reasoning: the brief's intent holds. Every `expect` stays in a test body, and a missing element fails the test's own comparing `expect`. The red Verifier checked that no stand-in can make a test pass falsely: a stand-in dialog isn't open, a stand-in link has no `href`, and a keyDown on a stand-in isn't prevented.

## #29 01ec1ad: the menu stays modal when the window widens past 48rem

- Issue: #29. Commit: 01ec1ad.
- What deviated: the menu can be open when the window widens past 48rem, such as a tablet rotated to landscape. The root's `md:hidden` then hides the dialog, but it stays modal and keeps the page behind inert until it is closed (Escape still closes it).
- Reason: raised as a note in the last brief review. No acceptance criterion covers it, and closing on that change would need a `matchMedia` listener the brief doesn't have.
- Ruling: driver's call: out of reach for this issue; a follow-up.
- Reasoning: it falls outside #29's criteria and only shows when the window is resized with the menu open. The close comment names it as a follow-up.

## #29 01ec1ad: three surviving optional-chaining mutants on refs

- Issue: #29. Commit: 01ec1ad.
- What deviated: mutate left `dialogRef.current?.showModal`, `closeRef.current?.focus` and `buttonRef.current?.focus` → `.` alive (`src/app/_components/mobile-menu.tsx:43`, `:44`, `:46`).
- Reason: the mutants are equivalent. The dialog and the Close button render only while the menu is open, and their refs attach before that commit's effect runs. The Menu button always renders, and the effect has no cleanup. The `?.` is there only because the ref types are nullable.
- Ruling: driver's call: out of reach.
- Reasoning: no test can tell the mutants apart from the original. The green Verifier judged them equivalent.

## #36 ab93ca8: seven surviving mutants on the About Me specialisations

- Issue: #36 (About Me photo page). Commit: ab93ca8.
- What deviated: mutate left `SPECIALTIES` → `[]` and each of its six strings → `""` alive (`src/app/therapy/about/page.tsx:21`-`27`).
- Reason: these are false survivors from the per-test coverage artefact in `docs/agents/facts.md` (the page module loads lazily inside a test, so its constants count as covered by one test only). `page.test.tsx:172` asserts the list items exactly, so it would kill every one of them.
- Ruling: driver's call: out of reach.
- Reasoning: the green Verifier judged all seven false survivors. The fix belongs to the test harness: load the page at the test file's top level. That is a follow-up, not this slice's work.
## #37 9328cdf: "self-confidence" breaks at its hyphen at 390 px

- Issue: #37 (Services). Commit: 9328cdf.
- What deviated: at 390 px wide, the "Therapy may help you…" item "Develop greater self worth and self-confidence" breaks after "self-", which leaves "confidence" alone on the last line. The green Verifier failed design 8 (Layout) on it.
- Reason: `tieItem` in `src/lib/tie.ts` ties "and" to "self-confidence" with a no-break space, but the browser can still break at the hyphen inside the tied word. tie.ts is outside #37's scope. The page can't put a U+2011 into the text itself, because the locked tests compare the item's text with an ordinary hyphen.
- Ruling: driver's call: out of reach; a follow-up bug.
- Reasoning: the defect is in shared tie.ts, and any list item that ends in a hyphenated word can hit it. Fixing it there serves every page. The main session files the follow-up `Kind: bug` slice in this milestone. Every other Verifier line passed, including the Driver's Chromium check (24/24).
## #63 5e2a4f0: the Lock lifted over the tie invariants

- Issue: #63 (a hyphenated last word breaks at its hyphen). Commit: 5e2a4f0.
- What deviated: the locked test `src/lib/tie.invariants.test.ts > tie invariants > gives back the input once tieItem's ZWSPs are removed and its NBSPs turned back into spaces` must change in the green phase. Once tieItem puts a word joiner after a tied pair's hyphens, it fails as written. The file was locked only because an uncounted red round (5e2a4f0) added the brief's 30 s timeout there after the Lock failed twice on the 5 s timeout at load 26 to 28.
- Reason: the test contradicts the sealed brief (6ad92a2), whose Existing tests and Constraints say the green phase rewrites this property as the tieItem round-trip invariant that also removes word joiners.
- Ruling: driver's call: lock lift.
- Reasoning: the test is wrong and the brief is right. The green round may change only `src/lib/tie.invariants.test.ts`, and only as the brief says (that property rewritten, the four `invariants` properties added, the 30 s timeouts kept); every other locked test stays as at 5e2a4f0. The Lock is recorded again after the round, on a full fresh verify, and a fresh Verifier checks it.
## #63 c44a14c: one-word lines on Bio and Media, outside this diff

- Issue: #63 (a hyphenated last word breaks at its hyphen). Commit: c44a14c.
- What deviated: the green Verifier failed design 8 (Layout) on two one-word lines at 390 px light: "Hotteterre" alone in the "Passacaille" video card (`src/app/(upcoming)/performing/media/page.tsx:16`), and "experiences." alone at the end of Bio's first paragraph (`src/app/(upcoming)/performing/bio/page.tsx:22`-`27`).
- Reason: neither page is in this issue's scope or diff (`git diff e70da5e HEAD -- "src/app/(upcoming)"` is empty), and neither calls tie.ts, so this fix can't reach them. Each is being rebuilt in its own slice: #39 (Bio, built with tieLast on each paragraph, waiting on this landing) and #40 (Media, next).
- Ruling: driver's call: out of reach.
- Reasoning: fixing either here would touch another in-flight issue's files. Everything else in the verdict passed, including criteria 1 to 3 (Services at 390 px now ends "and self-confidence"), every test, the fresh full gate and the mutant ruled equivalent.
