#!/usr/bin/env bash
# Arm an Adopted project: switch pre-commit from report to enforce. Arming is a gate
# change, so the human approves it before this runs. Run from the project's
# checkout:
#   bash factory/core/arm.sh
#
# It refuses on a project without a hook mode (not adopted), while the Baseline
# (tools/verify/ratchet/baseline.txt) holds an entry, and unless verify is green
# twice with identical output (verify.sh --twice): a red verify names its failing
# step, and differing runs show the difference. Then it writes `enforce` into
# tools/verify/hook-mode and stages it; from then on pre-commit refuses a commit
# with a finding. It commits nothing. On a project that is Armed already it says
# so and passes.
#
# verify's output goes to stderr, with the reason for a refusal.
# Exit codes: 0 Armed, 1 refused, 2 usage.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/hooks.sh"

FACTORY_BASELINE="$FACTORY_STEPS_DIR/ratchet/baseline.txt"

say() { echo "arm: $*" >&2; }
die() {
	say "$*"
	exit 1
}

[ "$#" -eq 0 ] || {
	echo "usage: bash factory/core/arm.sh" >&2
	exit 2
}

top="$(git rev-parse --show-toplevel 2> /dev/null)" || die "not inside a git checkout"
cd "$top" || die "cannot enter $top"

mode="$(factory_hook_mode)" || die "no hook mode in $FACTORY_HOOK_MODE_FILE, so the project hasn't adopted the factory; run factory/core/adopt.sh first"
if [ "$mode" = enforce ]; then
	say "already Armed ($FACTORY_HOOK_MODE_FILE is enforce)"
	exit 0
fi

if [ -f "$FACTORY_BASELINE" ]; then
	entries="$(tr -d '\r' < "$FACTORY_BASELINE" | grep -cv '^[[:space:]]*\(#.*\)\{0,1\}$')"
	[ "$entries" -eq 0 ] || die "refused: the Baseline ($FACTORY_BASELINE) still holds $entries entries; clean them up in Partial mode first"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
say "running verify twice"
bash "$core/verify.sh" --twice > "$tmp/verify"
status=$?
sed 's/^/  verify: /' "$tmp/verify" >&2
if grep -qxF "verify: two runs differ" "$tmp/verify"; then
	die "refused: two verify runs gave different output (above); make every step deterministic first"
fi
if [ "$status" -ne 0 ] || ! grep -qxF "verify: PASS" "$tmp/verify"; then
	failed="$(grep '^verify: FAILED' "$tmp/verify" | head -n 1)"
	die "refused: verify is red${failed:+ ($failed)}; make it green first"
fi

factory_hook_mode_write enforce || die "could not write $FACTORY_HOOK_MODE_FILE"
git add -- "$FACTORY_HOOK_MODE_FILE" || die "could not stage $FACTORY_HOOK_MODE_FILE"
say "Armed: the hooks now enforce; commit $FACTORY_HOOK_MODE_FILE"
