#!/usr/bin/env bash
# Print an issue's fixed prompts, filled in, for the Driver to redirect to a
# round's prompt file (the build skill's editor.md). Run in the issue's worktree, from
# its root:
#   bash factory/core/prompt.sh editor <phase>     the first Editor round; <phase> is
#                                                  red, `red, small lane`, partial,
#                                                  `green, test-only` or `green, amend`
#                                                  (a Kind amend in Phase green, whose
#                                                  Verifier takes phase green)
#   bash factory/core/prompt.sh green              the green round after the Lock: the
#                                                  green line, then the footer
#   bash factory/core/prompt.sh footer             a blank line, then the footer that
#                                                  ends every later round, to append
#                                                  under the Driver's own text
#   bash factory/core/prompt.sh verifier <phase>   a Verifier check; <phase> is red,
#                                                  green, `green, small lane` or
#                                                  `green, test-only`
#   bash factory/core/prompt.sh brief-review       the brief review's check
# A phase of two words may be one argument or several: `editor red, small lane`.
#
# Each prints its template from the build skill's prompts/ folder (editor.md, green.md,
# footer.md, verifier.md, brief-review.md) with these placeholders filled in, so
# the Driver never retypes the brief, the issue or the fixed text:
#   <n> <title>  from the issue's first line, `#<n>: <title>`
#   <phase>      the phase given
#   <base>       the diff base's commit, as the deviation step takes it: $FACTORY_BASE
#                when set, else the merge-base of HEAD and $FACTORY_BASE_BRANCH
#                (default dev; lib/diff.sh)
#   <issue>      the issue as start.sh saved it at Start (its --title), in
#                <git-dir>/factory/issue.md: the line `#<n>: <title>`, then its body
#   <brief>      the sealed Build Brief, <git-dir>/factory/brief.md ($FACTORY_BRIEF
#                when set; lib/brief.sh), verbatim
#   <rubric>     the output of rubric.sh for a Verifier, of rubric.sh --brief for
#                the brief review
# <issue>, <brief> and <rubric> each fill a line that holds only the placeholder;
# the others fill in within their line. What fills a placeholder is never read for
# one, and any other <...> in a template, such as `<path or rule>`, is left as it is.
# Nothing is printed unless every input is there and readable.
#
# A Verifier check comes after an Editor round, so verifier also needs the
# Editor's gate to have passed at HEAD: the run state's stamp for HEAD, which the
# Editor's stop hook records (factory_editor_gate_check, lib/run.sh). Without
# it, verifier runs that gate itself, once its inputs are there, and prints the
# prompt only when the gate passes; when it fails, it prints nothing and puts
# the gate's findings on stderr, for the Driver to send the Editor as a fix round.
#
# Exit codes: 0 ok, 1 an input is missing, unreadable or malformed (it names the
# file), rubric.sh failed or the Editor's gate fails (verifier), 2 usage.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/findings.sh"
. "$core/lib/brief.sh"
. "$core/lib/diff.sh"
. "$core/lib/run.sh"

prompts="$core/../skills/build/prompts"

usage() {
	echo "usage: bash factory/core/prompt.sh editor <red | red, small lane | partial | green, test-only | green, amend>" >&2
	echo "       bash factory/core/prompt.sh verifier <red | green | green, small lane | green, test-only>" >&2
	echo "       bash factory/core/prompt.sh green | footer | brief-review" >&2
	exit 2
}

die() {
	echo "prompt: $*" >&2
	exit 1
}

[ "$#" -ge 1 ] || usage
what="$1"
shift
phase="$*"
case "$what" in
	editor) case "$phase" in red | 'red, small lane' | partial | 'green, test-only' | 'green, amend') ;; *) usage ;; esac ;;
	verifier) case "$phase" in red | green | 'green, small lane' | 'green, test-only') ;; *) usage ;; esac ;;
	green | footer | brief-review) [ "$#" -eq 0 ] || usage ;;
	*) usage ;;
