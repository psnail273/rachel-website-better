# The skill size budget: description <= 200 characters, SKILL.md <= 100 lines,
# and, inside the factory folder, its words <= its budget in core/skill-words
# (1000 for a skill not listed).

# make_skill <name> <description> <total lines>: write skills/<name>/SKILL.md.
make_skill() {
	mkdir -p "skills/$1"
	{
		echo "---"
		echo "name: $1"
		echo "description: $2"
		echo "---"
		local i
		for ((i = 5; i <= $3; i++)); do echo "line $i"; done
	} > "skills/$1/SKILL.md"
}

# chars <n>: a string of n characters.
chars() {
	printf '%*s' "$1" '' | tr ' ' 'x'
}

# wordy_skill <skills dir> <name> <words>: write <skills dir>/<name>/SKILL.md
# holding exactly <words> words (wc -w) in at most 100 lines, its frontmatter's 6
# among them.
wordy_skill() {
	local f="$1/$2/SKILL.md"
	shift
	mkdir -p "$(dirname "$f")"
	{
		printf -- '---\nname: x\ndescription: Fine.\n---\n'
		local i
		for ((i = 6; i < $2; i += 20)); do
			if (($2 - i >= 20)); then
				printf 'w %.0s' {1..20}
			else
				printf 'w %.0s' $(seq 1 $(($2 - i)))
			fi
			echo
		done
	} > "$f"
	[ "$(LC_ALL=C wc -w < "$f" | tr -d ' ')" = "$2" ] || fail "wordy_skill wrote the wrong count"
}

run_budget() {
	run_cmd bash "$FACTORY_CORE/skill-budget.sh" skills
}

# mini_factory <skill-words text>: $TEST_TMP/factory, a factory folder (not a
# git checkout: a project's layout) holding the budget check and that words file.
mini_factory() {
	mkdir -p factory/core/lib factory/skills || fail "no mini factory"
	cp "$FACTORY_CORE/skill-budget.sh" factory/core/ &&
		cp "$FACTORY_CORE/lib/findings.sh" factory/core/lib/ || fail "could not copy the check"
	printf '%b' "$1" > factory/core/skill-words
}

