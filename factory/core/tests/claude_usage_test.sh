# The factory's claude-usage (factory/tools/), on hand-made transcripts shaped like
# Claude Code's, in a config folder of the test's own ($CLAUDE_CONFIG_DIR). Every
# expected number below is worked out by hand from the records.

USAGE="$FACTORY_CORE/../tools/claude-usage"

# The project the tests name, and its transcript folder's name: every character
# but a letter or a digit turned into -.
PROJECT=/work/my_game.v2
SLUG=-work-my-game-v2

# rec_prompt <file> <time> <text>: a user message (the first is the transcript's
# prompt). <text> is the JSON string's inside: \n is a line break, \\ a backslash.
rec_prompt() {
	mkdir -p "$(dirname "$1")"
	printf '{"parentUuid":null,"isSidechain":true,"type":"user","message":{"role":"user","content":"%s"},"uuid":"u1","timestamp":"%s"}\n' "$3" "$2" >> "$1"
}

# rec_meta <file> <time>: a user message Claude Code adds itself (isMeta).
rec_meta() {
	mkdir -p "$(dirname "$1")"
	printf '{"parentUuid":null,"isSidechain":true,"type":"user","message":{"role":"user","content":"factory-issue: 99\\nA caveat."},"isMeta":true,"uuid":"u0","timestamp":"%s"}\n' "$2" >> "$1"
}

# rec_call <file> <time> <id> <input> <cache-write> <cache-read> <output> [<5m write>]:
# an assistant record. Its usage repeats in iterations with bigger numbers, and its
# cache_creation splits the write when a 5-minute part is given.
rec_call() {
	local split=""
	mkdir -p "$(dirname "$1")"
	[ -z "${8:-}" ] || split=",\"cache_creation\":{\"ephemeral_1h_input_tokens\":$(($5 - $8)),\"ephemeral_5m_input_tokens\":$8}"
	printf '{"parentUuid":"u1","isSidechain":false,"message":{"model":"claude-opus-5-5","id":"%s","type":"message","role":"assistant","content":[{"type":"text","text":"done"}],"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s,"output_tokens_details":{"thinking_tokens":1}%s,"iterations":[{"input_tokens":900,"output_tokens":900,"cache_read_input_tokens":900,"cache_creation_input_tokens":900,"cache_creation":{"ephemeral_5m_input_tokens":900,"ephemeral_1h_input_tokens":0},"type":"message"}],"speed":"standard"}},"type":"assistant","uuid":"u2","timestamp":"%s"}\n' \
		"$3" "$4" "$5" "$6" "$7" "$split" "$2" >> "$1"
}

# rec_synthetic <file> <time>: Claude Code's own error note, which is no call.
rec_synthetic() {
	printf '{"parentUuid":"u2","isSidechain":false,"type":"assistant","uuid":"u3","timestamp":"%s","message":{"id":"msg_synthetic","model":"<synthetic>","role":"assistant","usage":{"input_tokens":5,"output_tokens":5,"cache_creation_input_tokens":5,"cache_read_input_tokens":5},"content":[{"type":"text","text":"Login expired"}]},"isApiErrorMessage":true}\n' "$2" >> "$1"
}

# rec_compaction <file> <time>: the summary a compaction leaves.
rec_compaction() {
	printf '{"parentUuid":"u2","isSidechain":false,"type":"user","message":{"role":"user","content":"This session is being continued."},"isCompactSummary":true,"uuid":"u4","timestamp":"%s"}\n' "$2" >> "$1"
}

# run_usage <args...>: claude-usage on the test's config folder.
run_usage() {
	run_cmd bash "$USAGE" "$@"
}

