# start.sh: an issue's worktree and branch, the issue saved for prompt.sh, then the
# adapter's bootstrap, once.

# slurp_file <file>: set REPLY to the file's text, its final newline kept.
slurp_file() {
	REPLY="$(
		cat "$1"
		echo x
	)"
	REPLY="${REPLY%x}"
}

run_start() {
	run_cmd bash "$FACTORY_CORE/start.sh" "$@"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_creates_the_worktree_and_branch_from_origin_dev_and_bootstraps_once() {
	fixture_repo
	push_from_elsewhere b.txt upstream
	run_start 7
	assert_status 0
	wt="$TEST_TMP/main/.claude/worktrees/issue-7"
	[ "$out" -ef "$wt" ] || fail "stdout is not the worktree path: $out"
	assert_eq "issue/7" "$(git -C "$wt" symbolic-ref --short HEAD)" "the worktree is on the wrong branch"
	assert_eq "$(git rev-parse origin/dev)" "$(git -C "$wt" rev-parse HEAD)" "the branch is not cut from the fetched origin/dev"
	assert_eq "upstream" "$(cat "$wt/b.txt")" "origin/dev was not fetched first"
	assert_eq "dev" "$(git symbolic-ref --short HEAD)" "the main checkout changed branch"
	assert_eq "bootstrap in issue-7 core=set tool=none" "$(cat "$BOOTSTRAP_LOG")" "bootstrap did not run once, in the worktree"
	assert_eq "done" "$(git config branch.issue/7.factory-bootstrap)"
	assert_eq "7" "$(git config branch.issue/7.factory-issue)"
}

test_rerun_reuses_the_worktree_and_does_not_bootstrap_again() {
	fixture_repo
	run_start 7
	assert_status 0
	commit_in "$TEST_TMP/main/.claude/worktrees/issue-7" c.txt work
	run_start 7
	assert_status 0
	assert_eq "1" "$(wc -l < "$BOOTSTRAP_LOG" | tr -d ' ')" "bootstrap ran again"
	assert_eq "work" "$(cat "$TEST_TMP/main/.claude/worktrees/issue-7/c.txt")" "the worktree was not kept"
}

test_reuses_an_existing_branch_without_a_worktree() {
	fixture_repo
	git branch issue/7 dev
	commit_in . a.txt main-only
	run_start 7
	assert_status 0
	assert_eq "$(git rev-parse issue/7)" "$(git -C .claude/worktrees/issue-7 rev-parse HEAD)"
	assert_eq "one" "$(cat .claude/worktrees/issue-7/a.txt)"
}

test_runs_from_inside_another_worktree() {
	fixture_repo
	run_start 7
	cd .claude/worktrees/issue-7 || fail "no worktree"
	run_start 8
	assert_status 0
	[ "$out" -ef "$TEST_TMP/main/.claude/worktrees/issue-8" ] || fail "worktree not under the main checkout: $out"
}

test_copies_local_env_and_bootstrap_sees_it() {
	fixture_repo
	echo "FIXTURE_TOOL=/opt/tool" > tools/verify/local.env
	run_start 7
	assert_status 0
	assert_eq "FIXTURE_TOOL=/opt/tool" "$(cat .claude/worktrees/issue-7/tools/verify/local.env)"
	assert_eq "bootstrap in issue-7 core=set tool=/opt/tool" "$(cat "$BOOTSTRAP_LOG")"
}

test_failed_bootstrap_fails_and_a_rerun_retries_it() {
	fixture_repo
	echo 'echo attempt >> "$BOOTSTRAP_LOG"; exit 4' > tools/verify/bootstrap
	git commit -q -am "failing bootstrap" && git push -q origin dev 2> /dev/null
	run_start 7
	assert_status 1
	assert_eq "" "$out" "stdout should be empty on failure"
	run_start 7
	assert_status 1
	assert_eq "2" "$(wc -l < "$BOOTSTRAP_LOG" | tr -d ' ')" "the rerun did not retry bootstrap"
	git config branch.issue/7.factory-bootstrap > /dev/null && fail "a failed bootstrap was recorded as done"
	return 0
}

test_noop_bootstrap_is_skipped() {
	fixture_repo
	printf '#!/usr/bin/env bash\n# factory: no-op\necho ran >> "$BOOTSTRAP_LOG"\n' > tools/verify/bootstrap
	git commit -q -am "no-op bootstrap" && git push -q origin dev 2> /dev/null
	run_start 7
	assert_status 0
	[ ! -e "$BOOTSTRAP_LOG" ] || fail "a no-op bootstrap ran"
}

test_missing_bootstrap_fails() {
	fixture_repo
	git rm -q tools/verify/bootstrap && git commit -q -m "no bootstrap" && git push -q origin dev 2> /dev/null
	run_start 7
	assert_status 1
	grep -q "no tools/verify/bootstrap" "$TEST_TMP/stderr" || fail "no reason on stderr: $(cat "$TEST_TMP/stderr")"
}

test_bad_arguments_are_usage_errors() {
	fixture_repo
	run_start
	assert_status 2
	run_start x
	assert_status 2
	run_start 07
	assert_status 2
	run_start 7 8
	assert_status 2
	[ ! -e .claude/worktrees ] || fail "a usage error made a worktree"
}

# The stats line's minutes count from the start: the time start.sh made the
# branch, which a resume keeps.
test_records_when_it_made_the_branch_and_a_resume_keeps_it() {
	fixture_repo
	FACTORY_NOW=1000 run_start 7
	assert_status 0
	assert_eq "1000" "$(git config branch.issue/7.factory-started)"
	FACTORY_NOW=2000 run_start 7
	assert_status 0
	assert_eq "1000" "$(git config branch.issue/7.factory-started)" "a resume moved the start"
	git worktree remove .claude/worktrees/issue-7 || fail "could not remove the worktree"
	FACTORY_NOW=3000 run_start 7
	assert_status 0
	assert_eq "1000" "$(git config branch.issue/7.factory-started)" "reusing the branch moved the start"
}

# A branch made before start.sh recorded the time stays without one: its minutes
# would count from the resume, not the start.
test_a_branch_from_before_the_start_time_gets_none() {
	fixture_repo
	git branch issue/7 dev
	FACTORY_NOW=1000 run_start 7
	assert_status 0
	git config branch.issue/7.factory-started > /dev/null && fail "a resumed branch got a start time"
	return 0
}

# issue_md <worktree>: where start.sh saves the issue, the worktree's git dir.
issue_md() {
	printf '%s/factory/issue.md\n' "$(git -C "$1" rev-parse --path-format=absolute --git-dir)"
}

# Drivers saved issue.md by hand at Start: start.sh saves it from the title and
# the body the Driver pipes in, where prompt.sh reads it.
test_a_fresh_start_saves_the_issue_from_the_title_and_the_body() {
	local wt issue
	fixture_repo
	printf 'Kind: build\n\nThe body, with <brief> & \\1 kept.' > "$TEST_TMP/body"
	run_start 7 --title 'Fix the <title> & \1 bug' < "$TEST_TMP/body"
	assert_status 0
	wt="$TEST_TMP/main/.claude/worktrees/issue-7"
	[ "$out" -ef "$wt" ] || fail "stdout is not the worktree path: $out"
	issue="$(issue_md "$wt")"
	assert_eq "$TEST_TMP/main/.git/worktrees/issue-7/factory/issue.md" "$issue"
	slurp_file "$issue"
	assert_eq '#7: Fix the <title> & \1 bug

Kind: build

The body, with <brief> & \1 kept.
' "$REPLY" "the saved issue"
	# prompt.sh takes it as it is.
	printf 'Kind: build. Phase: red.\n' > "${issue%/issue.md}/brief.md"
	cd "$wt" || fail "no worktree"
	run_cmd bash "$FACTORY_CORE/prompt.sh" editor red
	assert_status 0
	assert_line 'Issue #7: Fix the <title> & \1 bug. Phase: red.'
}

test_a_resume_keeps_the_saved_issue_unless_given_a_new_one() {
	local issue
	fixture_repo
	echo "The first body." > "$TEST_TMP/body"
	run_start 7 --title "First" < "$TEST_TMP/body"
	assert_status 0
	issue="$(issue_md .claude/worktrees/issue-7)"
	run_start 7
	assert_status 0
	assert_eq "#7: First

The first body." "$(cat "$issue")" "a resume without --title changed the issue"
	grep -q "no issue saved" "$TEST_TMP/stderr" && fail "a resume with an issue saved said there was none"
	echo "The second body." > "$TEST_TMP/body"
	run_start 7 --title "Second" < "$TEST_TMP/body"
	assert_status 0
	assert_eq "#7: Second

The second body." "$(cat "$issue")" "a rerun with --title kept the old issue"
	git worktree remove .claude/worktrees/issue-7 || fail "could not remove the worktree"
	run_start 7 --title "Third" < /dev/null
	assert_status 0
	assert_eq "#7: Third" "$(cat "$(issue_md .claude/worktrees/issue-7)")" "an empty body is the title line alone"
}

test_a_start_without_a_title_saves_no_issue_and_says_so() {
	fixture_repo
	run_start 7
	assert_status 0
	[ ! -e "$(issue_md .claude/worktrees/issue-7)" ] || fail "an issue was saved without --title"
	grep -qF "no issue saved at $(issue_md .claude/worktrees/issue-7) for prompt.sh: rerun with --title" "$TEST_TMP/stderr" ||
		fail "no note on stderr: $(cat "$TEST_TMP/stderr")"
}

# A CRLF title loses its CR; a title that is blank or more than one line, a
# missing one or another flag is a usage error that changes nothing.
test_the_title_is_one_line() {
	local title
	fixture_repo
	run_start 7 --title $'Fix it\r' < /dev/null
	assert_status 0
	assert_eq "#7: Fix it" "$(cat "$(issue_md .claude/worktrees/issue-7)")"
	for title in '' '   ' $'one\ntwo' $'one\rtwo'; do
		run_start 8 --title "$title" < /dev/null
		assert_status 2
		stderr_has "usage: <the issue's raw body> | bash factory/core/start.sh <issue number> --title <title>"
	done
	run_start 8 --title < /dev/null
	assert_status 2
	run_start 8 --name x < /dev/null
	assert_status 2
	run_start 8 x --title y < /dev/null
	assert_status 2
	[ ! -e .claude/worktrees/issue-8 ] || fail "a usage error made a worktree"
}

# A project naming a Scenario folder: an issue's worktree leaves it out of its
# checkout, a fresh one and a reused one alike, while git still tracks it.
test_the_worktree_leaves_the_scenario_folder_out() {
	fixture_repo
	printf '# the folder\nscenarios/\n' > tools/verify/scenario-folder
	mkdir -p scenarios/serve && echo play > scenarios/serve/once.gd && echo shared > scenarios.md
	git add -A && git commit -q -m scenarios && git push -q origin dev 2> /dev/null || fail "could not push"
	run_start 7
	assert_status 0
	wt="$TEST_TMP/main/.claude/worktrees/issue-7"
	[ ! -e "$wt/scenarios" ] || fail "the worktree holds the Scenario folder"
	assert_eq shared "$(cat "$wt/scenarios.md")" "a file beside the folder is left out"
	assert_eq "" "$(git -C "$wt" status --porcelain)" "the worktree isn't clean"
	git -C "$wt" ls-files --error-unmatch scenarios/serve/once.gd > /dev/null 2>&1 || fail "git no longer tracks the Scenario"
	[ -d scenarios ] || fail "the main checkout lost its Scenario folder"
	git worktree remove "$wt" || fail "could not remove the worktree"
	run_start 7
	assert_status 0
	[ ! -e "$wt/scenarios" ] || fail "a reused branch's worktree holds the Scenario folder"
	git -C "$wt" sparse-checkout disable || fail "could not undo the sparse checkout"
	[ -e "$wt/scenarios" ] || fail "no folder to leave out"
	git -C "$wt" config --worktree core.sparseCheckout false
	run_start 7
	assert_status 0
	[ ! -e "$wt/scenarios" ] || fail "a reused worktree holds the Scenario folder"
}

test_a_project_without_a_scenario_folder_checks_everything_out() {
	fixture_repo
	mkdir -p scenarios && echo play > scenarios/once.gd
	git add -A && git commit -q -m scenarios && git push -q origin dev 2> /dev/null || fail "could not push"
	run_start 7
	assert_status 0
	[ -f "$TEST_TMP/main/.claude/worktrees/issue-7/scenarios/once.gd" ] || fail "the worktree left a folder out"
}

# #21: after bootstrap, every start and resume runs the worktree's prepare
# (tools/verify.sh prepare), so its tools are installed before the first commit;
# its output goes to stderr, and stdout stays the worktree's path.
test_runs_prepare_in_the_worktree_after_bootstrap_on_every_start() {
	fixture_repo
	printf '%s\n' 'echo "prepare in $(basename "$PWD") args=$* stamp=${FACTORY_NO_STAMP:-}" >> "$BOOTSTRAP_LOG"' 'echo "verify: PASS"' > tools/verify.sh
	git commit -q -am "logging verify" && git push -q origin dev 2> /dev/null
	run_start 7
	assert_status 0
	[ "$out" -ef "$TEST_TMP/main/.claude/worktrees/issue-7" ] || fail "stdout is not the worktree path: $out"
	assert_eq "bootstrap in issue-7 core=set tool=none
prepare in issue-7 args=prepare stamp=1" "$(cat "$BOOTSTRAP_LOG")" "bootstrap, then prepare, in the worktree"
	grep -q "verify: PASS" "$TEST_TMP/stderr" || fail "prepare's output is not on stderr: $(cat "$TEST_TMP/stderr")"
	run_start 7
	assert_status 0
	assert_eq "prepare in issue-7 args=prepare stamp=1" "$(tail -n 1 "$BOOTSTRAP_LOG")" "a resume did not run prepare again"
	assert_eq "3" "$(wc -l < "$BOOTSTRAP_LOG" | tr -d ' ')" "a resume ran bootstrap again"
}

test_a_failing_prepare_fails_start_and_says_so() {
	fixture_repo
	printf '%s\n' 'echo "tools/verify/local.env:1 node-missing no node"' 'echo "verify: FAILED at step prepare"' 'exit 1' > tools/verify.sh
	git commit -q -am "failing prepare" && git push -q origin dev 2> /dev/null
	run_start 7
	assert_status 1
	assert_eq "" "$out" "stdout should be empty on failure"
	grep -q "node-missing" "$TEST_TMP/stderr" || fail "prepare's findings are not on stderr: $(cat "$TEST_TMP/stderr")"
	grep -q "start: bash tools/verify.sh prepare failed in .*issue-7" "$TEST_TMP/stderr" || fail "no reason on stderr: $(cat "$TEST_TMP/stderr")"
	assert_eq "done" "$(git config branch.issue/7.factory-bootstrap)" "bootstrap passed and should stay done"
}

# #69: while origin/dev's Baseline holds findings, only a Kind: cleanup issue can
# land, so start.sh refuses any other before it makes a worktree or branch.

# baseline_on_dev <text>: commit the Baseline's text on dev and push it.
baseline_on_dev() {
	mkdir -p tools/verify/ratchet && printf '%s' "$1" > tools/verify/ratchet/baseline.txt
	git add -A && git commit -q -m baseline && git push -q origin dev 2> /dev/null || fail "could not push the Baseline"
}

# no_start <n>: nothing of issue <n> was made: no worktree, branch or run state.
no_start() {
	[ ! -e ".claude/worktrees/issue-$1" ] || fail "a refused start made the worktree"
	git show-ref --verify --quiet "refs/heads/issue/$1" && fail "a refused start made the branch"
	git config --get-regexp "^branch\.issue/$1\." > /dev/null && fail "a refused start recorded run state"
	[ ! -s "$BOOTSTRAP_LOG" ] || fail "a refused start ran bootstrap"
	return 0
}

test_a_non_cleanup_issue_on_a_non_empty_baseline_is_refused_before_any_worktree() {
	local kind
	fixture_repo
	baseline_on_dev $'# kept\nsrc/a.ts R15 too deep\nsrc/b.ts R15 too deep\n\nsrc/c.ts lint/no-x an x\r\n'
	for kind in build bug amend; do
		printf 'Part of #1\n\nKind: %s\n\nThe body.\n' "$kind" > "$TEST_TMP/body"
		run_start 7 --title "Build it" < "$TEST_TMP/body"
		assert_status 3
		assert_eq "" "$out" "stdout should be empty on a refusal"
		stderr_has "start: refused: #7 is Kind: $kind, and the Baseline (tools/verify/ratchet/baseline.txt on origin/dev) holds 3 findings (R15 2, lint/no-x 1)."
		stderr_has "start: Run a Kind: cleanup issue first, this Spec's or the Adoption cleanup Spec's (the tracker doc's list command finds it), then start #7 again."
		no_start 7
	done
}

test_an_issue_with_no_kind_line_on_a_non_empty_baseline_is_refused() {
	fixture_repo
	baseline_on_dev $'src/a.ts R15 too deep\n'
	printf 'Part of #1\n\nThe body names Kind: cleanup only inside a line.\n' > "$TEST_TMP/body"
	run_start 7 --title "Build it" < "$TEST_TMP/body"
	assert_status 3
	stderr_has "start: refused: #7 has no Kind: line, and the Baseline (tools/verify/ratchet/baseline.txt on origin/dev) holds 1 findings (R15 1)."
	no_start 7
	run_start 7
	assert_status 3
	no_start 7
}

test_a_cleanup_issue_starts_on_a_non_empty_baseline() {
	fixture_repo
	baseline_on_dev $'src/a.ts R15 too deep\n'
	printf 'Part of #1\r\n\r\nKind: cleanup\r\n' > "$TEST_TMP/body"
	run_start 7 --title "Clean it" < "$TEST_TMP/body"
	assert_status 0
	[ "$out" -ef "$TEST_TMP/main/.claude/worktrees/issue-7" ] || fail "stdout is not the worktree path: $out"
	# A resume without --title reads the Kind from the saved issue.
	run_start 7
	assert_status 0
}

test_any_kind_starts_on_an_empty_baseline() {
	fixture_repo
	baseline_on_dev $'# no findings left\n\n'
	printf 'Kind: build\n' > "$TEST_TMP/body"
	run_start 7 --title "Build it" < "$TEST_TMP/body"
	assert_status 0
	run_start 8
	assert_status 0
	[ -e .claude/worktrees/issue-8 ] || fail "an issue with no Kind did not start"
}

# The Baseline read is origin/dev's, fetched first: one pushed after the main
# checkout last fetched refuses.
test_the_baseline_read_is_the_freshly_fetched_origin_dev() {
	fixture_repo
	git clone -q -b dev "$TEST_TMP/origin.git" "$TEST_TMP/other" 2> /dev/null || fail "could not clone"
	mkdir -p "$TEST_TMP/other/tools/verify/ratchet"
	commit_in "$TEST_TMP/other" tools/verify/ratchet/baseline.txt "src/a.ts R15 too deep"
	git -C "$TEST_TMP/other" push -q origin dev 2> /dev/null || fail "could not push"
	printf 'Kind: build\n' > "$TEST_TMP/body"
	run_start 7 --title "Build it" < "$TEST_TMP/body"
	assert_status 3
	no_start 7
}

# A resume of an issue already started is refused too: its gate still can't pass.
test_a_resume_is_refused_once_the_baseline_holds_findings() {
	local issue
	fixture_repo
	printf 'Kind: build\n' > "$TEST_TMP/body"
	run_start 7 --title "Build it" < "$TEST_TMP/body"
	assert_status 0
	issue="$(issue_md .claude/worktrees/issue-7)"
	commit_in .claude/worktrees/issue-7 c.txt work
	baseline_on_dev $'src/a.ts R15 too deep\n'
	run_start 7
	assert_status 3
	stderr_has "start: refused: #7 is Kind: build, and the Baseline (tools/verify/ratchet/baseline.txt on origin/dev) holds 1 findings (R15 1)."
	printf 'Kind: build\n' > "$TEST_TMP/body"
	run_start 7 --title "Build it" < "$TEST_TMP/body"
	assert_status 3
	assert_eq "#7: Build it

Kind: build" "$(cat "$issue")" "a refused resume changed the saved issue"
	assert_eq "work" "$(cat .claude/worktrees/issue-7/c.txt)" "a refused resume changed the worktree"
	# The branch alone, its worktree gone, has no saved issue: no Kind, refused.
	git worktree remove --force .claude/worktrees/issue-7 || fail "could not remove the worktree"
	run_start 7
	assert_status 3
	[ ! -e .claude/worktrees/issue-7 ] || fail "a refused resume made the worktree"
	# Its body says cleanup: it resumes.
	printf 'Kind: cleanup\n' > "$TEST_TMP/body"
	run_start 7 --title "Build it" < "$TEST_TMP/body"
	assert_status 0
}
