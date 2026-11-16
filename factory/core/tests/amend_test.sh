# amend.sh: an amend made in an Adopted project's vendored factory/ (adopt_project,
# then adopt.sh, committed). record re-records factory/ and refreshes what it
# installs, check finds what record would change, land checks, tests, verifies
# and pushes, against a bare remote and a stand-in for the full suite.

AGAIN="run bash factory/core/amend.sh record"

amend() {
	run_cmd bash factory/core/amend.sh "$@"
}

# tree_sums [dir...]: every file under the dirs with its blob id, sorted.
tree_sums() {
	find "$@" -type f | LC_ALL=C sort | while IFS= read -r f; do
		printf '%s %s\n' "$(git hash-object "$f")" "$f"
	done
}

# assert_clean_check: amend.sh check passes with no finding.
# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
assert_clean_check() {
	amend check
	assert_status 0
	assert_eq "" "$out" "check found something"
}

# --- record ---

test_record_installs_and_refreshes_the_copies_and_records_factory() {
	adopted
	echo "an amended line" >> factory/skills/factory-run/drift.md
	mkdir -p factory/skills/new-skill && printf -- '---\nname: new-skill\ndescription: New.\n---\n' > factory/skills/new-skill/SKILL.md
	echo "A new rule for <stack> in <project>." >> factory/agents/driver.md
	echo "echo amended entry point" >> factory/core/templates/verify.sh
	amend record
	assert_status 0
	assert_eq "installed .claude/skills/new-skill/SKILL.md
recorded tools/verify/factory-version
refreshed .claude/agents/driver.md
refreshed .claude/skills/factory-run/drift.md
refreshed tools/verify.sh" "$(printf '%s\n' "$out" | LC_ALL=C sort)" "what record printed"
	cmp -s factory/skills/factory-run/drift.md .claude/skills/factory-run/drift.md || fail "the skill's copy wasn't refreshed"
	cmp -s factory/skills/new-skill/SKILL.md .claude/skills/new-skill/SKILL.md || fail "the new skill wasn't installed"
	cmp -s factory/core/templates/verify.sh tools/verify.sh || fail "tools/verify.sh wasn't refreshed"
	assert_eq "A new rule for fake in my-game." "$(tail -n 1 .claude/agents/driver.md)" "the driver wasn't rendered"
	assert_eq "version $(cat factory/VERSION)"$'\n'"adapter fake" "$(head -n 2 tools/verify/factory-version)" "factory-version's header"
	assert_eq "file $(git hash-object factory/skills/new-skill/SKILL.md) factory/skills/new-skill/SKILL.md" \
		"$(grep ' factory/skills/new-skill/SKILL.md$' tools/verify/factory-version)" "the record of the new file"
	git diff --cached --quiet || fail "record staged something"
	assert_clean_check
}

test_a_second_record_changes_nothing() {
	adopted
	echo "an amended line" >> factory/skills/repro-first/SKILL.md
	amend record
	assert_status 0
	before="$(tree_sums factory tools .claude AGENTS.md)"
	amend record
	assert_status 0
	assert_eq "" "$out" "the second record printed changes"
	assert_eq "$before" "$(tree_sums factory tools .claude AGENTS.md)" "the second record changed files"
}

# A synced project's record names its tag, which record keeps.
test_record_keeps_the_version_adapter_and_tag_lines() {
	adopted
	sed -i '2a tag v1' tools/verify/factory-version
	git commit -q -am "synced to v1" || fail "could not commit"
	echo "an amended line" >> factory/core/verify.sh
	amend record
	assert_status 0
	assert_eq "version $(cat factory/VERSION)"$'\n'"adapter fake"$'\n'"tag v1" "$(head -n 3 tools/verify/factory-version)" "factory-version's header"
	assert_eq "file $(git hash-object factory/core/verify.sh) factory/core/verify.sh" \
		"$(grep ' factory/core/verify.sh$' tools/verify/factory-version)" "the record of the amended file"
}

# Every copy follows the factory, an edit the project made to one included; a
# seed's copy is the project's, written only when it is missing.
test_record_overwrites_an_edited_copy_but_never_a_seed() {
	adopted
	echo "the project's edit" >> .claude/skills/factory-run/editor.md
	echo "# the project's ps1" >> tools/verify.ps1
	git commit -q -am "own edits" || fail "could not commit"
	echo "# an amended template" >> factory/core/templates/verify.ps1
	amend record
	assert_status 0
	assert_line "refreshed .claude/skills/factory-run/editor.md"
	assert_no_line "refreshed tools/verify.ps1"
	cmp -s factory/skills/factory-run/editor.md .claude/skills/factory-run/editor.md || fail "the edited copy wasn't refreshed"
	assert_eq "# the project's ps1" "$(tail -n 1 tools/verify.ps1)" "the seed's copy was overwritten"
	assert_clean_check
	git rm -q tools/verify.ps1 || fail "could not remove the seed's copy"
	amend record
	assert_status 0
	assert_line "installed tools/verify.ps1"
	cmp -s factory/core/templates/verify.ps1 tools/verify.ps1 || fail "the missing seed's copy wasn't written"
	# A seed the factory now always writes is no longer the project's.
	sed -i 's#"seed core/templates/verify.ps1 tools/verify.ps1"#"replace core/templates/verify.ps1 tools/verify.ps1"#' factory/core/lib/vendor.sh
	grep -q '"replace core/templates/verify.ps1' factory/core/lib/vendor.sh || fail "the list still seeds verify.ps1"
	echo "# the project's ps1 again" >> tools/verify.ps1
	amend record
	assert_status 0
	assert_line "refreshed tools/verify.ps1"
}

test_record_removes_the_copies_of_what_the_factory_dropped() {
	adopted
	[ -f .claude/agents/asset-fetcher.md ] || fail "the adoption installed no asset fetcher"
	git rm -q -r factory/skills/factory-spec factory/skills/factory-run/editor.md factory/agents/asset-fetcher.md || fail "could not drop files"
	sed -i '/agents\/asset-fetcher.md/d; /core\/templates\/verify.ps1/d' factory/core/lib/vendor.sh
	amend check
	assert_status 1
	assert_line "factory/skills/factory-spec/SKILL.md:1 factory-record missing since tools/verify/factory-version was recorded; $AGAIN"
	assert_line ".claude/skills/factory-spec/SKILL.md:1 factory-copy factory/ no longer installs it; $AGAIN"
	amend record
	assert_status 0
	assert_line "removed .claude/skills/factory-spec/SKILL.md"
	assert_line "removed .claude/skills/factory-run/editor.md"
	assert_line "removed .claude/agents/asset-fetcher.md"
	[ ! -e .claude/skills/factory-spec ] || fail "the dropped skill's folder is still there"
	[ -f .claude/skills/factory-run/SKILL.md ] || fail "a kept file's copy went too"
	[ -f tools/verify.ps1 ] || fail "the copy of a seed the factory dropped was removed"
	assert_clean_check
}

# The third-party frontend-design skill is installed as it came, beside the
# factory's own skills, and the designer subagent with the rest; record puts
# back a copy that went missing or was edited.
test_record_installs_the_vendored_frontend_design_and_the_designer() {
	adopted
	local f
	for f in SKILL.md LICENSE.txt; do
		cmp -s "factory/third-party/frontend-design/$f" ".claude/skills/frontend-design/$f" || fail "the adoption didn't install frontend-design/$f as it came"
	done
	[ ! -e .claude/skills/frontend-design/README.md ] && [ ! -e .claude/skills/third-party ] || fail "the provenance note was installed as a skill"
	grep -qx 'model: claude-fable-5-2' .claude/agents/designer.md || fail "the designer wasn't installed on Fable"
	! grep -q '<project>' .claude/agents/designer.md || fail "the designer's <project> wasn't filled in"
	if grep -qF frontend-design .claude/agents/editor-sonnet.md; then fail "the installed Editor names frontend-design"; fi
	rm -r .claude/skills/frontend-design
	echo "the project's edit" >> .claude/agents/designer.md
	amend check
	assert_status 1
	assert_line ".claude/skills/frontend-design/SKILL.md:1 factory-copy missing; factory/ installs it; $AGAIN"
	assert_line ".claude/agents/designer.md:1 factory-copy differs from what factory/ installs; $AGAIN"
	amend record
	assert_status 0
	assert_eq "installed .claude/skills/frontend-design/LICENSE.txt
installed .claude/skills/frontend-design/SKILL.md
refreshed .claude/agents/designer.md" "$(printf '%s\n' "$out" | LC_ALL=C sort)" "what record printed"
	cmp -s factory/third-party/frontend-design/SKILL.md .claude/skills/frontend-design/SKILL.md || fail "record didn't install the skill as it came"
	assert_clean_check
}

# record writes factory/'s files into git, so a record taken over an uncommitted
# amend can be read back: here the agent list an earlier record saw.
test_record_reads_back_an_uncommitted_record() {
	adopted
	printf -- '---\nname: extra\n---\nFor <project>.\n' > factory/agents/extra.md
	sed -i 's#^\(\t*\)"agent agents/driver.md .claude/agents/driver.md" \\$#&\n\1"agent agents/extra.md .claude/agents/extra.md" \\#' factory/core/lib/vendor.sh
	grep -q 'agents/extra.md' factory/core/lib/vendor.sh || fail "the list names no extra agent"
	amend record
	assert_status 0
	assert_line "installed .claude/agents/extra.md"
	git checkout -q factory/core/lib/vendor.sh && rm factory/agents/extra.md || fail "could not drop the extra agent"
	amend record
	assert_status 0
	assert_line "removed .claude/agents/extra.md"
	assert_clean_check
}

# The step scripts are the project's: record writes none of them, and names each
# changed template the project's copy differs from.
test_record_says_which_template_changes_to_port() {
	adopted
	cmp -s factory/adapters/fake/tools/verify/lint tools/verify/lint || fail "the adoption seeded a different lint"
	echo "# an amended check" >> factory/adapters/fake/tools/verify/lint
	echo "# an amended check" >> factory/adapters/fake/tools/verify/format
	echo "# an amended check" >> tools/verify/format
	amend record
	assert_status 0
	stderr_has "port factory/adapters/fake/tools/verify/lint to tools/verify/lint by hand"
	! grep -q "verify/format" "$TEST_TMP/stderr" || fail "a ported template was named: $(cat "$TEST_TMP/stderr")"
	assert_no_line "refreshed tools/verify/lint"
	[ "$(tail -n 1 tools/verify/lint)" != "# an amended check" ] || fail "record wrote the project's step script"
}

test_record_regenerates_the_agents_section_and_the_hook_config() {
	adopted
	echo "- **Amended:** a new line." >> factory/core/templates/agents-section.md
	sed -i 's/NotebookRead|LS|Skill)/NotebookRead|LS|Skill|Task)/' factory/core/hooks/claude-hooks.json
	amend check
	assert_status 1
	assert_line "AGENTS.md:1 agents-section the factory section differs from factory/core/templates/agents-section.md; run bash factory/core/agents.sh generate"
	amend record
	assert_status 0
	assert_line "regenerated AGENTS.md"
	assert_line "regenerated .claude/settings.json"
	grep -qxF -- "- **Amended:** a new line." AGENTS.md || fail "the AGENTS.md section wasn't regenerated"
	grep -qF 'NotebookRead|LS|Skill|Task)' .claude/settings.json || fail "the Claude hook config wasn't regenerated"
	assert_clean_check
}

# A project that synced from a release with the Cursor Editor still has its
# generated files; record removes them and says so.
test_record_removes_the_retired_cursor_files() {
	adopted
	mkdir -p .cursor
	printf '{\n  "hooks": {\n    "stop": [{ "command": "bash factory/core/hooks/cursor-stop.sh" }]\n  }\n}\n' > .cursor/hooks.json
	printf '{\n  "permissions": {\n    "allow": ["Shell(bash tools/verify.sh)"],\n    "deny": []\n  }\n}\n' > .cursor/cli.json
	git add .cursor && git commit -q -m "the Cursor files" || fail "could not commit the Cursor files"
	amend record
	assert_status 0
	assert_line "removed .cursor/hooks.json"
	assert_line "removed .cursor/cli.json"
	[ ! -e .cursor/hooks.json ] && [ ! -e .cursor/cli.json ] || fail "the retired Cursor files are still there"
}

