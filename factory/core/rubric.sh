#!/usr/bin/env bash
# The Verifier's rubrics. Run from the project root:
#   bash factory/core/rubric.sh [ARCHITECTURE.md]   factory-run's verify-rubric.md with
#                                                   its review-rules marker line replaced by
#                                                   ARCHITECTURE.md's `review`-tagged rules
#                                                   (lib/architecture.sh)
#   bash factory/core/rubric.sh --brief             the brief review's rubric: factory-run's
#                                                   brief-rubric.md as it is
#
# The output depends only on the files, so two runs on one tree are identical.
# prompt.sh puts it into each Verifier prompt, and the --brief one into each
# brief review's prompt.
#
# Exit codes: 0 ok, 1 a file is missing or the marker isn't there once, 2 usage.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/architecture.sh"

usage() {
	echo "usage: bash factory/core/rubric.sh [ARCHITECTURE.md], or bash factory/core/rubric.sh --brief" >&2
	exit 2
}

# The brief review's rubric fills nothing in, so it reads no ARCHITECTURE.md.
if [ "${1:-}" = --brief ]; then
	[ "$#" -eq 1 ] || usage
	template="$core/../skills/factory-run/brief-rubric.md"
	[ -f "$template" ] || {
		echo "rubric: no template $template" >&2
		exit 1
	}
	tr -d '\r' < "$template" | while IFS= read -r line || [ -n "$line" ]; do
		printf '%s\n' "$line"
	done
	exit 0
fi

template="${FACTORY_RUBRIC_TEMPLATE:-$core/../skills/factory-run/verify-rubric.md}"
marker='<!-- review-rules -->'

[ "$#" -le 1 ] || usage
arch="${1:-ARCHITECTURE.md}"

[ -f "$arch" ] || {
	echo "rubric: no $arch" >&2
	exit 1
}
[ -f "$template" ] || {
	echo "rubric: no template $template" >&2
	exit 1
}
count="$(tr -d '\r' < "$template" | grep -cxF -- "$marker")"
[ "$count" = 1 ] || {
	echo "rubric: $template needs the line '$marker' exactly once (found $count)" >&2
	exit 1
}

rules="$(factory_arch_review_rules "$arch")"
[ -n "$rules" ] || rules="- (none: $arch tags no rule \`review\`)"

tr -d '\r' < "$template" | while IFS= read -r line || [ -n "$line" ]; do
	if [ "$line" = "$marker" ]; then
		printf '%s\n' "$rules"
	else
		printf '%s\n' "$line"
	fi
done