# two_sessions: the project's transcripts.
#   zeta (main, 2026-11-01): msg_a written twice (output 100, then 120), an error
#     note, msg_b with no cache split (output 50, then 40), then a compaction.
#     Its subagents:
#       agent-d7   a driver of #7 (factory-issue: 7 on the prompt's first line,
#                  after a meta message naming another): msg_c
#       agent-g10  a fallback driver of #10 (the line mid-prompt): msg_d
#       agent-x    no driver (the line after an escaped \n, which is no line
#                  break, and the words mid-line): msg_e
#   alpha (main, 2026-11-02, sorts first by name): a copy of msg_a with bigger
#     numbers, which counts in zeta, then msg_f. Its subagent agent-d7b, a second
#     driver of #7: msg_g.
two_sessions() {
	export CLAUDE_CONFIG_DIR="$TEST_TMP/claude"
	local d="$CLAUDE_CONFIG_DIR/projects/$SLUG"
	rec_prompt "$d/zeta.jsonl" 2026-11-01T10:00:00.000Z 'Run the Spec.'
	rec_call "$d/zeta.jsonl" 2026-11-01T10:01:00.000Z msg_a 2 1000 5000 100 200
	rec_call "$d/zeta.jsonl" 2026-11-01T10:01:01.000Z msg_a 2 1000 5000 120 200
	rec_synthetic "$d/zeta.jsonl" 2026-11-01T10:02:00.000Z
	rec_call "$d/zeta.jsonl" 2026-11-01T10:03:00.000Z msg_b 1 400 6000 50
	rec_call "$d/zeta.jsonl" 2026-11-01T10:03:01.000Z msg_b 1 400 6000 40
	rec_compaction "$d/zeta.jsonl" 2026-11-01T10:30:00.000Z
	rec_meta "$d/zeta/subagents/agent-d7.jsonl" 2026-11-01T10:05:00.000Z
	rec_prompt "$d/zeta/subagents/agent-d7.jsonl" 2026-11-01T10:05:00.000Z 'factory-issue: 7\nfactory-spec: 3\n\nDrive #7.'
	rec_call "$d/zeta/subagents/agent-d7.jsonl" 2026-11-01T10:06:00.000Z msg_c 3 2000 10000 300 2000
	rec_prompt "$d/zeta/subagents/agent-g10.jsonl" 2026-11-01T10:10:00.000Z 'You drive one issue.\nfactory-issue: 10\nfactory-spec: 3'
	rec_call "$d/zeta/subagents/agent-g10.jsonl" 2026-11-01T10:11:00.000Z msg_d 5 100 1000 7 0
	rec_prompt "$d/zeta/subagents/agent-x.jsonl" 2026-11-01T10:20:00.000Z 'Find where a brief says \\nfactory-issue: 8\nand why a factory-issue: 8 line matters.'
	rec_call "$d/zeta/subagents/agent-x.jsonl" 2026-11-01T10:21:00.000Z msg_e 4 0 3000 10
	rec_prompt "$d/alpha.jsonl" 2026-11-02T08:00:00.000Z 'Go on.'
	rec_call "$d/alpha.jsonl" 2026-11-02T08:00:01.000Z msg_a 9 9000 9000 999 0
	rec_call "$d/alpha.jsonl" 2026-11-02T09:00:00.000Z msg_f 1 0 15 1
	rec_prompt "$d/alpha/subagents/agent-d7b.jsonl" 2026-11-02T13:00:00.000Z 'factory-issue: 7\nResume #7.'
	rec_call "$d/alpha/subagents/agent-d7b.jsonl" 2026-11-02T13:01:00.000Z msg_g 1 0 100 2
}

# Costs, in hundredths of a token: 100 input + 125 5-minute write + 200 other
# write + 10 read + 500 output, rounded to a whole token at the end.
#   #7:    msg_c 300+250000+0+100000+150000, msg_g 100+0+1000+1000: 502400 -> 5024
#   #10:   msg_d 500+0+20000+10000+3500: 34000 -> 340
#   zeta:  msg_a 200+25000+160000+50000+60000, msg_b 100+80000+60000+25000,
#          msg_e 400+30000+5000: 495700 -> 4957
#   alpha: msg_f 100+150+500: 750 -> 8 (half rounds up)
# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_issues_and_sessions_count_every_call_once_each() {
	two_sessions
	run_usage issues --project "$PROJECT"
	assert_status 0
	assert_eq "issue=7 transcripts=2 calls=2 input=4 cache-write=2000 cache-read=10100 output=302 cost=5024
issue=10 transcripts=1 calls=1 input=5 cache-write=100 cache-read=1000 output=7 cost=340" "$out"
	run_usage sessions --project "$PROJECT"
	assert_status 0
	assert_eq "session=zeta start=2026-11-01T10:00:00.000Z compactions=1 transcripts=2 calls=3 input=7 cache-write=1400 cache-read=14000 output=180 cost=4957
