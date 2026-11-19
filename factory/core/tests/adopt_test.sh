# Adoption (adopt.sh) and the factory's AGENTS.md section (agents.sh), on a git
# project that vendors this factory/ and has a stub adapter, `fake`, made from the
# fixture project's step scripts (steered by .fixture/ files, see its _stub.sh).

AGENTS_BEGIN="<!-- factory:begin (generated from factory/core/templates/agents-section.md; edit that, then run bash factory/core/agents.sh generate) -->"
AGENTS_END="<!-- factory:end -->"

adopt() {
	run_cmd bash factory/core/adopt.sh "${1:-fake}"
}

# lint_finding: the fake lint step fails with one finding.
lint_finding() {
	mkdir -p .fixture
	echo "src/a.txt:1 fake-rule a finding" > .fixture/fail-lint
}

test_adoption_seeds_every_file_and_records_the_baseline() {
	adopt_project
	lint_finding
	adopt
	assert_status 0
	assert_last_line "baseline: RECORDED 1 entries in tools/verify/ratchet/baseline.txt"
	local f
	for f in $(cd factory/adapters/fake/tools/verify && find . -type f | sed 's#^\./##'); do
		cmp -s "factory/adapters/fake/tools/verify/$f" "tools/verify/$f" || fail "tools/verify/$f isn't seeded"
	done
	cmp -s factory/core/templates/verify.sh tools/verify.sh || fail "tools/verify.sh isn't the entry point"
	cmp -s factory/core/templates/verify.ps1 tools/verify.ps1 || fail "no tools/verify.ps1"
	assert_eq report "$(grep -v '^#' tools/verify/hook-mode)" "wrong hook mode"
	assert_eq factory/core/hooks/githooks "$(git config core.hooksPath)" "core.hooksPath"
	[ ! -e .cursor ] || fail "adopt wrote a .cursor folder"
	grep -q '"hooks"' .claude/settings.json || fail "no hooks in .claude/settings.json"
	grep -qxF '  "model": "claude-opus-5-5",' .claude/settings.json || fail "no main session model in .claude/settings.json"
	grep -qxF '  "effortLevel": "medium",' .claude/settings.json || fail "no main session effort in .claude/settings.json"
	grep -qxF '  "maxEffortLevel": "xhigh"' .claude/settings.json || fail "no effort cap in .claude/settings.json"
	grep -q '"A": "1"' .claude/settings.json || fail "the settings lost their env"
	for f in $(cd factory/skills && find . -type f | sed 's#^\./##'); do
		cmp -s "factory/skills/$f" ".claude/skills/$f" || fail ".claude/skills/$f isn't installed"
	done
	cmp -s factory/core/templates/deviations.md docs/deviations.md || fail "no docs/deviations.md"
	cmp -s factory/core/templates/ARCHITECTURE.md ARCHITECTURE.md || fail "no ARCHITECTURE.md skeleton"
	assert_eq "docs/agents/facts.md merge=union"$'\n'"docs/deviations.md merge=union" "$(cat .gitattributes)" "the new .gitattributes"
	grep -qxF "$AGENTS_BEGIN" AGENTS.md || fail "no factory section in AGENTS.md"
	assert_eq "version $(cat factory/VERSION)"$'\n'"adapter fake" "$(head -n 2 tools/verify/factory-version)" "factory-version"
	assert_eq "file $(git hash-object factory/core/verify.sh) factory/core/verify.sh" \
		"$(grep ' factory/core/verify.sh$' tools/verify/factory-version)" "factory-version's record of a vendored file"
	assert_eq "$(git ls-files factory | wc -l | tr -d " ")" "$(grep -c '^file ' tools/verify/factory-version)" "factory-version records every vendored file"
	assert_eq "src/a.txt fake-rule a finding" "$(cat tools/verify/ratchet/baseline.txt)" "the Baseline"
	git check-ignore -q tools/verify/local.env || fail "local.env isn't gitignored"
	assert_eq "" "$(git status --porcelain | grep -v '^[AM] ')" "adoption left files unstaged"
}

