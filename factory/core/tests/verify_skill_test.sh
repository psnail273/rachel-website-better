# The verify-<project> generator (verify-skill.sh), on a project that vendors this
# factory/ and has a stub adapter, `fake`, whose generator writes what .fixture/
# files ask for. Each adapter's own generator is tested in its tests/ folder.

# skill_project: $TEST_TMP/project, a git repo with the vendored factory/, the fake
# adapter's generator and an origin remote named My_Game; cd there.
skill_project() {
	isolate_git
	unset FACTORY_PROJECT
	mkdir -p "$TEST_TMP/project/factory/adapters/fake" || fail "could not make the project"
	copy_factory "$TEST_TMP/project/factory" || fail "could not vendor the factory"
	cd "$TEST_TMP/project" || fail "could not enter the project"
	cat > factory/adapters/fake/verify-skill.sh << 'SH'
# The fake adapter's generator: a skill for project $1 in $2, with SKILL.md and a
# feature map, broken the way .fixture/ asks.
name="verify-$1"
[ -f .fixture/vs-name ] && name="$(cat .fixture/vs-name)"
[ -f .fixture/vs-fail ] && exit 1
{
	printf -- '---\nname: %s\ndescription: Drive the fake build.\n---\n\n' "$name"
	for s in Launch Doctor Drive Evidence Cleanup "Feature map"; do
		[ -f ".fixture/vs-no-$s" ] || printf '## %s\n\nText.\n\n' "$s"
	done
	[ -f .fixture/vs-long ] && seq 1 100
} > "$2/SKILL.md"
echo "| src/ | a |" > "$2/feature-map.md"
SH
	mkdir -p .fixture
	git init -q -b dev . || fail "git init failed"
	git remote add origin "git@example.com:me/My_Game.git"
}

generate() {
	run_cmd bash factory/core/verify-skill.sh "$@"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_writes_the_skill_under_the_project_name() {
	skill_project
	generate --adapter fake
	assert_status 0
	assert_eq ".claude/skills/verify-my-game" "$out"
	grep -qxF "name: verify-my-game" .claude/skills/verify-my-game/SKILL.md || fail "no SKILL.md"
	[ -f .claude/skills/verify-my-game/feature-map.md ] || fail "the sibling file isn't written"
}

test_out_picks_the_folder_and_factory_project_the_name() {
	skill_project
	FACTORY_PROJECT=Other run_cmd bash factory/core/verify-skill.sh --adapter fake --out "$TEST_TMP/skill"
	assert_status 0
	assert_eq "$TEST_TMP/skill" "$out"
	grep -qxF "name: verify-other" "$TEST_TMP/skill/SKILL.md" || fail "FACTORY_PROJECT isn't used"
	[ ! -e .claude/skills ] || fail "it wrote under .claude/skills too"
}

test_the_adapter_comes_from_the_factory_version() {
	skill_project
	mkdir -p tools/verify
	printf 'version 0.1.0\nadapter fake\n' > tools/verify/factory-version
	generate
	assert_status 0
	generate --force
	assert_status 0
}

test_no_adapter_is_a_usage_error_and_one_without_a_generator_refuses() {
	skill_project
	generate
	assert_status 2
	generate --adapter fake --bogus
	assert_status 2
	generate --adapter fake --out
	assert_status 2
	mkdir -p factory/adapters/bare/tools/verify
	generate --adapter bare
	assert_status 1
	[ ! -e .claude/skills ] || fail "it wrote a skill"
}

test_an_existing_skill_is_kept_unless_forced() {
	skill_project
	mkdir -p .claude/skills/verify-my-game
	echo "the project's skill" > .claude/skills/verify-my-game/SKILL.md
	echo "the project's notes" > .claude/skills/verify-my-game/notes.md
	generate --adapter fake
	assert_status 1
	assert_eq "the project's skill" "$(cat .claude/skills/verify-my-game/SKILL.md)" "the skill was overwritten"
	generate --adapter fake --force
	assert_status 0
	grep -qxF "name: verify-my-game" .claude/skills/verify-my-game/SKILL.md || fail "--force didn't replace it"
	assert_eq "the project's notes" "$(cat .claude/skills/verify-my-game/notes.md)" "--force removed another file"
}

test_two_runs_write_the_same_bytes() {
	skill_project
	generate --adapter fake --out "$TEST_TMP/one"
	generate --adapter fake --out "$TEST_TMP/two"
	diff -r "$TEST_TMP/one" "$TEST_TMP/two" > /dev/null || fail "two runs differ"
}

# broken <fixture file> [content]: the adapter's output fails a check, so nothing
# is written.
broken() {
	skill_project
	printf '%s' "${2:-}" > ".fixture/$1"
	generate --adapter fake
	assert_status 1
	assert_eq "" "$out"
	[ ! -e .claude/skills ] || fail "a broken skill was written ($1)"
}

test_a_failing_generator_writes_nothing() { broken vs-fail; }
test_a_skill_with_the_wrong_name_is_refused() { broken vs-name verify-else; }
test_a_skill_missing_a_section_is_refused() {
	local s
	for s in Launch Doctor Drive Evidence Cleanup "Feature map"; do
		(rm -rf "$TEST_TMP/project" && broken "vs-no-$s") || fail "a skill without '## $s' passed"
	done
}
test_a_skill_over_the_budget_is_refused() {
	broken vs-long
	grep -qF "skill-too-long" "$TEST_TMP/stderr" || fail "the budget finding isn't shown:"$'\n'"$(cat "$TEST_TMP/stderr")"
}
