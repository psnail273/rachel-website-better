---
name: write-tests-godot
description: Write gdUnit4 tests for a Build Brief's red phase: public seams, hand-written expected values, typed stubs, seeded fuzzers, durable timing. Use when writing, reviewing or fixing flaky GDScript tests.
---

Tests written first, from a Build Brief, before the code exists. Each one pins a criterion of the brief so that only a correct implementation turns it green. The Verifier reads your tests against the **rubric** below, and the red gate checks the **gate rules** by script, so every item here is one you control.

## Red phase

The red commit holds the brief's named tests plus **typed stubs** of its named seams, and nothing else. It becomes the **Lock**: after it, any edit to those tests is a Deviation.

1. **Mirror.** Each product script `<path>/<name>.gd` gets its tests in `tests/<path>/<name>_test.gd` (R8), a `GdUnitTestSuite`. Add to the mirror file when it exists.
2. **Names.** Name each test `test_<behaviour>` exactly as the brief lists it; the gate reads the names from `results.xml` and compares them character for character.
3. **Typed stubs.** Each seam the brief names exists with its real signature: typed parameters, a typed return, `class_name` where the brief gives one. Its body returns the empty value of its type (`0`, `0.0`, `false`, `""`, `[]`, `Vector2.ZERO`, a fresh instance) and does nothing else. The stub parses and runs, so every test reaches its assertion.
4. **Red for the assertion.** Run the tests. Done when every named test fails with an assertion `FAILURE`. A pass means the test checks nothing the stub lacks; an `ABORT` (crash) or exit 105 (parse error, a missing stub) means it never reached its assertion. Rework the test or the stub until each one is red for its assertion.

## Rubric

Every item holds for every test.

- **Public seam.** Drive the code through what callers use: the class's public methods, its signals, the scene's exported properties and input. Leave `_`-prefixed members and private state untouched.
- **Hand-written expected values.** Work each expected value out from the brief and write it as a literal or a named constant in the test. The code under test never computes its own expected value.
- **Exact assertions.** Assert the exact value: `assert_int(score).is_equal(150)`. Floats use `is_equal_approx` with a named tolerance constant. Assert a signal's arguments as well as its emission.
- **Boundaries and negatives.** Each criterion gets its edge cases (zero, the last one, the limit and one past it, empty) and the case where nothing should happen: the input that is refused, the signal that stays silent, the state that is left unchanged.
- **Fakes at seams only.** Use a double (`mock(`, `spy(`) only for a seam the brief names, and prefer a small hand-written fake. Assert what the code under test did with the double's value, never the value you stubbed into it.
- **Straight-line.** Arrange, act, assert, with no branches or loops that decide what gets asserted, and no sleeps. Give every number a name or derive it from the config the test built (`_config.max_lives`). Every assertion runs on every run, so none sits under an `if`, `for`, `while` or `match`, or after a guard `return`, in the test or in a helper it calls. The shapes that pass:
  - **Many recorded values.** The double keeps them in a list, with `call_count()` and `call_at(i)`; `call_at(i)` returns a sentinel past the end, so a short list fails the assertion instead of crashing. Assert the count, then each index, one line per field: `assert_int(motor.call_count()).is_equal(3)`, `assert_int(motor.call_at(0).duration_ms).is_equal(PULSE_MS)`, `assert_float(motor.call_at(0).amplitude).is_equal_approx(PULSE_AMP, AMPLITUDE_TOLERANCE)`. When the order of the calls isn't the criterion, the double sorts the list.
  - **Every item of a collection.** The loop collects what is wrong, and one assertion after it checks the collection: `assert_array(problems).is_empty()`, with the item named in each entry. Or make it a parameterized test, one case per item.
  - **A collected check keeps the assertion's exact failure condition**, type included. Compare with `not is_same(v, <expected>)`; an Array with `!=`, since `is_same` compares Arrays by reference. Never put a typed `var`, `str()`, a truth test or `!=` between a value and its compare, and never let `elif` or `continue` skip a check. A rewrite that leaves a func fewer assertion calls than the base fails the deviation step's `assert-drop`, unless the brief declares it.
  - **An object that may be null.** Assert `is_not_null()` and go on, with no guard `return`. A stub returns a fresh instance, so the red test still reaches its assertions.
- **Property tests match the invariants.** A fuzzer checks an invariant the brief states ("the speed never exceeds max_speed"), asserted for every generated input.
- **No special-casing.** In the green phase, product code treats test inputs like any others: no branch on a test's values, names or run mode.

