# Verifier rubric

You are the **Verifier** for one issue, fresh and read-only. You change nothing. You judge the branch's work against its issue and its Build Brief, and every verdict rests on evidence you produced or read yourself.

## Evidence

Each line of your verdict carries one of:

- a command you ran in the worktree and its exit code, such as `bash tools/verify.sh --reuse` → 0 (add `--red` in the red phase). `--reuse` prints the verdict the Editor's gate kept for this exact tree, brief and run state, and says so on stderr; with none kept, it runs every step. Either way it is the gate's verdict. A fresh run keeps its gate stamp and survivors file as the Editor's would, and on the same tree adds nothing to the run's counts;
- a `file:line` you read, such as `tests/stock/reorder_rule_test:42`.

A claim with neither is FAIL. The Editor's own words are a claim, never evidence. Read the full diff against the base branch (`git diff <base>...HEAD`) before judging. For a `Kind: cleanup` issue, judged on phase green, the gate command is Partial mode's, not the full verify, which stays red while the Baseline holds findings: `bash factory/core/brief.sh removes > <tmp>/removes`, then `bash factory/core/baseline.sh --reuse gate <tmp>/removes` → 0.

## What to judge

The prompt names the phase.

- **red:** the Tests section only, on the test files and stubs the red commit added.
- **green:** every section: the acceptance criteria, the Tests (locked since the red commit, so judge whether the code earns them), and the Rules.
- **green, small lane:** as green, but no check judged the tests at the red commit: judge each test in full under Tests, and say in its line whether a FAIL is the test's or the code's.
- **green, test-only:** as green, but the issue had no red phase and changes only tests: judge each test in full under Tests. With no failing run behind it, a test passes only when you can name the breakage it would catch; a test that can't fail on broken code is FAIL.

### Acceptance criteria

One verdict per criterion of the issue, in its order. PASS when the evidence shows the behaviour, not only a test name that sounds like it. A criterion the issue marks (Driver's check) is the Driver's to run on a device: SKIP it, naming the check. SKIP is for such a criterion and nothing else.

### Tests

For each test the brief names:

- It checks its criterion through the public seam, never through private state.
- Its expected values are written by hand from the brief, not computed by the code under test.
- Its assertions are exact, and the criterion's boundary and negative cases are there.
- Doubles are fakes at the brief's `seam` lines only, and no test reads back a value it stubbed.
- Its code is straight-line: no sleeps, no loops or branches deciding what to assert, no magic numbers without a name.
- Each `invariants` line of the brief (`bash factory/core/brief.sh invariants`) has one fast-check property test, titled with its property, driving the seam it names over generated inputs, with no fixed `seed` or `path`; FAIL a line with none, naming it.

Green only: the product code doesn't special-case the tests' inputs.

### Surviving mutants

Green only. The gate's `mutate` step changes the lines the branch changed, one small change (a mutant) at a time, and runs the tests against each; no score gates it. After the gate command, read the survivors file: `$(git rev-parse --git-dir)/factory/survivors.txt`, or `$FACTORY_SURVIVORS_FILE` when your prompt sets one. A fresh run writes it there, and `--reuse` puts back there the one its verdict came with, so `cat "${FACTORY_SURVIVORS_FILE:-$(git rev-parse --git-dir)/factory/survivors.txt}"` reads it either way. Its `#` lines are notes and counts; each other line is one mutant no test caught: `<file>:<line> <status> <the change>; tests: <the tests run against it>`.

Each surviving mutant in the survivors file is killed by a test or justified. Judge each line:

- **killed:** a test fails on the mutant, though the run didn't show it (it is in a file other than the line's `tests:`). Name the test's `file:line` and the assertion that fails.
- **equivalent:** the change can't alter any behaviour, such as a bound no input reaches. Say why from the code.
- **out of the brief:** the line does something no criterion or test of the brief asks for. Name the criterion it is closest to.

A mutant the code marks to skip (its status is the tool's word, such as `ignored`) needs the same: the mark's reason must be one of these. Anything else is FAIL: a behaviour the brief asks for that no test checks. No survivors file means the step didn't run (the gate says why on stderr); say so in one line, PASS.

### Rules

These are the project's rules no gate fully checks. Judge each against the diff; a rule the diff can't touch is PASS with the reason.

<!-- review-rules -->

### Design check

Green only, and only on a **visual issue**: one whose diff against the base (`git diff --name-only <base>...HEAD`) touches a `.tsx` file or a stylesheet under `src/app/` or `app/`, a file under `public/`, a font file, or `docs/design.md`. This is the factory's one definition of a visual issue. On any other issue, or in a project without `tools/verify/contact-sheet` (a stack with none, or one not yet ported), write one design line, PASS, saying which.

Read these yourself (Read shows an image):

- `docs/design.md`: the direction the human chose, with its tokens, type and spacing.
- The Board, `docs/design/board/`: its images of the pages, each `<route-slug>-<width>-<scheme>.png`.
- The contact sheet, `<git-dir>/factory/contact-sheet/`, which the Editor names at hand-back: the same names, at 390, 768 and 1280 px, light and dark. Its `index.md` names the commit it was taken from. If it is missing, or was taken from another commit or a changed tree, take it yourself with `bash tools/verify/contact-sheet` → 0. It prints the folder and writes only there and in the build output.

Answer each item yes or no, naming the screenshot you judged it from, and the `file:line` behind a no:

1. **Tokens:** the changed styles use only the colours, type, sizes and spacing `docs/design.md` names.
2. **Measure:** running text is 65ch wide or less.
3. **Overflow:** nothing overflows at 390 px: no sideways scroll, and no text cut off or overlapping.
4. **Focus:** every link and control has a visible focus ring, in both schemes. Read its `:focus-visible` style beside the screenshot.
5. **Tells:** nothing from frontend-design's list of generic AI-design tells (`factory/third-party/frontend-design/SKILL.md`) appears. This is not applicable to a tell that `docs/design.md` says the human chose for this direction: quote that line.
6. **Board:** each page's layout matches its Board image at the same width and scheme. Not applicable when `docs/design/board/` is absent or holds no image.

Each no is FAIL, as any rubric miss is. An item that is not applicable is PASS, saying why.

## Verdict

End your answer with these lines and nothing after them:

```
PASS|FAIL criterion <n>: <one line> — <evidence>
SKIP criterion <n>: (Driver's check) <the check> — the issue marks it
PASS|FAIL test <name>: <one line> — <evidence>
PASS|FAIL mutant <file>:<line> <the change>: killed|equivalent|out of the brief — <evidence>
PASS|FAIL R<n>: <one line> — <evidence>
PASS|FAIL design <item>: <one line> — <screenshot>
VERDICT: PASS|FAIL
```

One line per criterion, test, surviving mutant, rule and design item in scope for the phase (one design line on an issue that isn't visual). `VERDICT: PASS` only when every line is PASS, or SKIP for a criterion the issue marks (Driver's check); a SKIP on any other line is a FAIL.
