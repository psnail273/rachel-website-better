# The factory-run skill's machine-read parts: the Build Brief template's block
# (brief.sh), the Verifier rubric (rubric.sh over verify-rubric.md) and the brief
# review's (rubric.sh --brief, brief-rubric.md).

SKILL_DIR="$FACTORY_CORE/../skills/factory-run"
MARKER='<!-- review-rules -->'

run_rubric() {
	run_cmd bash "$FACTORY_CORE/rubric.sh" "$@"
}

# review_rules: an ARCHITECTURE.md with review-only, arch-only, arch-and-review,
# two-line and non-arch rules, CRLF line endings on one of them.
review_rules() {
	cat > ARCHITECTURE.md << 'MD'
# Architecture

## Rules

**R1.** Alpha holds.
Enforced by: `review`
Source: convention

**R2.** Beta holds.
Enforced by: `arch:beta`
Source: convention

**R3.** Gamma holds, and `review` in a sentence is not a tag.
Enforced by: `arch:gamma`, `review`
Source: convention

**R4.** Delta holds
across two lines.
Enforced by: `review`
Source: convention

**R5.** Epsilon is a reviewer's word only in its source.
Enforced by: `typecheck`
Source: review notes

## Keeping it true

Reviewers read this.
MD
	printf '**R6.** Zeta holds.\r\nEnforced by: `lint:zeta`, `review`\r\n' >> ARCHITECTURE.md
}

# template <line...>: a rubric template made of the given lines.
template() {
	printf '%s\n' "$@" > template.md
	export FACTORY_RUBRIC_TEMPLATE="$TEST_TMP/template.md"
}

# The template, as build-brief.md gives it (inside its ````markdown fence),
# passes the same check the Driver's seal runs.
test_brief_template_passes_the_core_check() {
	awk '/^````markdown$/ { on = 1; next } /^````$/ { on = 0 } on' "$SKILL_DIR/build-brief.md" > template.md
	[ -s template.md ] || fail "no $()$()markdown template in build-brief.md"
	run_cmd bash "$FACTORY_CORE/brief.sh" check template.md
	assert_status 0
	assert_eq "" "$out"
	run_cmd bash "$FACTORY_CORE/brief.sh" tests template.md
	assert_status 0
	[ -n "$out" ] || fail "the template's block names no test"
}

test_rubric_lists_exactly_the_review_tagged_rules() {
	review_rules
	template "# Rubric" "$MARKER" "end"
	run_rubric
	assert_status 0
	assert_eq "# Rubric
- **R1.** Alpha holds. (ARCHITECTURE.md:5)
- **R3.** Gamma holds, and \`review\` in a sentence is not a tag. (ARCHITECTURE.md:13; \`arch:gamma\` checks part of it; judge the rest)
- **R4.** Delta holds across two lines. (ARCHITECTURE.md:17)
- **R6.** Zeta holds. (ARCHITECTURE.md:29; \`lint:zeta\` checks part of it; judge the rest)
end" "$out"
}

test_rubric_without_review_rules_says_so() {
	printf '**R1.** Alpha holds.\nEnforced by: `arch:alpha`\n' > ARCHITECTURE.md
	template "$MARKER"
	run_rubric
	assert_status 0
	assert_eq "- (none: ARCHITECTURE.md tags no rule \`review\`)" "$out"
}

test_rubric_needs_the_marker_exactly_once() {
	review_rules
	template "# Rubric" "no marker"
	run_rubric
	assert_status 1
	assert_eq "" "$out"
	template "$MARKER" "$MARKER"
	run_rubric
	assert_status 1
}

test_rubric_fails_without_an_architecture_file() {
	run_rubric
	assert_status 1
	run_rubric one two
	assert_status 2
}

test_shipped_rubric_has_the_marker_and_is_identical_twice() {
	review_rules
	run_rubric
	assert_status 0
	first="$out"
	run_rubric
	assert_eq "$first" "$out" "two runs differ"
	printf '%s\n' "$out" | grep -qxF -- "- **R1.** Alpha holds. (ARCHITECTURE.md:5)" || fail "the shipped rubric lacks the rules:"$'\n'"$out"
	printf '%s\n' "$out" | grep -qxF -- "$MARKER" && fail "the marker is still in the output"
	return 0
}

# The shipped rubric on review_rules: the review-tagged rules and no others, by number.
test_shipped_rubric_lists_the_review_tagged_rule_numbers_identically_twice() {
	review_rules
	run_rubric
	assert_status 0
	first="$out"
	run_rubric
	assert_eq "$first" "$out" "two runs differ"
	listed="$(printf '%s\n' "$out" | sed -n 's/^- \*\*\(R[0-9]*\)\.\*\*.*/\1/p' | paste -sd ' ' -)"
	assert_eq "R1 R3 R4 R6" "$listed" "the rubric's rules differ from the review-tagged ones"
}

# The Drift sweep's Verifier prompt is drift-rubric.md through rubric.sh.
test_drift_rubric_lists_the_review_rules_identically_twice() {
	review_rules
	export FACTORY_RUBRIC_TEMPLATE="$SKILL_DIR/drift-rubric.md"
	run_rubric
	assert_status 0
	first="$out"
	run_rubric
	assert_eq "$first" "$out" "two runs differ"
	printf '%s\n' "$out" | grep -qxF -- "- **R4.** Delta holds across two lines. (ARCHITECTURE.md:17)" || fail "the drift rubric lacks the rules:"$'\n'"$out"
	printf '%s\n' "$out" | grep -qxF -- "$MARKER" && fail "the marker is still in the output"
	return 0
}

# The brief review's prompt is brief-rubric.md as it is: no ARCHITECTURE.md, no
# template override, the same output twice.
test_brief_rubric_prints_brief_rubric_md_identically_twice() {
	export FACTORY_RUBRIC_TEMPLATE="$SKILL_DIR/drift-rubric.md"
	run_rubric --brief
	assert_status 0
	first="$out"
	run_rubric --brief
	assert_eq "$first" "$out" "two runs differ"
	assert_eq "$(tr -d '\r' < "$SKILL_DIR/brief-rubric.md")" "$out"
	printf '%s\n' "$out" | grep -qxF -- 'VERDICT: PASS|FAIL' || fail "no verdict line in the brief rubric"
	return 0
}

test_brief_rubric_takes_no_architecture_file() {
	review_rules
	run_rubric --brief ARCHITECTURE.md
	assert_status 2
	stderr_has "usage: bash factory/core/rubric.sh [ARCHITECTURE.md], or bash factory/core/rubric.sh --brief"
}

# Every relative .md link in the skill's files names a file that exists.
test_skill_links_resolve() {
	local file link missing=""
	for file in "$SKILL_DIR"/*.md; do
		# shellcheck disable=SC2013 # one link per word: the links hold no blanks
		for link in $(grep -o '](\([^)#:]*\.md\))' "$file" | sed 's/^](//; s/)$//'); do
			[ -f "$SKILL_DIR/$link" ] || missing="$missing $(basename "$file"):$link"
		done
	done
	assert_eq "" "$missing" "links to missing files"
	for link in drift.md playtest.md scenarios.md; do
		grep -qF "]($link)" "$SKILL_DIR/SKILL.md" || fail "SKILL.md doesn't link $link"
	done
	return 0
}
