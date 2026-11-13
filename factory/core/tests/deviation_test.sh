# The deviation step (deviation.sh): the branch's diff against the brief's scope,
# the Deviation trailers and the ratchet files.

# work_repo: a repo in $TEST_TMP/repo with one commit on dev and a work branch
# checked out from it, and cd there.
work_repo() {
	isolate_git
	git init -q -b dev "$TEST_TMP/repo" || fail "git init failed"
	cd "$TEST_TMP/repo" || fail "no repo"
	mkdir -p src docs tools/verify/ratchet
	echo one > src/a.txt
	echo one > docs/notes.md
	printf '# allowed tool scripts\nlib/guides.txt\nlib/old.txt\n' > tools/verify/ratchet/tools.txt
	commit "base"
	git checkout -q -b work
}

# commit <subject> [<paragraph>...]: commit everything, each extra argument a
# message paragraph (put trailers in the last one).
commit() {
	local args=() p
	for p in "$@"; do args+=(-m "$p"); done
	git add -A
	git commit -q "${args[@]}" || fail "commit failed"
}

run_deviation() {
	run_cmd bash "$FACTORY_CORE/deviation.sh"
}

sha() {
	git rev-parse --short "${1:-HEAD}"
}

# generated <line...>: the project's tools/verify/generated, in the base commit, so
# it isn't itself in the branch's diff.
generated() {
	printf '%s\n' "$@" > tools/verify/generated
	git add -A && git commit -q --amend -m base || fail "commit failed"
	git branch -f dev HEAD
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_in_scope_changes_pass_silently() {
	work_repo
	brief "scope src/**"
	echo two > src/a.txt
	echo new > src/b.txt
	commit "change src"
	run_deviation
	assert_status 0
	assert_eq "" "$out"
}

# A brief changed after the Driver sealed it fails the step, even on an empty diff.
test_a_brief_changed_after_its_seal_fails() {
	work_repo
	mkdir -p .git/factory
	printf '%s\n' '```factory-brief' 'scope src/**' '```' > .git/factory/brief.md
	git config branch.work.factory-brief-sha "$(git hash-object --no-filters .git/factory/brief.md)"
	run_deviation
	assert_status 0
	echo "grows tools/verify/ratchet/tools.txt lib/new.txt" >> .git/factory/brief.md
	run_deviation
	assert_status 1
	assert_eq ".git/factory/brief.md:1 brief-changed the Build Brief changed after the Driver sealed it; only the Driver edits it, then seals it again with brief.sh seal (Editor: report this and stop)" "$out"
}

test_off_scope_file_without_trailer_fails_naming_it() {
	work_repo
	brief "scope src/**"
	echo two > src/a.txt
	echo two > docs/notes.md
	commit "change both"
	run_deviation
	assert_status 1
	assert_eq "docs/notes.md:1 deviation-undeclared outside the brief's scope, and no commit has a 'Deviation: docs/notes.md: <reason>' trailer" "$out"
}

test_off_scope_file_with_trailer_passes_and_is_listed_as_declared() {
	work_repo
	brief "scope src/**"
	echo two > src/a.txt
	echo two > docs/notes.md
	commit "change both" "Deviation: docs/notes.md: the notes name the new file"
	run_deviation
	assert_status 0
	assert_eq "docs/notes.md:1 deviation-declared the notes name the new file (commit $(sha))" "$out"
}

test_trailer_in_an_earlier_commit_counts() {
	work_repo
	brief "scope src/**"
	echo two > docs/notes.md
	commit "notes" "Deviation: docs/notes.md: needed"
	echo two > src/a.txt
	commit "src"
	run_deviation
	assert_status 0
	assert_line "docs/notes.md:1 deviation-declared needed (commit $(sha HEAD~1))"
}

test_trailer_glob_declares_matching_files_only() {
	work_repo
	brief "scope src/**"
	echo x > docs/a.md
	echo x > docs/b.md
	mkdir -p other
	echo x > other/c.md
	commit "docs" "Deviation: docs/*.md: docs for the feature"
	run_deviation
	assert_status 1
	assert_eq "docs/*.md:1 deviation-declared docs for the feature (commit $(sha))
other/c.md:1 deviation-undeclared outside the brief's scope, and no commit has a 'Deviation: other/c.md: <reason>' trailer" "$out"
}

test_rule_deviation_is_listed_as_declared() {
	work_repo
	brief "scope src/**"
	echo two > src/a.txt
	commit "src" "Deviation: R11: a tool script the build needs"
	run_deviation
	assert_status 0
	assert_eq "R11:1 deviation-declared a tool script the build needs (commit $(sha))" "$out"
}

test_trailer_without_a_reason_fails() {
	work_repo
	brief "scope src/**"
	echo two > docs/notes.md
	commit "notes" "Deviation: docs/notes.md"
	run_deviation
	assert_status 1
	assert_line "tools/verify/deviation:1 deviation-format commit $(sha): expected 'Deviation: <path or rule>: <reason>', got: docs/notes.md"
	assert_line "docs/notes.md:1 deviation-undeclared outside the brief's scope, and no commit has a 'Deviation: docs/notes.md: <reason>' trailer"
}

test_renamed_file_counts_its_old_path() {
	work_repo
	brief "scope src/**"
	git mv docs/notes.md src/notes.md
	commit "move"
	run_deviation
	assert_status 1
	assert_eq "docs/notes.md:1 deviation-undeclared outside the brief's scope, and no commit has a 'Deviation: docs/notes.md: <reason>' trailer" "$out"
}

# tools/verify/generated: what the project's tools generate.
test_off_scope_file_matching_a_generated_glob_passes() {
	work_repo
	generated '**/*.uid' '**/*.import'
	brief "scope src/**"
	echo two > src/a.txt
	echo uid > root.uid
	echo uid > docs/notes.uid
	echo x > docs/notes.import
	commit "a change and what it generated"
	run_deviation
	assert_status 0
	assert_eq "" "$out"
}

test_off_scope_file_matching_no_generated_glob_still_fails() {
	work_repo
	generated '**/*.uid'
	brief "scope src/**"
	echo uid > docs/notes.uid
	echo two > docs/notes.md
	commit "a generated file and a real one"
	run_deviation
	assert_status 1
	assert_eq "docs/notes.md:1 deviation-undeclared outside the brief's scope, and no commit has a 'Deviation: docs/notes.md: <reason>' trailer" "$out"
}

test_nothing_is_generated_without_the_file() {
	work_repo
	brief "scope src/**"
	echo uid > docs/notes.uid
	commit "a generated file"
	run_deviation
	assert_status 1
	assert_eq "docs/notes.uid:1 deviation-undeclared outside the brief's scope, and no commit has a 'Deviation: docs/notes.uid: <reason>' trailer" "$out"
}

test_nothing_is_generated_by_a_file_with_no_glob() {
	work_repo
	generated '# nothing yet' ''
	brief "scope src/**"
	echo uid > docs/notes.uid
	commit "a generated file"
	run_deviation
	assert_status 1
	assert_eq "docs/notes.uid:1 deviation-undeclared outside the brief's scope, and no commit has a 'Deviation: docs/notes.uid: <reason>' trailer" "$out"
}

test_generated_file_may_hold_comments_blank_lines_and_crlf() {
	work_repo
	generated '# what the tools write' '' $'**/*.uid\r'
	brief "scope src/**"
	echo uid > docs/notes.uid
	commit "a generated file"
	run_deviation
	assert_status 0
	assert_eq "" "$out"
}

# The shell mustn't expand the globs against the tree: the deleted file isn't on
# disk, and keep.uid is.
test_generated_globs_match_a_file_the_branch_deleted() {
	work_repo
	echo uid > keep.uid
	echo uid > gone.uid
	generated '*.uid'
	brief "scope src/**"
	git rm -q gone.uid
	commit "drop what is no longer generated"
	run_deviation
	assert_status 0
	assert_eq "" "$out"
}

test_a_generated_ratchet_file_still_may_not_grow() {
	work_repo
	generated '**/*.txt'
	brief "scope src/**"
	echo "lib/new.txt" >> tools/verify/ratchet/tools.txt
	commit "allow a tool"
	run_deviation
	assert_status 1
	assert_eq "tools/verify/ratchet/tools.txt:4 ratchet-growth added 'lib/new.txt'; ratchet files may only shrink" "$out"
}

test_growing_ratchet_file_fails_even_in_scope_with_a_trailer() {
	work_repo
	brief "scope tools/**"
	echo "lib/new.txt" >> tools/verify/ratchet/tools.txt
	commit "allow a tool" "Deviation: tools/verify/ratchet/tools.txt: the editor needs it"
	run_deviation
	assert_status 1
	assert_eq "tools/verify/ratchet/tools.txt:1 deviation-declared the editor needs it (commit $(sha))
tools/verify/ratchet/tools.txt:4 ratchet-growth added 'lib/new.txt'; ratchet files may only shrink" "$out"
}

test_replacing_a_ratchet_entry_is_growth() {
	work_repo
	brief "scope src/**"
	printf '# allowed tool scripts\nlib/guides.txt\nlib/swapped.txt\n' > tools/verify/ratchet/tools.txt
	commit "swap"
	run_deviation
	assert_status 1
	assert_eq "tools/verify/ratchet/tools.txt:3 ratchet-growth added 'lib/swapped.txt'; ratchet files may only shrink" "$out"
}

test_new_ratchet_file_with_entries_is_growth() {
	work_repo
	brief "scope src/**"
	echo "src/main.txt" > tools/verify/ratchet/format_exclude.txt
	commit "exclude"
	run_deviation
	assert_status 1
	assert_eq "tools/verify/ratchet/format_exclude.txt:1 ratchet-growth added 'src/main.txt'; ratchet files may only shrink" "$out"
}

test_shrinking_ratchet_file_passes_without_scope_or_trailer() {
	work_repo
	brief "scope src/**"
	printf '# allowed tool scripts, now fewer\n\nlib/guides.txt\n' > tools/verify/ratchet/tools.txt
	commit "shrink"
	run_deviation
	assert_status 0
	assert_eq "" "$out"
}

test_ratchet_growth_fails_without_a_brief() {
	work_repo
	echo "lib/new.txt" >> tools/verify/ratchet/tools.txt
	commit "allow a tool"
	run_deviation
	assert_status 1
	assert_eq "tools/verify/ratchet/tools.txt:4 ratchet-growth added 'lib/new.txt'; ratchet files may only shrink" "$out"
}

test_changes_without_a_brief_fail() {
	work_repo
	echo two > src/a.txt
	commit "src"
	run_deviation
	assert_status 1
	assert_eq "$BRIEF:1 brief-missing no Build Brief at this path" "$out"
}

test_malformed_brief_fails_naming_the_problem() {
	work_repo
	brief "scope src/**" "scopes docs/**"
	echo two > src/a.txt
	commit "src"
	run_deviation
	assert_status 1
	assert_eq "$BRIEF:4 brief-format unknown key 'scopes'; the keys are: scope test seam removes grows asserts lane" "$out"
}

test_empty_diff_needs_no_brief() {
	work_repo
	run_deviation
	assert_status 0
	assert_eq "" "$out"
}

test_base_can_be_set() {
	work_repo
	brief "scope src/**"
	echo two > docs/notes.md
	commit "notes"
	echo two > src/a.txt
	commit "src"
	FACTORY_BASE="$(git rev-parse HEAD~1)" run_deviation
	assert_status 0
	assert_eq "" "$out"
}

test_missing_base_branch_fails() {
	work_repo
	FACTORY_BASE_BRANCH=main run_deviation
	assert_status 1
	assert_eq "tools/verify/deviation:1 deviation-base no merge-base of HEAD and 'main'; set FACTORY_BASE or FACTORY_BASE_BRANCH" "$out"
}

test_runner_reports_the_seeded_step_in_findings_format() {
	fixture_project
	echo 'exec bash "$FACTORY_CORE/deviation.sh"' > tools/verify/deviation
	isolate_git
	git init -q -b dev . || fail "git init failed"
	commit "base"
	git checkout -q -b work
	brief "scope src/**"
	echo x > off.txt
	commit "off scope"
	run_verify deviation
	assert_status 1
	assert_eq "== deviation FAIL
off.txt:1 deviation-undeclared outside the brief's scope, and no commit has a 'Deviation: off.txt: <reason>' trailer
verify: FAILED at step deviation" "$out"
}

test_duplicating_a_ratchet_entry_is_growth() {
	work_repo
	brief "scope src/**"
	echo "lib/guides.txt" >> tools/verify/ratchet/tools.txt
	commit "repeat an entry"
	run_deviation
	assert_status 1
	assert_eq "tools/verify/ratchet/tools.txt:4 ratchet-growth added 'lib/guides.txt'; ratchet files may only shrink" "$out"
}

test_removing_one_of_two_repeated_entries_passes() {
	work_repo
	printf '# allowed tool scripts\nlib/guides.txt\nlib/guides.txt\n' > tools/verify/ratchet/tools.txt
	git add -A && git commit -q --amend -m base
	git branch -f dev HEAD
	brief "scope src/**"
	printf '# allowed tool scripts\nlib/guides.txt\n' > tools/verify/ratchet/tools.txt
	commit "drop a repeat"
	run_deviation
	assert_status 0
	assert_eq "" "$out"
}

# Opus's accept ruling on a ratchet growth is a `grows` line in the brief (a rule
# may make a new allowlist entry a declared Deviation, not an amend).
test_growth_the_brief_accepts_passes_and_is_listed() {
	work_repo
	brief "scope src/**" "grows tools/verify/ratchet/tools.txt lib/new.txt"
	echo "lib/new.txt" >> tools/verify/ratchet/tools.txt
	commit "allow a tool" "Deviation: tools/verify/ratchet/tools.txt: the build tool needs it"
	run_deviation
	assert_status 0
	assert_eq "tools/verify/ratchet/tools.txt:1 deviation-declared the build tool needs it (commit $(sha))
tools/verify/ratchet/tools.txt:4 ratchet-accepted added 'lib/new.txt'; the brief accepts it (grows)" "$out"
}

test_accepted_growth_keeps_failing_the_entries_it_does_not_name() {
	work_repo
	brief "scope src/**" "grows tools/verify/ratchet/tools.txt lib/new.txt"
	printf 'lib/new.txt\nlib/other.txt\n' >> tools/verify/ratchet/tools.txt
	commit "allow two tools"
	run_deviation
	assert_status 1
	assert_line "tools/verify/ratchet/tools.txt:5 ratchet-growth added 'lib/other.txt'; ratchet files may only shrink"
	assert_no_line "tools/verify/ratchet/tools.txt:4 ratchet-growth added 'lib/new.txt'; ratchet files may only shrink"
}

test_one_grows_line_accepts_one_copy_of_an_entry() {
	work_repo
	brief "scope src/**" "grows tools/verify/ratchet/tools.txt lib/guides.txt"
	printf 'lib/guides.txt\nlib/guides.txt\n' >> tools/verify/ratchet/tools.txt
	commit "repeat an entry twice"
	run_deviation
	assert_status 1
	assert_line "tools/verify/ratchet/tools.txt:5 ratchet-growth added 'lib/guides.txt'; ratchet files may only shrink"
	assert_line "tools/verify/ratchet/tools.txt:5 ratchet-accepted added 'lib/guides.txt'; the brief accepts it (grows)"
}

test_grows_names_the_file_as_well_as_the_entry() {
	work_repo
	brief "scope src/**" "grows tools/verify/ratchet/other.txt lib/new.txt"
	echo "lib/new.txt" >> tools/verify/ratchet/tools.txt
	commit "allow a tool"
	run_deviation
	assert_status 1
	assert_eq "tools/verify/ratchet/tools.txt:4 ratchet-growth added 'lib/new.txt'; ratchet files may only shrink" "$out"
}

test_an_accepted_baseline_entry_keeps_its_spaces() {
	work_repo
	printf 'src/a.txt long-line line too long\n' > tools/verify/ratchet/baseline.txt
	git add -A && git commit -q --amend -m base
	git branch -f dev HEAD
	brief "scope src/**" "grows tools/verify/ratchet/baseline.txt src/b.txt unused-var x is  unused"
	printf 'src/b.txt unused-var x is  unused\n' >> tools/verify/ratchet/baseline.txt
	commit "grow the Baseline"
	run_deviation
	assert_status 0
	assert_eq "tools/verify/ratchet/baseline.txt:2 ratchet-accepted added 'src/b.txt unused-var x is  unused'; the brief accepts it (grows)" "$out"
}

# toy_probe: a stand-in tools/verify/assert-counts, so the Core's check runs
# without a stack. It counts a toy format in *.txt files: `func <name>` opens a
# func, and each `check(` after it is an assertion call. Not committed.
toy_probe() {
	cat > tools/verify/assert-counts << 'SH'
case "$1" in *.txt) ;; *) cat > /dev/null; exit 0 ;; esac
awk '
	$1 == "func" { f = $2; if (!(f in c)) { order[++n] = f; at[f] = NR; c[f] = 0 }; next }
	f != "" { c[f] += gsub(/check\(/, "&") }
	END { for (i = 1; i <= n; i++) print at[order[i]] " " order[i] " " c[order[i]] }
'
SH
}

