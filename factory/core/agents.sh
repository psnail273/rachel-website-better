#!/usr/bin/env bash
# The factory's section of AGENTS.md (lib/agents.sh). Run from the project root:
#   bash factory/core/agents.sh generate   write the section from its template
#   bash factory/core/agents.sh check      print a finding when the section differs
#
# generate replaces what lies between the markers and leaves the rest of AGENTS.md
# as it was; without markers it appends the section, and without AGENTS.md it
# creates one. It is idempotent: a second run writes the same bytes. adopt.sh runs
# it; sync.sh and amend.sh record rerun it when the template changes.
#
# Exit codes: 0 ok, 1 drift (check) or broken markers, 2 usage.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/findings.sh"
. "$core/lib/agents.sh"

[ "$#" -eq 1 ] && case "$1" in generate | check) true ;; *) false ;; esac || {
	echo "usage: bash factory/core/agents.sh generate|check" >&2
	exit 2
}

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

if ! factory_agents_render "$core" "$FACTORY_AGENTS_FILE" > "$tmp"; then
	msg="needs one factory:begin marker line followed by one factory:end line, or neither"
	if [ "$1" = check ]; then
		factory_finding "$FACTORY_AGENTS_FILE" 1 agents-section "$msg"
	else
		echo "agents: $FACTORY_AGENTS_FILE $msg; fix it by hand, then generate again" >&2
	fi
	exit 1
fi

if [ -f "$FACTORY_AGENTS_FILE" ] && tr -d '\r' < "$FACTORY_AGENTS_FILE" | cmp -s "$tmp" -; then
	exit 0
fi
if [ "$1" = check ]; then
	factory_finding "$FACTORY_AGENTS_FILE" 1 agents-section "the factory section differs from factory/core/templates/agents-section.md; run bash factory/core/agents.sh generate"
	exit 1
fi
cp "$tmp" "$FACTORY_AGENTS_FILE"