## Gate rules

The red gate fails a test that breaks any of these.

- **An assertion in every test.** Each `func test_` calls `assert_*(`, `verify(`, `verify_no_interactions(` or `verify_no_more_interactions(`.
- **Floats within a named tolerance.** The lint step fails a tolerance written as a number (`is_equal_approx(x, 0.01)`: declare `const TOLERANCE := 0.01`), a float tolerance given to `assert_vector(...).is_equal_approx`, which takes a vector (`Vector2(TOLERANCE, TOLERANCE)`), and a float compared exactly inside `assert_array` or `assert_dict` (compare each float on its own with `is_equal_approx`). A position a criterion bounds by distance ("within 4 px of") is one assertion on `position.distance_to(expected)`, not a check per axis.
- **No branched assertions.** The lint step's `branched-assert` check fails an assertion (`assert_*(`, `verify(`, `verify_no_interactions(`, `verify_no_more_interactions(`, `fail(`) on a line the branch adds to a test file, in a test or a helper, when it sits under an `if`, `elif`, `else`, `for`, `while` or `match`, or after a `return` inside one in the same func. A loop that waits for a state passes, with the assertion after it at the loop's own indent. The shapes that pass are under Straight-line.
- **Guarded polls.** A `while` loop that awaits puts its guard in its condition, a guard timer's `time_left` or a frame counter: `while not done and guard.time_left > 0.0:`. The lint step's `unguarded-poll` check fails a new one with neither.
- **Nothing skipped.** gdUnit4 skips a test silently when an argument breaks its rules, and a skip fails the gate. The legal arguments, in this order:
  - fuzzers first: one or more, each named `fuzzer` or `fuzzer_<x>` with a Fuzzer default; a fuzzer after any config argument skips the test;
  - a parameterized test's value arguments, then `test_parameters := [...]` after them;
  - config arguments: `timeout`, `fuzzer_iterations`, `fuzzer_seed`, `do_skip`, `skip_reason`.

  Any other name skips the test. `do_skip` skips it whenever its value is true (`do_skip := false` runs it), so leave it out. A leading `_` is allowed on any argument, and needed on one the body doesn't read: with `unused_parameter` at Error, as the typecheck gate has it, such an argument fails to parse. So write `_test_parameters := [...]`, `_fuzzer_iterations` and `_fuzzer_seed`.
- **Seeded fuzzers.** Every fuzzer test declares `fuzzer_seed`: `func test_speed_capped(fuzzer := Fuzzers.rangef(0.0, 2000.0), _fuzzer_iterations := 200, _fuzzer_seed := 7) -> void:`
- **Same verdict twice.** The red verdicts must match on a second run, which the durable rules below make true.

## Durable tests

A durable test gives the same verdict on a machine ten times slower, under a loaded CPU, and in any test order. Its verdict depends only on the code under test.

1. **The test drives time.** Advance a fixed number of frames or physics steps (`runner.simulate_frames(n)`), or call the tick function with a fixed `delta`.
2. **Fire timers by hand.** Emit the timer's `timeout` signal or call its handler, then assert the change. Make delays config values a test can set to zero.
3. **Await a signal or condition.** `await assert_signal(node).is_emitted("cleared")`. A timeout is only a hang guard, many times longer than the work, and the assertion never depends on it.
4. **Outcomes at the pure seam.** Angles, scores and collision rules are pure functions tested with exact inputs. A test that runs real physics asserts what holds whatever the frame timing: the body stayed inside the arena, a signal fired, nothing was orphaned.
5. **Inject randomness and dates.** Seed the RNG, or pass the random value or date in.
6. **Isolate shared state.** Each test uses its own paths (`user://test_<suite>_<case>.json`), cleans up and frees what it creates.

**Audit** the changed test files for `await_millis`, `create_timer`, `OS.delay_msec`, `Time.get_ticks_msec`, `Time.get_unix_time`, unseeded `randi`/`randf`, and `user://` paths shared between tests. Done when each hit is rewritten to the rules above or carries a one-line comment saying why its verdict can't depend on timing (a hang guard). The lint step's `fixed-wait` check fails a new `await_millis`, awaited `create_timer` or `OS.delay_msec` line unless that comment reads `# fixed-wait: <why>`, on the line or alone above it; a guard timer kept in a variable and polled needs none.

A test that failed once and then passed breaks one of these rules: find which and fix it, or delete it when a pure-seam test covers its behaviour. A retry or a longer wait leaves the bug in place.
