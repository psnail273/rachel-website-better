# The fixture's stub step, sourced by each step script with the step's name.
# Run from the fixture project root; tests steer it with files in .fixture/:
#   ran            every stub appends its step name, so tests see the run order
#   fail-<step>    the step prints this file's findings and fails
#   output-<step>  the step prints this file's lines and passes
#   vary-<step>    the step prints a finding that changes on every run
#   args-<step>    written by the stub: the arguments the step got, one per line,
#                  when it got any (the format step passes its own on)
#   run-<step>     the step runs this file with bash before it ends: a side effect
#                  a test needs while the gate runs, such as a commit
# The test step also writes the results file: .fixture/results when it exists
# (tab-separated, see factory/core/lib/results.sh), else one passing test; with
# .fixture/no-results it writes none.
# The mutate step (the fixture has no script for it; a test adds one) writes the
# survivors file: .fixture/survivors when it exists, else one note line; with
# .fixture/no-survivors it writes none. It keeps FACTORY_MUTATE_BASE and
# FACTORY_SURVIVORS_FILE in .fixture/mutate-env, one per line.
step="$1"
shift
mkdir -p .fixture
echo "$step" >> .fixture/ran
[ "$#" -eq 0 ] || printf '%s\n' "$@" > ".fixture/args-$step"
if [ -f ".fixture/vary-$step" ]; then
	n=$(($(cat ".fixture/vary-$step") + 1))
	echo "$n" > ".fixture/vary-$step"
	echo "src/vary.txt:$n vary run $n"
fi
if [ "$step" = test ] && [ ! -f .fixture/no-results ]; then
	if [ -f .fixture/results ]; then
		cat .fixture/results > "$FACTORY_RESULTS_FILE"
	else
		printf 'test_fixture_passes\tPASS\ttests/fixture_test.txt:1\n' > "$FACTORY_RESULTS_FILE"
	fi
fi
if [ "$step" = mutate ]; then
	printf '%s\n' "${FACTORY_MUTATE_BASE:-}" "${FACTORY_SURVIVORS_FILE:-}" > .fixture/mutate-env
	if [ ! -f .fixture/no-survivors ]; then
		mkdir -p "$(dirname "$FACTORY_SURVIVORS_FILE")"
		if [ -f .fixture/survivors ]; then
			cat .fixture/survivors > "$FACTORY_SURVIVORS_FILE"
		else
			echo "# no mutants" > "$FACTORY_SURVIVORS_FILE"
		fi
	fi
fi
if [ -f ".fixture/run-$step" ]; then
	bash ".fixture/run-$step" > /dev/null 2>&1
fi
if [ -f ".fixture/fail-$step" ]; then
	cat ".fixture/fail-$step"
	exit 1
fi
if [ -f ".fixture/output-$step" ]; then
	cat ".fixture/output-$step"
fi
echo "stub $step done" >&2
exit 0
