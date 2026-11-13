#!/usr/bin/env bash
# Run the project's Scenarios (lib/scenarios.sh): the Run's check of a Feature's
# behaviours at its end, before its Playtest; never a gate step. Run from the
# project's main checkout on dev, or from the Scenario run's own worktree:
#   bash factory/core/scenarios.sh
#
# It runs the adapter's driver, tools/verify/scenarios, from the root, with
# tools/verify/local.env loaded and FACTORY_CORE set, as the runner runs a step;
# the driver's stderr passes through. stdout is one line per Scenario as the
# driver printed it, `<name>\t<PASS|FAILURE|ERROR|SKIP>\t<file:line>`, then any
# finding on what it printed (results-format, results-duplicate, scenarios-exit),
# then one last line:
#   scenarios: PASS: <n> passed
#   scenarios: FAIL: <k> of <n> did not pass
#   scenarios: not run: <why>
# "Not run" is a project with no driver (or a no-op one), no Scenario folder
# (tools/verify/scenario-folder), no Scenario in the folder, or a driver that
# could not run them (its exit 2; its stderr says why): a project made before the
# Scenarios has none until its next Spec.
#
# Exit codes: 0 every Scenario passed, 1 one didn't or the driver's output is
# wrong, 2 usage, 3 not run.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/findings.sh"
. "$core/lib/results.sh"
. "$core/lib/scenarios.sh"

if [ "$#" -ne 0 ]; then
	echo "usage: bash factory/core/scenarios.sh" >&2
	exit 2
fi
if top="$(git rev-parse --show-toplevel 2> /dev/null)"; then
	cd "$top" || exit 1
fi

not_run() {
	echo "scenarios: not run: $1"
	exit 3
}

script="$(factory_step_script "$FACTORY_SCENARIOS_STEP")"
if [ ! -f "$script" ] || factory_step_is_noop "$script"; then
	not_run "the project has no Scenario driver ($script)"
fi
folder="$(factory_scenario_folder)" || not_run "the project names no Scenario folder ($FACTORY_SCENARIO_FOLDER_FILE)"

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
(
	local_env="$FACTORY_STEPS_DIR/local.env"
	if [ -f "$local_env" ]; then
		set -a
		# shellcheck disable=SC1090 # the project's own settings
		. "./$local_env"
		set +a
	fi
	export FACTORY_CORE="$core"
	bash "$script"
) > "$tmp/results"
status=$?
[ "$status" -ne 2 ] || not_run "the driver could not run them (it exited 2; its stderr says why)"
if [ ! -s "$tmp/results" ] && [ "$status" -eq 0 ]; then
	not_run "no Scenario in $folder/"
fi

bad=0
factory_results_read "$tmp/results" "$FACTORY_SCENARIOS_STEP" > "$tmp/findings" || bad=1
failed=0
for i in "${!RESULT_NAMES[@]}"; do
	printf '%s\t%s\t%s\n' "${RESULT_NAMES[i]}" "${RESULT_STATUSES[i]}" "${RESULT_LOCS[i]}"
	[ "${RESULT_STATUSES[i]}" = PASS ] || failed=$((failed + 1))
done
factory_sort_findings < "$tmp/findings"
total=${#RESULT_NAMES[@]}
if [ "$status" -ne 0 ] && [ "$failed" -eq 0 ]; then
	factory_finding "$script" 1 scenarios-exit "the driver exited $status, yet no Scenario it printed failed"
	bad=1
fi
if [ "$failed" -gt 0 ] || [ "$bad" -eq 1 ]; then
	echo "scenarios: FAIL: $failed of $total did not pass"
	exit 1
fi
echo "scenarios: PASS: $total passed"
