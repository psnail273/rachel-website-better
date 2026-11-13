# The results Seam, and the green judgement. Sourced by the Core's scripts (needs
# steps.sh and findings.sh); defines no side effects.
#
# The test step writes one line per test to the path in $FACTORY_RESULTS_FILE,
# which the runner sets (and empties) before the step runs:
#
#   <name>\t<PASS|FAILURE|ERROR|SKIP>\t<file:line>
#
#   name       the test's name; any text without a tab
#   status     PASS; FAILURE for a failed assertion; ERROR for a crash, a parse
#              error, a missing stub or any other failure; SKIP for a skipped test
#   file:line  where the test is declared, file relative to the project root
#
# The adapter judges nothing: the Core reads this file for both gates. The
# Scenario driver prints its results in this format too, one line per Scenario
# (lib/scenarios.sh).

FACTORY_RESULT_STATUSES="PASS FAILURE ERROR SKIP"

# Filled by factory_results_read, one entry per test, in file order.
RESULT_NAMES=() RESULT_STATUSES=() RESULT_LOCS=()

# factory_results_read <file> [step]: fill the RESULT_* arrays. Prints a finding
# (against the step's script, the test step's by default) for a missing file, a
# malformed line or a name listed twice, and returns 1 if there were any.
factory_results_read() {
	local file="$1" self="$FACTORY_STEPS_DIR/${2:-test}" n=0 bad=0 line name status loc rest
	RESULT_NAMES=() RESULT_STATUSES=() RESULT_LOCS=()
	if [ ! -f "$file" ]; then
		factory_finding "$self" 1 results-missing "the test step wrote no results file; it writes one line per test to \$FACTORY_RESULTS_FILE"
		return 1
	fi
	while IFS= read -r line || [ -n "$line" ]; do
		n=$((n + 1))
		line="${line%$'\r'}"
		[ -z "$line" ] && continue
		IFS=$'\t' read -r name status loc rest <<< "$line"
		if [ -z "$name" ] || [ -n "$rest" ] || ! [[ $loc =~ ^[^[:space:]]+:[0-9]+$ ]] ||
			! [[ " $FACTORY_RESULT_STATUSES " == *" $status "* ]]; then
			factory_finding "$self" 1 results-format "results line $n: expected '<name><TAB><PASS|FAILURE|ERROR|SKIP><TAB><file:line>', got: $line"
			bad=1
		elif factory_results_index "$name" > /dev/null; then
			printf '%s results-duplicate %s is listed twice in the results\n' "$loc" "$name"
			bad=1
		else
			RESULT_NAMES+=("$name") RESULT_STATUSES+=("$status") RESULT_LOCS+=("$loc")
		fi
	done < "$file"
	return "$bad"
}

# factory_results_index <name>: print the test's index in RESULT_*; false when absent.
factory_results_index() {
	local i
	for i in "${!RESULT_NAMES[@]}"; do
		if [ "${RESULT_NAMES[i]}" = "$1" ]; then
			echo "$i"
			return 0
		fi
	done
	return 1
}

# factory_result_finding <i> <rule> <message...>: a finding at test <i>'s file:line.
factory_result_finding() {
	local i="$1" rule="$2"
	shift 2
	printf '%s %s %s\n' "${RESULT_LOCS[i]}" "$rule" "$*"
}

# factory_green_judge <file>: the green gate. Every test in the results must PASS;
# prints a finding for each one that doesn't, and returns 1 if there were any.
factory_green_judge() {
	local i bad=0
	factory_results_read "$1" || bad=1
	for i in "${!RESULT_NAMES[@]}"; do
		[ "${RESULT_STATUSES[i]}" = PASS ] && continue
		factory_result_finding "$i" green-not-pass "${RESULT_NAMES[i]} is ${RESULT_STATUSES[i]}; the green gate needs every test to PASS"
		bad=1
	done
	return "$bad"
}