# /audit is installed as the human's to run, and the cleanup doc it files with
# is where its link leads.
test_adoption_installs_the_audit_skill_for_the_human_to_run() {
	adopt_project
	adopt
	assert_status 0
	grep -qxF "name: audit" .claude/skills/audit/SKILL.md || fail "no audit skill"
	grep -qxF "disable-model-invocation: true" .claude/skills/audit/SKILL.md || fail "the model may run the audit skill"
	grep -qF "](../adopt/cleanup.md)" .claude/skills/audit/SKILL.md || fail "the audit skill doesn't link the cleanup doc"
	[ -f .claude/skills/adopt/cleanup.md ] || fail "the audit skill's link to the cleanup doc leads nowhere"
}

test_the_adopted_project_verifies_through_tools_verify_sh() {
	adopt_project
	lint_finding
	adopt
	assert_status 0
	git commit -q -m adopt || fail "could not commit the adoption"
	run_cmd bash tools/verify.sh
	assert_status 1
	assert_line "== lint FAIL"
	assert_line "src/a.txt:1 fake-rule a finding"
	assert_last_line "verify: FAILED at step lint"
	run_cmd bash factory/core/baseline.sh gate
	assert_status 0
}

test_the_sonnet_editor_gets_the_adapter_and_project_names() {
	adopt_project
	adopt
	assert_status 0
	local agent=.claude/agents/editor-sonnet.md
	grep -qxF "  - write-tests-fake" "$agent" || fail "no write-tests-fake in $agent"
	grep -qxF "  - verify-my-game" "$agent" || fail "no verify-my-game in $agent"
	! grep -q '<stack>\|<project>' "$agent" || fail "placeholders left in $agent"
	grep -q '^model: claude-sonnet' "$agent" || fail "the model line is gone from $agent"
	grep -q '^name: asset-fetcher$' .claude/agents/asset-fetcher.md || fail "the asset fetcher wasn't installed"
	for agent in verifier amend-builder; do
		cmp -s "factory/agents/$agent.md" ".claude/agents/$agent.md" || fail "the $agent agent wasn't installed as it is"
	done
	grep -qx '^name: designer$' .claude/agents/designer.md || fail "the designer wasn't installed"
	grep -qF 'designer** of my-game' .claude/agents/designer.md || fail "the designer's <project> wasn't filled in"
	cmp -s factory/third-party/frontend-design/SKILL.md .claude/skills/frontend-design/SKILL.md ||
		fail "the frontend-design skill the designer and Verifier preload wasn't installed"
}

test_factory_project_names_the_project() {
	adopt_project
	FACTORY_PROJECT=Other run_cmd bash factory/core/adopt.sh fake
	assert_status 0
	grep -qxF "  - verify-other" .claude/agents/editor-sonnet.md || fail "FACTORY_PROJECT isn't used"
}

test_existing_project_files_are_kept() {
	adopt_project
	mkdir -p tools/verify .claude/skills/repro-first .claude/agents docs
	echo "# the project's lint" > tools/verify/lint
	echo "# the project's architecture" > ARCHITECTURE.md
	echo "the project's skill" > .claude/skills/repro-first/SKILL.md
	echo "the project's agent" > .claude/agents/editor-sonnet.md
	echo "the project's log" > docs/deviations.md
	echo "# the project's ps1" > tools/verify.ps1
	git add -A && git commit -q -m "own files" || fail "could not commit"
	adopt
	assert_status 0
	assert_eq "# the project's lint" "$(cat tools/verify/lint)" "lint was overwritten"
	assert_eq "# the project's architecture" "$(cat ARCHITECTURE.md)" "ARCHITECTURE.md was overwritten"
	assert_eq "the project's skill" "$(cat .claude/skills/repro-first/SKILL.md)" "the skill was overwritten"
	assert_eq "the project's agent" "$(cat .claude/agents/editor-sonnet.md)" "the agent was overwritten"
	assert_eq "the project's log" "$(cat docs/deviations.md)" "docs/deviations.md was overwritten"
	assert_eq "# the project's ps1" "$(cat tools/verify.ps1)" "tools/verify.ps1 was overwritten"
	stderr_has "kept ARCHITECTURE.md"
}

