# The session-start update check (hooks/claude-update-check.sh), on a project
# that records a factory version and an upstream: a local bare repo of tags.

UPDATE_HOOK="$FACTORY_CORE/hooks/claude-update-check.sh"

# project <version> [upstream]: $TEST_TMP/project, a git repo whose factory-version
# records <version> and, when given, an upstream line; CLAUDE_PROJECT_DIR points
# at it. The hook runs this Core's sync.sh, so no factory/ is vendored. The
# check's limits are lifted to 600 s, so a test that expects an answer gets one
# on a slow machine; a test of the limit sets its own.
project() {
	isolate_git
	unset FACTORY_UPSTREAM FACTORY_UPDATE_CHECK_EVERY
	export FACTORY_UPDATE_CHECK_TIMEOUT=600 FACTORY_SYNC_TIMEOUT=600
	mkdir -p "$TEST_TMP/project/tools/verify" && cd "$TEST_TMP/project" || fail "could not make the project"
	{
		printf 'version %s\nadapter fake\n' "$1"
		[ -z "${2:-}" ] || printf 'upstream %s\n' "$2"
	} > tools/verify/factory-version
	git init -q -b dev . && git add -A && git commit -q -m project || fail "could not commit the project"
	export CLAUDE_PROJECT_DIR="$TEST_TMP/project"
}

# releases <tag...>: $TEST_TMP/factory.git, a bare repo with one commit carrying
# each tag. git runs with no global or system config from here on.
releases() {
	local work="$TEST_TMP/factory" t
	isolate_git
	git init -q -b main "$work" && commit_in "$work" VERSION 0.0.0 || fail "could not make the factory repo"
	for t in "$@"; do git -C "$work" tag "$t" || fail "could not tag $t"; done
	git clone -q --bare "$work" "$TEST_TMP/factory.git" || fail "could not make the bare factory repo"
}

# run_hook: the hook as Claude Code runs it, from elsewhere, with its JSON on stdin.
run_hook() {
	out="$(cd / && bash "$UPDATE_HOOK" <<< '{"hook_event_name":"SessionStart","source":"startup"}' 2> "$TEST_TMP/stderr")"
	# shellcheck disable=SC2034 # read by assert_status, in factory/core/tests/lib.sh
	status=$?
}

STAMP=.git/factory/update-check

# shellcheck disable=SC2016 # the backticks are the message's own
NEWER_CONTEXT='The factory repo has a newer release, v0.3.0; this project is on 0.1.0. Ask the human whether to pull it in now with `bash factory/core/sync.sh v0.3.0` (or `sync.sh latest`). Sync only with their yes, and not while an issue is mid-Run: between issues. After a sync, review the staged diff, port any adapter-template diff it printed into tools/verify/ by hand, run `bash tools/verify.sh`, and commit.'

# assert_asks: the hook's stdout is SessionStart JSON asking about v0.3.0.
assert_asks() {
	. "$FACTORY_CORE/lib/json.sh"
	assert_eq SessionStart "$(printf '%s' "$out" | factory_json_get hookSpecificOutput.hookEventName)" "hookEventName"
	assert_eq "$NEWER_CONTEXT" "$(printf '%s' "$out" | factory_json_get hookSpecificOutput.additionalContext)" "additionalContext"
}

test_newer_release_prints_the_question() {
	releases v0.1.0 v0.3.0 v0.2.0
	project 0.1.0 "$TEST_TMP/factory.git"
	run_hook
	assert_status 0
	assert_asks
	assert_eq "" "$(cat "$TEST_TMP/stderr")" "the hook wrote to stderr"
	[ -s "$STAMP" ] || fail "no stamp written"
}

test_the_question_is_valid_json() {
	releases v0.3.0
	project 0.1.0 "$TEST_TMP/factory.git"
	run_hook
	assert_status 0
	if command -v jq > /dev/null; then
		printf '%s' "$out" | jq -e . > /dev/null || fail "not valid JSON: $out"
		assert_eq "$NEWER_CONTEXT" "$(printf '%s' "$out" | jq -r .hookSpecificOutput.additionalContext)" "jq read another context"
	elif command -v python3 > /dev/null; then
		printf '%s' "$out" | python3 -I -m json.tool > /dev/null || fail "not valid JSON: $out"
	else
		skip "neither jq nor python3 to validate the JSON"
	fi
}

test_current_release_prints_nothing() {
	releases v0.1.0
	project 0.1.0 "$TEST_TMP/factory.git"
	run_hook
	assert_status 0
	assert_eq "" "$out"
	[ -s "$STAMP" ] || fail "no stamp written"
}

