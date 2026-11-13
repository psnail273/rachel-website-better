#!/usr/bin/env bash
# The Baseline: the tracked list of findings a project had when it adopted the
# factory, which cleanup issues (Partial mode) shrink to empty. Run from the
# project root:
#   bash factory/core/baseline.sh record          write the Baseline from a full verify
#   bash factory/core/baseline.sh gate [entries]  the Partial-mode gate
#   bash factory/core/baseline.sh shrink          drop the Baseline entries now fixed
#   bash factory/core/baseline.sh add <rule>...   add a new check's findings (an amend)
#   bash factory/core/baseline.sh --reuse <subcommand> ...
#
# Each subcommand runs `verify.sh --keep-going`, so it sees every step's findings;
# with --reuse first, `verify.sh --keep-going --reuse`, which prints a gate
# stamp's verdict instead when a run on the same inputs left one (lib/stamp.sh).
# Only failing steps' findings count: a passing step's are information (such as
# deviation's deviation-declared lines, whose commit SHA changes on a rebase).
# A step that fails without printing a finding counts as the finding
# `tools/verify/<step>:1 step-failed the step failed with no findings`.
#
# An entry is a finding without its line number: `file rule message`. Findings
# match entries on file, rule and message only, so an edit that moves a finding
# doesn't make it new. The Baseline keeps duplicates (two identical findings are
# two entries) and is sorted byte-wise.
#
# record  writes tools/verify/ratchet/baseline.txt and stages it with git. It
#         refuses when a Baseline exists: the Baseline only shrinks.
# gate    passes when the current findings are within the Baseline minus the
#         entries named in the file [entries] (the brief's list; one entry per
#         line, with or without the line number; blank and # lines ignored). It
#         prints each finding not allowed, under "new:" or "still present:".
# shrink  rewrites the Baseline to the entries still found. It never adds one.
# add     is for an amend that brings in a check the code already fails (a new
#         lint or arch rule, or one a factory update adds). It adds the current
#         findings of the named rules (a finding's second word: `R15`,
#         `unnamed-tolerance`) to the Baseline and stages it, so the check lands
#         now and a Kind: cleanup issue removes them. It refuses, adding
#         nothing, when any finding outside the Baseline is from another rule:
#         those are not the amend's. The Driver runs it in the amend's own
#         commit; on an issue's branch the deviation step fails the growth.
#
# stdout ends with `baseline: PASS|FAILED|RECORDED|SHRUNK|ADDED ...`; verify's own
# output goes to stderr. Exit codes: 0 done, 1 gate failed or refused, 2 usage.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/findings.sh"

FACTORY_BASELINE="$FACTORY_STEPS_DIR/ratchet/baseline.txt"