# A .gitattributes the project has keeps its lines and gets only the
# union-merge lines it lacks, once each.
test_an_existing_gitattributes_gets_only_the_missing_union_lines() {
	adopt_project
	printf '*.png binary\ndocs/deviations.md merge=union' > .gitattributes
	git add -A && git commit -q -m "own .gitattributes" || fail "could not commit"
	adopt
	assert_status 0
	assert_eq "*.png binary"$'\n'"docs/deviations.md merge=union"$'\n'"docs/agents/facts.md merge=union" "$(cat .gitattributes)" "the .gitattributes"
	stderr_has "added 'docs/agents/facts.md merge=union' to .gitattributes"
	assert_eq "union" "$(git check-attr merge -- docs/agents/facts.md | sed 's/.*: //')" "facts.md's merge driver"
	assert_eq "union" "$(git check-attr merge -- docs/deviations.md | sed 's/.*: //')" "deviations.md's merge driver"
}

test_an_older_tools_verify_sh_is_replaced_by_the_entry_point() {
	adopt_project
	mkdir -p tools && echo 'echo old verify' > tools/verify.sh
	git add -A && git commit -q -m "old verify" || fail "could not commit"
	adopt
	assert_status 0
	cmp -s factory/core/templates/verify.sh tools/verify.sh || fail "tools/verify.sh wasn't replaced"
	stderr_has "replaced tools/verify.sh"
}

test_a_second_run_refuses() {
	adopt_project
	adopt
	assert_status 0
	git commit -q -m adopt || fail "could not commit the adoption"
	adopt
	assert_status 1
	stderr_has "already adopted"
	assert_eq "" "$(git status --porcelain)" "the refused run changed the tree"
}

test_a_dirty_tree_refuses() {
	adopt_project
	echo two > src/a.txt
	adopt
	assert_status 1
	stderr_has "dirty"
	[ ! -e tools/verify ] || fail "a refused run seeded tools/verify"
	[ -z "$(git config core.hooksPath)" ] || fail "a refused run set core.hooksPath"
}

test_an_untracked_file_makes_the_tree_dirty() {
	adopt_project
	echo new > src/new.txt
	adopt
	assert_status 1
	stderr_has "dirty"
}

test_an_unknown_adapter_is_a_usage_error() {
	adopt_project
	adopt nosuch
	assert_status 2
	run_cmd bash factory/core/adopt.sh
	assert_status 2
	run_cmd bash factory/core/adopt.sh --new
	assert_status 2
	run_cmd bash factory/core/adopt.sh fake --old
	assert_status 2
	run_cmd bash factory/core/adopt.sh fake --new extra
	assert_status 2
}

# --- --new: the adapter's skeleton ---

# fake_skeleton: give the fake adapter a --new skeleton (a .gitignore, a file
# naming <project>, a nested one) and an adopt.sh that logs its arguments, and
# commit them.
fake_skeleton() {
	local s=factory/adapters/fake/new
	mkdir -p "$s/src/main"
	printf '/build/\n/.fixture/\n' > "$s/.gitignore.txt"
	printf 'name=<project>\n' > "$s/project.cfg.txt"
	printf 'main\n' > "$s/src/main/main.txt.txt"
	printf 'echo "args:$*" > "%s/adapter-args"\n' "$TEST_TMP" > factory/adapters/fake/adopt.sh
	git add -A && git commit -q -m "fake skeleton" || fail "could not commit the skeleton"
}