run_mini() {
	run_cmd bash factory/core/skill-budget.sh "$@"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_no_skills_passes() {
	mkdir skills
	run_budget
	assert_status 0
	assert_eq "" "$out"
}

test_skill_at_both_limits_passes() {
	make_skill edge "$(chars 200)" 100
	run_budget
	assert_status 0
	assert_eq "" "$out"
}

test_description_over_limit_fails() {
	make_skill wordy "$(chars 201)" 10
	run_budget
	assert_status 1
	assert_eq "skills/wordy/SKILL.md:1 skill-description-too-long 201 characters; the budget is 200" "$out"
}

test_skill_over_line_limit_fails() {
	make_skill long "Short." 101
	run_budget
	assert_status 1
	assert_eq "skills/long/SKILL.md:1 skill-too-long 101 lines; the budget is 100" "$out"
}

test_quoted_description_is_measured_without_quotes() {
	make_skill quoted "\"$(chars 200)\"" 10
	run_budget
	assert_status 0
}

test_missing_description_fails() {
	mkdir -p skills/bare
	printf -- '---\nname: bare\n---\nbody\n' > skills/bare/SKILL.md
	run_budget
	assert_status 1
	assert_eq "skills/bare/SKILL.md:1 skill-description-missing no one-line description in the frontmatter" "$out"
}

test_every_skill_is_checked() {
	make_skill good "Fine." 10
	make_skill long "Short." 120
	make_skill wordy "$(chars 250)" 10
	run_budget
	assert_status 1
	assert_eq "skills/long/SKILL.md:1 skill-too-long 120 lines; the budget is 100
skills/wordy/SKILL.md:1 skill-description-too-long 250 characters; the budget is 200" "$out"
}

test_several_dirs_are_checked() {
	make_skill good "Fine." 10
	mkdir -p adapter/skills
	make_skill long "Short." 101
	mv skills/long adapter/skills/
	run_cmd bash "$FACTORY_CORE/skill-budget.sh" skills adapter/skills
	assert_status 1
	assert_eq "adapter/skills/long/SKILL.md:1 skill-too-long 101 lines; the budget is 100" "$out"
}

# A skill listed in the words file has that budget: at it passes, one word over
# fails naming the count and the budget.
test_a_listed_skill_has_its_word_budget() {
	mini_factory '# a comment\nskills/other 10\nskills/listed 1500\n'
	wordy_skill factory/skills listed 1500
	run_mini
	assert_status 0
	assert_eq "" "$out"
	wordy_skill factory/skills listed 1501
	run_mini
	assert_status 1
	assert_eq "factory/skills/listed/SKILL.md:1 skill-too-many-words 1501 words; the budget is 1500" "$out"
}

# A skill inside the factory that the words file doesn't list has the default,
# 1000 words; so has an adapter's, and a workspace skill's (workspace-skills/,
# checked by default too).
test_an_unlisted_skill_has_the_default_word_budget() {
	mini_factory 'skills/other 5000\n'
	wordy_skill factory/skills new 1000
	wordy_skill factory/adapters/demo/skills write-tests-demo 1000
	wordy_skill factory/workspace-skills start 1000
	run_mini
	assert_status 0
	assert_eq "" "$out"
	wordy_skill factory/skills new 1001
	wordy_skill factory/adapters/demo/skills write-tests-demo 1001
	wordy_skill factory/workspace-skills start 1001
	run_mini
	assert_status 1
	assert_eq "factory/adapters/demo/skills/write-tests-demo/SKILL.md:1 skill-too-many-words 1001 words; the budget is 1000
factory/skills/new/SKILL.md:1 skill-too-many-words 1001 words; the budget is 1000
factory/workspace-skills/start/SKILL.md:1 skill-too-many-words 1001 words; the budget is 1000" "$out"
}

# The words file's CRLF line endings don't hide a budget.
test_a_crlf_words_file_is_read() {
	mini_factory 'skills/listed 1500\r\n'
	wordy_skill factory/skills listed 1500
	run_mini
	assert_status 0
	assert_eq "" "$out"
	wordy_skill factory/skills listed 1501
	run_mini
	assert_status 1
	assert_eq "factory/skills/listed/SKILL.md:1 skill-too-many-words 1501 words; the budget is 1500" "$out"
}

# Skills dirs given as arguments, however spelled, find the same budgets.
test_named_dirs_find_the_same_budgets() {
	mini_factory 'skills/listed 1500\nadapters/demo/skills/write-tests-demo 1200\n'
	wordy_skill factory/skills listed 1500
	wordy_skill factory/adapters/demo/skills write-tests-demo 1200
	run_mini factory/skills factory/adapters/*/skills
	assert_status 0
	assert_eq "" "$out"
	run_mini "$TEST_TMP/factory/skills" ./factory/core/../adapters/demo/skills
	assert_status 0
	assert_eq "" "$out"
	wordy_skill factory/skills listed 1501
	run_mini factory/skills
	assert_status 1
	assert_eq "factory/skills/listed/SKILL.md:1 skill-too-many-words 1501 words; the budget is 1500" "$out"
}

# A skill outside the factory folder (verify-skill.sh checks a generated
# verify-<project> skill in a temp folder) has no word budget: an 81-line,
# 1068-word skill passes, as before.
test_a_skill_outside_the_factory_has_no_word_budget() {
	mini_factory ''
	wordy_skill out verify-demo 1068
	run_mini out
	assert_status 0
	assert_eq "" "$out"
	run_budget
	assert_status 0
}

# The factory's own skills are within their budgets, read from the folder that
# holds factory/ (a project's layout, and this workspace's), each found in
# core/skill-words; named as arguments, they pass too.
test_the_real_skills_are_within_budget() {
	[ -f "$FACTORY_CORE/skill-words" ] || fail "no core/skill-words"
	grep -qx 'skills/build [0-9]*' "$FACTORY_CORE/skill-words" || fail "skill-words doesn't list skills/build"
	run_cmd bash "$FACTORY_CORE/skill-budget.sh"
	assert_status 0
	assert_eq "" "$out"
	run_cmd bash "$FACTORY_CORE/skill-budget.sh" "$FACTORY_CORE/../skills" "$FACTORY_CORE/../workspace-skills" "$FACTORY_CORE"/../adapters/*/skills
	assert_status 0
	assert_eq "" "$out"
}