# The verify-<project> skill is generated, and a generator that fails changes
# nothing rather than reading as a dropped skill.
test_record_refreshes_the_generated_skill_and_stops_on_a_failing_generator() {
	adopt_project
	fake_generator
	run_cmd bash factory/core/adopt.sh fake
	assert_status 0
	git commit -q -m adopt || fail "could not commit the adoption"
	sed -i 's/Drive the fake build\./Drive the fake build, amended./' factory/adapters/fake/verify-skill.sh
	amend record
	assert_status 0
	assert_line "refreshed .claude/skills/verify-my-game/SKILL.md"
	grep -qxF "description: Drive the fake build, amended." .claude/skills/verify-my-game/SKILL.md || fail "the generated skill wasn't refreshed"
	echo "exit 1" >> factory/adapters/fake/verify-skill.sh
	before="$(tree_sums tools .claude)"
	amend record
	assert_status 1
	stderr_has "could not generate .claude/skills/verify-my-game"
	assert_eq "$before" "$(tree_sums tools .claude)" "the failed record changed files"
}

# A file that shares the generated skill's folder can't hide a failing generator.
test_record_stops_on_a_failing_generator_beside_a_skill_file_in_its_folder() {
	adopt_project
	fake_generator
	echo 'echo extra > "$2/extra.md"' >> factory/adapters/fake/verify-skill.sh
	git commit -q -am "a second generated file" || fail "could not commit"
	run_cmd bash factory/core/adopt.sh fake
	assert_status 0
	[ -f .claude/skills/verify-my-game/extra.md ] || fail "the generator wrote no extra.md"
	git add -A && git commit -q -m adopt || fail "could not commit the adoption"
	mkdir -p factory/skills/verify-my-game && cp .claude/skills/verify-my-game/SKILL.md factory/skills/verify-my-game/SKILL.md
	echo "exit 1" >> factory/adapters/fake/verify-skill.sh
	before="$(tree_sums tools .claude)"
	amend record
	assert_status 1
	stderr_has "could not generate .claude/skills/verify-my-game"
	assert_eq "$before" "$(tree_sums tools .claude)" "the failed record changed files"
	amend check
	assert_status 1
	stderr_has "could not generate .claude/skills/verify-my-game"
}

# The generated skill's folder is its generator's: a file it wrote for the
# project as it was, and no longer writes, goes.
test_record_removes_a_file_the_generator_no_longer_writes() {
	adopt_project
	fake_generator
	echo 'if [ -f src/extra.txt ]; then echo generated > "$2/extra.md"; fi' >> factory/adapters/fake/verify-skill.sh
	echo extra > src/extra.txt
	git add -A && git commit -q -m "a file generated for src/extra.txt" || fail "could not commit"
	run_cmd bash factory/core/adopt.sh fake
	assert_status 0
	[ -f .claude/skills/verify-my-game/extra.md ] || fail "the generator wrote no extra.md"
	git add -A && git commit -q -m adopt || fail "could not commit the adoption"
	git rm -q src/extra.txt || fail "could not drop the product file"
	amend check
	assert_status 1
	assert_eq ".claude/skills/verify-my-game/extra.md:1 factory-copy factory/ no longer installs it; $AGAIN" "$out" "check's findings"
	amend record
	assert_status 0
	assert_eq "removed .claude/skills/verify-my-game/extra.md" "$out" "what record printed"
	[ -f .claude/skills/verify-my-game/SKILL.md ] || fail "the generated SKILL.md went too"
	assert_clean_check
}

# A copy that is a symlink is replaced by a file; what it points to, and what
# stands where a file should, are left alone.
test_record_replaces_a_symlinked_copy_and_never_writes_its_target() {
	adopted
	cp tools/verify/lint "$TEST_TMP/lint.before"
	rm .claude/skills/factory-run/editor.md
	ln -s "$PWD/tools/verify/lint" .claude/skills/factory-run/editor.md
	rm .claude/skills/repro-first/SKILL.md
	ln -s "$TEST_TMP/outside.md" .claude/skills/repro-first/SKILL.md
	amend check
	assert_status 1
	assert_line ".claude/skills/factory-run/editor.md:1 factory-copy differs from what factory/ installs; $AGAIN"
	assert_line ".claude/skills/repro-first/SKILL.md:1 factory-copy differs from what factory/ installs; $AGAIN"
	amend record
	assert_status 0
	assert_line "refreshed .claude/skills/factory-run/editor.md"
	assert_line "refreshed .claude/skills/repro-first/SKILL.md"
	cmp -s "$TEST_TMP/lint.before" tools/verify/lint || fail "record wrote through the symlink into tools/verify/lint"
	[ ! -e "$TEST_TMP/outside.md" ] || fail "record wrote through the dangling symlink"
	[ ! -L .claude/skills/factory-run/editor.md ] && cmp -s factory/skills/factory-run/editor.md .claude/skills/factory-run/editor.md ||
		fail "the symlink wasn't replaced by the factory's file"
	assert_clean_check
	rm .claude/agents/driver.md && mkdir .claude/agents/driver.md
	before="$(tree_sums tools .claude)"
	amend record
	assert_status 1
	stderr_has ".claude/agents/driver.md is not a file; move it out of the way"
	assert_eq "$before" "$(tree_sums tools .claude)" "record changed files"
}

test_record_and_check_refuse_a_project_that_has_not_adopted() {
	adopt_project
	amend record
	assert_status 1
	stderr_has "not adopted"
	amend check
	assert_status 1
	stderr_has "not adopted"
}

test_a_bad_call_is_a_usage_error() {
	adopted
	amend
	assert_status 2
	amend sync
	assert_status 2
	amend record now
	assert_status 2
	amend land --all
	assert_status 2
	amend land --all-tests now
	assert_status 2
}

# --- check ---

test_check_passes_on_a_fresh_adoption_and_changes_nothing() {
	adopted
	before="$(tree_sums factory tools .claude)"
	assert_clean_check
	echo "an amended line" >> factory/skills/factory-run/drift.md
	rm .claude/skills/repro-first/SKILL.md
	before="$(tree_sums factory tools .claude)"
	amend check
	assert_status 1
	assert_eq "$before" "$(tree_sums factory tools .claude)" "check changed files"
	assert_eq ".claude/skills/factory-run/drift.md:1 factory-copy differs from what factory/ installs; $AGAIN
.claude/skills/repro-first/SKILL.md:1 factory-copy missing; factory/ installs it; $AGAIN
factory/skills/factory-run/drift.md:1 factory-record changed since tools/verify/factory-version was recorded; $AGAIN" "$out" "check's findings"
}

test_check_runs_the_skill_budget() {
	adopted
	mkdir -p factory/skills/long
	{
		printf -- '---\nname: long\ndescription: Long.\n---\n'
		for i in $(seq 5 101); do echo "line $i"; done
	} > factory/skills/long/SKILL.md
	amend record
	assert_status 0
	amend check
	assert_status 1
	assert_eq "factory/skills/long/SKILL.md:1 skill-too-long 101 lines; the budget is 100" "$out" "check's findings"
}

# --- land ---

# landable: adopted, origin a bare repo holding dev (named My_Game.git, so the
# project keeps its name), and an amend committed on a branch in a worktree, as
# factory-amend makes one; cd there. The amend swaps factory/core/test.sh for a
# stand-in that logs its call to $TEST_TMP/suite.log, runs $TEST_TMP/race.sh
# when there is one (in the suite's environment, its output the suite's) and
# fails while $TEST_TMP/suite-fails exists. $MAIN is the main checkout.
landable() {
	adopted
	mkdir -p "$TEST_TMP/remote"
	git init -q --bare -b dev "$TEST_TMP/remote/My_Game.git" || fail "could not make the remote"
	git remote set-url origin "$TEST_TMP/remote/My_Game.git"
	echo /.claude/worktrees/ >> .gitignore
	git commit -q -am "worktrees" || fail "could not commit"
	git push -q origin dev 2> /dev/null || fail "could not push dev"
	MAIN="$PWD"
	git worktree add -q --no-track -b amend/stand-in .claude/worktrees/amend-stand-in origin/dev 2> /dev/null || fail "could not add the worktree"
	cd .claude/worktrees/amend-stand-in || fail "could not enter the worktree"
	cat > factory/core/test.sh << 'SH'
echo "suite GODOT_BIN=${GODOT_BIN:-unset} args=$*" >> "$TEST_TMP/suite.log"
[ ! -f "$TEST_TMP/race.sh" ] || bash "$TEST_TMP/race.sh"
echo "PASS stand-in test_one"
if [ -f "$TEST_TMP/suite-fails" ]; then
	echo "FAIL stand-in test_two"
	echo "test.sh: 1 passed, 1 failed, 0 skipped"
	exit 1
fi
echo "test.sh: 1 passed, 0 failed, 0 skipped"
SH
	amend record
	assert_status 0
	git add -A && git commit -q -m "Amend the factory: a stand-in suite" -m "Release: patch" || fail "could not commit the amend"
}

# remote_dev: origin's dev SHA.
remote_dev() {
	git --git-dir="$TEST_TMP/remote/My_Game.git" rev-parse dev
}

# push_from_another_clone <file>: a clone of origin commits the file and pushes
# dev, as another landing would.
push_from_another_clone() {
	git clone -q -b dev "$TEST_TMP/remote/My_Game.git" "$TEST_TMP/other" 2> /dev/null || fail "could not clone"
	commit_in "$TEST_TMP/other" "$1" "elsewhere"
	git -C "$TEST_TMP/other" push -q origin dev 2> /dev/null || fail "could not push from the other clone"
}

test_land_checks_tests_verifies_pushes_and_fast_forwards() {
	landable
	mkdir -p .fixture
	echo 'echo "base=$FACTORY_BASE" >> "$TEST_TMP/verify.log"' > .fixture/run-deviation
	head="$(git rev-parse HEAD)"
	run_cmd env GODOT_BIN=/opt/env-godot bash factory/core/amend.sh land
	assert_status 0
	assert_eq "amend: fetch origin/dev
amend: check (bash factory/core/amend.sh check)
amend: the full suite (bash factory/core/test.sh)
test.sh: 1 passed, 0 failed, 0 skipped
amend: verify (FACTORY_BASE=HEAD bash tools/verify.sh)" "$(printf '%s\n' "$out" | sed -n '1,5p')" "the stages"
	assert_line "verify: PASS"
	assert_line "amend: landed $head on origin/dev"
	assert_line "amend: fast-forwarded dev in the main checkout ($MAIN) to $head"
	! printf '%s\n' "$out" | grep -q 'factory repo' || fail "land without an upstream line went to the factory repo"
	assert_eq "suite GODOT_BIN=/opt/env-godot args=" "$(cat "$TEST_TMP/suite.log")" "the suite's call"
	assert_eq "base=HEAD" "$(cat "$TEST_TMP/verify.log")" "verify's diff base"
	assert_eq "$head" "$(remote_dev)" "origin/dev"
	assert_eq "$head" "$(git -C "$MAIN" rev-parse dev)" "the main checkout's dev"
	cmp -s factory/core/test.sh "$MAIN/factory/core/test.sh" || fail "the main checkout's tree wasn't fast-forwarded"
}

# with_env_log: the stand-in suite logs the variables a local.env may set, as
# it sees them, to $TEST_TMP/env.log.
with_env_log() {
	# shellcheck disable=SC2016 # expanded by the stand-in
	echo 'echo "GODOT_BIN=${GODOT_BIN:-unset} NODE_BIN=${NODE_BIN:-unset} PNPM_BIN=${PNPM_BIN:-unset} FACTORY_TEST_HANG_GUARD=${FACTORY_TEST_HANG_GUARD:-unset}" >> "$TEST_TMP/env.log"' > "$TEST_TMP/race.sh"
}

# The suite gets every variable local.env sets, not only GODOT_BIN; the
# environment wins over it.
test_land_reads_all_of_local_env() {
	landable
	unset GODOT_BIN NODE_BIN PNPM_BIN FACTORY_TEST_HANG_GUARD
	with_env_log
	cp tools/verify/local.env.example tools/verify/local.env &&
		printf 'GODOT_BIN=/opt/local-env-godot\nNODE_BIN=/opt/node/bin/node\nPNPM_BIN=/opt/local-pnpm\nFACTORY_TEST_HANG_GUARD=30\n' >> tools/verify/local.env ||
		fail "could not write local.env"
	run_cmd env PNPM_BIN=/opt/env-pnpm bash factory/core/amend.sh land
	assert_status 0
	assert_eq "suite GODOT_BIN=/opt/local-env-godot args=" "$(cat "$TEST_TMP/suite.log")" "the suite's call"
	assert_eq "GODOT_BIN=/opt/local-env-godot NODE_BIN=/opt/node/bin/node PNPM_BIN=/opt/env-pnpm FACTORY_TEST_HANG_GUARD=30" "$(cat "$TEST_TMP/env.log")" "the suite's environment"
	! grep -q "neither the environment" "$TEST_TMP/stderr" || fail "land warned of a variable local.env leaves unset: $(cat "$TEST_TMP/stderr")"
}

