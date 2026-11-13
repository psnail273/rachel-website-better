# The red judgement, for `verify.sh --red`. Sourced by the Core's scripts (needs
# steps.sh, findings.sh, brief.sh, diff.sh and results.sh); defines no side effects.
#
# In the red phase the Editor adds the brief's tests and stubs its seams, nothing
# else, and every new test fails on an assertion. The runner runs every step as
# usual, but the test step's verdict is this judgement instead of the step's exit
# code. It fails on:
#   red-diff         a file changed since the diff base (committed or not, untracked
#                    included) that isn't in the brief's scope, or is neither a test
#                    file (tools/verify/test-paths), a seam's stub file nor one of
#                    the Driver's docs (FACTORY_DRIVER_DOCS, lib/brief.sh), which
#                    the Driver may commit before the Lock. A file the project's
#                    tools generate (tools/verify/generated) is skipped
#   red-no-tests     a brief that names no test
#   red-missing      a test the brief names with no line in the results
#   red-not-failure  a test the brief names that isn't FAILURE (a pass, an ERROR
#                    for a crash or parse error, or a SKIP)
#   red-unnamed      a test in the results the brief doesn't name that is new (its
#                    file:line is a line added since the base) or isn't PASS

# factory_red_judge <results> <brief>: print the findings; return 1 on any.
factory_red_judge() {
	local results="$1" brief="$2" bad=0 base file i j seam ok
	local -a seam_files=()

	if ! base="$(factory_diff_base)"; then
		factory_finding "$FACTORY_STEPS_DIR/test" 1 red-base "no merge-base of HEAD and '${FACTORY_BASE_BRANCH:-dev}'; set FACTORY_BASE or FACTORY_BASE_BRANCH"
		return 1
	fi
	factory_brief_parse "$brief" || return 1
	factory_test_paths_load || return 1
	factory_generated_load

	# The diff: only tests, stubs and the Driver's docs, in scope, and what the
	# project's tools generate.
	for seam in "${BRIEF_SEAMS[@]}"; do
		seam_files+=("${seam%% *}")
	done
	while IFS= read -r file; do
		[ -z "$file" ] && continue
		factory_is_generated "$file" && continue
		ok=0
		if factory_is_test_file "$file" || factory_is_driver_doc "$file"; then
			ok=1
		else
			for j in "${seam_files[@]}"; do
				[ "$j" = "$file" ] && ok=1 && break
			done
		fi
		if [ "$ok" -eq 0 ]; then
			factory_finding "$file" 1 red-diff "neither a test file ($FACTORY_TEST_PATHS), a seam's stub file in the brief nor one of the Driver's docs ($FACTORY_DRIVER_DOCS); the red phase changes only those"
			bad=1
		elif ! factory_in_scope "$file"; then
			factory_finding "$file" 1 red-diff "outside the brief's scope; the red phase changes only tests, stubs and the Driver's docs in scope"
			bad=1
		fi
	done < <({
		git diff --name-only --no-renames "$base" --
		git ls-files --others --exclude-standard
	} | tr -d '\r' | LC_ALL=C sort -u)

	# The results against the brief's test names.
	factory_results_read "$results" || bad=1
	if [ "${#BRIEF_TESTS[@]}" -eq 0 ]; then
		factory_finding "$brief" 1 red-no-tests "the brief names no test; the red phase adds at least one"
		bad=1
	fi
	for j in "${!BRIEF_TESTS[@]}"; do
		if ! i="$(factory_results_index "${BRIEF_TESTS[j]}")"; then
			factory_finding "$brief" "${BRIEF_TEST_LINES[j]}" red-missing "${BRIEF_TESTS[j]} is named in the brief but has no line in the results"
			bad=1
		elif [ "${RESULT_STATUSES[i]}" != FAILURE ]; then
			factory_result_finding "$i" red-not-failure "${RESULT_NAMES[i]} is ${RESULT_STATUSES[i]}; in the red phase a test the brief names fails with FAILURE"
			bad=1
		fi
	done
	for i in "${!RESULT_NAMES[@]}"; do
		factory_brief_has_test "${RESULT_NAMES[i]}" && continue
		if [ "${RESULT_STATUSES[i]}" != PASS ]; then
			factory_result_finding "$i" red-unnamed "${RESULT_NAMES[i]} is ${RESULT_STATUSES[i]} but the brief doesn't name it; only the brief's tests may fail"
			bad=1
		elif factory_line_added "$base" "${RESULT_LOCS[i]%:*}" "${RESULT_LOCS[i]##*:}"; then
			factory_result_finding "$i" red-unnamed "${RESULT_NAMES[i]} is new but the brief doesn't name it; the red phase adds only the brief's tests"
			bad=1
		fi
	done
	return "$bad"
}