test_new_lays_the_skeleton_then_adopts() {
	adopt_project
	fake_skeleton
	run_cmd bash factory/core/adopt.sh fake --new
	assert_status 0
	assert_last_line "baseline: RECORDED 0 entries in tools/verify/ratchet/baseline.txt"
	assert_eq "name=my-game" "$(cat project.cfg)" "<project> isn't filled in"
	assert_eq main "$(cat src/main/main.txt)" "the nested file"
	[ ! -e project.cfg.txt ] || fail "the .txt was kept"
	assert_eq "args:--new" "$(cat "$TEST_TMP/adapter-args")" "the adapter's adopt.sh didn't get --new"
	[ -f tools/verify/factory-version ] || fail "not adopted"
	assert_eq "" "$(git status --porcelain | grep -v '^[AM] ')" "adoption left files unstaged"
}

test_new_adds_the_skeleton_lines_to_an_existing_gitignore() {
	adopt_project
	fake_skeleton
	run_cmd bash factory/core/adopt.sh fake --new
	assert_status 0
	assert_eq 1 "$(grep -cxF '/.fixture/' .gitignore)" "a line the .gitignore had was added again"
	assert_eq 1 "$(grep -cxF '/build/' .gitignore)" "the skeleton's line wasn't added"
	assert_eq '/.fixture/' "$(head -n 1 .gitignore)" "the project's lines moved"
	stderr_has "added '/build/' to .gitignore"
}

test_new_refuses_a_project_that_has_a_skeleton_file() {
	adopt_project
	fake_skeleton
	echo "the project's own" > project.cfg
	git add -A && git commit -q -m "own project.cfg" || fail "could not commit"
	run_cmd bash factory/core/adopt.sh fake --new
	assert_status 1
	stderr_has "--new is for a new project, and project.cfg exists"
	assert_eq "" "$(git status --porcelain)" "the refused run changed the tree"
	[ ! -e src/main ] || fail "the refused run laid the skeleton"
}

test_adopting_without_new_lays_no_skeleton() {
	adopt_project
	fake_skeleton
	adopt
	assert_status 0
	[ ! -e project.cfg ] || fail "a plain adoption laid the skeleton"
	assert_eq "args:" "$(cat "$TEST_TMP/adapter-args")" "the adapter's adopt.sh got arguments"
}

test_new_without_a_skeleton_is_a_usage_error() {
	adopt_project
	run_cmd bash factory/core/adopt.sh fake --new
	assert_status 2
	stderr_has "no --new skeleton"
	assert_eq "" "$(git status --porcelain)" "the refused run changed the tree"
}

test_a_failing_prepare_stops_before_the_baseline() {
	adopt_project
	mkdir -p .fixture
	echo "src/a.txt:1 fake-prepare broken" > .fixture/fail-prepare
	adopt
	assert_status 1
	[ ! -e tools/verify/ratchet/baseline.txt ] || fail "a Baseline was recorded with prepare failing"
	stderr_has "src/a.txt:1 fake-prepare broken"
	stderr_has "run bash factory/core/adopt.sh fake again"
	[ -f tools/verify/factory-version ] || fail "the seeded files weren't kept"
}

# Once prepare is fixed, a second run resumes at the Baseline: it records it and
# stages the adoption, seeding nothing again.
test_a_rerun_after_a_failing_prepare_resumes_at_the_baseline() {
	adopt_project
	mkdir -p .fixture
	echo "src/a.txt:1 fake-prepare broken" > .fixture/fail-prepare
	adopt
	assert_status 1
	rm .fixture/fail-prepare
	lint_finding
	echo "the project's tuning" >> tools/verify/lint
	adopt
	assert_status 0
	stderr_has "resuming"
	assert_last_line "baseline: RECORDED 1 entries in tools/verify/ratchet/baseline.txt"
	assert_eq "the project's tuning" "$(tail -n 1 tools/verify/lint)" "the resumed run seeded again"
	assert_eq "" "$(git status --porcelain | grep -v '^[AM] ')" "the resumed run left files unstaged"
	git commit -q -m adopt || fail "could not commit the adoption"
	adopt
	assert_status 1
	stderr_has "already adopted"
}

