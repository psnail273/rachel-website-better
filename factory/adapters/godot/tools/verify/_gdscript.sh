# Shared by the Godot adapter's step scripts. Sourced; defines no side effects
# beyond sourcing the Core's glob matcher. Run from the project root.
#
# GDSCRIPT_FORMATTER (local.env) names the GDQuest gdscript-formatter binary; the
# default is the one on PATH. Its version is pinned in tools/verify/pins.

GDSCRIPT_FORMATTER="${GDSCRIPT_FORMATTER:-gdscript-formatter}"

# The format-exclude list: a ratchet file (it may only shrink). One project-relative
# path per line; blank lines and # comments are ignored.
GD_FORMAT_EXCLUDE="tools/verify/ratchet/format_exclude.txt"

# The scope: what the gates check, meaning what ships plus the tests. One glob per
# line (the Build Brief's glob syntax: `*` and `?` stay in one folder, `**` crosses
# folders, a trailing / means the whole folder); a line starting with ! takes the
# paths it matches back out. The last line that matches a path decides; a path no
# line matches is out of scope. Blank lines and # comments are ignored.
GD_SCOPE="tools/verify/scope"

# Which files are tests: one glob per line, the same syntax (the Core reads it too).
GD_TEST_PATHS="tools/verify/test-paths"

# The glob matcher is the Core's (lib/brief.sh), and so is the Scenario folder's
# reader (lib/scenarios.sh). The runner exports FACTORY_CORE; run by hand, a step
# finds the Core where adoption vendors it.
if ! declare -F factory_glob_regex > /dev/null || ! declare -F factory_scenario_folder > /dev/null; then
	if [ ! -f "${FACTORY_CORE:-factory/core}/lib/brief.sh" ]; then
		echo "no factory Core at '${FACTORY_CORE:-factory/core}'; set FACTORY_CORE" >&2
		exit 2
	fi
	declare -F factory_glob_regex > /dev/null || . "${FACTORY_CORE:-factory/core}/lib/brief.sh"
	[ -n "${FACTORY_STEPS_DIR:-}" ] || . "${FACTORY_CORE:-factory/core}/lib/steps.sh"
	. "${FACTORY_CORE:-factory/core}/lib/scenarios.sh"
fi

# The Scenario folder (tools/verify/scenario-folder), or empty when there is none.
# No step reads it: gd_all_files leaves it out, and its .gdignore keeps it from
# Godot's import, its exports and gdUnit4's search. The Scenario driver
# (tools/verify/scenarios) alone runs it.
GD_SCENARIOS="$(factory_scenario_folder)" || GD_SCENARIOS=""

# gd_glob_rules <file>: the file's globs as `<+|-> <anchored regex>` lines, one per
# non-blank, non-# line; a leading ! gives `-`.
gd_glob_rules() {
	local line sign
	[ -f "$1" ] || return 0
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line%$'\r'}"
		case "$line" in '' | '#'*) continue ;; esac
		sign=+
		if [ "${line:0:1}" = '!' ]; then
			sign=-
			line="${line:1}"
		fi
		printf '%s %s\n' "$sign" "$(factory_glob_regex "$line")"
	done < "$1"
}

# gd_filter <rules file>: the stdin paths the rules (gd_glob_rules) keep, in order.
gd_filter() {
	awk -v rules="$1" '
		BEGIN { while ((getline line < rules) > 0) { n++; sign[n] = substr(line, 1, 1); re[n] = substr(line, 3) } }
		{ keep = 0; for (i = 1; i <= n; i++) if ($0 ~ re[i]) keep = (sign[i] == "+"); if (keep) print }
	'
}

# gd_all_files: every tracked or new (not ignored) .gd file in the project, one per
# line, sorted byte-wise; never one in the Scenario folder.
gd_all_files() {
	git ls-files --cached --others --exclude-standard -- '*.gd' |
		while IFS= read -r f; do
			[ -z "$GD_SCENARIOS" ] || case "$f" in "$GD_SCENARIOS"/*) continue ;; esac
			[ -f "$f" ] && printf '%s\n' "$f"
		done |
		LC_ALL=C sort -u
}

# gd_files: every GDScript file the gates check, one per line, sorted byte-wise:
# gd_all_files narrowed by the scope. With no scope file, everything outside
# addons/ (prepare reports the missing scope).
gd_files() {
	if [ ! -f "$GD_SCOPE" ]; then
		gd_all_files | grep -v '^addons/'
		return 0
	fi
	local rules
	rules="$(mktemp)"
	gd_glob_rules "$GD_SCOPE" > "$rules"
	gd_all_files | gd_filter "$rules"
	rm -f "$rules"
}

# gd_format_excluded: the format-exclude list's paths, one per line, as
# "<line number> <path>".
gd_format_excluded() {
	[ -f "$GD_FORMAT_EXCLUDE" ] || return 0
	awk '{ sub(/\r$/, ""); sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
		$0 != "" && $0 !~ /^#/ { print NR " " $0 }' "$GD_FORMAT_EXCLUDE"
}

# gd_tests_regex: one extended regex for the test files: GD_TEST_PATHS's globs, or
# tests/** when it holds none (prepare reports a missing one).
gd_tests_regex() {
	{ [ -f "$GD_TEST_PATHS" ] && tr -d '\r' < "$GD_TEST_PATHS" | grep -Ev '^[[:space:]]*(#|$)' || echo 'tests/**'; } |
		while IFS= read -r glob; do factory_glob_regex "$glob"; done | paste -sd '|' -
}