# test_only_repo: work_repo with test paths and the toy probe in the base, and a
# test-only brief (Kind build, Phase green) scoping tests/** and the Driver's docs.
test_only_repo() {
	work_repo
	echo 'tests/**' > tools/verify/test-paths
	toy_probe
	git add -A && git commit -q --amend -m base || fail "commit failed"
	git branch -f dev HEAD
	mkdir -p .git/factory
	cat > "$BRIEF" << MD
# Build Brief: #7 Leak check

Kind: build. Phase: green.

## Acceptance criteria → tests
- a session leaks nothing → \`test_session_leaks_nothing\`

## Seams
None

## Probed
None

${FENCE}factory-brief
scope tests/**
scope docs/deviations.md
scope docs/agents/facts.md
test test_session_leaks_nothing
$FENCE
MD
}

test_a_test_only_branch_may_change_tests_and_the_drivers_docs() {
	test_only_repo
	mkdir -p tests docs/agents
	echo test_session_leaks_nothing > tests/leak_test.txt
	echo "a ruling" > docs/deviations.md
	echo "a fact" > docs/agents/facts.md
	commit "tests"
	run_deviation
	assert_status 0
	assert_eq "" "$out"
}

# A trailer excuses an off-scope file elsewhere, but not a product file here.
test_a_test_only_branch_fails_on_a_product_file_with_a_trailer_or_without() {
	test_only_repo
	echo two > src/a.txt
	commit "product" "Deviation: src/a.txt: the test needs a hook"
	echo two > docs/notes.md
	commit "notes"
	run_deviation
	assert_status 1
	assert_eq "docs/notes.md:1 deviation-undeclared outside the brief's scope, and no commit has a 'Deviation: docs/notes.md: <reason>' trailer
docs/notes.md:1 test-only-product changed under a test-only brief (Kind build, Phase green), which changes only test files (tools/verify/test-paths) and the Driver's docs, with a trailer or without; a product change needs a red phase
src/a.txt:1 deviation-declared the test needs a hook (commit $(sha HEAD~1))
src/a.txt:1 test-only-product changed under a test-only brief (Kind build, Phase green), which changes only test files (tools/verify/test-paths) and the Driver's docs, with a trailer or without; a product change needs a red phase" "$out"
}

# A file the project's tools generate stays out of it, as out of the scope check.
test_a_test_only_branch_skips_generated_files() {
	test_only_repo
	generated '**/*.uid'
	mkdir -p tests
	echo test_session_leaks_nothing > tests/leak_test.txt
	echo uid > tests/leak_test.txt.uid
	echo uid > src/a.txt.uid
	commit "tests"
	run_deviation
	assert_status 0
	assert_eq "" "$out"
}

# The same change under a brief with a red phase is only a declared Deviation.
test_a_red_phase_brief_takes_a_declared_product_change() {
	test_only_repo
	sed -i 's/Phase: green/Phase: red/' "$BRIEF"
	echo two > src/a.txt
	commit "product" "Deviation: src/a.txt: the test needs a hook"
	run_deviation
	assert_status 0
	assert_eq "src/a.txt:1 deviation-declared the test needs a hook (commit $(sha))" "$out"
}

# --- assert-drop: a test func's assertion calls, at the base and at HEAD ---

# assert_repo: work_repo with test paths and the toy probe in the base, and
# tests/a_test.txt, whose test_a makes 3 assertion calls, test_b 2 and helper
# none; the brief scopes tests/** and src/**.
assert_repo() {
	work_repo
	echo 'tests/**' > tools/verify/test-paths
	toy_probe
	mkdir -p tests
	printf 'func test_a\ncheck(1)\ncheck(2) check(3)\nfunc test_b\ncheck(4)\ncheck(5)\nfunc helper\nmake(6)\n' > tests/a_test.txt
	git add -A && git commit -q --amend -m base || fail "commit failed"
	git branch -f dev HEAD
	brief "scope tests/**" "scope src/**" "$@"
}

DROP_HINT="keep every check, or the Driver declares the drop in the brief"

# A sentinel helper that takes over a test's checks (#171) drops them: test_a's
# count falls, though the file's total stays, and a trailer doesn't excuse it.
test_a_func_that_loses_assertion_calls_fails_trailer_or_not() {
	assert_repo
	printf 'func test_a\ncheck(sentinel(1))\nfunc sentinel\ncheck(1) check(2)\nfunc test_b\ncheck(4)\ncheck(5)\nfunc helper\nmake(6)\n' > tests/a_test.txt
	commit "a sentinel helper" "Deviation: tests/a_test.txt: the helper reads better"
	run_deviation
	assert_status 1
	assert_eq "tests/a_test.txt:1 assert-drop test_a drops from 3 assertion calls at the base to 1 at HEAD: $DROP_HINT: asserts tests/a_test.txt test_a 3 1
tests/a_test.txt:1 deviation-declared the helper reads better (commit $(sha))" "$out"
}

# A fold keeps the file's count but loses a func: test_b is gone, and so is every
# func of a deleted test file. A func that held no assertion goes freely.
test_a_func_that_is_gone_fails_a_deleted_file_too() {
	assert_repo
	printf 'func test_a\ncheck(1)\ncheck(2) check(3)\ncheck(4)\ncheck(5)\n' > tests/a_test.txt
	printf 'func test_c\ncheck(1)\n' > tests/c_test.txt
	commit "fold test_b into test_a"
	git rm -q tests/c_test.txt && commit "drop c"
	run_deviation
	assert_status 1
	assert_eq "tests/a_test.txt:1 assert-drop test_b drops from 2 assertion calls at the base to 0 at HEAD, where it is gone: $DROP_HINT: asserts tests/a_test.txt test_b 2 0" "$out"
	git rm -q tests/a_test.txt && commit "drop a"
	run_deviation
	assert_status 1
	assert_eq "tests/a_test.txt:1 assert-drop test_a drops from 3 assertion calls at the base to 0 at HEAD, where it is gone: $DROP_HINT: asserts tests/a_test.txt test_a 3 0
tests/a_test.txt:1 assert-drop test_b drops from 2 assertion calls at the base to 0 at HEAD, where it is gone: $DROP_HINT: asserts tests/a_test.txt test_b 2 0" "$out"
}

# The Driver's accept ruling: a drop the brief declares exactly passes, and is
# listed at the func's line.
test_a_drop_the_brief_declares_passes_and_is_listed() {
	assert_repo "asserts tests/a_test.txt test_a 3 1" "asserts ./tests/a_test.txt test_b 2 0"
	printf 'func helper\nmake(6)\nfunc test_a\ncheck(1) # was three\n' > tests/a_test.txt
	commit "fold"
	run_deviation
	assert_status 0
	assert_eq "tests/a_test.txt:1 assert-declared test_b drops from 2 assertion calls at the base to 0 at HEAD, where it is gone; the brief declares it (asserts)
tests/a_test.txt:3 assert-declared test_a drops from 3 assertion calls at the base to 1 at HEAD; the brief declares it (asserts)" "$out"
}

# A declaration names what was measured, so a stale one can't hide a further
# drop: a count it misses fails, and so does a func that kept its checks or a
# file the branch never touched.
test_a_declaration_that_misses_the_measured_counts_fails_naming_both() {
	assert_repo "asserts tests/a_test.txt test_a 3 2" "asserts tests/a_test.txt test_b 2 1" \
		"asserts tests/z_test.txt test_z 1 0"
	printf 'func test_a\ncheck(1)\nfunc test_b\ncheck(4)\ncheck(5)\nfunc helper\nmake(6)\n' > tests/a_test.txt
	commit "drop two checks"
	run_deviation
	assert_status 1
	assert_eq "tests/a_test.txt:1 assert-drop the brief declares asserts tests/a_test.txt test_a 3 2, but test_a has 3 assertion calls at the base and 1 at HEAD
tests/a_test.txt:3 assert-drop the brief declares asserts tests/a_test.txt test_b 2 1, but test_b has 2 assertion calls at the base and 2 at HEAD
tests/z_test.txt:1 assert-drop the brief declares asserts tests/z_test.txt test_z 1 0, but test_z has 0 assertion calls at the base and 0 at HEAD, where it is gone" "$out"
}

# A count that rises or stays, a new func or file, and a product file the
# probe would count are no drop.
test_counts_that_rise_or_stay_pass_silently() {
	assert_repo
	printf 'func test_a\ncheck(1)\ncheck(2) check(3)\nfunc test_b\ncheck(4)\ncheck(5) check(6)\nfunc test_new\ncheck(7)\n' > tests/a_test.txt
	printf 'func test_c\ncheck(1)\n' > tests/c_test.txt
	mkdir -p src && printf 'func f\ncheck(1)\n' > src/p.txt
	commit "more checks"
	printf 'func f\n' > src/p.txt
	commit "fewer product checks"
	run_deviation
	assert_status 0
	assert_eq "" "$out"
}

# The adapter's probe: a missing one fails, as does one that fails or prints
# something else, with no drop judged from its counts; one holding the no-op
# marker turns the check off.
test_the_probe_must_be_there_and_answer_unless_it_is_a_noop() {
	assert_repo
	printf 'func test_a\nfunc test_b\n' > tests/a_test.txt
	commit "drop every check"
	rm tools/verify/assert-counts
	run_deviation
	assert_status 1
	assert_eq "tools/verify/assert-counts:1 assert-probe no assertion-count probe, so the test files' assertions can't be counted; it prints '<line> <func> <count>' per func of a file (the adapter seeds it), or holds the no-op marker" "$out"
	printf 'exit 3\n' > tools/verify/assert-counts
	FACTORY_BASE=dev run_deviation
	assert_status 1
	assert_eq "tools/verify/assert-counts:1 assert-probe the probe exited 3 on tests/a_test.txt at HEAD
tools/verify/assert-counts:1 assert-probe the probe exited 3 on tests/a_test.txt at dev" "$out"
	printf 'cat > /dev/null; echo "test_a 3"\n' > tools/verify/assert-counts
	FACTORY_BASE=dev run_deviation
	assert_status 1
	assert_eq "tools/verify/assert-counts:1 assert-probe the probe printed 'test_a 3' for tests/a_test.txt at HEAD, not '<line> <func> <count>'
tools/verify/assert-counts:1 assert-probe the probe printed 'test_a 3' for tests/a_test.txt at dev, not '<line> <func> <count>'" "$out"
	printf '# factory: no-op\n' > tools/verify/assert-counts
	run_deviation
	assert_status 0
	assert_eq "" "$out"
}

# Without the test paths no file is known to be a test, so only the files the
# asserts lines name are counted.
test_without_test_paths_only_the_declared_files_are_counted() {
	assert_repo "asserts tests/a_test.txt test_b 2 1"
	printf 'func test_c\ncheck(1)\n' > tests/c_test.txt
	git rm -q --cached tools/verify/test-paths && rm tools/verify/test-paths
	git add -A && git commit -q --amend -m base || fail "commit failed"
	git branch -f dev HEAD
	printf 'func test_a\ncheck(1)\ncheck(2) check(3)\nfunc test_b\ncheck(4)\n' > tests/a_test.txt
	printf 'func test_c\n' > tests/c_test.txt
	commit "drop checks"
	run_deviation
	assert_status 0
	assert_eq "tests/a_test.txt:4 assert-declared test_b drops from 2 assertion calls at the base to 1 at HEAD; the brief declares it (asserts)" "$out"
}
