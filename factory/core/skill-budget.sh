#!/usr/bin/env bash
# The skill size budget: every <skills-dir>/*/SKILL.md has a frontmatter
# description of at most 200 characters and is at most 100 lines long, and a
# skill inside the factory folder (this script's core/..) holds at most its word
# budget (LC_ALL=C wc -w).
#   bash factory/core/skill-budget.sh [skills-dir...]
# The word budgets are in core/skill-words, one `<skill folder> <max words>` line
# each, the folder named from the factory folder (skills/build,
# adapters/godot/skills/write-tests-godot) however the skills-dir is spelled; a
# skill inside the factory that it doesn't list has the default, 1000 words.
# Raising a budget is an edit to that file. A skill outside the factory folder
# (a generated verify-<project> skill) has no word budget: its lines limit it.
# Default: factory/skills, factory/workspace-skills (the skills only the
# factory's own repo installs) and every adapter's factory/adapters/*/skills; in a
# clone of the factory's repo (VERSION and core/ at the top of its checkout),
# skills, workspace-skills and adapters/*/skills there. Prints findings, sorted, and exits 1 on
# any. No skills is a pass.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/findings.sh"

FACTORY_SKILL_MAX_DESCRIPTION=200
FACTORY_SKILL_MAX_LINES=100
# A skill skill-words doesn't list: about 100 lines of ten words, the size the
# line budget meant before long lines outgrew it.
FACTORY_SKILL_DEFAULT_WORDS=1000
words_file="$core/skill-words"
factory_root="$(cd "$core/.." && pwd -P)"

if [ "$#" -ge 1 ]; then
	dirs=("$@")
elif cdup="$(git -C "$core/.." rev-parse --show-cdup 2> /dev/null)" && [ -z "$cdup" ] && [ -f "$core/../VERSION" ]; then
	cd "$core/.." || exit 1
	dirs=(skills workspace-skills adapters/*/skills)
else
	# From the folder holding factory/, so findings name factory/skills/....
	cd "$core/../.." || exit 1
	dirs=(factory/skills factory/workspace-skills factory/adapters/*/skills)
fi

# skill_key <SKILL.md>: its folder named from the factory folder; fails for a
# skill outside it.
skill_key() {
	local d
	d="$(cd "$(dirname "$1")" && pwd -P)" || return 1
	case "$d" in
		"$factory_root"/*) printf '%s\n' "${d#"$factory_root"/}" ;;
		*) return 1 ;;
	esac
}

# budget_for <skill folder>: its word budget from the words file, or the default.
budget_for() {
	local max=""
	[ -f "$words_file" ] && max="$(tr -d '\r' < "$words_file" | awk -v want="$1" '
		/^[[:space:]]*(#|$)/ { next }
		$1 == want && $2 ~ /^[0-9]+$/ { print $2; exit }
	')"
	printf '%s\n' "${max:-$FACTORY_SKILL_DEFAULT_WORDS}"
}

check() {
	local dir skill lines words key max desc bad=0
	for dir in "${dirs[@]}"; do
		for skill in "$dir"/*/SKILL.md; do
			[ -f "$skill" ] || continue
			lines="$(awk 'END { print NR }' "$skill")"
			if [ "$lines" -gt "$FACTORY_SKILL_MAX_LINES" ]; then
				factory_finding "$skill" 1 skill-too-long "$lines lines; the budget is $FACTORY_SKILL_MAX_LINES"
				bad=1
			fi
			if key="$(skill_key "$skill")"; then
				words="$(LC_ALL=C wc -w < "$skill" | tr -d '[:space:]')"
				max="$(budget_for "$key")"
				if [ "$words" -gt "$max" ]; then
					factory_finding "$skill" 1 skill-too-many-words "$words words; the budget is $max"
					bad=1
				fi
			fi
			# The description line inside the leading --- frontmatter block.
			desc="$(tr -d '\r' < "$skill" | awk '
				NR == 1 && $0 == "---" { inside = 1; next }
				inside && $0 == "---" { exit }
				inside && /^description:/ { sub(/^description:[[:space:]]*/, ""); print; exit }
			')"
			desc="${desc#\"}"
			desc="${desc%\"}"
			if [ -z "$desc" ]; then
				factory_finding "$skill" 1 skill-description-missing "no one-line description in the frontmatter"
				bad=1
			elif [ "${#desc}" -gt "$FACTORY_SKILL_MAX_DESCRIPTION" ]; then
				factory_finding "$skill" 1 skill-description-too-long "${#desc} characters; the budget is $FACTORY_SKILL_MAX_DESCRIPTION"
				bad=1
			fi
		done
	done
	return "$bad"
}

out="$(check)"
status=$?
[ -n "$out" ] && printf '%s\n' "$out" | factory_sort_findings
exit "$status"
