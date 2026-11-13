# The ARCHITECTURE.md parser and the arch step's sync check (lib/architecture.sh),
# driven through the runner by an arch step that registers stand-in checks.

# arch_project <check-id...>: the fixture project with an arch step that
# registers one check per id. Check <id> prints .fixture/check-<id> if present
# and exits with .fixture/exit-<id> if present.
arch_project() {
	fixture_project
	{
		echo '#!/usr/bin/env bash'
		echo '. "$FACTORY_CORE/lib/steps.sh"'
		echo '. "$FACTORY_CORE/lib/findings.sh"'
		echo '. "$FACTORY_CORE/lib/architecture.sh"'
		echo 'stand_in() { [ -f ".fixture/check-$1" ] && cat ".fixture/check-$1"; echo "$1" >> .fixture/checks-ran; [ -f ".fixture/exit-$1" ] && return "$(cat ".fixture/exit-$1")"; return 0; }'
		for id in "$@"; do
			echo "check_$id() { stand_in $id; }"
			echo "factory_arch_check $id check_$id"
		done
		echo 'factory_arch_main ARCHITECTURE.md'
	} > tools/verify/arch
}

# rules: an ARCHITECTURE.md holding R1 (arch:alpha, review) and R2 (arch:beta).
rules() {
	cat > ARCHITECTURE.md << 'EOF'
# Architecture

## Rules

**R1.** Alpha holds; `arch:` in a rule sentence is not a tag.
Enforced by: `arch:alpha`, `review`
Source: convention

**R2.** Beta holds.
Enforced by: `arch:beta`
Source: convention
EOF
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_every_tag_with_a_check_passes() {
	arch_project alpha beta
	rules
	run_verify arch
	assert_status 0
	assert_eq "== arch PASS
verify: PASS" "$out"
}

test_tag_with_no_check_fails_at_the_tag() {
	arch_project alpha
	rules
	run_verify arch
	assert_status 1
	assert_eq "== arch FAIL
ARCHITECTURE.md:10 arch-sync arch:beta (R2) has no check
verify: FAILED at step arch" "$out"
}

test_check_no_rule_cites_fails() {
	arch_project alpha beta gamma
	rules
	run_verify arch
	assert_status 1
	assert_line "tools/verify/arch:1 arch-sync check gamma is cited by no rule"
	grep -qx gamma .fixture/checks-ran && fail "an uncited check ran"
	return 0
}

test_reused_rule_number_fails() {
	arch_project alpha beta
	rules
	printf '\n**R1.** Gamma holds.\nEnforced by: `review`\n' >> ARCHITECTURE.md
	run_verify arch
	assert_status 1
	assert_line "ARCHITECTURE.md:13 arch-sync R1 is used twice (first at line 5); a rule number is never reused"
}

test_check_cited_by_two_rules_fails() {
	arch_project alpha beta
	rules
	printf '\n**R3.** Alpha again.\nEnforced by: `arch:alpha`\n' >> ARCHITECTURE.md
	run_verify arch
	assert_status 1
	assert_line "ARCHITECTURE.md:14 arch-sync arch:alpha is cited by R1 and R3; a check belongs to one rule"
}

test_tag_outside_a_rule_fails() {
	arch_project alpha beta
	rules
	sed -i '1a Enforced by: `arch:beta`' ARCHITECTURE.md
	run_verify arch
	assert_status 1
	assert_line "ARCHITECTURE.md:2 arch-sync arch:beta is outside any rule"
}

test_findings_carry_the_citing_rule_number() {
	arch_project alpha beta
	rules
	printf '%s\n' "src/b.txt:3 beta is broken here" > .fixture/check-beta
	printf '%s\n' "src/a.txt:7 alpha is broken here" > .fixture/check-alpha
	run_verify arch
	assert_status 1
	assert_eq "== arch FAIL
src/a.txt:7 R1 alpha is broken here
src/b.txt:3 R2 beta is broken here
verify: FAILED at step arch" "$out"
}

test_check_that_errors_fails_the_step() {
	arch_project alpha beta
	rules
	echo 3 > .fixture/exit-beta
	run_verify arch
	assert_status 1
	assert_line "tools/verify/arch:1 arch-error check beta exited 3"
}

test_missing_architecture_file_fails() {
	arch_project alpha
	run_verify arch
	assert_status 1
	assert_line "ARCHITECTURE.md:1 arch-sync no ARCHITECTURE.md; the arch step checks its rules"
}

test_parse_lists_rules_and_tags() {
	rules
	. "$FACTORY_CORE/lib/architecture.sh"
	assert_eq "rule 1 5
tag 1 6 alpha
rule 2 9
tag 2 10 beta" "$(factory_arch_parse ARCHITECTURE.md)"
}