test_an_unreachable_upstream_prints_nothing_and_stamps() {
	project 0.1.0 "$TEST_TMP/nowhere.git"
	run_hook
	assert_status 0
	assert_eq "" "$out"
	[ -s "$STAMP" ] || fail "a failed check wrote no stamp, so the next session would retry"
}

# The first run, with no stamp yet, says nothing on stderr either.
test_no_upstream_prints_nothing() {
	project 0.1.0
	[ ! -e "$STAMP" ] || fail "the fixture has a stamp"
	run_hook
	assert_status 0
	assert_eq "" "$out"
	assert_eq "" "$(cat "$TEST_TMP/stderr")" "the hook wrote to stderr"
}

test_the_stamp_throttles_a_second_run() {
	releases v0.3.0
	project 0.1.0 "$TEST_TMP/factory.git"
	export FACTORY_UPDATE_CHECK_EVERY=3600
	run_hook
	assert_asks
	run_hook
	assert_status 0
	assert_eq "" "$out" "the second run within the interval checked again"
}

test_the_stamp_lets_a_run_through_once_the_interval_passed() {
	releases v0.3.0
	project 0.1.0 "$TEST_TMP/factory.git"
	export FACTORY_UPDATE_CHECK_EVERY=3600
	run_hook
	assert_asks
	echo "$(($(date +%s) - 3601))" > "$STAMP"
	run_hook
	assert_status 0
	assert_asks
}

test_a_bad_stamp_does_not_stop_the_check() {
	releases v0.3.0
	project 0.1.0 "$TEST_TMP/factory.git"
	mkdir -p .git/factory && echo "089 not a time" > "$STAMP"
	run_hook
	assert_status 0
	assert_asks
	assert_eq "" "$(cat "$TEST_TMP/stderr")" "the hook complained"
}

test_the_stamp_is_shared_by_linked_worktrees() {
	releases v0.3.0
	project 0.1.0 "$TEST_TMP/factory.git"
	export FACTORY_UPDATE_CHECK_EVERY=3600
	run_hook
	assert_asks
	git worktree add -q -b other "$TEST_TMP/other" || fail "could not add a worktree"
	export CLAUDE_PROJECT_DIR="$TEST_TMP/other"
	run_hook
	assert_eq "" "$out" "the linked worktree checked again"
}

test_outside_an_adopted_project_prints_nothing() {
	releases v0.3.0
	project 0.1.0 "$TEST_TMP/factory.git"
	git rm -q tools/verify/factory-version && git commit -q -m unadopt || fail "could not unadopt"
	export FACTORY_UPSTREAM="$TEST_TMP/factory.git"
	run_hook
	assert_status 0
	assert_eq "" "$out"
	[ ! -e "$STAMP" ] || fail "a project that has not adopted got a stamp"
	export CLAUDE_PROJECT_DIR="$TEST_TMP/not-a-repo"
	mkdir -p "$CLAUDE_PROJECT_DIR"
	run_hook
	assert_status 0
	assert_eq "" "$out"
}

# --- a patch release syncs itself ----------------------------------------------

SYNC_LOG=.git/factory/update-sync.log

# patch_upstream: $TEST_TMP/up, a factory repo whose v0.1.0 is the project's
# factory/ and whose v0.1.1, a patch release, adds factory/patch.txt;
# FACTORY_UPSTREAM points at it. Run in an adopted project.
patch_upstream() {
	local up="$TEST_TMP/up"
	mkdir -p "$up/factory" && cp -R factory/. "$up/factory/" || fail "could not copy the factory upstream"
	git -C "$up" init -q -b main && git -C "$up" add -A && git -C "$up" commit -q -m v0.1.0 && git -C "$up" tag v0.1.0 ||
		fail "could not tag v0.1.0"
	echo 0.1.1 > "$up/factory/VERSION" && echo "from the patch" > "$up/factory/patch.txt" &&
		git -C "$up" add -A && git -C "$up" commit -q -m v0.1.1 && git -C "$up" tag v0.1.1 || fail "could not tag v0.1.1"
	export FACTORY_UPSTREAM="$up"
}

# sync_ended: the background sync's log has its last line.
sync_ended() {
	tail -n 1 "$SYNC_LOG" 2> /dev/null | grep -q '^update-check: \(synced\|failed\)'
}

