#!/usr/bin/env bash
# Generate the project's verify-<project> skill: how to Launch, Doctor, Drive,
# collect Evidence from and Cleanup after a running build, plus its feature map.
# Run from the project root:
#   bash factory/core/verify-skill.sh [--adapter <name>] [--out <dir>] [--force]
#
# The adapter writes the skill: factory/adapters/<adapter>/verify-skill.sh, run as
# `verify-skill.sh <project> <dir>` from the project root, writes SKILL.md (and any
# sibling files) into the empty <dir>. Its output must depend only on the project's
# files, so two runs write the same bytes. The Core then checks it: the frontmatter
# names verify-<project>; SKILL.md has the sections `## Launch`, `## Doctor`,
# `## Drive`, `## Evidence`, `## Cleanup` and `## Feature map`; and it is within
# the skill size budget (skill-budget.sh).
#
# <adapter> defaults to the `adapter` line of tools/verify/factory-version. <project>
# is factory_project_name (lib/project.sh), the name adopt.sh gives the Sonnet
# Editor. <dir> defaults to .claude/skills/verify-<project>. A <dir> that already
# holds a SKILL.md is refused unless --force, which replaces the files the adapter
# writes and leaves any others.
#
# stdout: <dir>, on success. Problems go to stderr.
# Exit codes: 0 written, 1 refused or the adapter's output failed a check, 2 usage.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/project.sh"

FACTORY_VERIFY_SKILL_SECTIONS=(Launch Doctor Drive Evidence Cleanup "Feature map")

usage() {
	echo "usage: bash factory/core/verify-skill.sh [--adapter <name>] [--out <dir>] [--force]" >&2
	exit 2
}
die() {
	echo "verify-skill: $*" >&2
	exit 1
}

adapter="" out="" force=0
while [ "$#" -gt 0 ]; do
	case "$1" in
		--adapter)
			[ "$#" -ge 2 ] || usage
			adapter="$2"
			shift 2
			;;
		--out)
			[ "$#" -ge 2 ] || usage
			out="$2"
			shift 2
			;;
		--force)
			force=1
			shift
			;;
		*) usage ;;
	esac
done

if [ -z "$adapter" ] && [ -f "$FACTORY_STEPS_DIR/factory-version" ]; then
	adapter="$(tr -d '\r' < "$FACTORY_STEPS_DIR/factory-version" | awk '$1 == "adapter" { print $2; exit }')"
fi
[ -n "$adapter" ] || {
	echo "verify-skill: no adapter: pass --adapter, or adopt first (tools/verify/factory-version)" >&2
	exit 2
}
generator="$core/../adapters/$adapter/verify-skill.sh"
[ -f "$generator" ] || die "the $adapter adapter has no verify-skill generator ($generator)"

project="$(factory_project_name)"
[ -n "$project" ] || die "cannot name the project"
name="verify-$project"
[ -n "$out" ] || out=".claude/skills/$name"
[ "$force" -eq 1 ] || [ ! -e "$out/SKILL.md" ] || die "$out/SKILL.md exists; pass --force to replace it"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/$name"
bash "$generator" "$project" "$tmp/$name" >&2 || die "the $adapter adapter's generator failed"

skill="$tmp/$name/SKILL.md"
[ -f "$skill" ] || die "the $adapter adapter's generator wrote no SKILL.md"
got="$(tr -d '\r' < "$skill" | awk 'NR == 1 && $0 == "---" { f = 1; next } f && $0 == "---" { exit } f && /^name:/ { sub(/^name:[[:space:]]*/, ""); print; exit }')"
[ "$got" = "$name" ] || die "SKILL.md names '$got', not '$name'"
for section in "${FACTORY_VERIFY_SKILL_SECTIONS[@]}"; do
	tr -d '\r' < "$skill" | grep -qxF "## $section" || die "SKILL.md has no '## $section' section"
done
budget="$(bash "$core/skill-budget.sh" "$tmp")" || die "the skill is over the size budget:"$'\n'"$budget"

mkdir -p "$out" || die "could not make $out"
cp -R "$tmp/$name/." "$out/" || die "could not write $out"
printf '%s\n' "$out"