# skips_for_missing_tools: the stand-in suite prints, besides its own lines, the
# SKIP lines of real-tool tests whose tools are missing (two Godot, one
# gdmutant, one Node), one that skips for its platform and a plain test's skip.
# After the Node skip's reason comes the next test's stdout, before its result
# line: an indented line naming another variable, which is no skip's reason.
skips_for_missing_tools() {
	cat > "$TEST_TMP/race.sh" << 'SH'
printf 'SKIP godot/arch test_a_probe_with_godot\n    GODOT_BIN is not set\n'
printf 'SKIP godot/steps test_mutants_with_gdmutant\n    no gdmutant 0.1.4 (set GDMUTANT_BIN, or put it on PATH)\n'
printf 'SKIP godot/steps test_gdunit4_runs_with_godot\n    GODOT_BIN is not set\n'
printf 'SKIP godot/isolation test_adb_with_godot\n    the stand-in adb is a shell script, and Windows Godot runs adb.exe\n'
printf 'SKIP nextjs/steps test_build_with_node\n    no Node (NODE_BIN, or node on PATH)\n'
printf '    the next test printed OTHER_VAR on its stdout\nPASS nextjs/steps test_after_the_skip\n'
printf 'SKIP stand-in test_json\n    neither jq nor python3 to validate the JSON (JQ_BIN)\n'
SH
}

# A project's land refuses when a real-tool test it ran skipped for a missing
# tool, naming the adapter, the tool and the variable; dev stays.
test_land_refuses_a_real_tool_test_skipped_for_a_missing_tool() {
	landable
	skips_for_missing_tools
	before="$(remote_dev)"
	amend land
	assert_status 1
	stderr_has "amend:   the godot adapter's godot tests: 2 skipped: GODOT_BIN is not set"
	stderr_has "amend:   the godot adapter's gdmutant tests: 1 skipped: no gdmutant 0.1.4 (set GDMUTANT_BIN, or put it on PATH)"
	stderr_has "amend:   the nextjs adapter's node tests: 1 skipped: no Node (NODE_BIN, or node on PATH)"
	stderr_has "amend: set GODOT_BIN GDMUTANT_BIN NODE_BIN (in the environment or tools/verify/local.env) so they run, then land again; dev not moved"
	! grep -q "adb\|JQ_BIN\|OTHER_VAR" "$TEST_TMP/stderr" || fail "land counted a platform's skip or a plain test's: $(cat "$TEST_TMP/stderr")"
	assert_eq "$before" "$(remote_dev)" "origin/dev moved"
}

test_land_refuses_a_dirty_tree_dev_not_contained_or_nothing_to_land() {
	landable
	echo stray > stray.txt
	amend land
	assert_status 1
	stderr_has "the tree is dirty"
	rm stray.txt
	push_from_another_clone b.txt
	moved="$(remote_dev)"
	amend land
	assert_status 1
	stderr_has "HEAD does not contain origin/dev; rebase onto it"
	assert_eq "$moved" "$(remote_dev)" "origin/dev moved"
	git reset -q --hard origin/dev || fail "could not reset"
	amend land
	assert_status 1
	stderr_has "HEAD is origin/dev; commit the amend first"
	[ ! -e "$TEST_TMP/suite.log" ] || fail "a refused land ran the suite"
}

test_land_stops_on_a_finding() {
	landable
	before="$(remote_dev)"
	echo "an unrecorded line" >> factory/skills/factory-run/drift.md
	git commit -q -am "an unrecorded amend" || fail "could not commit"
	amend land
	assert_status 1
	assert_line "factory/skills/factory-run/drift.md:1 factory-record changed since tools/verify/factory-version was recorded; $AGAIN"
	stderr_has "check failed"
	[ ! -e "$TEST_TMP/suite.log" ] || fail "land ran the suite after a finding"
	assert_eq "$before" "$(remote_dev)" "origin/dev moved"
}

test_land_stops_on_a_red_suite_or_a_red_verify() {
	landable
	before="$(remote_dev)"
	touch "$TEST_TMP/suite-fails"
	amend land
	assert_status 1
	assert_line "FAIL stand-in test_two"
	assert_no_line "PASS stand-in test_one"
	stderr_has "the full suite failed (exit 1"
	assert_eq "$before" "$(remote_dev)" "origin/dev moved on a red suite"
	rm "$TEST_TMP/suite-fails"
	mkdir -p .fixture && echo "src/a.txt:1 fake-rule a finding" > .fixture/fail-lint
	amend land
	assert_status 1
	assert_line "verify: FAILED at step lint"
	stderr_has "the gate is red"
	assert_eq "$before" "$(remote_dev)" "origin/dev moved on a red verify"
}

# While the Baseline holds findings the full verify is red by design, so land
# gates on the Baseline instead, as land.sh does in Partial mode.
test_land_gates_on_the_baseline_while_it_holds_findings() {
	landable
	echo "src/a.txt fake-rule old debt" > tools/verify/ratchet/baseline.txt
	git commit -q -am "a Baseline entry" || fail "could not commit"
	mkdir -p .fixture && echo "src/a.txt:1 fake-rule old debt" > .fixture/fail-lint
	head="$(git rev-parse HEAD)"
	amend land
	assert_status 0
	assert_line "amend: the Baseline gate (FACTORY_BASE=HEAD bash factory/core/baseline.sh gate): the Baseline holds findings, so the full verify is red by design"
	assert_no_line "amend: verify (FACTORY_BASE=HEAD bash tools/verify.sh)"
	assert_eq "$head" "$(remote_dev)" "origin/dev"
	echo "src/a.txt:2 fake-rule new debt" >> .fixture/fail-lint
	commit_in "$PWD" c.txt "a second amend"
	amend land
	assert_status 1
	stderr_has "the gate is red"
	assert_eq "$head" "$(remote_dev)" "origin/dev moved past a finding outside the Baseline"
}

# The stages check the tree, and the push sends HEAD: a stage that changes a
# tracked file stops the landing.
test_land_stops_when_a_stage_changes_a_tracked_file() {
	landable
	before="$(remote_dev)"
	mkdir -p .fixture && echo 'echo fixed > src/a.txt' > .fixture/run-smoke
	amend land
	assert_status 1
	stderr_has "a stage changed HEAD or a tracked file"
	assert_eq "$before" "$(remote_dev)" "origin/dev moved"
}

# A push to two URLs can land on one and be refused by the other.
test_land_refuses_a_remote_with_two_push_urls() {
	landable
	before="$(remote_dev)"
	git init -q --bare -b dev "$TEST_TMP/second.git" || fail "could not make a second remote"
	git config remote.origin.pushurl "$TEST_TMP/remote/My_Game.git"
	git config --add remote.origin.pushurl "$TEST_TMP/second.git"
	amend land
	assert_status 1
	stderr_has "origin has more than one push URL"
	[ ! -e "$TEST_TMP/suite.log" ] || fail "land ran the suite"
	assert_eq "$before" "$(remote_dev)" "origin/dev moved"
}

# Another landing between the fetch and the push: the push is refused and
# nothing moves.
test_land_says_to_rebase_when_the_push_is_refused() {
	landable
	mkdir -p .fixture
	cat > .fixture/run-smoke << 'SH'
git clone -q -b dev "$TEST_TMP/remote/My_Game.git" "$TEST_TMP/racer" && cd "$TEST_TMP/racer" &&
	echo raced > raced.txt && git add raced.txt && git commit -q -m raced && git push -q origin dev
SH
	main_dev="$(git -C "$MAIN" rev-parse dev)"
	amend land
	assert_status 1
	stderr_has "the push to origin/dev was refused (did it move?); fetch, rebase onto it and land again"
	assert_eq "raced" "$(git --git-dir="$TEST_TMP/remote/My_Game.git" show dev:raced.txt)" "the other landing's commit isn't on origin/dev"
	assert_eq "$main_dev" "$(git -C "$MAIN" rev-parse dev)" "the main checkout's dev moved"
}

test_land_leaves_dev_alone_off_dev_or_with_uncommitted_changes() {
	landable
	main_dev="$(git -C "$MAIN" rev-parse dev)"
	git -C "$MAIN" checkout -q -b elsewhere || fail "could not leave dev"
	amend land
	assert_status 0
	assert_line "amend: left dev alone: the main checkout ($MAIN) is on elsewhere"
	assert_eq "$main_dev" "$(git -C "$MAIN" rev-parse dev)" "the main checkout's dev moved"
	git -C "$MAIN" checkout -q dev || fail "could not go back to dev"
	echo two > "$MAIN/src/a.txt"
	commit_in "$PWD" c.txt "a second amend"
	head="$(git rev-parse HEAD)"
	amend land
	assert_status 0
	assert_line "amend: left dev alone: the main checkout ($MAIN) has uncommitted changes; once they are put away, git merge --ff-only $head there"
	assert_eq "$head" "$(remote_dev)" "origin/dev"
	assert_eq "$main_dev" "$(git -C "$MAIN" rev-parse dev)" "the main checkout's dev moved"
}

# --- release, and land with the factory's repo ---

# with_upstream_line <url>: factory-version names the factory's repo.
with_upstream_line() {
	sed -i "2a upstream $1" tools/verify/factory-version
}

# at_version <version>: factory/VERSION is <version>, recorded and committed,
# and origin/dev is that commit: the base a release reads the amends since.
at_version() {
	echo "$1" > factory/VERSION
	amend record
	git commit -q -am "at $1" || fail "could not commit"
	git update-ref refs/remotes/origin/dev HEAD || fail "could not set origin/dev"
}

test_release_bumps_the_patch_and_records_the_tag_keeping_upstream() {
	adopted
	with_upstream_line "$TEST_TMP/factory.git"
	at_version 0.1.0
	amend release
	assert_status 0
	assert_line "released 0.1.1 (was 0.1.0): patch, no amend commit since origin/dev; commit it as: Release factory 0.1.1"
	assert_line "recorded tools/verify/factory-version"
	assert_eq "0.1.1" "$(cat factory/VERSION)" "factory/VERSION"
	assert_eq "version 0.1.1
adapter fake
tag v0.1.1
upstream $TEST_TMP/factory.git" "$(head -n 4 tools/verify/factory-version)" "factory-version"
	git diff --cached --quiet || fail "release staged something"
	assert_clean_check
	amend release 0.3.0
	assert_status 0
	assert_line "released 0.3.0 (was 0.1.0): set by hand, over the amends' patch (no amend commit since origin/dev); commit it as: Release factory 0.3.0"
	assert_eq "0.3.0" "$(cat factory/VERSION)" "an explicit version"
	assert_eq "tag v0.3.0" "$(grep '^tag ' tools/verify/factory-version)" "the explicit version's tag"
}

# A bare release bumps by the amends' Release: trailers; release patch or minor
# is taken only when the amends make that kind.
test_release_bumps_by_the_amends_trailers() {
	adopted
	with_upstream_line "$TEST_TMP/factory.git"
	at_version 0.1.4
	echo "a line" >> factory/README.md
	git commit -q -am "Amend the factory: a line" -m "Release: patch" || fail "could not commit"
	before="$(tree_sums factory tools)"
	amend release minor
	assert_status 1
	stderr_has "release minor makes a minor, and the amends make a patch (the one amend commit says Release: patch): if one of the amends is a minor, give it the trailer Release: minor; else run bash factory/core/amend.sh release, which bumps by the amends' trailers; for a version no patch or minor step gives (such as 1.0.0), use release <version>; nothing released"
	amend release 0.2.0
	assert_status 1
	stderr_has "release 0.2.0 makes a minor, and the amends make a patch"
	amend release major
	assert_status 1
	stderr_has "'major' is not patch, minor or <major>.<minor>.<patch>"
	assert_eq "$before" "$(tree_sums factory tools)" "a refused release changed files"
	amend release patch
	assert_status 0
	assert_line "released 0.1.5 (was 0.1.4): patch, the one amend commit says Release: patch; commit it as: Release factory 0.1.5"
	git checkout -q -- factory tools || fail "could not drop the release"
	echo "another line" >> factory/README.md
	git commit -q -am "Amend the factory: a check" -m "Release: minor" || fail "could not commit"
	minor="$(git rev-parse --short=7 HEAD)"
	amend release patch
	assert_status 1
	stderr_has "release patch makes a patch, and the amends make a minor (from $minor (Release: minor)): run bash factory/core/amend.sh release, which bumps by the amends' trailers; nothing released"
	amend release
	assert_status 0
	assert_line "released 0.2.0 (was 0.1.4): minor, from $minor (Release: minor); commit it as: Release factory 0.2.0"
	assert_eq "tag v0.2.0" "$(grep '^tag ' tools/verify/factory-version)" "the minor's tag"
	amend release
	assert_status 0
	assert_eq "0.2.0" "$(cat factory/VERSION)" "a second release bumped again; it bumps from origin/dev's"
}