# assert_context_has <text>: the hook's additionalContext holds <text>.
assert_context_has() {
	. "$FACTORY_CORE/lib/json.sh"
	local context
	context="$(printf '%s' "$out" | factory_json_get hookSpecificOutput.additionalContext)"
	case "$context" in
		*"$1"*) ;;
		*) fail "the context lacks '$1': $context" ;;
	esac
}

# An adopted project on dev, clean, with no issue in flight: the hook starts the
# sync, says so, and the sync commits v0.1.1 on dev.
test_a_patch_release_syncs_itself_and_commits_on_dev() {
	adopted
	patch_upstream
	export FACTORY_UPDATE_CHECK_TIMEOUT=600 FACTORY_SYNC_TIMEOUT=600
	export CLAUDE_PROJECT_DIR="$TEST_TMP/project"
	local before
	before="$(git rev-parse HEAD)"
	run_hook
	assert_status 0
	assert_eq "" "$(cat "$TEST_TMP/stderr")" "the hook wrote to stderr"
	assert_context_has "newer patch release, v0.1.1; this project is on 0.1.0. Patch releases sync without asking"
	assert_context_has 'Tell the human so now in this one line: "factory synced 0.1.0 → 0.1.1 (patch); push dev so new issues get it".'
	assert_context_has "That commit stays local, so new issues, cut from origin/dev, get it only once dev is pushed."
	assert_context_has "$TEST_TMP/project/$SYNC_LOG"
	wait_until "the background sync" sync_ended
	tail -n 1 "$SYNC_LOG" | grep -q '^update-check: synced v0.1.1 (from 0.1.0) and committed it as ' || fail "the sync failed: $(cat "$SYNC_LOG")"
	assert_eq "Sync factory 0.1.1 (from 0.1.0)" "$(git log -1 --format=%s)" "the sync's commit"
	assert_eq "$before" "$(git rev-parse HEAD^)" "the sync's commit is not on dev's old head"
	assert_eq dev "$(git symbolic-ref --short HEAD)" "the branch"
	assert_eq "from the patch" "$(cat factory/patch.txt)" "factory/ is not v0.1.1's"
	assert_eq "version 0.1.1" "$(head -n 1 tools/verify/factory-version)" "factory-version"
	assert_eq "" "$(git status --porcelain)" "the sync left the tree dirty"
}

# A sync that fails (here: a project that records no vendored files) commits
# nothing and says why on the log's last line.
test_a_patch_sync_that_fails_says_so_in_its_log() {
	releases v0.1.1
	project 0.1.0 "$TEST_TMP/factory.git"
	run_hook
	assert_status 0
	assert_context_has "newer patch release, v0.1.1"
	wait_until "the background sync" sync_ended
	tail -n 1 "$SYNC_LOG" | grep -q '^update-check: failed: sync.sh v0.1.1 refused' || fail "no failure line: $(cat "$SYNC_LOG")"
	grep -q 'records no vendored files' "$SYNC_LOG" || fail "the log lacks sync.sh's reason: $(cat "$SYNC_LOG")"
	assert_eq project "$(git log -1 --format=%s)" "a failed sync committed"
}

# assert_holds_back <why>: the hook asked about the patch release v0.1.1, saying
# <why> kept it from syncing itself, and started no sync.
assert_holds_back() {
	assert_status 0
	assert_context_has "The factory repo has a newer release, v0.1.1; this project is on 0.1.0. Ask the human whether to pull it in now"
	assert_context_has "It is a patch release, which syncs itself at a session's start, but not this time: $1."
	[ ! -e "$(git rev-parse --git-common-dir)/factory/update-sync.log" ] || fail "a sync started"
}

# In flight: a .claude/worktrees/issue-<n> in the main checkout (whatever it
# holds), or a worktree anywhere on an issue/<n> branch.
test_a_patch_release_asks_while_an_issue_is_in_flight() {
	releases v0.1.1
	project 0.1.0 "$TEST_TMP/factory.git"
	mkdir -p .claude/worktrees/issue-12 && touch .claude/worktrees/issue-12/left.txt || fail "could not make the folder"
	run_hook
	assert_holds_back "an issue is in flight (.claude/worktrees/issue-12)"
	rm -rf .claude "$STAMP"
	git worktree add -q -b issue/7 "$TEST_TMP/issue-7" || fail "could not add the issue's worktree"
	run_hook
	assert_holds_back "an issue is in flight (the branch issue/7)"
}

