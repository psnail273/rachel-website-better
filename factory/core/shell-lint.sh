#!/usr/bin/env bash
# The shell lint: shellcheck and shfmt over every shell script the factory ships or
# the gate runs. The factory's test suite runs it, one test per script
# (tests/shell_lint_test.sh). Run from anywhere:
#   bash factory/core/shell-lint.sh            every shell script
#   bash factory/core/shell-lint.sh <path...>  only these, relative to the project root
#   bash factory/core/shell-lint.sh --list     print the scripts it lints, one per line
#   bash factory/core/shell-lint.sh --tools    only check the tools against their pins
#
# A shell script is a file under factory/ or tools/verify/ (in a clone of the
# factory's repo, VERSION and core/ at the top of its checkout: any file of the
# clone, paths relative to its top), tracked or untracked but not ignored by git, that is named *.sh or opens with a sh, bash or dash
# shebang (#!/bin/sh, #!/usr/bin/env bash, #!/usr/bin/env -S bash -e). A new
# script is linted with no list to update.
#
# The shellcheck run takes --norc and the codes ../.shellcheckrc disables (the one
# config, which shellcheck run by hand under factory/ reads too), so tools/verify/
# gets them as well and no other rc file counts. Both tools get the dialect: the
# shell the shebang runs (script_shell), or bash for a script with no shebang (a
# sourced lib or test suite); shellcheck as -s, shfmt as -ln (posix for sh, dash).
# shfmt diffs each script against its formatting with these flags, the only place
# they are written down:
SHFMT_FLAGS=(-ci -sr)
#
# Another version flags differently, so the tools are pinned, and the lint runs
# neither until both are at their pins:
SHELLCHECK_PIN=0.9.0
SHFMT_PIN=3.8.0
SHELL_LINT_INSTALL="sudo apt install -y shellcheck shfmt"
#
# Prints each finding on stdout: shellcheck's as <file>:<line>:<column>: lines,
# shfmt's as a diff whose header names the file. Exits 0 when every script is
# clean, 1 on a finding, 2 on a usage error or a bad config line, and 3 when a tool
# is missing or not at its pin (why, and the install command, on stderr).
set -u

core="${BASH_SOURCE[0]%/*}"
[ "$core" != "${BASH_SOURCE[0]}" ] || core=.
core="$(cd "$core" && pwd)" || exit 2
. "$core/lib/steps.sh"
. "$core/lib/vendor.sh"

usage() {
	echo "usage: bash factory/core/shell-lint.sh [--list | --tools | <path>...]" >&2
	exit 2
}

# tool_version <tool>: the version the tool prints, or "none" when it is not on
# PATH. Builtins only, so a test can run the check with a bare PATH.
tool_version() {
	local text
	if ! command -v "$1" > /dev/null; then
		echo none
		return
	fi
	text="$("$1" --version 2> /dev/null)"
	case "$1" in
		# "version: 0.9.0", on a line of its own.
		shellcheck) [[ $text =~ (^|$'\n')version:\ ([^[:space:]]+) ]] && text="${BASH_REMATCH[2]}" ;;
		# "3.8.0", or "v3.8.0" from an upstream build.
		shfmt) text="${text#v}" ;;
	esac
	echo "${text:-unknown}"
}

# check_tools: true when both tools are at their pins; otherwise say which is not,
# and how to install them, on stderr.
check_tools() {
	local tool pin found bad=0
	for tool in shellcheck shfmt; do
		pin=SHELLCHECK_PIN
		[ "$tool" = shellcheck ] || pin=SHFMT_PIN
		found="$(tool_version "$tool")"
		if [ "$found" != "${!pin}" ]; then
			echo "shell-lint: $tool: expected ${!pin}, found $found" >&2
			bad=1
		fi
	done
	[ "$bad" -eq 0 ] && return 0
	echo "shell-lint: install them with: $SHELL_LINT_INSTALL (Ubuntu 24.04 has shellcheck $SHELLCHECK_PIN and shfmt $SHFMT_PIN)" >&2
	return 1
}

# script_shell <first line>: set SCRIPT_SHELL to the shell a sh, bash or dash
# shebang runs, the way Linux and GNU env read the line; false, with it empty, for
# any other line. The kernel splits the line only at blanks (spaces and tabs), and
# passes env the rest of the line as one argument, so env runs a command only when
# that is one word (#!/usr/bin/env bash) or a -S or --split-string= string, whose
# words it reads past options (-u, -C and -P with their argument) and NAME=VALUE. A string with a quote, a backslash, a $ or a #
# is beyond this reader, and its script is not found: name it *.sh instead.
script_shell() {
	local line="${1%$'\r'}" interp args w i=0
	local -a words
	SCRIPT_SHELL=""
	[[ $line == '#!'* ]] || return 1
	line="${line#??}"
	line="${line#"${line%%[![:blank:]]*}"}"
	interp="${line%%[[:blank:]]*}"
	args="${line#"$interp"}"
	args="${args#"${args%%[![:blank:]]*}"}"
	args="${args%"${args##*[![:blank:]]}"}"
	w="$interp"
	if [ "${interp##*/}" = env ]; then
		case "$args" in
			-S*) args="${args#-S}" ;;
			--split-string=*) args="${args#--split-string=}" ;;
			*[[:blank:]]*) return 1 ;;
		esac
		case "$args" in
			*\'* | *\"* | *\\* | *\$* | *\#*) return 1 ;;
		esac
		read -r -a words <<< "$args"
		w=""
		while [ "$i" -lt "${#words[@]}" ]; do
			case "${words[i]}" in
				-S?*) words[i]="${words[i]#-S}" ;;
				--split-string=*) words[i]="${words[i]#--split-string=}" ;;
				-u | -C | -P | --unset | --chdir) i=$((i + 2)) ;;
				-* | *=*) i=$((i + 1)) ;;
				*)
					w="${words[i]}"
					break
					;;
			esac
		done
	fi
	case "${w##*/}" in
		sh | bash | dash) SCRIPT_SHELL="${w##*/}" ;;
		*) return 1 ;;
	esac
}

