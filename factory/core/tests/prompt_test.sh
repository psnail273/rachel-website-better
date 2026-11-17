# The fixed prompts of an issue's rounds and checks: prompt.sh over factory-run's
# prompts/ templates, which are the prompts editor.md held, with placeholders.

PROMPTS="$FACTORY_CORE/../skills/factory-run/prompts"
TITLE='Fix the <n> & <title> \1 bug'

# The prompts as editor.md held them before they moved to prompts/, with the lines
# added since: the `green, amend` phase, the test-only Verifier's limit, the
# facts file's line and the invariants lines (the first round's and the green phase's).
old_editor() {
	cat << 'TXT'
You are the Editor for this repo. You write and commit the code for one issue, inside this worktree, on its current branch.

## Issue
Issue #<n>: <title>. Phase: <red | red, small lane | partial | green, test-only | green, amend>.

## Build Brief
<the brief, verbatim; the Core reads the same text from <git-dir>/factory/brief.md>

## Read first
AGENTS.md for the repo's rules, ARCHITECTURE.md for its structure, CONTEXT.md for the domain terms.

## The phase
red: write the brief's tests by name and typed stubs of its seams, so every named test fails on an assertion. Nothing else.
red, small lane: write the brief's tests by name, so every named test fails on an assertion against the product as it is, and commit them. Once the red gate passes, your stop hook locks them and sends you the green phase in this chat.
partial: remove the Baseline findings the brief names, and add none.
green, test-only: write the brief's tests by name, for behaviour that is already built, so every named test passes under every gate step. Change only test files and nothing else: the gate fails any other file, even with a Deviation trailer. If a test can't pass without a product change, stop and name it.
green, amend: make the change the brief describes, and where it changes a script, write the brief's tests by name for it, so the change and every named test pass under every gate step. An amend has no red phase and no Lock: your gate is the full verify. The gate's own files (`factory/`, `tools/verify/`, the hook config) refuse your writes: the project's checks the brief names are an amend builder's, written before your round, and `factory/` changes only by `/factory-amend`. If the brief needs a gate file that isn't so, stop and name it.
Each `invariants` line of the brief gets one property test, as your write-tests skill says, once the code it drives is built: in the green phase, or in a partial or test-only round; never in red, where a stub may already hold it.
Your stop hook runs the phase's gate, when you stop or hand back your report, and sends you its findings until it passes. Commit before you stop: it first blocks any change this round made to what the factory protects (`round-changed`), then any uncommitted file, the formatter's included, before the gate runs.

## Rules
- Stay inside the brief's scope. A file outside it must change only with a commit trailer `Deviation: <path or rule>: <reason>`.
- The gate is not yours: factory/, tools/verify/, the brief, the run state and .claude/ stay as they are, and a hook refuses writes to them; growing a ratchet file fails even when declared, unless the brief accepts it. The brief is sealed: a changed brief fails every gate. A wrong or missing brief line is the Driver's to fix: stop and name it.
- A gate is never worked around. If one fails for a reason you can't fix honestly in the product, stop and quote the failing line.
- Product code never checks how it is run (a test, the smoke run, headless, a command-line flag) unless the brief says so.
- Commit on the current branch, in small commits. Push, rebase, merge, worktrees and the issue tracker belong to the Driver; you only finish a rebase the Driver started, when a round asks you to. A hook refuses git push, update-ref, a forced or deleted dev or main, and commit --no-verify.
- Work through to the end without waiting for answers: the run is unattended. If something outside the brief blocks you, stop and name what you need.

## Finishing
End with a short final message: what you changed, the gate's result line quoted as your stop hook gives it (`verify: PASS at <short HEAD>`; it refuses a final message without it), any Deviation and why, and anything you need from the Driver.
TXT
}

old_green() {
	cat << 'TXT'
Phase: green. Make the locked tests pass under every gate step. The tests the red commit touched are locked: editing them fails the gate. Write one property test for each `invariants` line of the brief, as your write-tests skill says. Your stop hook's green gate runs smoke in Chromium alone and mutate incremental; when it leaves mutants no test caught, it lists them once: kill each with a test that fails on it, or say in your final message why it can't be killed.
TXT
}

