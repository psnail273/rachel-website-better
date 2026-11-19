# baseline.sh: record, the Partial-mode gate, and shrink, on the fixture project.

BASELINE=tools/verify/ratchet/baseline.txt

run_baseline() {
	run_cmd bash "$FACTORY_CORE/baseline.sh" "$@"
}

# fixture_project_repo: the fixture project as a git repository with one commit.
fixture_project_repo() {
	fixture_project
	git init -q . || fail "git init failed"
	git -c user.name=t -c user.email=t@example.com add -A
	git -c user.name=t -c user.email=t@example.com commit -qm fixture || fail "git commit failed"
}

# Two failing steps, findings printed out of order, one duplicated.
seed_findings() {
	printf '%s\n' "src/b.txt:9 unused-var x is unused" "src/a.txt:3 long-line line too long" "src/a.txt:7 long-line line too long" > .fixture/fail-lint
	printf '%s\n' "src/c.txt:1 parse-error expected ')'" > .fixture/fail-typecheck
}

test_record_writes_a_sorted_tracked_baseline_without_line_numbers() {
	fixture_project_repo
	seed_findings
	run_baseline record
	assert_status 0
	assert_last_line "baseline: RECORDED 4 entries in $BASELINE"
	assert_eq "src/a.txt long-line line too long
src/a.txt long-line line too long
src/b.txt unused-var x is unused
src/c.txt parse-error expected ')'" "$(cat "$BASELINE")" "wrong Baseline"
	[ -n "$(git ls-files -- "$BASELINE")" ] || fail "the Baseline is not tracked"
}

test_record_on_a_green_project_writes_an_empty_baseline() {
	fixture_project_repo
	run_baseline record
	assert_status 0
	[ -f "$BASELINE" ] && [ ! -s "$BASELINE" ] || fail "expected an empty Baseline file"
}

test_record_counts_a_silent_failing_step() {
	fixture_project
	: > .fixture/fail-smoke
	run_baseline record
	assert_status 0
	assert_eq "tools/verify/smoke step-failed the step failed with no findings" "$(cat "$BASELINE")"
}

# A passing step's findings are information (deviation prints a
# deviation-declared line per trailer, with a commit SHA that changes on every
# rebase), so they are neither recorded nor gated.
test_findings_from_a_passing_step_are_ignored() {
	fixture_project
	seed_findings
	echo "docs/notes.md:1 deviation-declared needed (commit 1234567)" > .fixture/output-deviation
	run_baseline record
	assert_status 0
	assert_last_line "baseline: RECORDED 4 entries in $BASELINE"
	echo "docs/notes.md:1 deviation-declared needed (commit 89abcde)" > .fixture/output-deviation
	run_baseline gate
	assert_status 0
	assert_last_line "baseline: PASS"
}

test_record_refuses_when_a_baseline_exists() {
	fixture_project
	mkdir -p tools/verify/ratchet
	echo "src/a.txt long-line line too long" > "$BASELINE"
	seed_findings
	run_baseline record
	assert_status 1
	assert_eq "src/a.txt long-line line too long" "$(cat "$BASELINE")" "record changed an existing Baseline"
}

test_gate_passes_when_findings_are_within_the_baseline() {
	fixture_project
	seed_findings
	run_baseline record
	rm .fixture/fail-typecheck
	run_baseline gate
	assert_status 0
	assert_last_line "baseline: PASS"
}