test_release_refuses_a_version_not_greater_or_no_upstream() {
	adopted
	at_version 0.2.0
	amend release patch
	assert_status 1
	stderr_has "records no upstream"
	with_upstream_line "$TEST_TMP/factory.git"
	before="$(tree_sums factory tools)"
	for v in 0.2.0 0.1.9 0.1.10 1.0 v0.3.0; do
		amend release "$v"
		assert_status 1
	done
	amend release 0.1.9
	stderr_has "0.1.9 is not greater than factory/VERSION on origin/dev (0.2.0)"
	amend release 1.0
	stderr_has "'1.0' is not patch, minor or <major>.<minor>.<patch>"
	assert_eq "$before" "$(tree_sums factory tools)" "a refused release changed files"
	amend release 0.10.0
	assert_status 0
	assert_eq "0.10.0" "$(cat factory/VERSION)" "0.10.0 is greater than 0.2.0"
}

# With no origin/dev, release has no base to read the amends since.
test_release_needs_the_base_branch() {
	adopted
	with_upstream_line "$TEST_TMP/factory.git"
	git update-ref -d refs/remotes/origin/dev 2> /dev/null
	amend release
	assert_status 1
	stderr_has "no origin/dev to read the amends since; git fetch origin, then release again"
}

# landable_upstream: landable, plus the factory's repo, $TEST_TMP/factory.git: a
# bare repo whose main holds origin/dev's factory/ at its root (the fixtures'
# version, 0.1.0), tagged v0.1.0,
# named by factory-version's upstream line. The amend (the stand-in suite) is by
# Ada, dated 2001; a second commit by Bob edits only src/ (no factory/ change);
# then the release, 0.1.1. $UP is the factory repo. With `workspace`, the factory
# repo is in its workspace layout: its main holds origin/dev's factory/ under
# factory/, beside a .factory-repo and a CLAUDE.md of its own.
landable_upstream() {
	landable
	UP="$TEST_TMP/factory.git"
	git commit -q --amend --no-edit --author="Ada <ada@example.com>" --date="2001-02-03T04:05:06+0700" ||
		fail "could not set the amend's author"
	local base tree="origin/dev:factory"
	if [ "${1:-}" = workspace ]; then
		tree="$(printf '100644 blob %s\t.factory-repo\n100644 blob %s\tCLAUDE.md\n040000 tree %s\tfactory\n' \
			"$(echo "the workspace" | git hash-object -w --stdin)" "$(echo "# the factory repo" | git hash-object -w --stdin)" \
			"$(git rev-parse origin/dev:factory)" | git mktree)" || fail "could not make the workspace's tree"
	fi
	base="$(git commit-tree "$tree" -m "factory 0.1.0")" || fail "could not make the factory's commit"
	git init -q --bare -b main "$UP" && git push -q "$UP" "$base:refs/heads/main" 2> /dev/null &&
		git tag -a factory-v0.1.0 -m "factory 0.1.0" "$base" && git push -q "$UP" "refs/tags/factory-v0.1.0:refs/tags/v0.1.0" 2> /dev/null &&
		git tag -d factory-v0.1.0 > /dev/null || fail "could not make the factory's repo"
	echo two > src/a.txt
	git commit -q --author="Bob <bob@example.com>" -am "Project only" || fail "could not commit"
	with_upstream_line "$UP"
	amend release patch
	assert_status 0
	git add -A && git commit -q -m "Release factory 0.1.1" || fail "could not commit the release"
}

# up <git args...>: git in the factory repo.
up() {
	git --git-dir="$UP" "$@"
}

test_land_publishes_to_the_factory_repo_then_pushes_the_project() {
	landable_upstream
	head="$(git rev-parse HEAD)"
	amend land
	assert_status 0
	assert_eq "amend: fetch origin/dev
amend: fetch the factory repo's main ($UP)
amend: the release, 0.1.1: a patch from 0.1.0, as the amends make (the one amend commit says Release: patch)
amend: check (bash factory/core/amend.sh check)" "$(printf '%s\n' "$out" | sed -n '1,4p')" "the first stages"
	assert_line "amend: publish to the factory repo ($UP): 2 commits on its main, then the tag v0.1.1"
	assert_line "amend: published v0.1.1 to the factory repo: main at $(up rev-parse main)"
	assert_line "amend: landed $head on origin/dev"
	[ "$(printf '%s\n' "$out" | grep -n '^amend: published ' | cut -d: -f1)" -lt "$(printf '%s\n' "$out" | grep -n '^amend: push to origin/dev' | cut -d: -f1)" ] ||
		fail "the project was pushed before the factory repo"
	assert_eq "$head" "$(remote_dev)" "origin/dev"
	# The replay: one commit per factory/ change, oldest first, on the old main.
	assert_eq "Release factory 0.1.1
Amend the factory: a stand-in suite
factory 0.1.0" "$(up log --format=%s main)" "the factory repo's history"
	assert_eq "Ada <ada@example.com> $(date -d 2001-02-03T04:05:06+0700 +%s) +0700" "$(up log -1 --format='%an <%ae> %ad' --date=raw main~1)" "the amend's author and date"
	assert_eq "$(git rev-parse "$head~2:factory")" "$(up rev-parse 'main~1^{tree}')" "the amend's tree"
	assert_eq "$(git rev-parse "$head:factory")" "$(up rev-parse 'main^{tree}')" "the release's tree"
	assert_eq "$(git cat-file commit "$head~2" | sed '1,/^$/d')" "$(up cat-file commit main~1 | sed '1,/^$/d')" "the amend's message"
	assert_eq "tag" "$(up cat-file -t v0.1.1)" "v0.1.1 is no annotated tag"
	assert_eq "$(up rev-parse main)" "$(up rev-parse 'v0.1.1^{commit}')" "v0.1.1's commit"
	assert_eq "factory 0.1.1" "$(up tag -l --format='%(contents:subject)' v0.1.1)" "v0.1.1's message"
	assert_eq "" "$(git tag -l)" "land left a tag in the project"
}

# A refused project push after the publish: the rerun, rebased, skips publishing.
# A project's land that publishes to the factory repo checks the trailers;
# with no upstream line it publishes no release and needs none.
# (A synced branch, whose factory/ the factory repo holds already, needs none
# either: test_land_skips_the_release_kind_for_a_synced_factory.)
test_land_checks_the_release_kind_only_when_it_publishes() {
	landable_upstream
	before="$(remote_dev)"
	echo "an amended line" >> factory/CONTEXT.md
	amend record
	git commit -q -am "Amend the factory: no trailer" || fail "could not commit"
	c="$(git rev-parse --short=7 HEAD)"
	amend land
	assert_status 1
	stderr_has "$c (\"Amend the factory: no trailer\") changes factory/ and has no Release: trailer"
	stderr_has "; dev not moved"
	assert_eq "$before" "$(remote_dev)" "origin/dev moved"
	assert_eq "$(up rev-parse 'v0.1.0^{commit}')" "$(up rev-parse main)" "the factory repo's main moved"
	sed -i '/^upstream /d' tools/verify/factory-version
	git commit -q -am "no upstream" || fail "could not commit"
	amend land
	assert_status 0
	assert_no_line "amend: the release, 0.1.1: a patch from 0.1.0, as the amends make (the one amend commit says Release: patch)"
}

# A sync commit changes factory/ with no Release: trailer; the factory repo's
# main and tag hold that factory/ already, so land publishes nothing and checks
# no release kind.
test_land_skips_the_release_kind_for_a_synced_factory() {
	landable_upstream
	local tip
	git reset -q --soft origin/dev && git commit -q -m "Sync factory 0.1.1 (from 0.1.0)" || fail "could not commit the sync"
	head="$(git rev-parse HEAD)"
	tip="$(git commit-tree "$head:factory" -p "$(up rev-parse main)" -m "Release factory 0.1.1")" &&
		git push -q "$UP" "$tip:refs/heads/main" 2> /dev/null &&
		git tag -a factory-v0.1.1 -m "factory 0.1.1" "$tip" && git push -q "$UP" "refs/tags/factory-v0.1.1:refs/tags/v0.1.1" 2> /dev/null &&
		git tag -d factory-v0.1.1 > /dev/null || fail "could not publish the release by hand"
	amend land
	assert_status 0
	assert_line "amend: the factory repo has v0.1.1 already (main and the tag hold HEAD's factory/); skipped publishing"
	! printf '%s\n' "$out" | grep -q '^amend: the release, ' || fail "land checked the release kind of a sync: $out"
	assert_eq "$head" "$(remote_dev)" "origin/dev"
}

test_land_rerun_after_a_refused_project_push_skips_publishing() {
	landable_upstream
	mkdir -p .fixture
	cat > .fixture/run-smoke << 'SH'
[ -e "$TEST_TMP/raced" ] && exit 0
touch "$TEST_TMP/raced"
git clone -q -b dev "$TEST_TMP/remote/My_Game.git" "$TEST_TMP/racer" && cd "$TEST_TMP/racer" &&
	echo raced > raced.txt && git add raced.txt && git commit -q -m raced && git push -q origin dev
SH
	amend land
	assert_status 1
	stderr_has "the push to origin/dev was refused (did it move?); fetch, rebase onto it and land again (the factory repo has v0.1.1 already, and a rerun skips publishing)"
	published="$(up rev-parse main)"
	assert_eq "Release factory 0.1.1" "$(up log -1 --format=%s main)" "the factory repo wasn't published first"
	git fetch -q origin && git rebase -q origin/dev || fail "could not rebase"
	head="$(git rev-parse HEAD)"
	amend land
	assert_status 0
	assert_line "amend: the factory repo has v0.1.1 already (main and the tag hold HEAD's factory/); skipped publishing"
	assert_no_line "amend: publish to the factory repo ($UP): 2 commits on its main, then the tag v0.1.1"
	assert_eq "$published" "$(up rev-parse main)" "the rerun moved the factory repo's main"
	assert_eq "$head" "$(remote_dev)" "origin/dev"
}

# A refused push to the factory repo lands nothing anywhere.
test_land_stops_when_the_factory_repo_refuses_the_push() {
	landable_upstream
	before="$(remote_dev)"
	mkdir -p .fixture
	cat > .fixture/run-smoke << 'SH'
git clone -q "$TEST_TMP/factory.git" "$TEST_TMP/upracer" && cd "$TEST_TMP/upracer" &&
	echo raced > raced.txt && git add raced.txt && git commit -q -m raced && git push -q origin main
SH
	amend land
	assert_status 1
	stderr_has "the push to the factory repo's main was refused (did it move?); nothing landed"
	assert_eq "raced" "$(up log -1 --format=%s main)" "the factory repo's main"
	assert_eq "" "$(up tag -l v0.1.1)" "the tag was pushed"
	assert_eq "$before" "$(remote_dev)" "origin/dev moved"
}

# Each new refusal comes before any stage: the suite never runs.
test_land_refuses_an_unreachable_factory_repo() {
	landable_upstream
	before="$(remote_dev)"
	sed -i "s#^upstream .*#upstream $TEST_TMP/missing.git#" tools/verify/factory-version
	git commit -q -am "a lost upstream" || fail "could not commit"
	amend land
	assert_status 1
	stderr_has "could not fetch the factory repo ($TEST_TMP/missing.git)"
	[ ! -e "$TEST_TMP/suite.log" ] || fail "land ran the suite"
	assert_eq "$before" "$(remote_dev)" "origin/dev moved"
}

test_land_refuses_a_project_behind_the_factory_repo() {
	landable_upstream
	before="$(remote_dev)"
	git clone -q "$UP" "$TEST_TMP/elsewhere" 2> /dev/null || fail "could not clone the factory repo"
	commit_in "$TEST_TMP/elsewhere" CONTEXT.md "another amend"
	git -C "$TEST_TMP/elsewhere" push -q origin main 2> /dev/null || fail "could not push"
	amend land
	assert_status 1
	stderr_has "the factory repo's main differs from factory/ on origin/dev: the project is behind it or ahead of it; sync first"
	[ ! -e "$TEST_TMP/suite.log" ] || fail "land ran the suite"
	assert_eq "$before" "$(remote_dev)" "origin/dev moved"
}

test_land_refuses_a_version_not_greater_than_the_factory_repo() {
	landable_upstream
	git reset -q --hard HEAD~1 || fail "could not drop the release"
	with_upstream_line "$UP"
	git commit -q -am "the factory's repo, no release" || fail "could not commit"
	amend land
	assert_status 1
	stderr_has "factory/VERSION (0.1.0) is not greater than the factory repo's (0.1.0); run bash factory/core/amend.sh release"
	[ ! -e "$TEST_TMP/suite.log" ] || fail "land ran the suite"
}

test_land_refuses_a_tag_already_on_another_tree() {
	landable_upstream
	up tag v0.1.1 main || fail "could not tag"
	amend land
	assert_status 1
	stderr_has "the factory repo has the tag v0.1.1 already, on a different tree"
	[ ! -e "$TEST_TMP/suite.log" ] || fail "land ran the suite"
	assert_eq "factory 0.1.0" "$(up log -1 --format=%s main)" "the factory repo was published"
}