usage() {
	echo "usage: bash factory/core/baseline.sh [--reuse] record | gate [entries-file] | shrink | add <rule>..." >&2
	exit 2
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# findings: run a keep-going verify and write its failing steps' findings to $tmp/findings,
# with a step-failed finding for each failed step that printed none.
findings() {
	bash "$core/verify.sh" --keep-going "${reuse[@]}" > "$tmp/verify"
	if [ "$?" -eq 2 ]; then
		echo "baseline: verify refused to run" >&2
		exit 2
	fi
	sed 's/^/  verify: /' "$tmp/verify" >&2
	awk -v re="$FACTORY_FINDING_RE" '
		function flush() { if (failed && !seen) print "tools/verify/" step ":1 step-failed the step failed with no findings" }
		/^== [^ ]+ (PASS|FAIL|SKIP)$/ { flush(); step = $2; failed = ($3 == "FAIL"); seen = 0; next }
		$0 ~ re && failed { print; seen = 1 }
		END { flush() }
	' "$tmp/verify" > "$tmp/findings"
}

# entries: read findings or entries on stdin and print them as sorted entries.
entries() {
	tr -d '\r' | grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*#' |
		sed -E 's/^([^[:space:]]+):[0-9]+ /\1 /' | factory_sort_findings
}

# not_in <entries-file> < findings: print each finding whose entry is not left
# in <entries-file> once earlier findings have used theirs up.
not_in() {
	awk -v list="$1" '
		BEGIN { while ((getline line < list) > 0) allowed[line]++ }
		{ key = $0; sub(/:[0-9]+ /, " ", key) }
		allowed[key] > 0 { allowed[key]--; next }
		{ print }
	'
}

require_baseline() {
	if [ ! -f "$FACTORY_BASELINE" ]; then
		echo "baseline: no Baseline at $FACTORY_BASELINE; run 'baseline.sh record' first" >&2
		exit 1
	fi
	entries < "$FACTORY_BASELINE" > "$tmp/baseline"
}

cmd_record() {
	[ "$#" -eq 0 ] || usage
	if [ -e "$FACTORY_BASELINE" ]; then
		echo "baseline: $FACTORY_BASELINE exists, and the Baseline only shrinks; use 'baseline.sh shrink'" >&2
		exit 1
	fi
	findings
	entries < "$tmp/findings" > "$tmp/new"
	mkdir -p "$(dirname "$FACTORY_BASELINE")"
	cp "$tmp/new" "$FACTORY_BASELINE"
	if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
		if ! git add -- "$FACTORY_BASELINE"; then
			echo "baseline: could not track $FACTORY_BASELINE (is it gitignored?)" >&2
			exit 1
		fi
	fi
	echo "baseline: RECORDED $(wc -l < "$FACTORY_BASELINE" | tr -d ' ') entries in $FACTORY_BASELINE"
}

cmd_gate() {
	[ "$#" -le 1 ] || usage
	require_baseline
	: > "$tmp/named"
	if [ "$#" -eq 1 ]; then
		[ -f "$1" ] || {
			echo "baseline: no entries file $1" >&2
			exit 2
		}
		entries < "$1" > "$tmp/named"
	fi

	# A named entry the Baseline doesn't hold is a mistake in the brief.
	LC_ALL=C comm -23 "$tmp/named" "$tmp/baseline" > "$tmp/unknown"
	if [ -s "$tmp/unknown" ]; then
		echo "named entries not in the Baseline:"
		sed 's/^/  /' "$tmp/unknown"
		echo "baseline: FAILED"
		exit 1
	fi

	findings
	factory_sort_findings < "$tmp/findings" > "$tmp/current"
	LC_ALL=C comm -23 "$tmp/baseline" "$tmp/named" > "$tmp/allowed"
	not_in "$tmp/allowed" < "$tmp/current" > "$tmp/bad"
	# Split the findings not allowed: a named entry still found, or a new one.
	not_in "$tmp/named" < "$tmp/bad" > "$tmp/new"
	entries < "$tmp/new" > "$tmp/new-entries"
	not_in "$tmp/new-entries" < "$tmp/bad" > "$tmp/still"

	if [ ! -s "$tmp/bad" ]; then
		echo "baseline: PASS"
		return 0
	fi
	if [ -s "$tmp/new" ]; then
		echo "new:"
		sed 's/^/  /' "$tmp/new"
	fi
	if [ -s "$tmp/still" ]; then
		echo "still present:"
		sed 's/^/  /' "$tmp/still"
	fi
	echo "baseline: FAILED"
	exit 1
}

cmd_shrink() {
	[ "$#" -eq 0 ] || usage
	require_baseline
	findings
	entries < "$tmp/findings" > "$tmp/current"
	LC_ALL=C comm -12 "$tmp/baseline" "$tmp/current" > "$tmp/kept"
	LC_ALL=C comm -23 "$tmp/baseline" "$tmp/current" > "$tmp/removed"
	cp "$tmp/kept" "$FACTORY_BASELINE"
	if [ -s "$tmp/removed" ]; then
		echo "removed:"
		sed 's/^/  /' "$tmp/removed"
	fi
	echo "baseline: SHRUNK $(wc -l < "$tmp/removed" | tr -d ' ') removed, $(wc -l < "$tmp/kept" | tr -d ' ') left"
}

cmd_add() {
	[ "$#" -ge 1 ] || usage
	local rule
	for rule in "$@"; do
		case "$rule" in "" | *[!A-Za-z0-9_.-]*) usage ;; esac
	done
	if [ -f "$FACTORY_BASELINE" ]; then
		entries < "$FACTORY_BASELINE" > "$tmp/baseline"
	else
		: > "$tmp/baseline"
	fi
	findings
	factory_sort_findings < "$tmp/findings" > "$tmp/current"
	not_in "$tmp/baseline" < "$tmp/current" > "$tmp/outside"
	awk -v rules=" $* " -v named="$tmp/named" -v other="$tmp/other" '
		{ if (index(rules, " " $2 " ")) print > named; else print > other }
	' "$tmp/outside"
	touch "$tmp/named" "$tmp/other"
	if [ -s "$tmp/other" ]; then
		echo "findings outside the Baseline from other rules:"
		sed 's/^/  /' "$tmp/other"
		echo "baseline: FAILED (added nothing; fix those first, or name their rule if the amend adds it)"
		exit 1
	fi
	entries < "$tmp/named" > "$tmp/added"
	mkdir -p "$(dirname "$FACTORY_BASELINE")"
	cat "$tmp/baseline" "$tmp/added" | factory_sort_findings > "$FACTORY_BASELINE"
	if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
		if ! git add -- "$FACTORY_BASELINE"; then
			echo "baseline: could not track $FACTORY_BASELINE (is it gitignored?)" >&2
			exit 1
		fi
	fi
	if [ -s "$tmp/added" ]; then
		echo "added:"
		sed 's/^/  /' "$tmp/added"
	fi
	echo "baseline: ADDED $(wc -l < "$tmp/added" | tr -d ' ') entries for $*, $(wc -l < "$FACTORY_BASELINE" | tr -d ' ') in all"
}

reuse=()
if [ "${1:-}" = --reuse ]; then
	reuse=(--reuse)
	shift
fi
[ "$#" -ge 1 ] || usage
sub="$1"
shift
case "$sub" in
	record) cmd_record "$@" ;;
	gate) cmd_gate "$@" ;;
	shrink) cmd_shrink "$@" ;;
	add) cmd_add "$@" ;;
	*) usage ;;
esac
