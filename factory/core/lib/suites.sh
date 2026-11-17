# Which suites a change can affect: the rules stress.sh --since chooses its suites
# by, and amend.sh land skips an adapter's suites by. Sourced by both; defines no
# side effects but FACTORY_SUITES_CORE, the core/ folder this lib is in.
#
# Suites are spelled as test.sh spells them: <name> for core/tests/<name>_test.sh,
# <a>/<name> for adapters/<a>/tests/<name>_test.sh. For each path a change
# touches (paths below are relative to the factory folder unless they say so):
#   - core/tests/<name>_test.sh: that suite; adapters/<a>/tests/<name>_test.sh: <a>/<name>.
#   - core/tests/lib.sh (every test loads it) and core/test.sh (the runner): every suite.
#   - Any other file in core/tests/ (a fixture, a test file in one): every core
#     suite; in adapters/<a>/tests/ (its lib.sh, a fixture): every suite of <a>.
#   - adapters/<a>/<entry> outside tests/: every suite of adapter <a>, and each
#     core suite whose test file names adapters/*/<entry> or adapters/<a>/<entry>
#     (skill_budget checks every adapter's skills/); so does a project's ported
#     tools/verify/ (but its factory-version record and local.env) for the
#     adapter in use (factory-version's `adapter` line).
#   - Any other file in core/: every core suite and every adapter's suites, as
#     adapters' scripts and tests run core's scripts and libs, directly or through
#     one another.
#   - Any other factory file: each suite whose test file (or all of a folder's
#     suites, whose tests/lib.sh) names its folder (skills, agents, third-party;
#     tools/<entry> for tools/) or, at the top, its name. VERSION is left out, as
#     land leaves it out: tests read it only as a version string.
#   - A folder outside the factory that an adapter's tests read
#     (factory_suites_outside; relative to the checkout's top): every suite of
#     that adapter. The Godot adapter's fall back on the project's gdUnit4.
#   - Any other file outside the factory (a project's code and docs): no suite.

FACTORY_SUITES_CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# factory_suites_outside <adapter>: the folders outside the factory (relative to
# the checkout's top) that the adapter's tests read, one per line.
factory_suites_outside() {
	case "$1" in
		# tests/lib.sh's gdunit4_source falls back on the project's own gdUnit4.
		godot) echo addons/gdUnit4/ ;;
	esac
	return 0
}

# factory_suite_of <test file>: its suite name, as test.sh spells it.
factory_suite_of() {
	case "$1" in
		"$FACTORY_SUITES_CORE/tests/"*) basename "$1" _test.sh ;;
		*) echo "$(basename "$(dirname "$(dirname "$1")")")/$(basename "$1" _test.sh)" ;;
	esac
}

# factory_suites_in <tests folder>: every suite there, one per line.
factory_suites_in() {
	local f
	for f in "$1"/*_test.sh; do
		[ -f "$f" ] && factory_suite_of "$f"
	done
	return 0
}

# factory_suites_naming <tests folder> <needle>: the suites of that folder whose
# test file names <needle> (a fixed string); all of them when its lib.sh does.
factory_suites_naming() {
	local folder="$1" needle="$2" f
	if [ -f "$folder/lib.sh" ] && grep -qF -e "$needle" "$folder/lib.sh"; then
		factory_suites_in "$folder"
		return 0
	fi
	for f in "$folder"/*_test.sh; do
		[ -f "$f" ] && grep -qF -e "$needle" "$f" && factory_suite_of "$f"
	done
	return 0
}

# factory_suites_folders: core/tests, then each adapter's tests folder.
factory_suites_folders() {
	local d
	echo "$FACTORY_SUITES_CORE/tests"
	for d in "$FACTORY_SUITES_CORE"/../adapters/*/tests; do
		[ -d "$d" ] && echo "$d"
	done
	return 0
}

# factory_suites_choose <path below the factory folder>: the suites a change to
# it can affect, one per line (repeats possible).
factory_suites_choose() {
	local rel="$1" a d first rest needle adapters="$FACTORY_SUITES_CORE/../adapters"
	case "$rel" in
		core/tests/lib.sh | core/test.sh)
			while IFS= read -r d; do factory_suites_in "$d"; done < <(factory_suites_folders)
			;;
		core/tests/*)
			rest="${rel#core/tests/}"
			if [[ $rest == *_test.sh && $rest != */* ]]; then
				echo "${rest%_test.sh}"
			else
				factory_suites_in "$FACTORY_SUITES_CORE/tests"
			fi
			;;
		core/*)
			while IFS= read -r d; do factory_suites_in "$d"; done < <(factory_suites_folders)
			;;
		adapters/*/*)
			a="${rel#adapters/}" a="${a%%/*}" rest="${rel#adapters/*/}"
			if [[ $rest == tests/*_test.sh && ${rest#tests/} != */* ]]; then
				rest="${rest#tests/}"
				echo "$a/${rest%_test.sh}"
			else
				factory_suites_in "$adapters/$a/tests"
				# A core suite may check every adapter's folder (skill_budget, its skills/).
				if [[ $rest != tests/* ]]; then
					factory_suites_naming "$FACTORY_SUITES_CORE/tests" "adapters/*/${rest%%/*}"
					factory_suites_naming "$FACTORY_SUITES_CORE/tests" "adapters/$a/${rest%%/*}"
				fi
			fi
			;;
		VERSION) ;;
		*/*)
			first="${rel%%/*}" rest="${rel#*/}"
			if [ "$first" = tools ]; then needle="tools/${rest%%/*}"; else needle="$first"; fi
			while IFS= read -r d; do factory_suites_naming "$d" "$needle"; done < <(factory_suites_folders)
			;;
		*)
			while IFS= read -r d; do factory_suites_naming "$d" "$rel"; done < <(factory_suites_folders)
			;;
	esac
	return 0
}

# factory_suites_affected <factory prefix> <adapter in use>: the suites a change
# to the paths on stdin can affect (relative to the checkout's top, one per line),
# sorted, one per line, each with a test file. <factory prefix> is the factory
# folder's path from the top with a trailing slash ("factory/"; empty when the
# factory is the top); <adapter in use> is a project's, empty elsewhere, for its
# ported tools/verify/.
factory_suites_affected() {
	local vend="$1" in_use="$2" p a folder s
	local adapters="$FACTORY_SUITES_CORE/../adapters"
	while IFS= read -r p; do
		[ -n "$p" ] || continue
		case "$p" in
			"$vend"*) factory_suites_choose "${p#"$vend"}" ;;
			tools/verify/factory-version | tools/verify/local.env*) ;;
			tools/verify/*) [ -n "$in_use" ] && [ -d "$adapters/$in_use/tests" ] && factory_suites_in "$adapters/$in_use/tests" ;;
		esac
		for a in "$adapters"/*/; do
			a="$(basename "$a")"
			while IFS= read -r folder; do
				[ -z "$folder" ] || [ "${p#"$folder"}" = "$p" ] || factory_suites_in "$adapters/$a/tests"
			done < <(factory_suites_outside "$a")
		done
	done | LC_ALL=C sort -u | while IFS= read -r s; do
		[ -n "$s" ] || continue
		case "$s" in
			*/*) [ -f "$adapters/${s%%/*}/tests/${s#*/}_test.sh" ] && echo "$s" ;;
			*) [ -f "$FACTORY_SUITES_CORE/tests/${s}_test.sh" ] && echo "$s" ;;
		esac
	done
	return 0
}
