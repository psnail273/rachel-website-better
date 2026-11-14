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
