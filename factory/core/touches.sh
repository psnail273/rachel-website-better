#!/usr/bin/env bash
# A Run's Pick by area (the build skill's parallel.md): which ready issues can go
# now, by the `Touches:` lines the Spec gave its slices (the spec skill's
# slicing.md). Run from any checkout of the repo:
#   bash factory/core/touches.sh pick [--busy <n>:<body file>]... <n>:<body file>...
#   bash factory/core/touches.sh areas <body file>
#
# Each <n>:<body file> after the options is a ready issue, in the Spec's order:
# its number, and its body as the tracker gives it, saved to a file. pick prints
# `#<n>`, one per line in that order, for each issue to dispatch now: one whose
# areas share none with an issue in flight or with one picked before it. In
# flight are the issue/<n> branches checked out in a worktree of this repo (a
# parked issue's too: its worktree still holds its files), each read from the
# <git-dir>/factory/issue.md start.sh saves there, and each --busy issue: one
# dispatched whose issue.md isn't saved yet (its driver hasn't run start.sh, or
# start.sh hasn't got that far). A candidate already in flight is the Resume
# step's, not the Pick's. For each issue it doesn't pick it says why on stderr,
# one of
#   touches: #<n> waits on #<m>: <area>
#   touches: #<n> is in flight
# and for an issue in flight with no issue.md to read and no --busy body, whose
# areas it can't hold:
#   touches: #<n> is in flight with no issue.md to read its areas from; pass its body as --busy <n>:<file>
#
# An issue's areas are on its first `Touches:` line, split at commas and
# semicolons, each trimmed of blanks, backticks, a closing full stop and a leading
# "the", and compared without case: "The header." and "header" are one area. A
# missing line, an empty one or `Touches: none` names no area and overlaps
# nothing; `brief.sh seal`'s brief-overlap stays the backstop for what the areas
# miss, and for an issue in flight whose areas can't be read. areas prints an
# issue's areas, as compared, one per line.
#
# Exit codes: 0 ok (nothing to pick included), 2 usage (a body file that can't
# be read among them).
set -u

usage() {
	sed -n '2,30s/^# \{0,1\}//p' "${BASH_SOURCE[0]}" >&2
	exit 2
}

# areas <file>: the areas of the issue in <file>, one per line, each once.
areas() {
	local line a
	line="$(tr -d '\r' < "$1" | sed -n '/^[[:space:]]*Touches:/{s/^[[:space:]]*Touches://p;q;}')"
	while IFS= read -r a; do
		a="${a//\`/}"
		a="$(printf '%s' "${a,,}" | tr -s '[:space:]' ' ')"
		a="${a# }"
		a="${a% }"
		a="${a%.}"
		a="${a% }"
		a="${a#the }"
		[ -n "$a" ] && [ "$a" != none ] && printf '%s\n' "$a"
	done < <(printf '%s\n' "$line" | tr ',;' '\n') | awk '!seen[$0]++'
}

# body <arg>: check a <n>:<body file> argument, setting n and file.
body() {
	n="${1%%:*}" file="${1#*:}"
	case "$n" in
		'' | *[!0-9]*)
			echo "touches: $1 is not <n>:<body file>" >&2
			usage
			;;
	esac
	[ "$file" != "$1" ] && [ -f "$file" ] && [ -r "$file" ] || {
		echo "touches: no body file for #$n: $file" >&2
		usage
	}
}

case "${1:-}" in
	areas)
		[ "$#" -eq 2 ] && [ -f "$2" ] && [ -r "$2" ] || usage
		areas "$2"
		exit 0
		;;
	pick) shift ;;
	*) usage ;;
esac

# held: one line per area in flight, "<n> <area>"; flying: " <n> " for each
# issue; unread: each in flight with no issue.md; busy: " <n> " for each --busy.
held="" flying=" " unread=() busy=" "
hold() {
	local a
	flying+="$1 "
	while IFS= read -r a; do
		[ -n "$a" ] && held+="$1 $a"$'\n'
	done < <(areas "$2")
}

while IFS=$'\t' read -r n dir; do
	flying+="$n "
	gitdir="$(git -C "$dir" rev-parse --path-format=absolute --git-dir 2> /dev/null)" || continue
	if [ -f "$gitdir/factory/issue.md" ] && [ -r "$gitdir/factory/issue.md" ]; then
		hold "$n" "$gitdir/factory/issue.md"
	else
		unread+=("$n")
	fi
done < <(git worktree list --porcelain 2> /dev/null | tr -d '\r' | awk '
	/^worktree / { dir = substr($0, 10) }
	/^branch refs\/heads\/issue\/[0-9]+$/ { print substr($0, 25) "\t" dir }
')

candidates=()
while [ "$#" -gt 0 ]; do
	case "$1" in
		--busy)
			[ "$#" -ge 2 ] || usage
			body "$2"
			hold "$n" "$file"
			busy+="$n "
			shift 2
			;;
		-h | --help) usage ;;
		*)
			body "$1"
			candidates+=("$1")
			shift
			;;
	esac
done
[ "${#candidates[@]}" -gt 0 ] || usage

for n in "${unread[@]}"; do
	case "$busy" in *" $n "*) continue ;; esac
	echo "touches: #$n is in flight with no issue.md to read its areas from; pass its body as --busy $n:<file>" >&2
done

for c in "${candidates[@]}"; do
	body "$c"
	case "$flying" in *" $n "*)
		echo "touches: #$n is in flight" >&2
		continue
		;;
	esac
	clash=""
	while IFS= read -r a; do
		[ -n "$a" ] || continue
		clash="$(printf '%s' "$held" | awk -v a="$a" '{ m = $1; sub(/^[^ ]* /, "") } $0 == a { print m; exit }')"
		[ -z "$clash" ] || break
	done < <(areas "$file")
	if [ -n "$clash" ]; then
		echo "touches: #$n waits on #$clash: $a" >&2
		continue
	fi
	echo "#$n"
	hold "$n" "$file"
done
exit 0