session=alpha start=2026-11-02T08:00:00.000Z compactions=0 transcripts=1 calls=1 input=1 cache-write=0 cache-read=15 output=1 cost=8" "$out"
}

# amends: zeta also started the builder and a reviewer of the amend amend-flow (the
# line second in the builder's prompt, after its effort, and first in the
# reviewer's), a builder of tidy-docs, and a subagent with both lines, which is
# #10's: its issue line wins. Costs: msg_h 100+1000+1000, msg_i 200+500: 2800 ->
# 28; msg_j 500 -> 5; #10 gains msg_k, 100: 34100 -> 341. Sessions stay as they were.
test_amends_count_their_subagents_and_an_issue_line_wins() {
	two_sessions
	local d="$CLAUDE_CONFIG_DIR/projects/$SLUG/zeta/subagents"
	rec_prompt "$d/agent-b1.jsonl" 2026-11-01T11:00:00.000Z 'factory-effort: high\nfactory-amend: amend-flow\n\nBuild the amend.'
	rec_call "$d/agent-b1.jsonl" 2026-11-01T11:01:00.000Z msg_h 1 0 100 2
	rec_prompt "$d/agent-r1.jsonl" 2026-11-01T11:10:00.000Z 'factory-amend: amend-flow\nReview the amend.'
	rec_call "$d/agent-r1.jsonl" 2026-11-01T11:11:00.000Z msg_i 2 0 0 1
	rec_prompt "$d/agent-o.jsonl" 2026-11-01T11:20:00.000Z 'factory-effort: medium\nfactory-amend: tidy-docs'
	rec_call "$d/agent-o.jsonl" 2026-11-01T11:21:00.000Z msg_j 5 0 0 0
	rec_prompt "$d/agent-both.jsonl" 2026-11-01T11:30:00.000Z 'factory-issue: 10\nfactory-amend: amend-flow'
	rec_call "$d/agent-both.jsonl" 2026-11-01T11:31:00.000Z msg_k 1 0 0 0
	run_usage amends --project "$PROJECT"
	assert_status 0
	assert_eq "amend=amend-flow transcripts=2 calls=2 input=3 cache-write=0 cache-read=100 output=3 cost=28
amend=tidy-docs transcripts=1 calls=1 input=5 cache-write=0 cache-read=0 output=0 cost=5" "$out"
	run_usage issues --project "$PROJECT"
	assert_status 0
	assert_eq "issue=7 transcripts=2 calls=2 input=4 cache-write=2000 cache-read=10100 output=302 cost=5024
issue=10 transcripts=2 calls=2 input=6 cache-write=100 cache-read=1000 output=7 cost=341" "$out"
	run_usage sessions --project "$PROJECT"
	assert_status 0
	assert_eq "session=zeta start=2026-11-01T10:00:00.000Z compactions=1 transcripts=2 calls=3 input=7 cache-write=1400 cache-read=14000 output=180 cost=4957
session=alpha start=2026-11-02T08:00:00.000Z compactions=0 transcripts=1 calls=1 input=1 cache-write=0 cache-read=15 output=1 cost=8" "$out"
}

# In the window: msg_b, msg_e and the compaction for zeta (msg_a is before it,
# msg_f at its end, which is out); msg_g alone for #7 from its own time on.
test_since_and_until_keep_the_calls_and_compactions_in_the_window() {
	two_sessions
	run_usage sessions --project "$PROJECT" --since 2026-11-01T10:02 --until 2026-11-02T09:00:00.000Z
	assert_status 0
	assert_eq "session=zeta start=2026-11-01T10:00:00.000Z compactions=1 transcripts=2 calls=2 input=5 cache-write=400 cache-read=9000 output=60 cost=2005" "$out"
	run_usage issues --project "$PROJECT" --since 2026-11-02T13:01:00.000Z
	assert_status 0
	assert_eq "issue=7 transcripts=1 calls=1 input=1 cache-write=0 cache-read=100 output=2 cost=21" "$out"
	run_usage issues --project "$PROJECT" --since 2026-11-03T00:00:00.000Z
	assert_status 0
	assert_eq "" "$out"
}