test_a_patch_release_asks_off_the_base_branch() {
	releases v0.1.1
	project 0.1.0 "$TEST_TMP/factory.git"
	git checkout -q -b topic || fail "no topic branch"
	run_hook
	assert_holds_back "the main checkout is on topic, not dev"
	git checkout -q dev && rm -f "$STAMP" || fail "could not go back to dev"
	export FACTORY_BASE_BRANCH=topic
	run_hook
	assert_holds_back "the main checkout is on dev, not topic"
}

test_a_patch_release_asks_on_a_dirty_tree() {
	releases v0.1.1
	project 0.1.0 "$TEST_TMP/factory.git"
	echo stray > stray.txt
	run_hook
	assert_holds_back "the tree is dirty"
}

test_a_patch_release_asks_in_a_linked_worktree() {
	releases v0.1.1
	project 0.1.0 "$TEST_TMP/factory.git"
	git worktree add -q -b other "$TEST_TMP/other" || fail "could not add a worktree"
	export CLAUDE_PROJECT_DIR="$TEST_TMP/other"
	run_hook
	assert_holds_back "this session is not in the main checkout"
}

# A minor release asks with no word about patches, whatever the checkout.
test_a_minor_release_asks_without_syncing() {
	releases v0.2.0
	project 0.1.0 "$TEST_TMP/factory.git"
	run_hook
	assert_status 0
	. "$FACTORY_CORE/lib/json.sh"
	# shellcheck disable=SC2016 # the backticks are the message's own
	assert_eq 'The factory repo has a newer release, v0.2.0; this project is on 0.1.0. Ask the human whether to pull it in now with `bash factory/core/sync.sh v0.2.0` (or `sync.sh latest`). Sync only with their yes, and not while an issue is mid-Run: between issues. After a sync, review the staged diff, port any adapter-template diff it printed into tools/verify/ by hand, run `bash tools/verify.sh`, and commit.' \
		"$(printf '%s' "$out" | factory_json_get hookSpecificOutput.additionalContext)" "additionalContext"
	[ ! -e "$SYNC_LOG" ] || fail "a sync started"
}

# fake_timeout [limited]: a stand-in for the timeout command, first on PATH. It
# writes the arguments it was given, a line each, to $TEST_TMP/timeout.log, and
# takes its folder off PATH, so only the hook's call reaches it. It then runs the
# command with no limit; limited, it hands its arguments to the real command
# instead and writes that one's exit status to $TEST_TMP/timeout.status.
fake_timeout() {
	local bin="$TEST_TMP/stand-in bin"
	mkdir -p "$bin" || fail "could not make the stand-in's folder"
	{
		echo '#!/usr/bin/env bash'
		printf 'log=%q status=%q bin=%q mode=%q\n' "$TEST_TMP/timeout.log" "$TEST_TMP/timeout.status" "$bin" "${1:-}"
		cat << 'STANDIN'
printf '%s\n' "$@" >> "$log"
export PATH="${PATH#"$bin":}"
if [ "$mode" != limited ]; then
	shift
	exec "$@"
fi
"${0##*/}" "$@"
s=$?
echo "$s" > "$status"
exit "$s"
STANDIN
	} > "$bin/timeout"
	chmod +x "$bin/timeout" || fail "could not make the stand-in"
	export PATH="$bin:$PATH"
}

# assert_check_limited_to <seconds> [what]: the hook ran the check, this Core's
# sync.sh, once, under a limit of <seconds>, by the stand-in's log.
assert_check_limited_to() {
	assert_eq "$(printf '%s\n' "$1" bash "$FACTORY_CORE/sync.sh" check)" "$(cat "$TEST_TMP/timeout.log" 2> /dev/null)" "${2:-the limit of the check}"
}

test_the_check_is_limited_to_12_seconds_by_default() {
	releases v0.3.0
	project 0.1.0 "$TEST_TMP/factory.git"
	unset FACTORY_UPDATE_CHECK_TIMEOUT
	fake_timeout
	run_hook
	assert_status 0
	assert_asks
	assert_check_limited_to 12
}

test_the_limit_is_a_setting() {
	releases v0.3.0
	project 0.1.0 "$TEST_TMP/factory.git"
	fake_timeout
	local value
	for value in 600 7 007; do
		export FACTORY_UPDATE_CHECK_TIMEOUT="$value"
		rm -f "$STAMP" "$TEST_TMP/timeout.log"
		run_hook
		assert_status 0
		assert_asks
		assert_check_limited_to "$value" "the limit of the check for '$value'"
	done
}

