#!/usr/bin/env bash
# The pin check: each tool's version against the project's tracked pin file.
# Run from the project root (the runner runs it as part of prepare):
#   bash factory/core/pins.sh
#
# tools/verify/pins   tracked; one `<tool> <version>` per line, # comments allowed.
# tools/verify/versions  project-owned probe; prints one `<tool> <version>` per
#                     line for the tools it finds. It may read local.env's paths.
#
# Prints findings, sorted, and exits 1 on any mismatch. Versions compare as exact
# strings, so the probe normalises what each tool prints.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/findings.sh"

pins="$FACTORY_STEPS_DIR/pins"
probe="$FACTORY_STEPS_DIR/versions"

check() {
	if [ ! -f "$pins" ]; then
		factory_finding "$pins" 1 pin-file-missing "no pin file; list each tool as '<tool> <version>'"
		return 1
	fi

	# Read the pins first: an empty pin file needs no probe.
	local n=0 line tool version rest
	local -a pin_lines=() pin_tools=() pin_versions=()
	local bad=0
	# shellcheck disable=SC2094 # the loop reads the pins; factory_finding only names the file
	while IFS= read -r line || [ -n "$line" ]; do
		n=$((n + 1))
		line="${line%$'\r'}"
		case "$line" in '' | '#'*) continue ;; esac
		read -r tool version rest <<< "$line"
		if [ -z "$version" ] || [ -n "$rest" ]; then
			factory_finding "$pins" "$n" pin-format "expected '<tool> <version>', got: $line"
			bad=1
			continue
		fi
		pin_lines+=("$n")
		pin_tools+=("$tool")
		pin_versions+=("$version")
	done < "$pins"
	[ "${#pin_tools[@]}" -eq 0 ] && return "$bad"

	if [ ! -f "$probe" ]; then
		factory_finding "$probe" 1 pin-probe-missing "no version probe; it prints '<tool> <version>' per pinned tool"
		return 1
	fi
	local found status
	found="$(bash "$probe")"
	status=$?
	if [ "$status" -ne 0 ]; then
		factory_finding "$probe" 1 pin-probe-failed "the version probe exited $status"
		return 1
	fi

	local i want got
	for i in "${!pin_tools[@]}"; do
		tool="${pin_tools[$i]}"
		want="${pin_versions[$i]}"
		got="$(printf '%s\n' "$found" | tr -d '\r' | awk -v t="$tool" '$1 == t { print $2; exit }')"
		if [ "$got" != "$want" ]; then
			factory_finding "$pins" "${pin_lines[$i]}" pin-mismatch "$tool: expected $want, found ${got:-none}"
			bad=1
		fi
	done
	return "$bad"
}

out="$(check)"
status=$?
[ -n "$out" ] && printf '%s\n' "$out" | factory_sort_findings
exit "$status"
