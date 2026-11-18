# The gate's steps: their order, where their scripts live and the no-op marker. Sourced
# by the Core's scripts; defines no side effects.
#
# Every step is a project-owned script at tools/verify/<step>, run with bash from
# the project root. It prints findings on stdout (see findings.sh), anything else
# on stderr, and exits 0 to pass; it exits FACTORY_TRANSIENT_EXIT (75) to fail for
# a cause that is no fault of the code (a lock another run held too long, a
# refused connection): the step fails all the same, but the runner keeps no gate
# stamp of the run, so --reuse runs it again. A step the stack lacks keeps its
# script, holding only the no-op marker line, so a missing script is a mistake,
# except for an optional step: a project without its script skips it as it skips
# a no-op.

# The fixed order. Every run, full or subset, follows it.
FACTORY_STEPS=(prepare format typecheck lint arch deviation test mutate smoke)

# The optional steps (mutate: lib/mutate.sh), space-separated.
FACTORY_OPTIONAL_STEPS="mutate"

# The static steps, space-separated: they read the code without running it, so
# they are quick. verify.sh --all-static runs every one even after one fails.
FACTORY_STATIC_STEPS="format typecheck lint arch deviation"

# The steps that may run at once (#57 item 3, ruled 2026-11-17), space-separated:
# they come one after another in the fixed order, and none needs what another
# makes. verify.sh starts them together where the project's no-overlap
# file lets it, and prints each one's result in the fixed order.
FACTORY_PARALLEL_STEPS="typecheck lint arch deviation test"

# The exit code of a step that failed for a transient cause (sysexits' EX_TEMPFAIL).
# shellcheck disable=SC2034 # read by verify.sh
FACTORY_TRANSIENT_EXIT=75

# Where a project keeps its step scripts, pins and local.env, relative to its root.
FACTORY_STEPS_DIR="tools/verify"

# The project's no-overlap file: a line per set of the parallel steps that write
# the same place (a cache, a tool's import folder), space-separated; no two steps
# a line names run at the same time. `#` starts a comment. With no file the runner
# runs the parallel steps one by one, as a stack that never said its steps share
# nothing; an empty one lets all five run at once.
FACTORY_NO_OVERLAP="$FACTORY_STEPS_DIR/no-overlap"

# The line that declares a step a no-op. It must be the whole line.
FACTORY_NOOP_MARKER="# factory: no-op"

# factory_is_step <name>: true when <name> is one of the steps.
factory_is_step() {
	local s
	for s in "${FACTORY_STEPS[@]}"; do
		[ "$s" = "$1" ] && return 0
	done
	return 1
}

# factory_step_is_optional <name>: true when the step's script may be left out.
factory_step_is_optional() {
	case " $FACTORY_OPTIONAL_STEPS " in
		*" $1 "*) return 0 ;;
	esac
	return 1
}

# factory_step_is_static <name>: true when the step is one of the static steps.
factory_step_is_static() {
	case " $FACTORY_STATIC_STEPS " in
		*" $1 "*) return 0 ;;
	esac
	return 1
}

# factory_step_is_parallel <name>: true when the step is one of the parallel steps.
factory_step_is_parallel() {
	case " $FACTORY_PARALLEL_STEPS " in
		*" $1 "*) return 0 ;;
	esac
	return 1
}

# factory_no_overlap_words: the no-overlap file's lines, comments and carriage
# returns left out, one line of space-separated words per line that names any.
factory_no_overlap_words() {
	tr -d '\r' < "$FACTORY_NO_OVERLAP" | sed 's/#.*//' | awk 'NF { $1 = $1; print }'
}

# factory_no_overlap_check: print, and return 1 for, each word of the no-overlap
# file that is not a parallel step; true with no file.
factory_no_overlap_check() {
	[ -f "$FACTORY_NO_OVERLAP" ] || return 0
	factory_no_overlap_words | awk -v steps="$FACTORY_PARALLEL_STEPS" '
		BEGIN { n = split(steps, s, " "); for (i = 1; i <= n; i++) ok[s[i]] = 1 }
		{ for (i = 1; i <= NF; i++) if (!($i in ok)) { print $i; bad = 1 } }
		END { exit bad }'
}

# factory_steps_may_overlap <a> <b>: true when the two steps may run at the same
# time: two different parallel steps, a no-overlap file, and no line of it that
# names both.
factory_steps_may_overlap() {
	[ "$1" != "$2" ] && factory_step_is_parallel "$1" && factory_step_is_parallel "$2" &&
		[ -f "$FACTORY_NO_OVERLAP" ] || return 1
	factory_no_overlap_words | awk -v a="$1" -v b="$2" '
		{ x = 0; y = 0; for (i = 1; i <= NF; i++) { if ($i == a) x = 1; if ($i == b) y = 1 } if (x && y) shared = 1 }
		END { exit shared }'
}

# factory_step_script <step>: the step's script path, relative to the project root.
factory_step_script() {
	printf '%s/%s\n' "$FACTORY_STEPS_DIR" "$1"
}

# factory_step_is_noop <script>: true when the script declares the step a no-op.
factory_step_is_noop() {
	grep -qxF "$FACTORY_NOOP_MARKER" "$1" 2> /dev/null
}