test_a_limit_that_is_not_a_positive_whole_number_means_12() {
	releases v0.3.0
	project 0.1.0 "$TEST_TMP/factory.git"
	fake_timeout
	local value
	for value in "" 0 00 -5 1.5 abc " 7" "7 " 1e3; do
		export FACTORY_UPDATE_CHECK_TIMEOUT="$value"
		rm -f "$STAMP" "$TEST_TMP/timeout.log"
		run_hook
		assert_status 0
		assert_asks
		assert_eq "" "$(cat "$TEST_TMP/stderr")" "the hook complained about '$value'"
		assert_check_limited_to 12 "the limit of the check for '$value'"
	done
}

# On a machine with no timeout (stock macOS), the check still runs, under
# lib/bounded.sh's watchdog, and asks about the newer release.
test_newer_release_prints_the_question_where_timeout_is_missing() {
	releases v0.1.0 v0.3.0
	project 0.1.0 "$TEST_TMP/factory.git"
	path_without timeout
	run_hook
	assert_status 0
	assert_asks
}

# A Core whose path has spaces: the hook still hands the check its limit.
test_the_limit_holds_for_a_core_whose_path_has_spaces() {
	releases v0.3.0
	project 0.1.0 "$TEST_TMP/factory.git"
	mkdir -p "$TEST_TMP/a factory" && cp -R "$FACTORY_CORE" "$TEST_TMP/a factory/core" || fail "could not copy the Core"
	FACTORY_CORE="$TEST_TMP/a factory/core"
	UPDATE_HOOK="$FACTORY_CORE/hooks/claude-update-check.sh"
	export FACTORY_UPDATE_CHECK_TIMEOUT=600
	fake_timeout
	run_hook
	assert_status 0
	assert_asks
	assert_check_limited_to 600
}

# assert_ended_at_the_limit: the hook, run under a limit of 1 s, said nothing and
# exited 0, and the real command's status 124 says its limit ended the check.
assert_ended_at_the_limit() {
	export FACTORY_UPDATE_CHECK_TIMEOUT=1
	fake_timeout limited
	run_hook
	assert_status 0
	assert_eq "" "$out"
	assert_eq "" "$(cat "$TEST_TMP/stderr")" "the hook wrote to stderr"
	assert_check_limited_to 1
	assert_eq 124 "$(cat "$TEST_TMP/timeout.status" 2> /dev/null)" "the limit did not end the check"
	[ -s "$STAMP" ] || fail "no stamp written"
}

# An upstream that never answers: its ssh stand-in blocks opening a fifo nobody
# writes, until it is killed. sync.sh's own limit on ls-remote, 2 s, starts after
# the hook's 1 s, so the hook's ends the check first; the ls-remote runs in a
# process group of its own, out of the hook's reach, and its own limit ends it,
# its stand-in too, a second later.
test_a_check_whose_upstream_does_not_answer_ends_silently_at_the_limit() {
	project 0.1.0 "ssh://example.invalid/factory.git"
	mkfifo "$TEST_TMP/never" || fail "could not make the fifo"
	printf '#!/usr/bin/env bash\nexec cat %q\n' "$TEST_TMP/never" > "$TEST_TMP/ssh"
	chmod +x "$TEST_TMP/ssh" || fail "could not make the ssh stand-in"
	export GIT_SSH_COMMAND="$TEST_TMP/ssh" FACTORY_SYNC_TIMEOUT=2
	assert_ended_at_the_limit
}

# A check that stalls before it reaches the upstream (a slow machine): a git
# stand-in, first on PATH, runs the real git until the hook has written its stamp,
# and from then on, inside the check, waits to read a fifo nobody writes, until it
# is killed. Its 60 s hang guard only ends a hook that set no limit.
test_a_check_that_stalls_before_the_upstream_ends_silently_at_the_limit() {
	releases v0.3.0
	project 0.1.0 "$TEST_TMP/factory.git"
	local bin="$TEST_TMP/git bin" git
	git="$(command -v git)" || fail "no git"
	mkdir -p "$bin" && mkfifo "$TEST_TMP/never" || fail "could not make the git stand-in's folder and fifo"
	printf '#!/usr/bin/env bash\n[ -e %q ] || exec %q "$@"\nexec 3<> %q\nread -r -t 60 -u 3 _\nexit 1\n' \
		"$TEST_TMP/project/$STAMP" "$git" "$TEST_TMP/never" > "$bin/git"
	chmod +x "$bin/git" || fail "could not make the git stand-in"
	export PATH="$bin:$PATH"
	assert_ended_at_the_limit
}