# Claude Code names the folder from the path's UTF-16 code units, whatever the
# locale: é is one, so one -, and 🎮 two. A slug past 200 of them is cut to 200 and
# ends with - and the path's hash, worked out apart from the tool (ycozhb, p6bxpo).
test_a_path_gets_claude_codes_slug_in_any_locale_and_a_long_one_its_hash() {
	export CLAUDE_CONFIG_DIR="$TEST_TMP/claude"
	local long dir
	rec_call "$CLAUDE_CONFIG_DIR/projects/-work-caf-/s.jsonl" 2026-11-01T10:00:00.000Z msg_a 1 0 0 1
	LC_ALL=C run_usage sessions --project /work/café
	assert_status 0
	assert_eq "session=s start=2026-11-01T10:00:00.000Z compactions=0 transcripts=1 calls=1 input=1 cache-write=0 cache-read=0 output=1 cost=6" "$out"

	long="/work/$(printf 'a-folder-name-that-runs-long/%.0s' 1 2 3 4 5 6 7 8)game"
	dir="$(printf '%s' "$long" | tr -c '0-9A-Za-z' '-' | cut -c 1-200)-ycozhb"
	rec_call "$CLAUDE_CONFIG_DIR/projects/$dir/t.jsonl" 2026-11-01T10:00:00.000Z msg_a 1 0 0 1
	run_usage sessions --project "$long"
	assert_status 0
	assert_eq "session=t start=2026-11-01T10:00:00.000Z compactions=0 transcripts=1 calls=1 input=1 cache-write=0 cache-read=0 output=1 cost=6" "$out"

	long="/work/🎮-$(printf 'émoji-and-long-names/%.0s' 1 2 3 4 5 6 7 8 9 10)x"
	dir="$(printf '%s' "-work----$(printf -- '-moji-and-long-names-%.0s' 1 2 3 4 5 6 7 8 9 10)x" | cut -c 1-200)-p6bxpo"
	rec_call "$CLAUDE_CONFIG_DIR/projects/$dir/u.jsonl" 2026-11-01T10:00:00.000Z msg_a 1 0 0 1
	LC_ALL=C run_usage sessions --project "$long"
	assert_status 0
	assert_eq "session=u start=2026-11-01T10:00:00.000Z compactions=0 transcripts=1 calls=1 input=1 cache-write=0 cache-read=0 output=1 cost=6" "$out"
}

# A call's id, model and usage are its message's own: a tool input before them (with
# an id, a model, quotes and a backslash at a string's end) and a copy of the input
# after them hold the same names, deeper. The message's keys count in any order:
# an id or a model after the usage too.
test_a_call_is_read_from_its_messages_own_id_model_and_usage() {
	export CLAUDE_CONFIG_DIR="$TEST_TMP/claude"
	mkdir -p "$CLAUDE_CONFIG_DIR/projects/$SLUG"
	printf '%s\n' '{"parentUuid":"u1","message":{"content":[{"type":"tool_use","id":"toolu_1","name":"probe","input":{"id":"msg_decoy","model":"<synthetic>","note":"a \"quoted\" word, a {brace} and C:\\dir\\","usage":{"input_tokens":700,"output_tokens":700}}}],"model":"claude-opus-5-5","id":"msg_h","usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":4}},"wireToolInputs":{"toolu_1":{"usage":{"input_tokens":800}}},"type":"assistant","uuid":"u5","timestamp":"2026-11-01T10:40:00.000Z"}' > "$CLAUDE_CONFIG_DIR/projects/$SLUG/s.jsonl"
	rec_call "$CLAUDE_CONFIG_DIR/projects/$SLUG/s.jsonl" 2026-11-01T10:41:00.000Z msg_decoy 9 0 0 9
	printf '%s\n' '{"message":{"usage":{"input_tokens":20,"output_tokens":2},"content":[],"model":"claude-opus-5-5","id":"msg_late"},"type":"assistant","timestamp":"2026-11-01T10:42:00.000Z"}' \
		'{"message":{"id":"msg_note","usage":{"input_tokens":50,"output_tokens":5},"model":"<synthetic>"},"type":"assistant","timestamp":"2026-11-01T10:43:00.000Z"}' >> "$CLAUDE_CONFIG_DIR/projects/$SLUG/s.jsonl"
	run_usage sessions --project "$PROJECT"
	assert_status 0
	assert_eq "session=s start=2026-11-01T10:40:00.000Z compactions=0 transcripts=1 calls=3 input=32 cache-write=0 cache-read=0 output=15 cost=107" "$out"
}

