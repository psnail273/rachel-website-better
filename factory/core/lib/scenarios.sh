# The Scenarios seam. Sourced by the Core's scripts (needs steps.sh); defines no
# side effects.
#
# A Scenario is a scripted play-through of one behaviour of a Feature
# (CONTEXT.md). The project keeps the scripts in one folder, which the adapter
# names in tools/verify/scenario-folder: one line, the folder relative to the
# project root (`scenarios/`), letters, digits, `.`, `_`, `-` and `/` only; blank
# lines and # comments are ignored. A project without that file has no Scenarios.
# The folder is kept from the Editor two ways: its hook refuses to read or write
# it (lib/protect.sh, the scenarios class), and an issue's worktree leaves it out
# of its checkout (start.sh), so the Verifier, which checks there, doesn't meet
# it, and the verifier agent's rules have it leave the folder unread; only the
# Scenarios' writer works in it. It must lie outside what the gate's steps read,
# and out of the exports: the adapter sees to that. The gate stamp counts on it,
# keying a worktree that leaves the folder out (lib/stamp.sh).
#
# The adapter's driver, tools/verify/scenarios, is not a gate step: the Run runs it
# at each Feature's end, through factory/core/scenarios.sh. It runs every script in
# the folder against the build, from the project root, and prints one line per
# Scenario on stdout, in the results seam's format (lib/results.sh):
#
#   <name>\t<PASS|FAILURE|ERROR|SKIP>\t<file:line>
#
#   name       the Scenario's name, unique in the folder; any text without a tab
#   status     PASS when what must hold held; FAILURE for a failed check; ERROR
#              for a script that crashed, didn't load or reported nothing; SKIP
#   file:line  where the script failed, else where it starts
#
# It prints nothing when the folder holds no Scenario, and anything else on
# stderr. Exits 0 when every Scenario passed, 1 when one didn't, 2 when it could
# not run them (the reason on stderr).

# shellcheck disable=SC2034 # read by the scripts that source this lib
FACTORY_SCENARIO_FOLDER_FILE="$FACTORY_STEPS_DIR/scenario-folder"
# shellcheck disable=SC2034 # read by the scripts that source this lib
FACTORY_SCENARIOS_STEP="scenarios"

# factory_scenario_folder [root]: print the Scenario folder the root's
# scenario-folder file names (default root: the current folder), relative to the
# root, with no ./ before it and no / after it. False when there is no file, or
# its line names no folder inside the root: empty, absolute, the root itself, with
# a .. segment, or with a character outside the allowed ones.
factory_scenario_folder() {
	local file="${1:-.}/$FACTORY_SCENARIO_FOLDER_FILE" line
	[ -f "$file" ] || return 1
	line="$(tr -d '\r' < "$file" | awk 'NF && $1 !~ /^#/ { print $1; exit }')"
	while [[ $line == ./* ]]; do line="${line#./}"; done
	while [[ $line == */ ]]; do line="${line%/}"; done
	[[ $line =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] || return 1
	case "/$line/" in */./* | */../*) return 1 ;; esac
	printf '%s\n' "$line"
}
