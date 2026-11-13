#!/usr/bin/env bash
# Install the factory's machine tools, the ones a Run calls by name:
#   claude-usage  totals the Claude tokens per issue and per session (the retro)
# They ship in factory/tools/ so a project that adopts the factory brings them,
# and they run from a folder on PATH so the human's autoMode.allow entries name
# one fixed path on the machine.
#
#   bash factory/tools/install.sh [<bin>]          copy them into <bin> (default ~/.local/bin)
#   bash factory/tools/install.sh --check [<bin>]  exit 1 unless <bin> holds these same copies
#
# install copies over an older copy, and removes from <bin> the retired tools
# (ai-pane and codex-verify, the Cursor Editor's and the Codex Verifier's) when
# they are the factory's copies, known by their second line (retired_copy).
# --check flags one still there.
#
# Exit codes: 0 ok, 1 a copy failed or (--check) is missing or differs, 2 usage.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tools="claude-usage"
retired="ai-pane codex-verify"

# retired_copy <tool> <file>: true when the file is the factory's copy of that
# retired tool, by the second line every release of it had.
retired_copy() {
	local mark
	case "$1" in
		ai-pane) mark="# Run Cursor's CLI agent (\`agent\`) as named jobs" ;;
		codex-verify) mark="# codex-verify: one fresh Verifier check with Codex" ;;
	esac
	[ -f "$2" ] && sed -n 2p "$2" | grep -qF -- "$mark"
}

check=""
if [ "${1:-}" = --check ]; then
	check=1
	shift
fi
[ "$#" -le 1 ] || {
	echo "usage: bash factory/tools/install.sh [--check] [<bin>]" >&2
	exit 2
}
bin="${1:-${HOME:?}/.local/bin}"

status=0
for tool in $tools; do
	if [ -n "$check" ]; then
		if [ ! -f "$bin/$tool" ]; then
			echo "install: $bin/$tool is missing; run bash factory/tools/install.sh" >&2
			status=1
		elif ! cmp -s "$here/$tool" "$bin/$tool"; then
			echo "install: $bin/$tool differs from factory/tools/$tool; run bash factory/tools/install.sh" >&2
			status=1
		fi
		continue
	fi
	mkdir -p -- "$bin" || exit 1
	# Through a temp file in <bin>, renamed into place: a running copy keeps its inode.
	if cp -- "$here/$tool" "$bin/.$tool.$$" && chmod 755 "$bin/.$tool.$$" && mv -f -- "$bin/.$tool.$$" "$bin/$tool"; then
		echo "install: $bin/$tool"
	else
		rm -f -- "$bin/.$tool.$$"
		status=1
	fi
done
for tool in $retired; do
	retired_copy "$tool" "$bin/$tool" || continue
	if [ -n "$check" ]; then
		echo "install: $bin/$tool is retired; run bash factory/tools/install.sh to remove it" >&2
		status=1
	elif rm -f -- "$bin/$tool"; then
		echo "install: removed the retired $bin/$tool"
	else
		status=1
	fi
done
exit "$status"
