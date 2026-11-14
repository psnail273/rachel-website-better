# Writing a Build Brief

The **Build Brief** is everything the Editor builds to for one issue, and what the gates check its work against. Write it against the code as it is now: read the issue, the code it touches, `ARCHITECTURE.md` and the rules the issue lists. The issue has no file paths; the brief adds them.

Save it at `<git-dir>/factory/brief.md` of the issue's worktree (`git -C <worktree> rev-parse --git-dir`), so it never lands and the Editor can't edit it. Done when `bash factory/core/brief.sh seal` passes in the worktree: it runs `brief.sh check`, which reads the block and the template's Kind line and sections and checks that they agree, then stores the brief's hash in the run state. `state.sh` sets no phase before that. Edit the brief later only as the Driver (a ruling, a correction), then seal it again: the Editor's gate and the deviation step fail with `brief-changed` on a brief that no longer matches its seal.

## What a brief says, and what it leaves out

A brief states behaviour, expected values, names and files: what to build and how to tell it works. It never restates a rule a gate, the rubric or the test skill already enforces (null guards, helper shapes, assertion styles, "fail on an assertion, not an error"): the Editor reads those where they live, and the Verifier reads a brief's words as requirements, so a restated rule turns into a FAIL wherever the brief worded it more strictly than the rule. When a gate enforces something, leave it to the gate.

Write every part: each clause of a criterion, each value, each direction or target and each channel of a colour, alpha too, gets an expected value in a test bullet. Give the whole value, never only a property of it: the exact list, every field that matters, "a new X, not the one before", not "contains", a size, "not null" or "changes". Copy a value the product stores (in a theme, a scene, a resource) from its file, exactly, and name the file: no hex for a stored float, and no tolerance where the criterion asks for the same value. Every bound or behaviour a Constraint states gets a test bullet that pins it: a resource bound (ids, nodes, timers, threads, memory, files), a listener removed on cleanup, a `finally` that closes, a timeout. The brief review checks all of this before the Lock ([`editor.md`](editor.md)).

Every engine or library fact the brief relies on goes under **Probed**, with the probe that showed it (a command, a headless script, a version). Probe it before writing the brief; never pass on a fact from memory. Facts that later briefs will need also go in the project's facts file, `docs/agents/facts.md` (start it the first time), so the next brief reads them instead of probing again.

Find the existing tests the change reaches: search the test files (the globs in `tools/verify/test-paths`) for each signal, method, node, constant and state the issue changes. Each test that reads one goes under **Existing tests**, with its file in scope or the reason it is unaffected; with none, say what you searched. For a test-only issue, Existing tests lists the tests it rewrites and the suites it adds to.

## The fenced block

The Core reads exactly one block, opened by an unindented line `` ```factory-brief `` and closed by `` ``` ``. One `<key> <value>` per line; blank and `#` lines are allowed.

| Key | Meaning |
|---|---|
| `scope <glob>` | A path the issue may touch (at least one). `*` and `?` stay in one folder, `**` crosses folders, a trailing `/` is the whole folder. Cover the product files, their mirrored tests and the seams' stubs; what `tools/verify/generated` lists needs no line. Always add `scope docs/deviations.md`, where your rulings land, and `scope docs/agents/facts.md` when the brief probes a fact for it. These two are the Driver's docs: commit them on the branch in any phase, since the red gate lets them through. |
| `test <name>` | One acceptance test the red phase writes, by the name the test step reports for it: the rest of the line, spaces included. The red gate wants each to fail on an assertion; the green gate wants each to pass. |
| `seam <path> <symbol>` | A seam the red phase stubs (typed, so the tests compile) and the tests may double. Doubles anywhere else are a rubric finding. One symbol per line: a second seam of the same file is a second line. The red phase may create or change only the product files the `seam` lines name, by their exact path: so every product file a red test imports that doesn't exist yet gets a `seam` line, and so does each test tooling config the red tests need created or changed outside the `tools/verify/test-paths` globs (a test runner config at the root, say), with the export the tests rely on as its symbol. A file those globs match is a test file and needs none. |
| `removes <file> <rule> <message>` | Partial mode only: one Baseline entry the issue removes, copied whole from `tools/verify/ratchet/baseline.txt`. The Partial gate passes when the findings sit within the Baseline minus these. |
| `grows <file> <entry>` | Never at first. Added only after you accept a ratchet growth as a Deviation: the ratchet file and the exact line it gains. One line per added entry. |
| `asserts <file> <func> <from> <to>` | A drop in a test func's assertion calls that you accept: the test file (in scope), the func as `tools/verify/assert-counts` prints it (`<Class>.<func>` in an inner class), its count at the base and its count at HEAD, `0` once the func is gone. The deviation step counts every func of each test file the branch changes, and fails one whose count falls (`assert-drop`) unless a line names exactly the counts it measured; a line that no longer matches them fails too. A brief that rewrites or folds existing tests (a straight-line cleanup, a sentinel helper, two tests made one) lists each drop it expects; count the base with `git show <base>:<file> \| bash tools/verify/assert-counts <file>`. When the step reports a drop you accept, put an `asserts` line with the counts its finding names in the brief and seal again; a drop you reject is a fix round. |
| `lane small` | The issue runs in the small lane (SKILL.md), when its slice says `Lane: small`. Kind build or bug in Phase red, at most 4 `test` lines, no `seam`, and each `scope` line one file: at most 3 product files besides the tests and `docs/deviations.md`, none in the gate. |