esac

tmp="$(mktemp -d)" || die "could not make a temp folder"
trap 'rm -rf "$tmp"' EXIT
n="" title="" base="" issue="" brief=""

# need_issue: the issue file, and <n> and <title> from its first line.
need_issue() {
	local dir first re='^#([1-9][0-9]*): (.+)$'
	dir="$(git rev-parse --path-format=relative --git-dir 2> /dev/null)" || die "not in a git repository; run it in the issue's worktree"
	issue="$dir/factory/issue.md"
	[ -s "$issue" ] || die "no issue at $issue; save it with start.sh from the main checkout: pipe the issue's raw body into 'bash factory/core/start.sh <n> --title \"<title>\"'"
	can_read "$issue"
	IFS= read -r first < "$issue"
	first="${first%$'\r'}"
	if [[ $first =~ $re ]] && [ -n "${BASH_REMATCH[2]//[[:space:]]/}" ]; then
		n="${BASH_REMATCH[1]}"
		title="${BASH_REMATCH[2]}"
	else
		die "$issue starts with '$first', not the line '#<n>: <title>'"
	fi
}

# need_brief: the sealed brief's path.
need_brief() {
	brief="$(factory_brief_path)" || die "not in a git repository; run it in the issue's worktree"
	[ -s "$brief" ] || die "no Build Brief at $brief; write it and seal it first"
	can_read "$brief"
}

# need_base: the diff base, as a commit SHA.
need_base() {
	local b
	b="$(factory_diff_base)" || die "no merge-base of HEAD and '${FACTORY_BASE_BRANCH:-dev}'; set FACTORY_BASE or FACTORY_BASE_BRANCH"
	base="$(git rev-parse --verify -q "$b^{commit}")" || die "the diff base '$b' names no commit"
}

# need_rubric [--brief]: rubric.sh's output, in $tmp/rubric.
need_rubric() {
	bash "$core/rubric.sh" "$@" > "$tmp/rubric" || die "rubric.sh${1:+ $1} failed, so the prompt has no rubric"
}

# can_read <file>: dies unless the file is a regular file it can read.
can_read() {
	[ -f "$1" ] && [ -r "$1" ] || die "can't read $1"
}

# copy <file> <to>: copies the file in one read, or dies, so a read that fails at
# any point stops the prompt.
copy() {
	cat "$1" > "$2" || die "can't read $1"
}

# put <file>: the file as it is, ending in a newline.
put() {
	copy "$1" "$tmp/put"
	cat "$tmp/put"
	[ -z "$(tail -c 1 "$tmp/put")" ] || echo
}

# fill <template>: the template with its placeholders filled in. <title> goes in
# last, so a title is never read for the others.
fill() {
	local line
	[ -f "$1" ] || die "no template $1"
	copy "$1" "$tmp/template"
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line%$'\r'}"
		case "$line" in
			'<issue>') put "$issue" ;;
			'<brief>') put "$brief" ;;
			'<rubric>') put "$tmp/rubric" ;;
			*)
				line="${line//'<n>'/"$n"}"
				line="${line//'<phase>'/"$phase"}"
				line="${line//'<base>'/"$base"}"
				line="${line//'<title>'/"$title"}"
				printf '%s\n' "$line"
				;;
		esac
	done < "$tmp/template"
}

{
	case "$what" in
		editor)
			need_issue
			need_brief
			fill "$prompts/editor.md"
			;;
		green)
			fill "$prompts/green.md"
			echo
			fill "$prompts/footer.md"
			;;
		footer)
			echo
			fill "$prompts/footer.md"
			;;
		verifier)
			need_issue
			need_brief
			need_base
			need_rubric
			factory_editor_gate_check prompt || exit 1
			fill "$prompts/verifier.md"
			;;
		brief-review)
			need_issue
			need_brief
			need_rubric --brief
			fill "$prompts/brief-review.md"
			;;
	esac
} > "$tmp/prompt"
cat "$tmp/prompt"