# Main has the amend, the tag is missing (its push failed): the rerun tags main.
test_land_tags_a_main_that_holds_the_amend_already() {
	landable_upstream
	head="$(git rev-parse HEAD)"
	local tip
	tip="$(git commit-tree "$head:factory" -p "$(up rev-parse main)" -m "published by hand")" &&
		git push -q "$UP" "$tip:refs/heads/main" 2> /dev/null || fail "could not publish by hand"
	amend land
	assert_status 0
	assert_line "amend: publish to the factory repo: its main holds HEAD's factory/ already; tag it v0.1.1"
	assert_eq "$tip" "$(up rev-parse 'v0.1.1^{commit}')" "the tag's commit"
	assert_eq "$head" "$(remote_dev)" "origin/dev"
}

# --- land with the factory's repo in its workspace layout ---

# The compare and the replay take main's factory/ alone: a workspace-only commit
# on main lands nothing in the way, and each replayed commit keeps main's
# workspace files, as the latest parent has them.
test_land_publishes_to_a_workspace_factory_repo_keeping_its_files() {
	landable_upstream workspace
	git clone -q -b main "$UP" "$TEST_TMP/ws" 2> /dev/null || fail "could not clone the factory repo"
	commit_in "$TEST_TMP/ws" CLAUDE.md "# the factory repo, edited there"
	git -C "$TEST_TMP/ws" push -q origin main 2> /dev/null || fail "could not push the workspace edit"
	head="$(git rev-parse HEAD)"
	amend land
	assert_status 0
	assert_line "amend: publish to the factory repo ($UP): 2 commits on its main, then the tag v0.1.1"
	assert_eq "Release factory 0.1.1
Amend the factory: a stand-in suite
edit CLAUDE.md
factory 0.1.0" "$(up log --format=%s main)" "the factory repo's history"
	assert_eq "$(git rev-parse "$head~2:factory")" "$(up rev-parse 'main~1:factory')" "the amend's factory/"
	assert_eq "$(git rev-parse "$head:factory")" "$(up rev-parse 'main:factory')" "the release's factory/"
	assert_eq ".factory-repo
CLAUDE.md
factory" "$(up ls-tree --name-only main)" "the release's top"
	assert_eq "# the factory repo, edited there" "$(up show main:CLAUDE.md)" "the workspace edit on main"
	assert_eq "the workspace" "$(up show main~1:.factory-repo)" "the marker"
	assert_eq "$(up rev-parse main)" "$(up rev-parse 'v0.1.1^{commit}')" "v0.1.1's commit"
	assert_eq "$head" "$(remote_dev)" "origin/dev"
}

# A main whose factory/ moved past origin/dev's is ahead of the project, in this
# layout as in the root one.
test_land_refuses_a_project_behind_a_workspace_factory_repo() {
	landable_upstream workspace
	before="$(remote_dev)"
	git clone -q -b main "$UP" "$TEST_TMP/ws" 2> /dev/null || fail "could not clone the factory repo"
	commit_in "$TEST_TMP/ws" factory/CONTEXT.md "another amend"
	git -C "$TEST_TMP/ws" push -q origin main 2> /dev/null || fail "could not push"
	amend land
	assert_status 1
	stderr_has "the factory repo's main differs from factory/ on origin/dev"
	[ ! -e "$TEST_TMP/suite.log" ] || fail "land ran the suite"
	assert_eq "$before" "$(remote_dev)" "origin/dev moved"
}

# Main holds HEAD's factory/ already, under factory/: land only tags it.
test_land_tags_a_workspace_main_that_holds_the_amend_already() {
	landable_upstream workspace
	head="$(git rev-parse HEAD)"
	local tip
	tip="$(git commit-tree "$(printf '100644 blob %s\t.factory-repo\n040000 tree %s\tfactory\n' \
		"$(echo "the workspace" | git hash-object -w --stdin)" "$(git rev-parse "$head:factory")" | git mktree)" \
		-p "$(up rev-parse main)" -m "published by hand")" &&
		git push -q "$UP" "$tip:refs/heads/main" 2> /dev/null || fail "could not publish by hand"
	amend land
	assert_status 0
	assert_line "amend: publish to the factory repo: its main holds HEAD's factory/ already; tag it v0.1.1"
	assert_eq "$tip" "$(up rev-parse 'v0.1.1^{commit}')" "the tag's commit"
}

# --- in the factory's own repo (the workspace layout) ---

# factory_workspace: $TEST_TMP/ws, a clone of the factory's repo in its workspace
# layout, on main: this factory (at the fixtures' version) under factory/, with
# a stand-in suite that logs its call to $TEST_TMP/suite.log, fails while
# $TEST_TMP/suite-fails exists, runs $TEST_TMP/race.sh when there is one, and
# prints $TEST_TMP/wall (a wall-time line) last when there is one;
# and the workspace's .factory-repo, CLAUDE.md, .gitignore and the copies record
# installs. Its origin, $ORIGIN, a bare repo, holds main, tagged v0.1.0. Then a
# worktree on amend/x from origin/main, as factory-amend makes one; cd there.
# $WS is the main checkout.
factory_workspace() {
	isolate_git
	unset GODOT_BIN FACTORY_GDUNIT4 FACTORY_PNPM_STORE FACTORY_PLAYWRIGHT_BROWSERS FACTORY_BASE_BRANCH FACTORY_REMOTE
	WS="$TEST_TMP/ws"
	ORIGIN="$TEST_TMP/origin.git"
	mkdir -p "$WS" && copy_factory "$WS/factory" || fail "could not make the workspace"
	cd "$WS" || fail "could not enter the workspace"
	cat > factory/core/test.sh << 'SH'
echo "suite GODOT_BIN=${GODOT_BIN:-unset} FACTORY_GDUNIT4=${FACTORY_GDUNIT4:-unset} FACTORY_PNPM_STORE=${FACTORY_PNPM_STORE:-unset} FACTORY_PLAYWRIGHT_BROWSERS=${FACTORY_PLAYWRIGHT_BROWSERS:-unset} args=$*" >> "$TEST_TMP/suite.log"
[ ! -f "$TEST_TMP/race.sh" ] || bash "$TEST_TMP/race.sh"
echo "PASS stand-in test_one"
if [ -f "$TEST_TMP/suite-fails" ]; then
	echo "FAIL stand-in test_two"
	echo "test.sh: 1 passed, 1 failed, 0 skipped"
	exit 1
fi
echo "test.sh: 1 passed, 0 failed, 0 skipped"
[ ! -f "$TEST_TMP/wall" ] || cat "$TEST_TMP/wall"
SH
	echo "the workspace" > .factory-repo
	echo "# CLAUDE.md" > CLAUDE.md
	printf '/local.env\n/.claude/worktrees/\n' > .gitignore
	git init -q -b main . || fail "git init failed"
	amend record
	assert_status 0
	assert_eq "installed .claude/skills/factory-amend/SKILL.md
installed .claude/skills/frontend-design/SKILL.md" "$(printf '%s\n' "$out" | grep SKILL.md | LC_ALL=C sort)" "record's copies"
	git add -A && git commit -q -m "factory 0.1.0" && git tag -a v0.1.0 -m "factory 0.1.0" || fail "could not commit the workspace"
	git init -q --bare -b main "$ORIGIN" && git remote add origin "$ORIGIN" &&
		git push -q origin main v0.1.0 2> /dev/null && git fetch -q origin || fail "could not push the workspace"
	git worktree add -q --no-track -b amend/x .claude/worktrees/amend-x origin/main 2> /dev/null || fail "could not add the worktree"
	cd .claude/worktrees/amend-x || fail "could not enter the worktree"
}

# origin_git <git args...>: git in $ORIGIN.
origin_git() {
	git --git-dir="$ORIGIN" "$@"
}

# a_release: commit an amend to factory/, then its release, 0.1.1.
a_release() {
	echo "an amended line" >> factory/README.md
	git commit -q -am "Amend the factory: a line" -m "Release: patch" || fail "could not commit the amend"
	amend release
	assert_status 0
	git commit -q -am "Release factory 0.1.1" || fail "could not commit the release"
}

test_repo_record_installs_refreshes_and_removes_the_workspace_copies() {
	factory_workspace
	assert_clean_check
	# A blank line: the skill differs from its copy, and its words, which
	# core/skill-words budgets at their count, don't grow.
	echo >> factory/skills/factory-amend/SKILL.md
	echo "a new file" > factory/skills/factory-amend/new.md
	echo "a stray" > .claude/skills/factory-amend/old.md
	amend check
	assert_status 1
	assert_eq ".claude/skills/factory-amend/SKILL.md:1 factory-copy differs from what factory/ installs; $AGAIN
.claude/skills/factory-amend/new.md:1 factory-copy missing; factory/ installs it; $AGAIN
.claude/skills/factory-amend/old.md:1 factory-copy factory/ no longer installs it; $AGAIN" "$out" "check's findings"
	amend record
	assert_status 0
	assert_eq "installed .claude/skills/factory-amend/new.md
refreshed .claude/skills/factory-amend/SKILL.md
removed .claude/skills/factory-amend/old.md" "$(printf '%s\n' "$out" | LC_ALL=C sort)" "what record printed"
	cmp -s factory/skills/factory-amend/SKILL.md .claude/skills/factory-amend/SKILL.md || fail "the copy wasn't refreshed"
	[ ! -e tools/verify/factory-version ] && [ ! -e AGENTS.md ] && [ ! -e .claude/agents/driver.md ] ||
		fail "record wrote a project's files"
	[ ! -e .claude/skills/factory-run ] || fail "record installed a skill the workspace does not take"
	git diff --cached --quiet || fail "record staged something"
	assert_clean_check
	amend record
	assert_status 0
	assert_eq "" "$out" "a second record printed changes"
}

# The workspace takes the amend builder and the Verifier as they are, and the
# main session's model and effort in its settings, its other keys kept.
test_repo_record_installs_the_agents_and_the_main_model() {
	factory_workspace
	cmp -s factory/agents/amend-builder.md .claude/agents/amend-builder.md &&
		cmp -s factory/agents/verifier.md .claude/agents/verifier.md || fail "the agents weren't copied as they are"
	# The Verifier preloads frontend-design, so the workspace takes it too.
	cmp -s factory/third-party/frontend-design/SKILL.md .claude/skills/frontend-design/SKILL.md &&
		cmp -s factory/third-party/frontend-design/LICENSE.txt .claude/skills/frontend-design/LICENSE.txt || fail "the Verifier's skill wasn't copied as it is"
	[ ! -e .claude/agents/designer.md ] || fail "the workspace took the designer"
	grep -qxF '  "model": "claude-opus-5-5",' .claude/settings.json &&
		grep -qxF '  "effortLevel": "medium",' .claude/settings.json &&
		grep -qxF '  "maxEffortLevel": "xhigh"' .claude/settings.json || fail "the settings lack the main model, effort and cap: $(cat .claude/settings.json)"
	printf '{\n  "permissions": { "allow": ["Bash(ls)"] },\n  "model": "claude-sonnet-5-5",\n  "effortLevel": "medium",\n  "maxEffortLevel": "xhigh"\n}\n' > .claude/settings.json
	echo "an amended line" >> factory/agents/verifier.md
	amend check
	assert_status 1
	assert_eq ".claude/agents/verifier.md:1 factory-copy differs from what factory/ installs; $AGAIN
.claude/settings.json:1 hook-drift its \"hooks\", \"model\", \"effortLevel\" or \"maxEffortLevel\" key differs from what the factory writes (factory/core/hooks/claude-workspace-hooks.json, lib/hooks.sh); $AGAIN" "$out" "check's findings"
	amend record
	assert_status 0
	assert_eq "refreshed .claude/agents/verifier.md
regenerated .claude/settings.json" "$out" "what record printed"
	grep -qF '"model": "claude-opus-5-5"' .claude/settings.json || fail "record didn't write the main model: $(cat .claude/settings.json)"
	grep -qF '"permissions": { "allow": ["Bash(ls)", "Bash(bash factory/core/lock.sh lift:*)"] }' .claude/settings.json || fail "record dropped the settings' other keys: $(cat .claude/settings.json)"
	assert_clean_check
}

