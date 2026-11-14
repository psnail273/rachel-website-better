#!/usr/bin/env bash
# The pre-commit hook: it formats what is staged, then runs the static parts of the
# gates on it. git runs it through githooks/pre-commit from the project root; by
# hand:
#   bash factory/core/hooks/pre-commit.sh
#
# 1. Formatting, so a commit is never left unformatted (#21: a format --write after
#    the commit left the fix uncommitted). The project's format step runs as
#    `tools/verify/format --write <file...>` on the staged files: added, changed or
#    renamed ones that are regular files in the working tree. Deleted files, and
#    the Lock's locked tests (which stay as the Lock holds them), are left out, and
#    the step itself formats only the files in its scope with its extensions.
#    - A fully staged file (the working tree holds what is staged) that the step
#      changes is re-staged: the commit takes the formatted bytes, the tree is clean.
#    - A partially staged file (unstaged changes beside the staged ones) is never
#      re-staged, since that would stage the unstaged hunks too; nor is any file of
#      a `git commit <paths>`: git commits a temporary index then and writes the
#      real one apart, which re-staging would leave unformatted. Its staged bytes
#      are formatted in its place for the moment, and its working-tree bytes put
#      back, mtime and all; when the step would change the staged bytes, that is a
#      `format` finding with the fix to run:
#        bash tools/verify/format --write <file> && git add <file>
#    A missing or no-op format step is skipped, and the step's own output and
#    findings are not shown: one that can't run (no Node, its tool not installed)
#    changes nothing and is no finding here, since the gate's format step reports
#    it. Run by hand, outside a commit, the hook works on the index all the same.
# 2. The Lock: no staged change to a locked test (lib/lock.sh, against the index).
# 3. The arch step's static checks (the grep rules, R7's @warning_ignore ban among
#    them), run on a copy of the index with FACTORY_ARCH_STATIC_ONLY=1, so checks
#    that need the stack's runtime are left to the full verify.
# A missing or no-op arch step is skipped, as is the Lock when there is none.
#
# The hook mode (lib/hooks.sh) decides what a finding does: `enforce` (Armed)
# refuses the commit, `report` (Adopted, or no mode) prints the findings and lets
# it through. Formatting and re-staging a fully staged file is not a finding, so
# it happens in both modes: it changes no verdict. Everything goes to stderr.
#
# Exit codes: 0 commit, 1 refused.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/findings.sh"
. "$core/lib/brief.sh"
. "$core/lib/diff.sh"
. "$core/lib/run.sh"
. "$core/lib/lock.sh"
. "$core/lib/hooks.sh"

tmp="$(mktemp -d)"
: > "$tmp/findings"
: > "$tmp/swapped"

# restore_swapped: put back the working-tree bytes of each partially staged file
# whose staged bytes were swapped in to be formatted.
restore_swapped() {
	local f
	while IFS= read -r f; do
		cp -p -- "$tmp/keep/$f" "$f" ||
			echo "pre-commit: could not put back $f's unstaged changes; they are in $tmp/keep/$f" >&2
	done < "$tmp/swapped"
	: > "$tmp/swapped"
}
trap 'restore_swapped; rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM

# 1. Format the staged files.
format="$FACTORY_STEPS_DIR/format"
if [ -f "$format" ] && ! factory_step_is_noop "$format"; then
	git -c core.quotepath=off diff --cached --name-only --no-renames --diff-filter=d -- | tr -d '\r' > "$tmp/staged"
	git -c core.quotepath=off diff --name-only --no-renames -- | tr -d '\r' > "$tmp/unstaged"
	: > "$tmp/locked"
	if git rev-parse -q --verify HEAD > /dev/null; then
		factory_locked_files > "$tmp/locked"
	fi
	# `git commit <paths>` commits a temporary index (next-index-*.lock) and writes
	# the real one apart, so a file re-staged here would leave the real index
	# holding the unformatted bytes: such a commit's files go as partial.
	why="it has unstaged changes"
	index_file="${GIT_INDEX_FILE:-}"
	case "${index_file##*/}" in
		next-index-*) why="git commit <paths> keeps the index out of reach" ;;
	esac
	full=()
	partial=()
	while IFS= read -r f; do
		[ -f "$f" ] && [ ! -L "$f" ] || continue
		grep -qxF -- "$f" "$tmp/locked" && continue
		if [ "$why" != "it has unstaged changes" ] || grep -qxF -- "$f" "$tmp/unstaged"; then
			partial+=("$f")
		else
			full+=("$f")
		fi
	done < "$tmp/staged"
	# Swap each partially staged file's staged bytes in, keeping its own.
	swapped=()
	for f in ${partial[@]+"${partial[@]}"}; do
		mkdir -p "$tmp/keep/$(dirname "$f")" "$tmp/index/$(dirname "$f")" &&
			cp -p -- "$f" "$tmp/keep/$f" &&
			git cat-file --filters ":$f" > "$tmp/index/$f" || continue
		echo "$f" >> "$tmp/swapped"
		cat "$tmp/index/$f" > "$f" && swapped+=("$f")
	done
	if [ "${#full[@]}" -gt 0 ] || [ "${#swapped[@]}" -gt 0 ]; then
		bash "$format" --write ${full[@]+"${full[@]}"} ${swapped[@]+"${swapped[@]}"} < /dev/null > /dev/null 2>&1 || true
	fi
	# changed <file>: true when the file's bytes no longer hash to its staged blob.
	changed() {
		[ "$(git hash-object -- "$1" 2> /dev/null)" != "$(git rev-parse -q --verify ":$1" 2> /dev/null)" ]
	}
	for f in ${full[@]+"${full[@]}"}; do
		changed "$f" || continue
		if git add -- "$f"; then
			echo "pre-commit: format --write reformatted $f; staged it" >&2
		else
			factory_finding "$f" 1 format "format --write reformatted it, and staging it failed; run: git add $f" >> "$tmp/findings"
		fi
	done
	for f in ${swapped[@]+"${swapped[@]}"}; do
		changed "$f" || continue
		line="$(diff "$tmp/index/$f" "$f" | sed -n '1s/^\([0-9]*\).*/\1/p')"
		factory_finding "$f" "${line:-1}" format "not formatted as staged, and $why, so pre-commit can't stage the fix; run: bash $format --write $f && git add $f" >> "$tmp/findings"
	done
	restore_swapped
fi

# 2. The Lock, against the index. Without a commit or a base there is no Lock to break.
if git rev-parse -q --verify HEAD > /dev/null && factory_lock_red_commit > /dev/null; then
	if base="$(factory_diff_base)"; then
		factory_lock_check "$base" :index >> "$tmp/findings"
	else
		factory_finding "$FACTORY_STEPS_DIR/deviation" 1 locked-test "no merge-base of HEAD and '${FACTORY_BASE_BRANCH:-dev}', so the Lock can't be checked" >> "$tmp/findings"
	fi
fi

# 3. The arch step's static checks, on the staged tree: its own script, rules and
# ratchet files as staged, outside any repo so it lists the files it finds.
tree="$tmp/tree"
mkdir -p "$tree"
if git checkout-index --all --prefix="$tree/" 2> /dev/null; then
	arch="$FACTORY_STEPS_DIR/arch"
	if [ -f "$tree/$arch" ] && ! factory_step_is_noop "$tree/$arch"; then
		(
			unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX
			export GIT_CEILING_DIRECTORIES="$tmp" FACTORY_CORE="$core" FACTORY_ARCH_STATIC_ONLY=1
			cd "$tree" && bash "$arch"
		) > "$tmp/arch.out" 2> "$tmp/arch.err"
		status=$?
		tr -d '\r' < "$tmp/arch.out" | grep -E "$FACTORY_FINDING_RE" > "$tmp/arch.findings"
		cat "$tmp/arch.findings" >> "$tmp/findings"
		if [ "$status" -ne 0 ] && [ ! -s "$tmp/arch.findings" ]; then
			factory_finding "$arch" 1 pre-commit "the arch step exited $status with no findings" >> "$tmp/findings"
		fi
	fi
else
	factory_finding "$FACTORY_STEPS_DIR/arch" 1 pre-commit "could not copy the index to check it" >> "$tmp/findings"
fi

mode="$(factory_hook_mode)" || mode=report
[ -s "$tmp/findings" ] || exit 0
factory_sort_findings < "$tmp/findings" | sed 's/^/pre-commit: /' >&2
if [ "$mode" = enforce ]; then
	echo "pre-commit: refused (the project is Armed); fix the findings above" >&2
	exit 1
fi
echo "pre-commit: reported only (the project is Adopted); the commit goes ahead" >&2
exit 0