# The default project is the main checkout of the repo around the current folder
# (from a linked worktree too), else the current folder; a symlinked folder is
# found under its own path when its real one has no transcripts.
test_the_project_is_the_main_checkout_the_folder_or_a_symlink() {
	isolate_git
	export CLAUDE_CONFIG_DIR="$TEST_TMP/claude"
	local main slug
	git init -q -b dev "$TEST_TMP/main" || fail "could not make the repo"
	commit_in "$TEST_TMP/main" a.txt one
	git -C "$TEST_TMP/main" worktree add -q -b other "$TEST_TMP/wt" || fail "could not add the worktree"
	main="$(cd "$TEST_TMP/main" && pwd -P)"
	slug="$(printf '%s' "$main" | sed 's/[^0-9A-Za-z]/-/g')"
	rec_call "$CLAUDE_CONFIG_DIR/projects/$slug/main-s.jsonl" 2026-11-01T10:00:00.000Z msg_a 1 0 0 1
	cd "$TEST_TMP/wt" || fail "could not enter the worktree"
	run_usage sessions
	assert_status 0
	assert_eq "session=main-s start=2026-11-01T10:00:00.000Z compactions=0 transcripts=1 calls=1 input=1 cache-write=0 cache-read=0 output=1 cost=6" "$out"

	mkdir -p "$TEST_TMP/plain" "$TEST_TMP/home"
	slug="$(cd "$TEST_TMP/plain" && pwd -P | sed 's/[^0-9A-Za-z]/-/g')"
	rec_call "$TEST_TMP/home/.claude/projects/$slug/plain-s.jsonl" 2026-11-01T10:00:00.000Z msg_b 2 0 0 0
	cd "$TEST_TMP/plain" || fail "could not enter the folder"
	(
		unset CLAUDE_CONFIG_DIR
		export HOME="$TEST_TMP/home" GIT_CEILING_DIRECTORIES="$TEST_TMP"
		run_usage sessions
		assert_status 0
		assert_eq "session=plain-s start=2026-11-01T10:00:00.000Z compactions=0 transcripts=1 calls=1 input=2 cache-write=0 cache-read=0 output=0 cost=2" "$out"
	) || exit 1

	mkdir -p "$TEST_TMP/real"
	ln -s real "$TEST_TMP/link" || fail "could not make the symlink"
	slug="$(printf '%s' "$TEST_TMP/link" | sed 's/[^0-9A-Za-z]/-/g')"
	rec_call "$CLAUDE_CONFIG_DIR/projects/$slug/link-s.jsonl" 2026-11-01T10:00:00.000Z msg_c 3 0 0 0
	run_usage sessions --project "$TEST_TMP/link"
	assert_status 0
	assert_eq "session=link-s start=2026-11-01T10:00:00.000Z compactions=0 transcripts=1 calls=1 input=3 cache-write=0 cache-read=0 output=0 cost=3" "$out"
}

# shellcheck disable=SC2154 # status: set by run_cmd, in factory/core/tests/lib.sh
test_no_transcript_folder_exits_1_and_bad_usage_exits_2() {
	export CLAUDE_CONFIG_DIR="$TEST_TMP/claude"
	run_usage issues --project "$PROJECT"
	assert_status 1
	stderr_has "no transcripts for $PROJECT in $CLAUDE_CONFIG_DIR/projects/$SLUG"
	mkdir -p "$CLAUDE_CONFIG_DIR/projects/$SLUG"
	run_usage sessions --project "$PROJECT"
	assert_status 0
	assert_eq "" "$out"
	run_usage --help
	assert_status 0
	printf '%s\n' "$out" | grep -qF "a cache read 0.1, output 5" || fail "--help has no cost weights:"$'\n'"$out"
	local args
	for args in "" "totals" "issues --project" "issues --since yesterday" "sessions --until 2026-11-3" "issues --verbose" "issues --project not/here"; do
		# shellcheck disable=SC2086 # each case is its words
		run_usage $args
		[ "$status" -eq 2 ] || fail "'claude-usage $args' exited $status, not 2"
	done
}