test_gate_fails_on_a_finding_not_in_the_baseline() {
	fixture_project
	seed_findings
	run_baseline record
	echo "src/d.txt:4 unused-var y is unused" >> .fixture/fail-lint
	run_baseline gate
	assert_status 1
	assert_line "new:"
	assert_line "  src/d.txt:4 unused-var y is unused"
	assert_no_line "still present:"
	assert_last_line "baseline: FAILED"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_gate_fails_on_an_extra_copy_of_a_baseline_finding() {
	fixture_project
	seed_findings
	run_baseline record
	echo "src/b.txt:20 unused-var x is unused" >> .fixture/fail-lint
	run_baseline gate
	assert_status 1
	assert_eq "new:" "$(printf '%s\n' "$out" | head -n 1)" "the extra copy is not reported new"
	# Which copy is the extra one can't be told apart, so only one is reported.
	assert_eq 1 "$(printf '%s\n' "$out" | grep -c 'unused-var x is unused$')" "expected one copy reported"
}

# The audit skill's run (factory/skills/audit): one keep-going verify, whose
# verdict the gate then reuses, running no step again, to name what is new.
test_the_audits_gate_reuses_its_keep_going_verify() {
	fixture_git_project
	seed_findings
	run_baseline record
	git commit -qm baseline || fail "could not commit the Baseline"
	echo "src/d.txt:2 new-rule a new finding" >> .fixture/fail-lint
	FACTORY_BASE=HEAD run_cmd bash "$FACTORY_CORE/verify.sh" --keep-going --reuse
	assert_status 1
	rm -f .fixture/ran
	FACTORY_BASE=HEAD run_baseline --reuse gate
	assert_status 1
	assert_eq "" "$(ran_steps)" "the gate ran a step again"
	assert_eq "new:
  src/d.txt:2 new-rule a new finding
baseline: FAILED" "$out" "the gate's verdict"
}

test_gate_fails_on_a_named_entry_still_present() {
	fixture_project
	seed_findings
	run_baseline record
	printf '%s\n' "# entries this issue removes" "src/c.txt:1 parse-error expected ')'" > named.txt
	run_baseline gate named.txt
	assert_status 1
	assert_line "still present:"
	assert_line "  src/c.txt:1 parse-error expected ')'"
	assert_no_line "new:"
	assert_last_line "baseline: FAILED"
}

test_gate_names_one_copy_of_a_duplicate_entry_still_present() {
	fixture_project
	seed_findings
	run_baseline record
	echo "src/a.txt long-line line too long" > named.txt
	run_baseline gate named.txt
	assert_status 1
	assert_line "still present:"
	assert_no_line "new:"
	assert_eq 1 "$(printf '%s\n' "$out" | grep -c 'long-line line too long$')" "expected one copy reported"
}

test_gate_passes_once_the_named_entries_are_fixed() {
	fixture_project
	seed_findings
	run_baseline record
	echo "src/c.txt parse-error expected ')'" > named.txt
	rm .fixture/fail-typecheck
	run_baseline gate named.txt
	assert_status 0
	assert_last_line "baseline: PASS"
}

test_gate_fails_on_a_named_entry_the_baseline_lacks() {
	fixture_project
	seed_findings
	run_baseline record
	echo "src/z.txt lint-x not there" > named.txt
	run_baseline gate named.txt
	assert_status 1
	assert_line "  src/z.txt lint-x not there"
	assert_last_line "baseline: FAILED"
}

test_gate_matches_a_baseline_finding_whose_line_moved() {
	fixture_project
	seed_findings
	run_baseline record
	printf '%s\n' "src/b.txt:42 unused-var x is unused" "src/a.txt:13 long-line line too long" "src/a.txt:17 long-line line too long" > .fixture/fail-lint
	run_baseline gate
	assert_status 0
	assert_last_line "baseline: PASS"
}

test_gate_without_a_baseline_fails() {
	fixture_project
	run_baseline gate
	assert_status 1
}

test_shrink_removes_fixed_entries() {
	fixture_project
	seed_findings
	run_baseline record
	rm .fixture/fail-typecheck
	echo "src/a.txt:30 long-line line too long" > .fixture/fail-lint
	run_baseline shrink
	assert_status 0
	assert_line "  src/a.txt long-line line too long"
	assert_line "  src/b.txt unused-var x is unused"
	assert_line "  src/c.txt parse-error expected ')'"
	assert_last_line "baseline: SHRUNK 3 removed, 1 left"
	assert_eq "src/a.txt long-line line too long" "$(cat "$BASELINE")" "wrong Baseline after shrink"
}

test_shrink_never_adds_entries() {
	fixture_project
	seed_findings
	run_baseline record
	before="$(cat "$BASELINE")"
	echo "src/d.txt:4 unused-var y is unused" >> .fixture/fail-lint
	echo "src/e.txt:1 smoke-error boom" > .fixture/fail-smoke
	run_baseline shrink
	assert_status 0
	assert_last_line "baseline: SHRUNK 0 removed, 4 left"
	assert_eq "$before" "$(cat "$BASELINE")" "shrink changed the Baseline"
}

test_add_puts_a_new_rules_findings_in_the_baseline() {
	fixture_project_repo
	mkdir -p tools/verify/ratchet
	echo "src/a.txt long-line line too long" > "$BASELINE"
	printf '%s\n' "src/a.txt:3 long-line line too long" "src/b.txt:9 named-tol the tolerance 0.1 is a number" "src/b.txt:12 named-tol the tolerance 0.1 is a number" > .fixture/fail-lint
	run_baseline add named-tol
	assert_status 0
	assert_line "  src/b.txt named-tol the tolerance 0.1 is a number"
	assert_last_line "baseline: ADDED 2 entries for named-tol, 3 in all"
	assert_eq "src/a.txt long-line line too long
src/b.txt named-tol the tolerance 0.1 is a number
src/b.txt named-tol the tolerance 0.1 is a number" "$(cat "$BASELINE")" "wrong Baseline after add"
	[ -n "$(git diff --cached --name-only -- "$BASELINE")" ] || fail "add did not stage the Baseline"
	run_baseline gate
	assert_status 0
}

# A plugin's ESLint rule id has an @ and a /.
test_add_takes_a_plugin_rule_id() {
	fixture_project_repo
	mkdir -p tools/verify/ratchet
	: > "$BASELINE"
	printf '%s\n' "src/b.ts:4 @typescript-eslint/require-await Async function 'f' has no 'await' expression." > .fixture/fail-lint
	run_baseline add @typescript-eslint/require-await
	assert_status 0
	assert_last_line "baseline: ADDED 1 entries for @typescript-eslint/require-await, 1 in all"
	assert_eq "src/b.ts @typescript-eslint/require-await Async function 'f' has no 'await' expression." "$(cat "$BASELINE")" "wrong Baseline after add"
}

test_add_refuses_a_rule_with_a_space_or_a_glob_as_usage() {
	fixture_project
	run_baseline add 'two words'
	assert_status 2
	run_baseline add 'rule*'
	assert_status 2
}

test_add_refuses_a_finding_from_another_rule() {
	fixture_project
	mkdir -p tools/verify/ratchet
	: > "$BASELINE"
	printf '%s\n' "src/b.txt:9 named-tol the tolerance 0.1 is a number" "src/c.txt:2 unused-var y is unused" > .fixture/fail-lint
	run_baseline add named-tol
	assert_status 1
	assert_line "  src/c.txt:2 unused-var y is unused"
	assert_no_line "  src/b.txt:9 named-tol the tolerance 0.1 is a number"
	[ ! -s "$BASELINE" ] || fail "a refused add changed the Baseline"
}

test_add_without_a_rule_is_usage() {
	fixture_project
	run_baseline add
	assert_status 2
}

test_unknown_subcommand_is_usage() {
	fixture_project
	run_baseline grow
	assert_status 2
}