old_footer() {
	cat << 'TXT'
When done: commit on the current branch and end with a short final message: what you changed, the gate's result line quoted as your stop hook gives it, each surviving mutant it listed that you left and why, any Deviation, and anything you need from the Driver. The rules of your first prompt still hold.
TXT
}

old_verifier() {
	cat << 'TXT'
You are the Verifier for issue #<n> in this worktree. Phase: <red | green | green, small lane | green, test-only>. Base: <base SHA>.

## Issue
<title, body and acceptance criteria>

## Build Brief
<the brief>

Criteria marked (Driver's check) are the Driver's to run on a device: report each as SKIP, naming the check, not FAIL.
In phase green, test-only: judge only the tests the brief's `test` lines name. Existing tests are context, except that none of their assertions is dropped or loosened.
Stay off the web. Leave the Scenario folder that `tools/verify/scenario-folder` names unread, in git's history too: the Scenarios check the Feature at its end.
Before judging a library's behaviour, read `docs/agents/facts.md` if it exists: a fact recorded there with its probe stands unless you probe it again.

<the output of `bash factory/core/rubric.sh`, run in the worktree>
TXT
}

old_brief_review() {
	cat << 'TXT'
You review the Build Brief for issue #<n> in this worktree, before its tests are written.

## Issue
<title, body and acceptance criteria>

## Build Brief
<the brief, as sealed>

Criteria marked (Driver's check) are the Driver's to run on a device: report each as SKIP, naming the check, not FAIL.
Change no file. Stay off the web. Leave the Scenario folder that `tools/verify/scenario-folder` names unread, in git's history too: the Scenarios check the Feature at its end.
Before judging a library's behaviour, read `docs/agents/facts.md` if it exists: a fact recorded there with its probe stands unless you probe it again.

<the output of `bash factory/core/rubric.sh --brief`>
TXT
}

SKIP_LINE="Criteria marked (Driver's check) are the Driver's to run on a device: report each as SKIP, naming the check, not FAIL."
TEST_ONLY_LINE="In phase green, test-only: judge only the tests the brief's \`test\` lines name. Existing tests are context, except that none of their assertions is dropped or loosened."
AMEND_LINE="green, amend: make the change the brief describes, and where it changes a script, write the brief's tests by name for it, so the change and every named test pass under every gate step. An amend has no red phase and no Lock: your gate is the full verify. The gate's own files (\`factory/\`, \`tools/verify/\`, the hook config) refuse your writes: the project's checks the brief names are an amend builder's, written before your round, and \`factory/\` changes only by \`/factory-amend\`. If the brief needs a gate file that isn't so, stop and name it."

# prompt_repo: a git repo on branch work, a commit ahead of dev, with one
# review-tagged rule, the issue as Start saves it and a brief. Both hold text
# that looks like placeholders.
prompt_repo() {
	isolate_git
	git init -q -b dev . || fail "git init failed"
	printf '**R1.** Alpha holds.\nEnforced by: `review`\n' > ARCHITECTURE.md
	echo one > a.txt
	git add -A && git commit -q -m one || fail "could not commit"
	git checkout -q -b work || fail "no work branch"
	echo two > a.txt
	git commit -q -am two || fail "could not commit"
	mkdir -p .git/factory
	cat > .git/factory/issue.md << MD
#7: $TITLE

Kind: build

The body names <brief> and <n>.
<rubric>

## Acceptance criteria
- [ ] It works & stays \\1 fast.
MD
	cat > .git/factory/brief.md << 'MD'
# Build Brief: #7 Fix the bug

Kind: build. Phase: red.

<issue>
<phase> and <base> stay as written, & \1 too.

```factory-brief
scope src/a.gd
test test_it_works
```
MD
}

# slurp <file>: set REPLY to the file's text, its final newline kept, for exact checks.
slurp() {
	REPLY="$(
		cat "$1"
		echo x
	)"
	REPLY="${REPLY%x}"
}

# The templates hold editor.md's prompts byte for byte, apart from the
# placeholders prompt.sh fills: <phase>, <base>, <issue>, <brief> and <rubric>.
test_templates_are_the_prompts_editor_md_held() {
	local t
	slurp "$PROMPTS/editor.md"
	t="$REPLY"
	t="${t//'Phase: <phase>.'/'Phase: <red | red, small lane | partial | green, test-only | green, amend>.'}"
	t="${t//$'\n<brief>\n'/$'\n<the brief, verbatim; the Core reads the same text from <git-dir>/factory/brief.md>\n'}"
	assert_eq "$(
		old_editor
		echo x
	)" "${t}x" "prompts/editor.md differs from the first round's prompt"

	slurp "$PROMPTS/verifier.md"
	t="$REPLY"
	t="${t//'Phase: <phase>. Base: <base>.'/'Phase: <red | green | green, small lane | green, test-only>. Base: <base SHA>.'}"
	t="${t//$'\n<issue>\n'/$'\n<title, body and acceptance criteria>\n'}"
	t="${t//$'\n<brief>\n'/$'\n<the brief>\n'}"
	t="${t//$'\n<rubric>\n'/$'\n<the output of `bash factory/core/rubric.sh`, run in the worktree>\n'}"
	assert_eq "$(
		old_verifier
		echo x
	)" "${t}x" "prompts/verifier.md differs from the Verifier prompt"

	slurp "$PROMPTS/brief-review.md"
	t="$REPLY"
	t="${t//$'\n<issue>\n'/$'\n<title, body and acceptance criteria>\n'}"
	t="${t//$'\n<brief>\n'/$'\n<the brief, as sealed>\n'}"
	t="${t//$'\n<rubric>\n'/$'\n<the output of `bash factory/core/rubric.sh --brief`>\n'}"
	assert_eq "$(
		old_brief_review
		echo x
	)" "${t}x" "prompts/brief-review.md differs from the brief review prompt"

	slurp "$PROMPTS/green.md"
	assert_eq "$(
		old_green
		echo x
	)" "${REPLY}x" "prompts/green.md differs from the green line"
	slurp "$PROMPTS/footer.md"
	assert_eq "$(
		old_footer
		echo x
	)" "${REPLY}x" "prompts/footer.md differs from the footer"
}

