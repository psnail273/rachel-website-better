# Slicing a Spec

How the spec skill cuts a Spec into slices: the rules each slice passes, and the body each one is published with. The run writes each slice's Build Brief when it starts the issue, against the code as it is then, so a slice states behaviour and leaves files to the brief.

## Rules

Every slice passes all of these:

- **Tracer bullet.** A slice cuts a narrow, complete path through every layer the behaviour needs, sized for one Build Brief, and lands green on its own.
- **Amends and prefactors first.** An approved amend is its own `Kind: amend` slice, ahead of the slices that rely on it. A prefactor that makes later slices easy goes ahead of them too.
- **Assets first.** The files in the Spec's Assets table arrive in `Kind: asset` slices, one per Feature that first needs any, at the top of that Feature, ahead of every slice that uses them.
- **Wide refactors use expand–contract.** When one mechanical change (a rename, a retyped shared symbol) breaks too many callers to land green in one slice: an expand slice adds the new form beside the old; migrate slices, each blocked by the expand and sized by blast radius (per folder or module), move callers over; a contract slice, blocked by every migrate slice, deletes the old form.
- **Dependencies point back.** A slice is blocked only by slices in its own Feature or an earlier one. A dependency that would point forward means the Features are in the wrong order or split in the wrong place: fix the split.
- **Areas apart.** Each `build`, `bug` or `cleanup` slice names the shared areas it changes on a `Touches:` line: coarse names, not file lists, such as the header, the footer, `globals.css`/tokens, the layout components, or one named page. The Run works slices at once only where their areas are apart. Where two slices of a Feature with no dependency between them share an area, split them so they don't, or make one blocked by the other (it must still point back, as above).
- **Invariants for data.** A slice that parses, formats or transforms data lists its invariants: the properties that hold for every input, such as "never throws on any input", "comes out sorted", "format then parse gives it back". Each becomes an `invariants` line of the Build Brief and a property test.
- **No open Human's call.** If slicing finds a decision only the human can make, ask it before approval and log the answer under Human's calls.

## Kind

Each slice has one Kind, which the run parses:

- `build`: new behaviour, built test-first; or, marked `Tests only: yes`, tests over behaviour already built.
- `bug`: behaviour that contradicts the Spec; the run uses repro-first.
- `cleanup`: removes Baseline findings, or a Drift sweep's findings on a `review` rule; the run uses Partial mode, on an Adopted or an Armed project.
- `amend`: changes `ARCHITECTURE.md` or an ADR, plus the project's checks that enforce them, which an amend builder writes in the Run (the build skill's `amend-slices.md`). A check inside `factory/` is no slice's: it is a `factory-improvement` proposal for `/factory-amend`.
- `asset`: brings the Assets table's rows for this Feature into the repo, with their licences and credits; the run's asset subagent fetches them, with no Editor.

## Lane

Mark a `build` or `bug` slice `Lane: small` when it needs at most 4 tests and changes at most 3 product files, adds no seam and touches no gate file (`factory/`, `tools/verify/`, the hook config). Its tests must fail on an assertion against the code as it is, since the small lane's red commit changes only tests: a bug, a changed value or behaviour, not a new API. The run then works it in one Editor round with one Verifier.

## Tests only

Mark a `build` slice `Tests only: yes` when it adds or widens tests over behaviour already built, such as a leak check that now covers new screens, and changes no product file. A test of working code can't fail first, so the run skips the red phase, and its gate fails any file but tests. A slice that may need a product change isn't tests only.

## Slice body

Title the issue with the behaviour it delivers. The body, in order:

```markdown
Part of #<spec>

Kind: build | bug | cleanup | amend | asset
Touches: <area>, <area> (for a build, bug or cleanup slice: the shared areas it changes; `none` when it changes none)
Lane: small (only when the slice qualifies; leave the line out otherwise)
Tests only: yes (only for a build slice that changes no product file; leave the line out otherwise)
Invariants: <property>; <property> (only for a slice that parses, formats or transforms data; leave the line out otherwise)

## Synopsis

Two or three plain sentences: what changes for the player or the developer, and why.

## What to build

The behaviour this slice makes work, end to end, from the user's side.

## Acceptance criteria

- [ ] One observable behaviour per line, phrased so a test can check it (the Build Brief turns each into a test name).
- [ ] (Driver's check) Only for what no test can show, such as frame pacing on a phone: the Driver runs it on the device after green, and the Verifier reports it as SKIP.

## Rules it touches

The ARCHITECTURE.md rules by id, or "None".
```

An asset slice's What to build lists its rows of the Assets table, and its criteria say each file is in place with its manifest row and credit.

Leave out file paths and code. The one exception is a prototype's snippet that pins a decision better than prose (a state machine, a schema); trim it to the decision and say it came from a prototype.
