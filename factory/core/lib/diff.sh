# What a branch changed, and which of its files are tests. Sourced by the Core's
# scripts (needs steps.sh and findings.sh); defines no side effects.
#
# The diff base is $FACTORY_BASE when set, else the merge-base of HEAD and
# $FACTORY_BASE_BRANCH (default dev).
#
# Which files are tests is the project's call, not the brief's: the tracked
# tools/verify/test-paths, seeded from the adapter, holds one glob per line (glob
# syntax as for the brief's scope, lib/brief.sh; blank lines and # comments are
# allowed), often `tests/**`. The red gate and the Lock read it.
#
# What the project's own tools generate is its call too: the tracked, optional
# tools/verify/generated, in the same format, seeded from the adapter when its
# tools write such files. The red gate and the deviation step skip a file that
# matches, so it needs no scope line, test or seam. A missing file, or one with no
# glob, means nothing is generated.

FACTORY_TEST_PATHS="$FACTORY_STEPS_DIR/test-paths"
FACTORY_GENERATED="$FACTORY_STEPS_DIR/generated"

# Filled by factory_test_paths_load and factory_generated_load.
TEST_PATHS=()
GENERATED=()

# factory_diff_base: print the diff base; false when there is none.
factory_diff_base() {
	if [ -n "${FACTORY_BASE:-}" ]; then
		printf '%s\n' "$FACTORY_BASE"
		return 0
	fi
	git merge-base HEAD "${FACTORY_BASE_BRANCH:-dev}" 2> /dev/null
}

# factory_read_globs <file>: set GLOBS to the file's lines, less blank lines and #
# comments. Runs in this shell, so the shell never expands the globs against the
# tree and a hook pays for no subshell.
factory_read_globs() {
	local line
	GLOBS=()
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line%$'\r'}"
		case "$line" in '' | '#'*) continue ;; esac
		GLOBS+=("$line")
	done < "$1"
}

# factory_test_paths_load: fill TEST_PATHS from the test-paths file. Prints a
# finding and returns 1 when it is missing or holds no glob.
factory_test_paths_load() {
	TEST_PATHS=()
	if [ ! -f "$FACTORY_TEST_PATHS" ]; then
		factory_finding "$FACTORY_TEST_PATHS" 1 test-paths-missing "no test-paths file; it lists the globs of the project's test files, one per line"
		return 1
	fi
	factory_read_globs "$FACTORY_TEST_PATHS"
	TEST_PATHS=("${GLOBS[@]}")
	if [ "${#TEST_PATHS[@]}" -eq 0 ]; then
		factory_finding "$FACTORY_TEST_PATHS" 1 test-paths-missing "the test-paths file lists no glob"
		return 1
	fi
}

# factory_is_test_file <path>: true when the path matches a loaded test-paths glob.
factory_is_test_file() {
	local g
	for g in "${TEST_PATHS[@]}"; do
		factory_glob_match "$g" "$1" && return 0
	done
	return 1
}

# factory_generated_load: fill GENERATED from the generated file, if there is one.
factory_generated_load() {
	GENERATED=()
	[ -f "$FACTORY_GENERATED" ] || return 0
	factory_read_globs "$FACTORY_GENERATED"
	GENERATED=("${GLOBS[@]}")
}

# factory_is_generated <path>: true when the path matches a loaded generated glob.
factory_is_generated() {
	local g
	for g in "${GENERATED[@]}"; do
		factory_glob_match "$g" "$1" && return 0
	done
	return 1
}

# factory_line_added <base> <file> <line>: true when the working tree's <line> of
# <file> is new or changed since <base> (a new file's lines all are).
factory_line_added() {
	git cat-file -e "$1:$2" 2> /dev/null || return 0
	git diff --no-color --no-ext-diff -U0 "$1" -- "$2" 2> /dev/null | awk -v n="$3" '
		/^@@/ {
			split($3, r, ",")
			start = substr(r[1], 2) + 0
			count = (2 in r) ? r[2] + 0 : 1
			if (n >= start && n < start + count) found = 1
		}
		END { exit !found }
	'
}