# The workspace's settings run the wait guard on every Bash call, as a
# project's do, and none of a project's other hooks; settings from before it
# (no "hooks" key) are stale until record writes it.
test_repo_record_writes_the_wait_guard_alone_into_the_workspace_settings() {
	factory_workspace
	. "$FACTORY_CORE/lib/json.sh"
	assert_eq 'bash "$CLAUDE_PROJECT_DIR/factory/core/hooks/claude-wait-guard.sh"' \
		"$(factory_json_get hooks.PreToolUse.0.hooks.0.command < .claude/settings.json)" "the workspace's PreToolUse hook"
	assert_eq '^Bash$' "$(factory_json_get hooks.PreToolUse.0.matcher < .claude/settings.json)" "its matcher"
	! grep -qE 'claude-(deny|update-check|subagent-start|subagent-stop)\.sh|SessionStart|Subagent' .claude/settings.json ||
		fail "record wrote a project's hooks into the workspace: $(cat .claude/settings.json)"
	printf '{\n  "permissions": {\n    "allow": [\n      "Bash(bash factory/core/lock.sh lift:*)"\n    ]\n  },\n  "model": "claude-opus-5-5",\n  "effortLevel": "medium",\n  "maxEffortLevel": "xhigh"\n}\n' > .claude/settings.json
	amend check
	assert_status 1
	assert_eq ".claude/settings.json:1 hook-drift its \"hooks\", \"model\", \"effortLevel\" or \"maxEffortLevel\" key differs from what the factory writes (factory/core/hooks/claude-workspace-hooks.json, lib/hooks.sh); $AGAIN" "$out" "check's finding"
	amend record
	assert_status 0
	assert_eq "regenerated .claude/settings.json" "$out" "what record printed"
	grep -qF 'claude-wait-guard.sh' .claude/settings.json || fail "record didn't write the guard: $(cat .claude/settings.json)"
	assert_clean_check
}

test_repo_check_runs_the_skill_budget() {
	factory_workspace
	mkdir -p factory/skills/big
	{
		printf -- '---\nname: big\ndescription: Too long.\n---\n'
		seq 1 120
	} > factory/skills/big/SKILL.md
	amend check
	assert_status 1
	assert_line "factory/skills/big/SKILL.md:1 skill-too-long 124 lines; the budget is 100"
}

test_repo_release_bumps_factory_version_and_commits_nothing() {
	factory_workspace
	head="$(git rev-parse HEAD)"
	amend release
	assert_status 0
	assert_eq "released 0.1.1 (was 0.1.0): patch, no amend commit since origin/main; commit it as: Release factory 0.1.1" "$out" "release's line"
	assert_eq "0.1.1" "$(cat factory/VERSION)" "factory/VERSION"
	amend release patch
	assert_status 0
	assert_eq "0.1.1" "$(cat factory/VERSION)" "a second patch bumps from origin/main's again"
	amend release minor
	assert_status 1
	stderr_has "release minor makes a minor, and the amends make a patch (no amend commit since origin/main)"
	amend release 0.2.0
	assert_status 1
	stderr_has "release 0.2.0 makes a minor, and the amends make a patch"
	amend release 0.3.0
	assert_status 0
	assert_eq "released 0.3.0 (was 0.1.0): set by hand, over the amends' patch (no amend commit since origin/main); commit it as: Release factory 0.3.0" "$out" "an override's line"
	assert_eq "0.3.0" "$(cat factory/VERSION)" "an explicit version"
	amend release 0.1.0
	assert_status 1
	stderr_has "0.1.0 is not greater than factory/VERSION on origin/main (0.1.0)"
	assert_eq "0.3.0" "$(cat factory/VERSION)" "a refused release wrote"
	assert_eq "$head" "$(git rev-parse HEAD)" "release committed"
	git diff --cached --quiet || fail "release staged something"
	assert_eq " M factory/VERSION" "$(git status --porcelain)" "release changed more than factory/VERSION"
}