# first_line <file>: its first line, at most 128 characters of it.
first_line() {
	local line=""
	IFS= read -r -n 128 line < "$1" 2> /dev/null
	printf '%s' "$line"
}

# list: every shell script, relative to the project root, sorted; false outside
# a git checkout.
list() {
	local f
	git rev-parse --git-dir > /dev/null 2>&1 || {
		echo "shell-lint: not in a git checkout: $PWD" >&2
		return 1
	}
	git -c core.quotePath=false ls-files -co --exclude-standard -z -- "${scope[@]}" |
		while IFS= read -r -d '' f; do
			[ -f "$f" ] && [ ! -L "$f" ] || continue
			case "${f##*/}" in
				*.sh) printf '%s\n' "$f" ;;
				# Secrets stay unread, even their first line.
				.env* | *.env | *credentials*) ;;
				*) script_shell "$(first_line "$f")" && printf '%s\n' "$f" ;;
			esac
		done | LC_ALL=C sort -u
}

# disabled_codes: the codes ../.shellcheckrc disables, comma-separated. A line in
# it that is not a comment, a blank or a disable line with its reason is an error,
# since the lint would not pass it on.
disabled_codes() {
	local rc="$core/../.shellcheckrc" line codes="" n=0
	[ -f "$rc" ] || {
		echo "shell-lint: no config at $FACTORY_VENDOR_DIR/.shellcheckrc" >&2
		return 1
	}
	while IFS= read -r line || [ -n "$line" ]; do
		n=$((n + 1))
		line="${line%$'\r'}"
		[[ $line =~ ^[[:space:]]*(#.*)?$ ]] && continue
		if [[ $line =~ ^disable=(SC[0-9]+(,SC[0-9]+)*)[[:space:]]+#[[:space:]]*[^[:space:]] ]]; then
			codes+="${codes:+,}${BASH_REMATCH[1]}"
		else
			echo "shell-lint: $FACTORY_VENDOR_DIR/.shellcheckrc:$n: expected 'disable=<code,...> # <reason>', got: $line" >&2
			return 1
		fi
	done < "$rc"
	printf '%s' "$codes"
}

# lint <file>: print the file's findings; false when it has any.
lint() {
	local f="$1" first text status bad=0
	local -a opts=(--norc -f gcc) dialect=()
	[ -z "$codes" ] || opts+=(-e "$codes")
	first="$(first_line "$f")"
	if script_shell "$first"; then
		opts+=(-s "$SCRIPT_SHELL")
	elif [[ $first != '#!'* ]]; then
		SCRIPT_SHELL=bash
		opts+=(-s bash)
	fi
	case "$SCRIPT_SHELL" in
		bash) dialect=(-ln bash) ;;
		sh | dash) dialect=(-ln posix) ;;
	esac
	text="$(shellcheck "${opts[@]}" -- "$f" 2>&1)"
	status=$?
	if [ "$status" -ne 0 ]; then
		printf '%s\n' "${text:-$f: shellcheck exited $status}"
		bad=1
	fi
	text="$(shfmt "${SHFMT_FLAGS[@]}" "${dialect[@]}" -d -- "$f" 2>&1)"
	status=$?
	if [ "$status" -ne 0 ]; then
		printf '%s\n' "${text:-$f: shfmt exited $status}"
		bad=1
	fi
	return "$bad"
}

mode=lint
case "${1:-}" in
	--list | --tools)
		[ "$#" -eq 1 ] || usage
		mode="${1#--}"
		;;
	-*) usage ;;
esac

if cdup="$(git -C "$core/.." rev-parse --show-cdup 2> /dev/null)" && [ -z "$cdup" ] && [ -f "$core/../VERSION" ]; then
	cd "$core/.." || exit 2
	scope=(.)
else
	cd "$core/../.." || exit 2
	scope=("$FACTORY_VENDOR_DIR" "$FACTORY_STEPS_DIR")
fi
if [ "$mode" = list ]; then
	list
	exit
fi
check_tools || exit 3
[ "$mode" = tools ] && exit 0
codes="$(disabled_codes)" || exit 2

files=("$@")
if [ "$#" -eq 0 ]; then
	listing="$(list)" || exit 2
	if [ -z "$listing" ]; then
		echo "shell-lint: found no shell script under $FACTORY_VENDOR_DIR/ or $FACTORY_STEPS_DIR/" >&2
		exit 2
	fi
	mapfile -t files <<< "$listing"
fi
failed=0
for f in "${files[@]}"; do
	if [ ! -f "$f" ]; then
		echo "shell-lint: no file $f" >&2
		exit 2
	fi
	lint "$f" || failed=$((failed + 1))
done
if [ "$failed" -gt 0 ]; then
	echo "shell-lint: $failed of ${#files[@]} scripts have findings" >&2
	exit 1
fi