# A step that fails before the Baseline undoes the run: here the adapter's own
# adoption, after --new laid the skeleton.
test_a_failure_before_the_baseline_leaves_the_tree_as_it_was() {
	adopt_project
	fake_skeleton
	printf 'exit 1\n' > factory/adapters/fake/adopt.sh
	git add -A && git commit -q -m "failing adapter" || fail "could not commit"
	run_cmd bash factory/core/adopt.sh fake --new
	assert_status 1
	stderr_has "the fake adapter's adopt.sh failed"
	stderr_has "undoing the adoption"
	assert_eq "" "$(git status --porcelain --ignored | grep -v '^!! .fixture/$')" "the failed run left files behind"
	[ -z "$(git config core.hooksPath)" ] || fail "the failed run left core.hooksPath set"
	run_cmd bash factory/core/adopt.sh fake
	assert_status 1
	stderr_has "the fake adapter's adopt.sh failed"
}

test_labels_go_through_the_label_command() {
	adopt_project
	printf '#!/usr/bin/env bash\nprintf "%%s|%%s|%%s\\n" "$@" >> "%s/labels"\n' "$TEST_TMP" > "$TEST_TMP/label.sh"
	FACTORY_LABEL_CMD="bash $TEST_TMP/label.sh" run_cmd bash factory/core/adopt.sh fake
	assert_status 0
	assert_eq "spec approved playtest" "$(cut -d'|' -f1 "$TEST_TMP/labels" | tr '\n' ' ' | sed 's/ $//')" "labels created"
	grep -q '^approved|[0-9a-f]\{6\}|The human approved this Spec$' "$TEST_TMP/labels" || fail "label arguments:"$'\n'"$(cat "$TEST_TMP/labels")"
}

test_without_a_label_command_the_labels_are_listed() {
	adopt_project
	adopt
	assert_status 0
	stderr_has "create the label 'spec'"
	stderr_has "create the label 'approved'"
	stderr_has "create the label 'playtest'"
}

test_a_gitignored_local_env_adds_no_gitignore_line() {
	adopt_project
	printf '/.fixture/\n/tools/verify/local.env\n' > .gitignore
	git commit -q -am "ignore local.env" || fail "could not commit"
	adopt
	assert_status 0
	assert_eq 1 "$(grep -c 'local.env' .gitignore)" ".gitignore gained a second local.env line"
}

# --- the AGENTS.md section ---

agents() {
	run_cmd bash factory/core/agents.sh "$@"
}