# amend_commit <trailer...>: commit a line added to factory/README.md, with
# these trailers in one paragraph; sets $c to its short SHA.
amend_commit() {
	local trailers
	echo "a line" >> factory/README.md
	trailers="$(printf '%s\n' "$@")"
	if [ $# -gt 0 ]; then
		git commit -q -am "Amend the factory: a line" -m "$trailers" || fail "could not commit the amend"
	else
		git commit -q -am "Amend the factory: a line" || fail "could not commit the amend"
	fi
	c="$(git rev-parse --short=7 HEAD)"
}

# A bare release reads the Release: trailers of the amend commits since
# origin/main: minor when one says minor, naming it; the release's own commit and
# a workspace-only commit need none.
test_repo_release_bumps_by_the_trailers() {
	factory_workspace
	amend_commit "Release: patch"
	first="$c"
	commit_in "$PWD" CLAUDE.md "# CLAUDE.md, with no trailer"
	amend_commit "Release: patch"
	amend release
	assert_status 0
	assert_eq "released 0.1.1 (was 0.1.0): patch, each of the 2 amend commits says Release: patch; commit it as: Release factory 0.1.1" "$out" "the patch's line"
	git commit -q -am "Release factory 0.1.1" || fail "could not commit the release"
	amend_commit "Amend-class: tests-or-docs" "Release: minor"
	minor="$c"
	amend_commit "Release: minor"
	amend release
	assert_status 0
	assert_eq "released 0.2.0 (was 0.1.0): minor, from $minor, $c (Release: minor); commit it as: Release factory 0.2.0" "$out" "the minor's line"
	amend release patch
	assert_status 1
	stderr_has "release patch makes a patch, and the amends make a minor (from $minor, $c (Release: minor)): run bash factory/core/amend.sh release, which bumps by the amends' trailers; nothing released"
	[ "$first" != "$minor" ] || fail "the fixture's commits are one"
}

# An amend commit with no Release: trailer, or another value than minor or
# patch, is refused, named.
test_repo_release_refuses_a_missing_or_bad_trailer() {
	factory_workspace
	amend_commit "Release: patch"
	amend_commit
	amend release
	assert_status 1
	stderr_has "$c (\"Amend the factory: a line\") changes factory/ and has no Release: trailer; give it Release: minor when it adds or tightens a check, changes a step the human does, changes how issues are filed or needs a template ported by hand, else Release: patch (git commit --amend, or a rebase); nothing released"
	assert_eq "0.1.0" "$(cat factory/VERSION)" "a refused release wrote"
	for value in major "Minor" "patch, minor"; do
		git reset -q --hard origin/main
		amend_commit "Release: $value"
		amend release
		assert_status 1
		stderr_has "$c (\"Amend the factory: a line\") has the trailer Release: $value; it takes one, minor or patch; nothing released"
	done
	git reset -q --hard origin/main
	amend_commit "Release: patch" "Release: minor"
	amend release
	assert_status 1
	stderr_has "has the trailer Release: patch,minor; it takes one, minor or patch"
}

# The floor: a change to a path in the header's list makes a minor, though each
# trailer says patch, and release says which path; other paths leave a patch.
test_repo_release_floor_raises_a_patch_to_a_minor() {
	factory_workspace
	local path reason
	while IFS='|' read -r path reason; do
		git reset -q --hard origin/main
		mkdir -p "$(dirname "$path")"
		echo "# an edit" >> "$path"
		git add -A && git commit -q -m "Amend the factory: $path" -m "Release: patch" || fail "could not commit $path"
		amend release
		assert_status 0
		assert_eq "released 0.2.0 (was 0.1.0): minor, from the floor, where the trailers say patch: $path ($reason) changed; commit it as: Release factory 0.2.0" "$out" "the floor for $path"
	done << 'PATHS'
factory/adapters/godot/tools/verify/lint|an adapter template, which a project ports by hand
factory/adapters/nextjs/tools/verify/a-new-step|an adapter template, which a project ports by hand
factory/core/skill-words|the skills' word budgets
factory/core/lib/steps.sh|the gate's steps
factory/core/lib/architecture.sh|a check the gate runs
factory/core/deviation.sh|a check the gate runs
factory/core/hooks/claude-deny.sh|a hook that refuses calls
factory/core/lib/protect.sh|a hook that refuses calls
factory/core/hooks/claude-wait-guard.sh|a hook that refuses calls
factory/core/hooks/pre-commit.sh|the pre-commit checks
factory/core/hooks/githooks/pre-commit|the pre-commit checks
factory/core/hooks/claude-hooks.json|which hooks run
factory/core/hooks/claude-workspace-hooks.json|which hooks run
factory/core/hooks/a-new-hook.sh|a new hook
PATHS
	git reset -q --hard origin/main
	echo "# an edit" >> factory/core/hooks/claude-update-check.sh
	echo "# an edit" >> factory/core/lib/vendor.sh
	git commit -q -am "Amend the factory: no floor" -m "Release: patch" || fail "could not commit"
	amend release
	assert_status 0
	assert_line "released 0.1.1 (was 0.1.0): patch, the one amend commit says Release: patch; commit it as: Release factory 0.1.1"
	git reset -q --hard origin/main
	echo "# an edit" >> factory/adapters/godot/tools/verify/lint
	echo "# an edit" >> factory/adapters/godot/tools/verify/test
	echo "# an edit" >> factory/core/skill-words
	git commit -q -am "Amend the factory: two templates" -m "Release: patch" || fail "could not commit"
	amend release
	assert_status 0
	assert_line "released 0.2.0 (was 0.1.0): minor, from the floor, where the trailers say patch: factory/adapters/godot/tools/verify/lint (an adapter template, which a project ports by hand), factory/core/skill-words (the skills' word budgets) changed (3 such paths in all); commit it as: Release factory 0.2.0"
}

test_repo_land_checks_tests_pushes_and_tags_a_release() {
	factory_workspace
	printf 'GODOT_BIN=/opt/local-godot\nFACTORY_GDUNIT4=/opt/gdunit4\nFACTORY_PNPM_STORE=/opt/pnpm-store\nFACTORY_PLAYWRIGHT_BROWSERS=/opt/browsers\n' > local.env
	echo "an amended line" >> factory/README.md
	git commit -q -am "Amend the factory: a line" -m "Release: patch" || fail "could not commit the amend"
	amend land
	assert_status 1
	stderr_has "factory/ changed since origin/main, and factory/VERSION (0.1.0) is not greater than its (0.1.0); run bash factory/core/amend.sh release"
	[ ! -e "$TEST_TMP/suite.log" ] || fail "a refused land ran the suite"
	amend release
	git commit -q -am "Release factory 0.1.1" || fail "could not commit the release"
	head="$(git rev-parse HEAD)"
	run_cmd env FACTORY_GDUNIT4=/opt/env-gdunit4 bash factory/core/amend.sh land
	assert_status 0
	assert_eq "amend: fetch origin/main
amend: the release, 0.1.1: a patch from 0.1.0, as the amends make (the one amend commit says Release: patch)
amend: check (bash factory/core/amend.sh check)
amend: the full suite (bash factory/core/test.sh)
test.sh: 1 passed, 0 failed, 0 skipped
amend: push to origin/main, with the tag v0.1.1
amend: landed $head on origin/main, tagged v0.1.1
amend: fast-forwarded main in the main checkout ($WS) to $head" "$out" "the stages"
	assert_eq "suite GODOT_BIN=/opt/local-godot FACTORY_GDUNIT4=/opt/env-gdunit4 FACTORY_PNPM_STORE=/opt/pnpm-store FACTORY_PLAYWRIGHT_BROWSERS=/opt/browsers args=" "$(cat "$TEST_TMP/suite.log")" "the suite's call"
	assert_eq "$head" "$(origin_git rev-parse main)" "origin's main"
	assert_eq "tag" "$(origin_git cat-file -t v0.1.1)" "v0.1.1 is no annotated tag"
	assert_eq "$head" "$(origin_git rev-parse 'v0.1.1^{commit}')" "v0.1.1's commit"
	assert_eq "factory 0.1.1" "$(origin_git tag -l --format='%(contents:subject)' v0.1.1)" "v0.1.1's message"
	assert_eq "$head" "$(git -C "$WS" rev-parse main)" "the main checkout's main"
}

# Land takes the release's kind from the trailers: a VERSION bump of the other
# plain step is refused, a missing trailer too; neither runs the suite.
test_repo_land_refuses_a_release_the_amends_disagree_with() {
	factory_workspace
	amend_commit "Release: minor"
	echo 0.1.1 > factory/VERSION
	git commit -q -am "Release factory 0.1.1" || fail "could not commit the release"
	amend land
	assert_status 1
	stderr_has "factory/VERSION 0.1.1 (from 0.1.0) makes a patch, and the amends make a minor (from $c (Release: minor)): run bash factory/core/amend.sh release, which bumps by the amends' trailers, commit it as Release factory <new>, then land again; main not moved"
	git reset -q --hard origin/main
	amend_commit "Release: patch"
	echo 0.2.0 > factory/VERSION
	git commit -q -am "Release factory 0.2.0" || fail "could not commit the release"
	amend land
	assert_status 1
	stderr_has "factory/VERSION 0.2.0 (from 0.1.0) makes a minor, and the amends make a patch (the one amend commit says Release: patch): if one of the amends is a minor, give it the trailer Release: minor; else run bash factory/core/amend.sh release"
	git reset -q --hard origin/main
	amend_commit
	echo 0.1.1 > factory/VERSION
	git commit -q -am "Release factory 0.1.1" || fail "could not commit the release"
	amend land
	assert_status 1
	stderr_has "$c (\"Amend the factory: a line\") changes factory/ and has no Release: trailer"
	stderr_has "; main not moved"
	[ ! -e "$TEST_TMP/suite.log" ] || fail "a refused land ran the suite"
	assert_eq "$(git -C "$WS" rev-parse main)" "$(origin_git rev-parse main)" "origin's main moved"
}

# release <version> overrides the amends' kind, and land says so.
test_repo_land_accepts_a_version_set_by_hand() {
	factory_workspace
	amend_commit "Release: patch"
	amend release 1.0.0
	assert_status 0
	git commit -q -am "Release factory 1.0.0" || fail "could not commit the release"
	amend land
	assert_status 0
	assert_line "amend: the release, 1.0.0: no patch or minor step from 0.1.0, so set by hand (release <version>), over the amends' patch (the one amend commit says Release: patch)"
	assert_eq "$(git rev-parse HEAD)" "$(origin_git rev-parse 'v1.0.0^{commit}')" "v1.0.0's commit"
}

test_repo_land_pushes_a_workspace_change_with_no_tag() {
	factory_workspace
	commit_in "$PWD" CLAUDE.md "# CLAUDE.md, edited"
	head="$(git rev-parse HEAD)"
	amend land
	assert_status 0
	assert_line "amend: landed $head on origin/main"
	assert_line "amend: push to origin/main"
	assert_eq "$head" "$(origin_git rev-parse main)" "origin's main"
	assert_eq "v0.1.0" "$(origin_git tag -l)" "origin's tags"
	amend land
	assert_status 1
	stderr_has "HEAD is origin/main; nothing to land"
}

test_repo_land_refuses_a_dirty_tree_or_a_head_without_origin_main() {
	factory_workspace
	commit_in "$PWD" CLAUDE.md "# CLAUDE.md, edited"
	echo stray > stray.txt
	amend land
	assert_status 1
	stderr_has "the tree is dirty"
	rm stray.txt
	git clone -q -b main "$ORIGIN" "$TEST_TMP/other" 2> /dev/null || fail "could not clone"
	commit_in "$TEST_TMP/other" README.md "elsewhere"
	git -C "$TEST_TMP/other" push -q origin main 2> /dev/null || fail "could not push from the other clone"
	moved="$(origin_git rev-parse main)"
	amend land
	assert_status 1
	stderr_has "HEAD does not contain origin/main; rebase onto it"
	assert_eq "$moved" "$(origin_git rev-parse main)" "origin's main moved"
	[ ! -e "$TEST_TMP/suite.log" ] || fail "a refused land ran the suite"
}

test_repo_land_refuses_a_tag_already_on_another_commit() {
	factory_workspace
	before="$(origin_git rev-parse main)"
	origin_git tag v0.1.1 main || fail "could not tag"
	a_release
	amend land
	assert_status 1
	stderr_has "origin has the tag v0.1.1 already, on another commit ($before)"
	[ ! -e "$TEST_TMP/suite.log" ] || fail "a refused land ran the suite"
	assert_eq "$before" "$(origin_git rev-parse main)" "origin's main moved"
}

test_repo_land_stops_on_a_finding_or_a_red_suite() {
	factory_workspace
	before="$(origin_git rev-parse main)"
	echo "an edit" >> .claude/skills/factory-amend/SKILL.md
	git commit -q -am "an edited copy" || fail "could not commit"
	amend land
	assert_status 1
	assert_line ".claude/skills/factory-amend/SKILL.md:1 factory-copy differs from what factory/ installs; $AGAIN"
	stderr_has "check failed"
	[ ! -e "$TEST_TMP/suite.log" ] || fail "land ran the suite after a finding"
	git reset -q --hard HEAD~1 || fail "could not drop the edit"
	a_release
	touch "$TEST_TMP/suite-fails"
	amend land
	assert_status 1
	assert_line "FAIL stand-in test_two"
	assert_no_line "PASS stand-in test_one"
	stderr_has "the full suite failed (exit 1"
	assert_eq "$before" "$(origin_git rev-parse main)" "origin's main moved"
	assert_eq "v0.1.0" "$(origin_git tag -l)" "a red land tagged"
}

# Another landing between the fetch and the push: main takes a fast-forward
# only, so nothing lands and nothing is tagged.
test_repo_land_pushes_main_as_a_fast_forward_only() {
	factory_workspace
	cat > "$TEST_TMP/race.sh" << 'SH'
git clone -q -b main "$TEST_TMP/origin.git" "$TEST_TMP/racer" 2> /dev/null && cd "$TEST_TMP/racer" &&
	echo raced > raced.txt && git add raced.txt && git commit -q -m raced && git push -q origin main 2> /dev/null
SH
	a_release
	amend land
	assert_status 1
	stderr_has "the push to origin/main and its tag v0.1.1 was refused (did main move?); fetch, rebase onto it and land again; nothing landed"
	assert_eq "raced" "$(origin_git log -1 --format=%s main)" "origin's main"
	assert_eq "v0.1.0" "$(origin_git tag -l)" "a refused land tagged"
}

# A refused tag refuses main too (one atomic push), so a rerun lands both, and
# a workspace-only land after it is never tagged.
test_repo_land_pushes_main_and_its_tag_together_or_neither() {
	factory_workspace
	printf '#!/bin/sh\nwhile read -r old new ref; do case "$ref" in refs/tags/*) echo "no tags today" >&2; exit 1 ;; esac; done\n' > "$ORIGIN/hooks/pre-receive"
	chmod +x "$ORIGIN/hooks/pre-receive"
	before="$(origin_git rev-parse main)"
	a_release
	head="$(git rev-parse HEAD)"
	amend land
	assert_status 1
	stderr_has "no tags today"
	stderr_has "nothing landed"
	assert_eq "$before" "$(origin_git rev-parse main)" "origin's main moved without its tag"
	assert_eq "v0.1.0" "$(origin_git tag -l)" "origin's tags"
	rm "$ORIGIN/hooks/pre-receive"
	amend land
	assert_status 0
	assert_line "amend: landed $head on origin/main, tagged v0.1.1"
	assert_line "amend: fast-forwarded main in the main checkout ($WS) to $head"
	assert_eq "$head" "$(origin_git rev-parse 'v0.1.1^{commit}')" "v0.1.1's commit"
	commit_in "$PWD" CLAUDE.md "# CLAUDE.md, edited"
	amend land
	assert_status 0
	assert_line "amend: push to origin/main"
	assert_eq "v0.1.0
v0.1.1" "$(origin_git tag -l)" "a workspace-only land was tagged"
}

# --- the full suite at land: the real-tool tests it skips, and the budget ---

# suite_args: the arguments land gave the stand-in suite, last call.
suite_args() {
	tail -n 1 "$TEST_TMP/suite.log" | sed 's/.* args=//'
}

# A land whose diff touches neither an adapter's folder nor a path its real-tool
# tests read skips them, saying so; the run is test.sh's full run all the same.
test_repo_land_skips_the_real_tool_tests_of_a_workspace_change() {
	factory_workspace
	commit_in "$PWD" CLAUDE.md "# CLAUDE.md, edited"
	amend land
	assert_status 0
	assert_line "amend: skip the godot adapter's real-tool tests (*_with_<tool>): the diff since origin/main touches no path they read (factory/ but the other adapters' folders and factory/VERSION; addons/gdUnit4/); land --all-tests runs them"
	assert_line "amend: skip the nextjs adapter's real-tool tests (*_with_<tool>): the diff since origin/main touches no path they read (factory/ but the other adapters' folders and factory/VERSION); land --all-tests runs them"
	assert_line "amend: the full suite (bash factory/core/test.sh --skip-real godot --skip-real nextjs)"
	assert_eq "--skip-real godot --skip-real nextjs" "$(suite_args)" "the suite's arguments"
}

# An adapter's change runs its real-tool tests and skips the other adapter's.
test_repo_land_runs_the_real_tool_tests_of_the_adapter_it_changes() {
	factory_workspace
	echo "A note." >> factory/adapters/godot/ARCHITECTURE.md
	git add -A && git commit -q -m "Amend the factory: the Godot adapter" -m "Release: patch" || fail "could not commit the amend"
	amend release patch
	git commit -q -am "Release factory 0.1.1" || fail "could not commit the release"
	amend land
	assert_status 0
	assert_eq "--skip-real nextjs" "$(suite_args)" "the suite's arguments"
	assert_no_line "amend: skip the godot adapter's real-tool tests (*_with_<tool>): the diff since origin/main touches no path they read (factory/ but the other adapters' folders and factory/VERSION; addons/gdUnit4/); land --all-tests runs them"
}

# The Core, or any other path of factory/ the tests read (a skill, a file moved
# out of it), runs every adapter's; a release alone (factory/VERSION) runs none.
test_repo_land_runs_every_real_tool_test_for_the_core_or_a_path_they_read() {
	local path
	for path in factory/core/lib/steps.sh factory/skills/factory-run/drift.md; do
		factory_workspace
		echo "# a line" >> "$path"
		git commit -q -am "Amend the factory: $path" -m "Release: patch" || fail "could not commit the amend"
		amend release
		git commit -q -am "Release factory 0.1.1" || fail "could not commit the release"
		amend land
		assert_status 0
		assert_eq "" "$(suite_args)" "the suite's arguments for a change to $path"
		cd "$TEST_TMP" && rm -rf "$TEST_TMP/ws" "$TEST_TMP/origin.git" "$TEST_TMP/suite.log" || fail "could not clear the workspace"
	done
	factory_workspace
	mkdir -p docs && git mv factory/README.md docs/README.md || fail "could not move the file"
	git commit -q -m "Amend the factory: a file moved out" -m "Release: patch" || fail "could not commit the move"
	amend release patch
	git commit -q -am "Release factory 0.1.1" || fail "could not commit the release"
	amend land
	assert_status 0
	assert_eq "" "$(suite_args)" "the suite's arguments for a file moved out of factory/"
	cd "$TEST_TMP" && rm -rf "$TEST_TMP/ws" "$TEST_TMP/origin.git" "$TEST_TMP/suite.log" || fail "could not clear the workspace"
	factory_workspace
	amend release patch
	git commit -q -am "Release factory 0.1.1" || fail "could not commit the release"
	amend land
	assert_status 0
	assert_eq "--skip-real godot --skip-real nextjs" "$(suite_args)" "the suite's arguments for a release alone"
}

test_repo_land_all_tests_skips_none() {
	factory_workspace
	commit_in "$PWD" CLAUDE.md "# CLAUDE.md, edited"
	amend land --all-tests
	assert_status 0
	assert_eq "" "$(suite_args)" "the suite's arguments"
	assert_line "amend: the full suite (bash factory/core/test.sh)"
	! printf '%s\n' "$out" | grep -q '^amend: skip ' || fail "land --all-tests skipped some:"$'\n'"$out"
}

# In the factory's repo too, the suite gets every variable local.env sets, the
# environment winning.
test_repo_land_reads_all_of_local_env() {
	factory_workspace
	unset NODE_BIN PNPM_BIN FACTORY_TEST_HANG_GUARD
	with_env_log
	printf 'GODOT_BIN=/opt/local-godot\nNODE_BIN=/opt/node/bin/node\nPNPM_BIN=/opt/local-pnpm\nFACTORY_TEST_HANG_GUARD=30\n' > local.env
	commit_in "$PWD" CLAUDE.md "# CLAUDE.md, edited"
	run_cmd env PNPM_BIN=/opt/env-pnpm bash factory/core/amend.sh land
	assert_status 0
	assert_eq "GODOT_BIN=/opt/local-godot NODE_BIN=/opt/node/bin/node PNPM_BIN=/opt/env-pnpm FACTORY_TEST_HANG_GUARD=30" "$(cat "$TEST_TMP/env.log")" "the suite's environment"
}

# A land that runs an adapter's real-tool tests refuses when one skipped for a
# missing tool; main and the tag stay. The tests of an adapter it skips by the
# diff, and a skip for a platform, don't count.
test_repo_land_refuses_a_real_tool_test_skipped_for_a_missing_tool() {
	factory_workspace
	skips_for_missing_tools
	echo "A note." >> factory/adapters/godot/ARCHITECTURE.md
	git add -A && git commit -q -m "Amend the factory: the Godot adapter" -m "Release: patch" || fail "could not commit the amend"
	amend release patch
	git commit -q -am "Release factory 0.1.1" || fail "could not commit the release"
	before="$(origin_git rev-parse main)"
	amend land
	assert_status 1
	assert_eq "--skip-real nextjs" "$(suite_args)" "the suite's arguments"
	stderr_has "amend:   the godot adapter's godot tests: 2 skipped: GODOT_BIN is not set"
	stderr_has "amend:   the godot adapter's gdmutant tests: 1 skipped: no gdmutant 0.1.4 (set GDMUTANT_BIN, or put it on PATH)"
	stderr_has "amend: set GODOT_BIN GDMUTANT_BIN (in the environment or local.env) so they run, then land again; main not moved"
	! grep -q "nextjs\|adb" "$TEST_TMP/stderr" || fail "land counted a skipped adapter's test or a platform's skip: $(cat "$TEST_TMP/stderr")"
	assert_eq "$before" "$(origin_git rev-parse main)" "origin's main moved"
	assert_eq "v0.1.0" "$(origin_git tag -l)" "a refused land was tagged"
	# Only a platform's skip, and the tests of the adapter the diff skips: it lands.
	sed -i '/GODOT_BIN\|GDMUTANT_BIN/d' "$TEST_TMP/race.sh"
	amend land
	assert_status 0
	assert_line "amend: landed $(git rev-parse HEAD) on origin/main, tagged v0.1.1"
	# A workspace change skips both adapters' real-tool tests, so none counts.
	skips_for_missing_tools
	commit_in "$PWD" CLAUDE.md "# CLAUDE.md, edited"
	amend land
	assert_status 0
	assert_eq "--skip-real godot --skip-real nextjs" "$(suite_args)" "the suite's arguments for a workspace change"
}

# a_test_amend <path> <class>: a commit appending a test to <path> (a test
# file), with the trailer Amend-class: <class>.
a_test_amend() {
	printf '\ntest_an_added_one() {\n\t:\n}\n' >> "$1"
	git add -A && git commit -q -m "Amend the factory: a test" -m "Amend-class: $2"$'\n'"Release: patch" || fail "could not commit the amend"
}

# The tests-or-docs class: a commit with Amend-class: tests-or-docs that touches
# only the test folders and the doc list lands, saying so; one that touches
# anything else, or names another class, is refused before check.
test_repo_land_takes_a_tests_or_docs_amend_and_refuses_one_that_touches_more() {
	factory_workspace
	local path
	a_test_amend factory/adapters/nextjs/tests/names_test.sh tests-or-docs
	echo "A line." >> factory/README.md
	echo "A line." >> README.md
	echo "# a line" >> local.env.example
	git add -A && git commit -q -m "Amend the factory: docs" -m "Amend-class: tests-or-docs"$'\n'"Release: patch" || fail "could not commit the docs"
	amend release patch
	git commit -q -am "Release factory 0.1.1" || fail "could not commit the release"
	amend land
	assert_status 0
	assert_line "amend: the tests-or-docs class, claimed by 2 commits: they touch only the factory's tests/ folders and the doc list, and no test file lost a test"
	for path in factory/skills/factory-amend/SKILL.md factory/CONTEXT.md CLAUDE.md factory/agents/verifier.md \
		factory/adapters/godot/new/tests/main/main_test.gd.txt factory/core/test.sh docs/agents/issue-tracker.md; do
		git fetch -q origin && git reset -q --hard origin/main || fail "could not reset"
		rm -f "$TEST_TMP/suite.log"
		a_test_amend factory/core/tests/stress_test.sh tests-or-docs
		mkdir -p "$(dirname "$path")" && echo "# a line" >> "$path"
		git add -A && git commit -q -m "Amend the factory: $path" -m "Amend-class: tests-or-docs"$'\n'"Release: patch" || fail "could not commit $path"
		amend release patch
		git commit -q -am "Release factory 0.1.2" || fail "could not commit the release"
		amend land
		assert_status 1
		stderr_has "claims Amend-class: tests-or-docs and touches $path: outside the factory's tests/ folders and the tests-or-docs doc list (tests_or_docs_paths, amend.sh), so the human approves it"
		[ ! -e "$TEST_TMP/suite.log" ] || fail "land ran the suite for $path"
	done
	git fetch -q origin && git reset -q --hard origin/main || fail "could not reset"
	a_test_amend factory/core/tests/stress_test.sh docs
	amend release patch
	git commit -q -am "Release factory 0.1.2" || fail "could not commit the release"
	amend land
	assert_status 1
	stderr_has "has the trailer Amend-class: docs, and the only class is tests-or-docs; main not moved"
}

# When a commit claims the class, no test file may end with fewer tests: one
# removed in any commit of the batch, or a file deleted, is refused; a test
# renamed is not.
test_repo_land_refuses_a_tests_or_docs_batch_that_loses_a_test() {
	factory_workspace
	a_test_amend factory/core/tests/stress_test.sh tests-or-docs
	sed -i '0,/^test_[a-z_]*() {$/s//test_a_renamed_one() {/' factory/core/tests/stress_test.sh
	git commit -q -am "Amend the factory: a test renamed" -m "Amend-class: tests-or-docs"$'\n'"Release: patch" || fail "could not commit the rename"
	amend release patch
	git commit -q -am "Release factory 0.1.1" || fail "could not commit the release"
	amend land
	assert_status 0
	local was
	was="$(grep -c '^test_[A-Za-z0-9_]*() {$' factory/core/tests/stress_test.sh)"
	sed -i '/^test_an_added_one() {$/,/^}$/d' factory/core/tests/stress_test.sh
	git commit -q -am "Amend the factory: a test removed" -m "Release: patch" || fail "could not commit the removal"
	echo "A line." >> factory/README.md
	git commit -q -am "Amend the factory: a line" -m "Amend-class: tests-or-docs"$'\n'"Release: patch" || fail "could not commit the doc"
	amend release patch
	git commit -q -am "Release factory 0.1.2" || fail "could not commit the release"
	amend land
	assert_status 1
	stderr_has "factory/core/tests/stress_test.sh has $((was - 1)) tests at HEAD, fewer than its $was at origin/main, in a batch that claims Amend-class: tests-or-docs"
	git reset -q --hard origin/main || fail "could not reset"
	git rm -q factory/adapters/godot/tests/names_test.sh || fail "could not remove the suite"
	git commit -q -m "Amend the factory: a suite removed" -m "Amend-class: tests-or-docs"$'\n'"Release: patch" || fail "could not commit the removal"
	amend release patch
	git commit -q -am "Release factory 0.1.2" || fail "could not commit the release"
	amend land
	assert_status 1
	stderr_has "factory/adapters/godot/tests/names_test.sh has 0 tests at HEAD"
	# Without the class, a test may go.
	git reset -q --soft HEAD~2 && git commit -q -m "Amend the factory: a suite removed, the human's yes" -m "Release: patch" || fail "could not recommit"
	amend land
	assert_status 0
}

# In a project the class holds too: factory-version, which record writes,
# is in the list; a product file isn't.
test_land_in_a_project_checks_the_tests_or_docs_class() {
	landable
	a_test_amend factory/core/tests/stress_test.sh tests-or-docs
	git reset -q --soft HEAD~1 || fail "could not uncommit"
	amend record
	git add -A && git commit -q -m "Amend the factory: a test" -m "Amend-class: tests-or-docs"$'\n'"Release: patch" || fail "could not commit the amend"
	git show --name-only --format= HEAD | grep -qx tools/verify/factory-version || fail "the amend recorded no factory-version"
	amend land
	assert_status 0
	assert_line "amend: the tests-or-docs class, claimed by 1 commits: they touch only the factory's tests/ folders and the doc list, and no test file lost a test"
	echo three > src/a.txt
	git commit -q -am "Amend the factory: a product line" -m "Amend-class: tests-or-docs"$'\n'"Release: patch" || fail "could not commit"
	amend land
	assert_status 1
	stderr_has "claims Amend-class: tests-or-docs and touches src/a.txt: outside"
	stderr_has "; dev not moved"
}

# In a project the diff is origin/dev's: the project's own gdUnit4 is a path the
# Godot adapter's tests read; a product file is none.
test_land_in_a_project_skips_by_the_diff_since_origin_dev() {
	landable
	git push -q origin HEAD:dev 2> /dev/null && git fetch -q origin || fail "could not push the stand-in to dev"
	mkdir -p addons/gdUnit4 && echo 'version="6.0.0"' > addons/gdUnit4/plugin.cfg
	git add -A && git commit -q -m "a gdUnit4 bump" || fail "could not commit"
	amend land
	assert_status 0
	assert_eq "--skip-real nextjs" "$(suite_args)" "the suite's arguments for a gdUnit4 change"
	commit_in "$PWD" src/a.txt "two"
	amend land
	assert_status 0
	assert_line "amend: skip the godot adapter's real-tool tests (*_with_<tool>): the diff since origin/dev touches no path they read (factory/ but the other adapters' folders and factory/VERSION; addons/gdUnit4/); land --all-tests runs them"
	assert_eq "--skip-real godot --skip-real nextjs" "$(suite_args)" "the suite's arguments for a product change"
	commit_in "$PWD" src/a.txt "three"
	amend land --all-tests
	assert_status 0
	assert_eq "" "$(suite_args)" "the suite's arguments with --all-tests"
}

# The budget: over it, land warns with the load average and still lands; the
# figure comes from the environment, else local.env, else 180. The test sets
# each itself, whatever FACTORY_SUITE_BUDGET the machine running the suite has.
test_repo_land_warns_over_the_suite_budget_and_lands() {
	factory_workspace
	unset FACTORY_SUITE_BUDGET
	echo "test.sh: wall time 180.4 s, 900.0 test-seconds summed" > "$TEST_TMP/wall"
	commit_in "$PWD" CLAUDE.md "# CLAUDE.md, edited"
	head="$(git rev-parse HEAD)"
	amend land
	assert_status 0
	stderr_has "amend: warning: the full suite took 180.4 s, over its budget of 180 s (FACTORY_SUITE_BUDGET); the load average is "
	assert_line "amend: landed $head on origin/main"
	commit_in "$PWD" CLAUDE.md "# CLAUDE.md, edited again"
	echo "FACTORY_SUITE_BUDGET=200" > local.env
	amend land
	assert_status 0
	! grep -q "warning" "$TEST_TMP/stderr" || fail "warned under a budget of 200 from local.env: $(cat "$TEST_TMP/stderr")"
	commit_in "$PWD" CLAUDE.md "# CLAUDE.md, edited a third time"
	run_cmd env FACTORY_SUITE_BUDGET=100 bash factory/core/amend.sh land
	assert_status 0
	stderr_has "over its budget of 100 s"
	commit_in "$PWD" CLAUDE.md "# CLAUDE.md, edited a fourth time"
	echo "test.sh: wall time 180.0 s, 900.0 test-seconds summed" > "$TEST_TMP/wall"
	rm local.env
	amend land
	assert_status 0
	! grep -q "warning" "$TEST_TMP/stderr" || fail "warned at the budget exactly: $(cat "$TEST_TMP/stderr")"
	commit_in "$PWD" CLAUDE.md "# CLAUDE.md, edited a fifth time"
	echo "test.sh: wall time 300.0 s, 900.0 test-seconds summed" > "$TEST_TMP/wall"
	touch "$TEST_TMP/suite-fails"
	amend land
	assert_status 1
	! grep -q "warning" "$TEST_TMP/stderr" || fail "a red suite was timed too: $(cat "$TEST_TMP/stderr")"
}

# The workspace's settings carry the Lock lift's allow rule too (#17.17): check
# names a removed rule as its own finding, and record puts it back beside the
# human's rules.
test_repo_check_reports_a_missing_lock_lift_rule() {
	factory_workspace
	grep -qF '"Bash(bash factory/core/lock.sh lift:*)"' .claude/settings.json || fail "record didn't write the lift rule: $(cat .claude/settings.json)"
	sed -i 's|"Bash(bash factory/core/lock.sh lift:\*)"|"Bash(ls)"|' .claude/settings.json
	amend check
	assert_status 1
	assert_eq ".claude/settings.json:1 lift-rule its \"permissions\" \"allow\" list lacks the factory's rule for the Lock lift, Bash(bash factory/core/lock.sh lift:*) (lib/hooks.sh); $AGAIN" "$out" "check's findings"
	amend record
	assert_status 0
	assert_eq "regenerated .claude/settings.json" "$out" "what record printed"
	grep -qF '"Bash(ls)",' .claude/settings.json || fail "record dropped the human's rule: $(cat .claude/settings.json)"
	assert_clean_check
}

# A workspace settings file whose "allow" is of another type: check names it.
test_repo_check_names_an_allow_of_another_type() {
	factory_workspace
	echo '{"permissions": {"allow": "Bash(ls)"}}' > .claude/settings.json
	amend check
	assert_status 1
	assert_eq ".claude/settings.json:1 hook-drift not a JSON object, or its \"permissions\" or their \"allow\" is of another type; fix it by hand, then $AGAIN" "$out" "check's findings"
}
