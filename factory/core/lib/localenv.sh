# A machine's local.env: the tool locations and settings its tests read, as
# NAME=value lines (a shell file, gitignored). Sourced by amend.sh and stress.sh;
# defines no side effects.

# factory_load_env <file>: export every variable the env file <file> sets into
# this shell, the environment winning: a variable already exported with a
# non-empty value keeps it. Nothing when there is no <file>. It changes this
# shell's environment, so call it in a subshell of its own (or a process that
# then runs the suite).
factory_load_env() {
	local factory_env_file="$1" factory_env_name
	local -a factory_env_kept=()
	[ -f "$factory_env_file" ] || return 0
	case "$factory_env_file" in /*) ;; *) factory_env_file="./$factory_env_file" ;; esac
	while IFS= read -r factory_env_name; do
		[ -z "${!factory_env_name:-}" ] || factory_env_kept+=("$factory_env_name")
	done < <(compgen -e)
	local -A factory_env_was=()
	for factory_env_name in ${factory_env_kept[@]+"${factory_env_kept[@]}"}; do
		factory_env_was[$factory_env_name]="${!factory_env_name}"
	done
	set -a
	# shellcheck disable=SC1090
	. "$factory_env_file" > /dev/null 2>&1
	set +a
	for factory_env_name in ${factory_env_kept[@]+"${factory_env_kept[@]}"}; do
		[ "${!factory_env_name:-}" = "${factory_env_was[$factory_env_name]}" ] ||
			export "$factory_env_name=${factory_env_was[$factory_env_name]}"
	done
	return 0
}