# editor.md points to the templates and no longer holds their text.
test_editor_md_points_to_each_template() {
	local name skill="$FACTORY_CORE/../skills/factory-run/editor.md"
	for name in editor green footer verifier brief-review; do
		grep -qF "](prompts/$name.md)" "$skill" || fail "editor.md doesn't link prompts/$name.md"
	done
	grep -qF "You are the Editor for this repo." "$skill" && fail "editor.md still holds the first round's prompt"
	grep -qF "You are the Verifier for issue" "$skill" && fail "editor.md still holds the Verifier prompt"
	return 0
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_editor_prints_the_first_round_for_each_phase() {
	local phase expected
	prompt_repo
	for phase in red 'red, small lane' partial 'green, test-only' 'green, amend'; do
		run_cmd bash "$FACTORY_CORE/prompt.sh" editor "$phase"
		assert_status 0
		expected="$(old_editor)"
		expected="${expected//'Issue #<n>: <title>. Phase: <red | red, small lane | partial | green, test-only | green, amend>.'/"Issue #7: $TITLE. Phase: $phase."}"
		expected="${expected//'<the brief, verbatim; the Core reads the same text from <git-dir>/factory/brief.md>'/"$(cat .git/factory/brief.md)"}"
		assert_eq "$expected" "$out" "the first round in phase $phase"
	done
}

test_a_phase_of_two_words_may_be_two_arguments() {
	prompt_repo
	run_cmd bash "$FACTORY_CORE/prompt.sh" editor red, small lane
	assert_status 0
	assert_line "Issue #7: $TITLE. Phase: red, small lane."
	run_cmd bash "$FACTORY_CORE/prompt.sh" verifier green, test-only
	assert_status 0
	printf '%s\n' "$out" | head -n 1 | grep -qF "Phase: green, test-only. Base: " || fail "no phase in: $(printf '%s\n' "$out" | head -n 1)"
}

test_verifier_prints_the_check_for_each_phase() {
	local phase expected base rubric
	prompt_repo
	base="$(git merge-base HEAD dev)"
	rubric="$(bash "$FACTORY_CORE/rubric.sh")" || fail "rubric.sh failed"
	for phase in red green 'green, small lane' 'green, test-only'; do
		run_cmd bash "$FACTORY_CORE/prompt.sh" verifier "$phase"
		assert_status 0
		expected="$(old_verifier)"
		expected="${expected//'issue #<n> in this worktree. Phase: <red | green | green, small lane | green, test-only>. Base: <base SHA>.'/"issue #7 in this worktree. Phase: $phase. Base: $base."}"
		expected="${expected//'<title, body and acceptance criteria>'/"$(cat .git/factory/issue.md)"}"
		expected="${expected//$'\n<the brief>\n'/$'\n'"$(cat .git/factory/brief.md)"$'\n'}"
		expected="${expected//'<the output of `bash factory/core/rubric.sh`, run in the worktree>'/"$rubric"}"
		assert_eq "$expected" "$out" "the Verifier prompt in phase $phase"
	done
	assert_line "$SKIP_LINE"
	assert_line "- **R1.** Alpha holds. (ARCHITECTURE.md:1)"
}

# #187's Verifier failed an older test its brief named only as context: the
# test-only check is held to the brief's `test` lines.
test_the_test_only_verifier_judges_only_the_briefs_tests() {
	prompt_repo
	run_cmd bash "$FACTORY_CORE/prompt.sh" verifier green, test-only
	assert_status 0
	assert_line "$TEST_ONLY_LINE"
}

# #157, a Kind amend in Phase green, had no first prompt; its Verifier takes
# phase green.
test_an_amend_in_phase_green_has_a_first_prompt() {
	prompt_repo
	run_cmd bash "$FACTORY_CORE/prompt.sh" editor green, amend
	assert_status 0
	assert_line "Issue #7: $TITLE. Phase: green, amend."
	assert_line "$AMEND_LINE"
	run_cmd bash "$FACTORY_CORE/prompt.sh" verifier green, amend
	assert_status 2
}

# doc_phases <file...>: each prompt the docs name a phase for, as `editor <phase>`
# or `verifier <phase>` lines, sorted. A doc names one as
#   "first prompt" or "first Editor round" ... "with", "on" or "uses phase <p>"  an Editor's
#   "Verifier" ... "with" or "on phase <p>"                                      a Verifier's
#   "`prompt.sh editor <phase>`, with phase `<p>`, `<p>` or `<p>`"             each an Editor's
# (`prompt.sh verifier` the same), where <p> is a phase in backticks or one bare
# word, and at most 40 characters, none of them . ; : or a backtick, come between
# the role and its verb. A `<p>: ` line under the editor template's `## The phase`
# names an Editor's.
doc_phases() {
	local m role
	{
		grep -ohE '(first prompt|first Editor round)[^.;:`]{0,40} (with|on|uses) phase (`[^`]+`|[a-z]+)' "$@" |
			sed -E 's/.* phase `?([^`]+)`?$/editor \1/'
		grep -ohE 'Verifier[^.;:`]{0,40} (with|on) phase (`[^`]+`|[a-z]+)' "$@" |
			sed -E 's/.* phase `?([^`]+)`?$/verifier \1/'
		grep -ohE '`prompt\.sh (editor|verifier) <phase>`, with phase `[^`]+`((, | or )`[^`]+`)*' "$@" |
			while IFS= read -r m; do
				role="${m#'`prompt.sh '}"
				role="${role%% *}"
				grep -oE '`[^`]+`' <<< "${m#*with phase }" | tr -d '`' | sed "s/^/$role /"
			done
		awk '/^## The phase$/ { on = 1; next } /^## / { on = 0 } on && /^[a-z][a-z ,-]*: / { sub(/: .*/, ""); print "editor " $0 }' "$@"
	} | LC_ALL=C sort -u
}

# missing_prompts <file...>: each phase doc_phases finds in the files that prompt.sh
# prints no prompt for; run in prompt_repo.
missing_prompts() {
	local role phase
	doc_phases "$@" | while IFS=' ' read -r role phase; do
		if ! bash "$FACTORY_CORE/prompt.sh" "$role" "$phase" > prompt.txt 2> /dev/null || ! grep -qF "Phase: $phase." prompt.txt; then
			echo "$role $phase"
		fi
	done
}

# Every phase SKILL.md, editor.md and the editor template name for an Editor or a
# Verifier has its prompt, so a phase a doc gains without one fails here.
test_every_phase_the_docs_name_has_a_prompt() {
	local skill="$FACTORY_CORE/../skills/factory-run" found
	prompt_repo
	found="$(doc_phases "$skill/SKILL.md" "$skill/editor.md" "$PROMPTS/editor.md")"
	grep -qxF "editor green, amend" <<< "$found" || fail "the docs name no amend's first prompt:"$'\n'"$found"
	grep -qxF "verifier green, test-only" <<< "$found" || fail "the docs name no test-only Verifier:"$'\n'"$found"
	assert_eq "" "$(missing_prompts "$skill/SKILL.md" "$skill/editor.md" "$PROMPTS/editor.md")" "phases the docs name with no prompt"
}

# The check on a doc naming phases prompt.sh has no prompt for, and phrases that
# name no prompt's phase.
test_a_phase_a_doc_names_without_a_prompt_is_found() {
	prompt_repo
	cat > doc.md << 'MD'
- Send the first prompt with phase `green, bogus`, then step 4 with the Verifier on phase `partial`.
- The first Editor round uses phase `partial`, and a Verifier with phase red.
- **First Editor round:** `prompt.sh editor <phase>`, with phase `red`, `blue` or `green, amend` (a list).
- `state.sh set phase green`, then the phase still red: no prompt's.

## The phase
red: the template's line.
violet, lane: a new line.
Your stop hook runs.
MD
	assert_eq "editor blue
editor green, amend
editor green, bogus
editor partial
editor red
editor violet, lane
verifier partial
verifier red" "$(doc_phases doc.md)"
	assert_eq "editor blue
editor green, bogus
editor violet, lane
verifier partial" "$(missing_prompts doc.md)"
}

test_brief_review_prints_the_issue_the_brief_and_the_brief_rubric() {
	local expected rubric
	prompt_repo
	rubric="$(bash "$FACTORY_CORE/rubric.sh" --brief)" || fail "rubric.sh --brief failed"
	run_cmd bash "$FACTORY_CORE/prompt.sh" brief-review
	assert_status 0
	expected="$(old_brief_review)"
	expected="${expected//'issue #<n>'/'issue #7'}"
	expected="${expected//'<title, body and acceptance criteria>'/"$(cat .git/factory/issue.md)"}"
	expected="${expected//'<the brief, as sealed>'/"$(cat .git/factory/brief.md)"}"
	expected="${expected//'<the output of `bash factory/core/rubric.sh --brief`>'/"$rubric"}"
	assert_eq "$expected" "$out"
	assert_line "$SKIP_LINE"
	assert_line "VERDICT: PASS|FAIL"
}

# The first round holds no SKIP line: only the checks' templates have it.
test_the_skip_line_is_only_in_the_checks() {
	prompt_repo
	run_cmd bash "$FACTORY_CORE/prompt.sh" editor red
	assert_status 0
	assert_no_line "$SKIP_LINE"
}

test_green_is_the_green_line_then_the_footer() {
	run_cmd bash "$FACTORY_CORE/prompt.sh" green
	assert_status 0
	assert_eq "$(old_green)"$'\n\n'"$(old_footer)" "$out"
}

# The footer starts with a blank line, so it can be appended under a round's text.
test_footer_is_a_blank_line_then_the_footer() {
	bash "$FACTORY_CORE/prompt.sh" footer > footer.txt || fail "footer failed"
	slurp footer.txt
	assert_eq $'\n'"$(old_footer)"$'\n' "$REPLY"
}

# Neither needs the issue, the brief or a repo.
test_green_and_footer_need_no_inputs() {
	run_cmd bash "$FACTORY_CORE/prompt.sh" green
	assert_status 0
	run_cmd bash "$FACTORY_CORE/prompt.sh" footer
	assert_status 0
}

# Text that fills a placeholder is put in as it is: never read for one, with &
# and backslashes kept.
test_what_fills_a_placeholder_is_never_filled_again() {
	prompt_repo
	run_cmd bash "$FACTORY_CORE/prompt.sh" verifier green
	assert_status 0
	assert_line "#7: $TITLE"
	assert_line "The body names <brief> and <n>."
	assert_line "<rubric>"
	assert_line "- [ ] It works & stays \\1 fast."
	assert_line "<issue>"
	assert_line '<phase> and <base> stay as written, & \1 too.'
	run_cmd bash "$FACTORY_CORE/prompt.sh" editor red
	assert_status 0
	assert_line "Issue #7: $TITLE. Phase: red."
	assert_line "- Stay inside the brief's scope. A file outside it must change only with a commit trailer \`Deviation: <path or rule>: <reason>\`."
}

# A brief or an issue with no final newline still ends its line, and a CRLF first
# line gives the title without its CR.
test_inputs_end_their_lines() {
	prompt_repo
	printf '#7: The title\r\nThe body' > .git/factory/issue.md
	printf 'The brief, with no final newline' > .git/factory/brief.md
	run_cmd bash "$FACTORY_CORE/prompt.sh" brief-review
	assert_status 0
	assert_line "The body"
	assert_line "The brief, with no final newline"
	assert_line "## Build Brief"
	run_cmd bash "$FACTORY_CORE/prompt.sh" editor red
	assert_status 0
	assert_line "Issue #7: The title. Phase: red."
}

test_base_is_factory_base_when_set_as_a_commit() {
	prompt_repo
	FACTORY_BASE=HEAD run_cmd bash "$FACTORY_CORE/prompt.sh" verifier red
	assert_status 0
	printf '%s\n' "$out" | head -n 1 | grep -qF "Base: $(git rev-parse HEAD)." || fail "not HEAD's commit: $(printf '%s\n' "$out" | head -n 1)"
	git branch -q other HEAD
	FACTORY_BASE_BRANCH=other run_cmd bash "$FACTORY_CORE/prompt.sh" verifier red
	assert_status 0
	printf '%s\n' "$out" | head -n 1 | grep -qF "Base: $(git rev-parse HEAD)." || fail "not the merge-base with other: $(printf '%s\n' "$out" | head -n 1)"
}

test_a_missing_issue_exits_1_naming_the_file() {
	local what
	prompt_repo
	rm .git/factory/issue.md
	for what in 'editor red' 'verifier green' brief-review; do
		# shellcheck disable=SC2086 # each case is its words
		run_cmd bash "$FACTORY_CORE/prompt.sh" $what
		assert_status 1
		assert_eq "" "$out" "$what printed a prompt"
		stderr_has "no issue at .git/factory/issue.md; save it with start.sh from the main checkout: pipe the issue's raw body into 'bash factory/core/start.sh <n> --title \"<title>\"'"
	done
	: > .git/factory/issue.md
	run_cmd bash "$FACTORY_CORE/prompt.sh" editor red
	assert_status 1
	stderr_has "no issue at .git/factory/issue.md"
}

test_an_issue_without_its_first_line_exits_1_naming_the_file() {
	local first
	prompt_repo
	for first in 'Fix the bug' '#7:' '#7:   ' '#07: Fix it' '7: Fix it' '#x: Fix it'; do
		printf '%s\nThe body.\n' "$first" > .git/factory/issue.md
		run_cmd bash "$FACTORY_CORE/prompt.sh" editor red
		assert_status 1
		assert_eq "" "$out" "a prompt for the first line '$first'"
		stderr_has ".git/factory/issue.md starts with '$first', not the line '#<n>: <title>'"
	done
}

test_a_missing_brief_exits_1_naming_the_file() {
	local what
	prompt_repo
	rm .git/factory/brief.md
	for what in 'editor partial' 'verifier red' brief-review; do
		# shellcheck disable=SC2086 # each case is its words
		run_cmd bash "$FACTORY_CORE/prompt.sh" $what
		assert_status 1
		assert_eq "" "$out" "$what printed a prompt"
		stderr_has "no Build Brief at .git/factory/brief.md"
	done
}

# An input it can't read is refused, never filled in as empty.
test_an_unreadable_input_exits_1_and_prints_nothing() {
	local what
	prompt_repo
	refusing_stand_in cat '*/factory/brief.md'
	for what in 'editor red' 'verifier green' brief-review; do
		# shellcheck disable=SC2086 # each case is its words
		run_cmd bash "$FACTORY_CORE/prompt.sh" $what
		assert_status 1
		assert_eq "" "$out" "$what printed a prompt"
		stderr_has "can't read .git/factory/brief.md"
	done
	# The brief review is the prompt that copies the issue whole.
	refusing_stand_in cat '*/factory/issue.md'
	run_cmd bash "$FACTORY_CORE/prompt.sh" brief-review
	assert_status 1
	assert_eq "" "$out"
	stderr_has "can't read .git/factory/issue.md"
}

# A template it can't read stops the prompt too: prompt.sh in a copy of the Core
# and the templates.
test_an_unreadable_template_exits_1_and_prints_nothing() {
	local prompts=copy/skills/factory-run/prompts
	mkdir -p copy/core copy/skills/factory-run
	cp "$FACTORY_CORE/prompt.sh" copy/core/
	cp -R "$FACTORY_CORE/lib" copy/core/
	cp -R "$FACTORY_CORE/../skills/factory-run/prompts" copy/skills/factory-run/
	run_cmd bash copy/core/prompt.sh green
	assert_status 0
	refusing_stand_in cat '*/footer.md'
	run_cmd bash copy/core/prompt.sh green
	assert_status 1
	assert_eq "" "$out"
	stderr_has "prompt: can't read $PWD/copy/core/../skills/factory-run/prompts/footer.md"
	rm -f "$prompts/footer.md"
	run_cmd bash copy/core/prompt.sh footer
	assert_status 1
	assert_eq "" "$out"
	stderr_has "no template"
}

test_a_folder_for_an_input_exits_1_and_prints_nothing() {
	prompt_repo
	mkdir -p folder
	echo x > folder/file
	FACTORY_BRIEF=folder run_cmd bash "$FACTORY_CORE/prompt.sh" editor red
	assert_status 1
	assert_eq "" "$out"
	stderr_has " folder"
}

test_a_failing_rubric_exits_1_and_prints_nothing() {
	prompt_repo
	rm ARCHITECTURE.md
	run_cmd bash "$FACTORY_CORE/prompt.sh" verifier green
	assert_status 1
	assert_eq "" "$out"
	stderr_has "rubric: no ARCHITECTURE.md"
	stderr_has "prompt: rubric.sh failed"
	# The brief rubric reads no ARCHITECTURE.md.
	run_cmd bash "$FACTORY_CORE/prompt.sh" brief-review
	assert_status 0
}

test_no_base_exits_1() {
	prompt_repo
	FACTORY_BASE_BRANCH=nope run_cmd bash "$FACTORY_CORE/prompt.sh" verifier red
	assert_status 1
	assert_eq "" "$out"
	stderr_has "no merge-base of HEAD and 'nope'"
	FACTORY_BASE=nope run_cmd bash "$FACTORY_CORE/prompt.sh" verifier red
	assert_status 1
	stderr_has "the diff base 'nope' names no commit"
}

test_outside_a_repo_the_issue_is_refused() {
	run_cmd bash "$FACTORY_CORE/prompt.sh" editor red
	assert_status 1
	stderr_has "not in a git repository"
}

test_usage_exits_2() {
	local args
	prompt_repo
	for args in '' bogus editor 'editor green' 'editor amend' 'editor red small lane' 'verifier partial' 'verifier green, amend' verifier 'green now' 'footer x' 'brief-review red'; do
		# shellcheck disable=SC2086 # each case is its words
		run_cmd bash "$FACTORY_CORE/prompt.sh" $args
		assert_status 2
		assert_eq "" "$out" "'$args' printed a prompt"
		stderr_has "usage: bash factory/core/prompt.sh editor"
	done
}