## Template

Fill each `<...>`, keep the headings, and replace the example's names and block lines: they show valid syntax, and the template as it stands passes `brief.sh check`. The Kind line is one of `Kind: <build | bug | cleanup | amend | asset>. Phase: <red | partial | green>.`

````markdown
# Build Brief: #<n> <title>

Kind: build. Phase: red.

## Goal
<What changes for the user or in the code, in two or three sentences.>

## Acceptance criteria → tests
- <criterion, as the issue words it> → `test_reorder_waits_for_the_threshold` in `tests/stock/reorder_rule_test`
  - <the expected values this test asserts, written out>
- <a boundary or negative case the criterion implies> → `test_reorder_keeps_the_order_size`

## Existing tests
- `test_report_lists_due_orders` in `tests/stock/report_test`: in scope; <what it reads that the issue changes>
- `test_supplier_retries_an_order` in `tests/supplier/client_test`: unaffected: <why the change can't reach it>

## Seams
- `src/stock/supplier` `SupplierClient.place_order`: <what the stub returns or records, and why it is the seam>

## Probed
- <an engine or library fact the brief relies on>: <the probe that showed it, and its result>

## Constraints
- Rules this touches: <R-numbers from ARCHITECTURE.md, with one line each on what they mean here>.
- <anything decided for this issue: names, data shapes, test helpers, what must stay untouched>

## Skills
<write-tests-<stack> in the red phase; repro-first for Kind: bug; verify-<project> when a criterion needs a running build.>

```factory-brief
# Paths the issue may touch, the seams' stubs among them.
scope src/stock/reorder_rule
scope src/stock/supplier
scope tests/stock/**
scope docs/deviations.md

# One line per acceptance test.
test test_reorder_waits_for_the_threshold
test test_reorder_keeps_the_order_size

# Seams the red phase stubs.
seam src/stock/supplier SupplierClient.place_order

# Partial mode only (drop it otherwise): one line per Baseline entry removed.
removes src/stock/report long-line the line is too long
# After an accept ruling on a ratchet growth, e.g.
# grows tools/verify/ratchet/allowlist.txt src/stock/new_exception
# A rewrite of existing tests: one line per func whose assertion calls drop, e.g.
# asserts tests/stock/report_test test_report_lists_due_orders 4 1
```
````

What `brief.sh check` holds the prose to:

- **Kind line:** exactly one `Kind: <build | bug | cleanup | amend | asset>. Phase: <red | partial | green>.`; Kind cleanup goes with Phase partial, and only with it; Kind asset goes with Phase green. Kind build in Phase green is a test-only issue (SKILL.md).
- **Acceptance criteria → tests:** each bullet at the start of a line is a criterion. Its tests are the backticked names after its last `→`, but for a file named after `in`. Detail goes in indented bullets or plain lines under it; notes for the whole issue go in Constraints. A fixture several tests share goes in a plain paragraph, never a bullet at the start of a line: that bullet is a criterion, and in Phase red one without its tests fails. Every `test` line is mapped by a criterion. In Phase red every criterion maps to `test` lines; in any other phase one may say `→ judged by the Verifier` instead.
- **Seams:** bullets that name exactly the block's `seam` lines, each `` `<path>` `` then one or more `` `<symbol>` ``, or a bare `None` (`- None` and a closing `.` pass; any words after it fail). A seam described here but missing from the block is the commonest brief bug: the red phase can't stub it. Each seam's path is in scope.
- **Probed:** each fact and its probe, or None. Seams and Probed may be left out only in Phase partial.
- **Existing tests:** a bullet per existing test the change reaches, `` - `<test>` in `<file>`: `` then in scope or `unaffected: <reason>`; a file no `scope` line covers needs the `unaffected`. With none, one line `None: searched <where> for <what>`. For a test-only issue, Existing tests lists the tests it rewrites and the suites it adds to, a suite by a test already in it. Only Phase partial and Kind asset may leave it out.
- **Small lane:** a `lane small` brief stays inside the limits its table row gives, and `brief.sh seal` records the lane in the run state.
- **Test-only:** a `Kind: build. Phase: green.` brief scopes only test files and the Driver's docs (a glob counts only inside a `tests/**`-style folder of `tools/verify/test-paths`), names at least one test, and has no seam. Its criteria map to tests, or say `→ judged by the Verifier`.

A criterion the issue marks (Driver's check) maps to no test: it goes under Constraints as `The Driver's check after green: <the check, with its limits>. It is not the Editor's to run.` The Driver runs it before Land and reports it in the close comment, and the Verifier prompt tells the Verifier to SKIP it ([`prompts/verifier.md`](prompts/verifier.md)). A criterion, test bullet or Constraint never asks the Editor to run a command only the Driver runs (`brief.sh`, `lock.sh`, `state.sh`, `baseline.sh`, `start.sh`, `land.sh`): a check that needs one is a Driver's check, written as above.

In Partial mode (`Kind: cleanup`) drop the tests and seams: list `removes` lines, and scope the files those findings sit in.

An asset the issue uses is already in the repo: name it by its path from `docs/assets.md`. The Editor stays off the web, so a brief never asks it to fetch one; a missing asset is a `Kind: asset` slice first ([`assets.md`](assets.md)).
