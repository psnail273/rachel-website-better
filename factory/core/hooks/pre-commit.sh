#!/usr/bin/env bash
# The pre-commit checks: the static parts of the gates, on what is staged. git runs
# them through githooks/pre-commit from the project root; by hand:
#   bash factory/core/hooks/pre-commit.sh
#
# - the Lock: no staged change to a locked test (lib/lock.sh, against the index);
# - the arch step's static checks (the grep rules, R7's @warning_ignore ban among
#   them), run on a copy of the index with FACTORY_ARCH_STATIC_ONLY=1, so checks
#   that need the stack's runtime are left to the full verify.
# A missing or no-op arch step is skipped, as is the Lock when there is none.
#
# The hook mode (lib/hooks.sh) decides what a finding does: `enforce` (Armed)
# refuses the commit, `report` (Adopted, or no mode) prints the findings and lets
# it through. Everything goes to stderr.
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
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/findings"

# The Lock, against the index. Without a commit or a base there is no Lock to break.
if git rev-parse -q --verify HEAD > /dev/null && factory_lock_red_commit > /dev/null; then
	if base="$(factory_diff_base)"; then
		factory_lock_check "$base" :index >> "$tmp/findings"
	else
		factory_finding "$FACTORY_STEPS_DIR/deviation" 1 locked-test "no merge-base of HEAD and '${FACTORY_BASE_BRANCH:-dev}', so the Lock can't be checked" >> "$tmp/findings"
	fi
fi

# The arch step's static checks, on the staged tree: its own script, rules and
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