test_the_agents_section_sits_between_markers_after_the_project_text() {
	adopt_project
	agents generate
	assert_status 0
	assert_eq "# AGENTS.md" "$(head -n 1 AGENTS.md)" "the project's heading moved"
	grep -qxF "The project's own words." AGENTS.md || fail "the project's text is gone"
	sed -n "/^<!-- factory:begin/,/^<!-- factory:end -->\$/p" AGENTS.md | sed '1d;$d' > "$TEST_TMP/section"
	cmp -s factory/core/templates/agents-section.md "$TEST_TMP/section" || fail "the section isn't the template"
	assert_eq "$AGENTS_END" "$(tail -n 1 AGENTS.md)" "the section isn't last"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_regenerating_the_agents_section_changes_nothing() {
	adopt_project
	agents generate
	cp AGENTS.md "$TEST_TMP/first"
	agents generate
	assert_status 0
	cmp -s "$TEST_TMP/first" AGENTS.md || fail "a second generate changed AGENTS.md"
	agents check
	assert_status 0
	assert_eq "" "$out" "check printed findings"
}

test_generate_rewrites_only_the_section() {
	adopt_project
	agents generate
	sed -i "s/^## Factory\$/## Edited by hand/" AGENTS.md
	echo "Words after the section." >> AGENTS.md
	agents check
	assert_status 1
	assert_eq "AGENTS.md:1 agents-section the factory section differs from factory/core/templates/agents-section.md; run bash factory/core/agents.sh generate" "$out"
	agents generate
	assert_status 0
	grep -qxF "## Factory" AGENTS.md || fail "the section wasn't restored"
	! grep -qxF "## Edited by hand" AGENTS.md || fail "the hand edit survived"
	assert_eq "Words after the section." "$(tail -n 1 AGENTS.md)" "the text after the section is gone"
	grep -qxF "The project's own words." AGENTS.md || fail "the text before the section is gone"
}

test_a_missing_agents_md_is_created() {
	adopt_project
	git rm -q AGENTS.md
	agents generate
	assert_status 0
	assert_eq "# AGENTS.md" "$(head -n 1 AGENTS.md)" "no heading"
	grep -qxF "$AGENTS_BEGIN" AGENTS.md || fail "no section"
}

test_broken_markers_are_refused() {
	adopt_project
	printf '%s\n' "$AGENTS_BEGIN" >> AGENTS.md
	cp AGENTS.md "$TEST_TMP/before"
	agents generate
	assert_status 1
	cmp -s "$TEST_TMP/before" AGENTS.md || fail "generate wrote over broken markers"
	agents check
	assert_status 1
	assert_line "AGENTS.md:1 agents-section needs one factory:begin marker line followed by one factory:end line, or neither"
}

test_agents_sh_usage() {
	adopt_project
	agents
	assert_status 2
	agents write
	assert_status 2
}

test_adoption_generates_the_verify_skill_when_the_adapter_has_a_generator() {
	adopt_project
	fake_generator
	adopt
	assert_status 0
	grep -qxF "name: verify-my-game" .claude/skills/verify-my-game/SKILL.md || fail "no verify-my-game skill"
	git diff --cached --name-only | grep -qxF .claude/skills/verify-my-game/SKILL.md || fail "the skill isn't staged"
}

test_adoption_keeps_a_verify_skill_the_project_has() {
	adopt_project
	fake_generator
	mkdir -p .claude/skills/verify-my-game
	echo "the project's skill" > .claude/skills/verify-my-game/SKILL.md
	git add -A && git commit -q -m "own skill" || fail "could not commit"
	adopt
	assert_status 0
	assert_eq "the project's skill" "$(cat .claude/skills/verify-my-game/SKILL.md)" "the skill was overwritten"
	stderr_has "kept .claude/skills/verify-my-game"
}

test_adoption_without_a_generator_writes_no_verify_skill() {
	adopt_project
	adopt
	assert_status 0
	[ ! -e .claude/skills/verify-my-game ] || fail "a verify skill appeared without a generator"
}

# install.sh copies factory/ in uncommitted and runs adopt.sh with FACTORY_INSTALL=1:
# that factory/ is no dirt, any other change still is, and its tag and upstream
# are recorded.
test_an_install_adopts_over_an_uncommitted_factory_and_records_tag_and_upstream() {
	adopt_project
	git rm -r -q --cached factory && git commit -q -m "no factory yet" || fail "could not untrack the factory"
	adopt
	assert_status 1
	stderr_has "the tree is dirty"
	echo two > src/a.txt
	run_cmd env FACTORY_INSTALL=1 bash factory/core/adopt.sh fake
	assert_status 1
	stderr_has "the tree is dirty outside factory/"
	git checkout -q src/a.txt
	run_cmd env FACTORY_INSTALL=1 FACTORY_INSTALL_TAG=v0.1.0 FACTORY_INSTALL_UPSTREAM=git@example.com:me/factory.git bash factory/core/adopt.sh fake
	assert_status 0
	assert_eq "version $(cat factory/VERSION)
adapter fake
tag v0.1.0
upstream git@example.com:me/factory.git" "$(head -n 4 tools/verify/factory-version)" "factory-version"
	assert_eq "" "$(git status --porcelain | grep -v '^[AM] ')" "adoption left files unstaged"
}
