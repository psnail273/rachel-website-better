# The gate's steps: their order, where their scripts live and the no-op marker. Sourced
# by the Core's scripts; defines no side effects.
#
# Every step is a project-owned script at tools/verify/<step>, run with bash from
# the project root. It prints findings on stdout (see findings.sh), anything else
# on stderr, and exits 0 to pass. A step the stack lacks keeps its script, holding
# only the no-op marker line, so a missing script is a mistake, except for an
# optional step: a project without its script skips it as it skips a no-op.

# The fixed order. Every run, full or subset, follows it.
FACTORY_STEPS=(prepare format typecheck lint arch deviation test mutate smoke)

# The optional steps (mutate: lib/mutate.sh), space-separated.
FACTORY_OPTIONAL_STEPS="mutate"

# The static steps, space-separated: they read the code without running it, so
# they are quick. verify.sh --all-static runs every one even after one fails.
FACTORY_STATIC_STEPS="format typecheck lint arch deviation"

# Where a project keeps its step scripts, pins and local.env, relative to its root.
FACTORY_STEPS_DIR="tools/verify"

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

# factory_step_script <step>: the step's script path, relative to the project root.
factory_step_script() {
	printf '%s/%s\n' "$FACTORY_STEPS_DIR" "$1"
}

# factory_step_is_noop <script>: true when the script declares the step a no-op.
factory_step_is_noop() {
	grep -qxF "$FACTORY_NOOP_MARKER" "$1" 2> /dev/null
}
