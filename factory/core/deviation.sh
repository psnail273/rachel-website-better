#!/usr/bin/env bash
# The deviation step: what the branch changed against what the Build Brief allows.
# A project's tools/verify/deviation holds the one line
#   exec bash "$FACTORY_CORE/deviation.sh"
# and the runner runs it like any step. Run from the project root.
#
# It compares `git diff --name-only <base>..HEAD` with the brief's scope globs
# (lib/brief.sh) and the commits' `Deviation: <path or rule>: <reason>` trailers:
#   - a changed file outside the scope that no trailer names fails
#     (deviation-undeclared). A trailer's <path> may be a glob;
#   - every trailer is listed as a passing deviation-declared finding, for the ruling;
#   - a ratchet file (any file under tools/verify/ratchet/: allowlists, excludes,
#     the Baseline) that gains an entry fails (ratchet-growth), trailer or not,
#     unless the brief has a `grows <file> <entry>` line for it: Opus's accept
#     ruling, which only the Driver can write. Accepted growth is listed as a
#     passing ratchet-accepted finding; each `grows` line accepts one entry.
#     An entry is a line that isn't blank or a # comment. A ratchet file that only
#     shrinks passes, in scope or not;
#   - once the branch has a Lock (lock.sh), a locked test whose change differs
#     from the red commit's fails (locked-test), trailer or not (lib/lock.sh);
#   - under a test-only brief (Kind build in Phase green, lib/brief.sh), a changed
#     file that is neither a test file (tools/verify/test-paths) nor one of the
#     Driver's docs fails (test-only-product), trailer or not: with no red phase,
#     no failing test shows a product change is needed;
#   - a func of a test file the branch changes (tools/verify/test-paths) that
#     holds fewer assertion calls at HEAD than at <base>, or is gone, fails
#     (assert-drop), trailer or not, unless the brief has an `asserts <file>
#     <func> <from> <to>` line for it: the Driver's accept ruling, <from> the
#     base's count and <to> HEAD's (0 for a func that is gone). A declared drop
#     passes and is listed (assert-declared); a declaration that doesn't match
#     what was measured fails (assert-drop), naming both, so a stale one can't
#     hide a further drop. A count that rises or stays passes. The adapter
#     counts: tools/verify/assert-counts <path>, given the file's text on stdin,
#     prints `<line> <func> <count>` per func; nothing for a file it doesn't
#     count. A probe holding the no-op marker (lib/steps.sh) turns the check
#     off; a missing or failing one fails (assert-probe). Every func of a file
#     an asserts line names is counted too, so with no test-paths file only
#     those files are;
#   - a missing or malformed brief fails, unless the diff is empty;
#   - a brief that no longer matches the Driver's seal fails (brief-changed,
#     lib/brief.sh), whatever the diff.
#
# <base> is $FACTORY_BASE when set, else the merge-base of HEAD and
# $FACTORY_BASE_BRANCH (default dev). The brief is $FACTORY_BRIEF when set, else
# <git-dir>/factory/brief.md.
#
# A changed file that tools/verify/generated matches (lib/diff.sh) skips the scope
# check, so it needs no scope line or trailer; a ratchet file's growth is still
# checked.
#
# Prints findings (`file:line rule message`) and exits 1 on any failing one.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/findings.sh"
. "$core/lib/brief.sh"
. "$core/lib/diff.sh"
. "$core/lib/run.sh"
. "$core/lib/lock.sh"

ratchet_dir="$FACTORY_STEPS_DIR/ratchet"
self="$FACTORY_STEPS_DIR/deviation"
probe="$FACTORY_STEPS_DIR/assert-counts"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# entries <rev> <file>: the file's ratchet entries at <rev>, sorted, repeats kept (a
# repeated entry counts, as the Baseline counts repeated findings); none if absent.
entries() {
	git show "$1:$2" 2> /dev/null | tr -d '\r' | grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*#' | LC_ALL=C sort
}

# assert_drops <base>: the assert-drop check, against the parsed brief's asserts
# lines. Prints its findings; returns 1 on a failing one.
assert_drops() {
	local base="$1" file rev side status bad=0 a tab=$'\t'
	{
		if factory_test_paths_load > /dev/null; then
			while IFS= read -r file; do
				! factory_is_test_file "$file" || printf '%s\n' "$file"
			done < <(tr -d '\r' < "$tmp/changed")
		fi
		for a in "${BRIEF_ASSERTS[@]}"; do printf '%s\n' "${a%% *}"; done
	} | LC_ALL=C sort -u > "$tmp/counted"
	[ -s "$tmp/counted" ] || return 0
	if [ ! -f "$probe" ]; then
		factory_finding "$probe" 1 assert-probe "no assertion-count probe, so the test files' assertions can't be counted; it prints '<line> <func> <count>' per func of a file (the adapter seeds it), or holds the no-op marker"
		return 1
	fi
	! factory_step_is_noop "$probe" || return 0

	# One `<side>\t<file>\t<func>\t<count>\t<line>` per func: B the base, H HEAD.
	: > "$tmp/counts"
	while IFS= read -r file; do
		for side in B H; do
			rev="$base"
			[ "$side" = B ] || rev=HEAD
			git cat-file -e "$rev:$file" 2> /dev/null || continue
			git show "$rev:$file" | bash "$probe" "$file" > "$tmp/probe"
			status="${PIPESTATUS[1]}"
			if [ "$status" -ne 0 ]; then
				factory_finding "$probe" 1 assert-probe "the probe exited $status on $file at $rev"
				bad=1
			elif grep -qvE '^[0-9]+ [^[:space:]]+ [0-9]+$' "$tmp/probe"; then
				factory_finding "$probe" 1 assert-probe "the probe printed '$(grep -vE '^[0-9]+ [^[:space:]]+ [0-9]+$' "$tmp/probe" | head -n 1)' for $file at $rev, not '<line> <func> <count>'"
				bad=1
			else
				awk -v s="$side" -v f="$file" '{ print s "\t" f "\t" $2 "\t" $3 "\t" $1 }' "$tmp/probe" >> "$tmp/counts"
			fi
		done
	done < "$tmp/counted"
	# A count missing for a probe that failed would read as a drop.
	[ "$bad" -eq 0 ] || return 1
	for a in "${BRIEF_ASSERTS[@]}"; do
		printf 'D\t%s\n' "${a// /$tab}"
	done >> "$tmp/counts"

	awk -F '\t' '
		$1 == "B" { k = $2 SUBSEP $3; keys[k] = 1; from[k] += $4 }
		$1 == "H" { k = $2 SUBSEP $3; keys[k] = 1; to[k] += $4; if (!(k in at)) at[k] = $5 }
		$1 == "D" { k = $2 SUBSEP $3; keys[k] = 1; dfrom[k] = $4; dto[k] = $5 }
		END {
			for (k in keys) {
				split(k, p, SUBSEP)
				b = (k in from) ? from[k] : 0
				h = (k in to) ? to[k] : 0
				line = (k in at) ? at[k] : 1
				was = b " assertion call" (b == 1 ? "" : "s") " at the base"
				now = h " at HEAD" ((k in to) ? "" : ", where it is gone")
				if (k in dfrom) {
					if (dfrom[k] == b && dto[k] == h) {
						print p[1] ":" line " assert-declared " p[2] " drops from " was " to " now "; the brief declares it (asserts)"
					} else {
						print p[1] ":" line " assert-drop the brief declares asserts " p[1] " " p[2] " " dfrom[k] " " dto[k] ", but " p[2] " has " was " and " now
						bad = 1
					}
				} else if (h < b) {
					print p[1] ":" line " assert-drop " p[2] " drops from " was " to " now ": keep every check, or the Driver declares the drop in the brief: asserts " p[1] " " p[2] " " b " " h
					bad = 1
				}
			}
			exit bad
		}
	' "$tmp/counts"
}

# check: print the findings, unsorted; exit 1 on any failing one.
check() {
	local base bad=0 file entry n brief sha value target reason t declared
	local -a targets=()

	if ! base="$(factory_diff_base)"; then
		factory_finding "$self" 1 deviation-base "no merge-base of HEAD and '${FACTORY_BASE_BRANCH:-dev}'; set FACTORY_BASE or FACTORY_BASE_BRANCH"
		exit 1
	fi
	if ! git diff --name-only --no-renames "$base" HEAD > "$tmp/changed" 2> /dev/null; then
		factory_finding "$self" 1 deviation-base "cannot diff '$base'..HEAD"
		exit 1
	fi

	brief="$(factory_brief_path)"
	factory_brief_seal_check "$brief" || bad=1

	# Ratchet files are checked for growth; the rest against the scope, unless the
	# project's tools generate them.
	factory_generated_load
	: > "$tmp/others"
	: > "$tmp/growth"
	while IFS= read -r file; do
		case "$file" in
			"$ratchet_dir"/*)
				entries "$base" "$file" > "$tmp/before"
				entries HEAD "$file" > "$tmp/after"
				LC_ALL=C comm -13 "$tmp/before" "$tmp/after" | awk -v f="$file" '{ print f "	" $0 }' >> "$tmp/growth"
				;;
			*) factory_is_generated "$file" || echo "$file" >> "$tmp/others" ;;
		esac
	done < <(tr -d '\r' < "$tmp/changed" | LC_ALL=C sort -u)

	# Growth the brief's `grows` lines accept passes and is listed; the rest fails.
	# A brief that doesn't parse accepts nothing (the scope check reports it).
	: > "$tmp/accepted"
	if [ -s "$tmp/growth" ] && factory_brief_parse "$brief" > /dev/null 2>&1; then
		for value in "${BRIEF_GROWS[@]}"; do
			printf '%s\t%s\n' "${value%% *}" "${value#* }"
		done | LC_ALL=C sort > "$tmp/accepted"
	fi
	LC_ALL=C sort -o "$tmp/growth" "$tmp/growth"
	while IFS=$'\t' read -r file entry; do
		n="$(git show "HEAD:$file" | tr -d '\r' | grep -nxF -- "$entry" | tail -n 1 | cut -d: -f1)"
		factory_finding "$file" "${n:-1}" ratchet-accepted "added '$entry'; the brief accepts it (grows)"
	done < <(LC_ALL=C comm -12 "$tmp/growth" "$tmp/accepted")
	while IFS=$'\t' read -r file entry; do
		n="$(git show "HEAD:$file" | tr -d '\r' | grep -nxF -- "$entry" | tail -n 1 | cut -d: -f1)"
		factory_finding "$file" "${n:-1}" ratchet-growth "added '$entry'; ratchet files may only shrink"
		bad=1
	done < <(LC_ALL=C comm -23 "$tmp/growth" "$tmp/accepted")

	# The trailers, one `<sha>\t<value>` per line; each is listed for the ruling.
	git log --format='%x1e%h%n%(trailers:key=Deviation,valueonly,unfold)' "$base..HEAD" |
		tr -d '\r' | awk -v mark="$(printf '\036')" '
			index($0, mark) == 1 { sha = substr($0, 2); next }
			NF { print sha "\t" $0 }
		' > "$tmp/trailers"
	while IFS=$'\t' read -r sha value; do
		target="${value%%: *}"
		reason="${value#*: }"
		if [ -z "$target" ] || [ "$target" = "$value" ] || [ -z "${reason// /}" ] || [[ $target =~ [[:space:]] ]]; then
			factory_finding "$self" 1 deviation-format "commit $sha: expected 'Deviation: <path or rule>: <reason>', got: $value"
			bad=1
			continue
		fi
		factory_finding "$target" 1 deviation-declared "$reason (commit $sha)"
		targets+=("$target")
	done < "$tmp/trailers"

	# The Lock: a locked test changed after the red commit fails, trailer or not.
	factory_lock_check "$base" || bad=1

	[ -s "$tmp/others" ] || exit "$bad"

	factory_brief_parse "$brief" || exit 1

	# A test-only brief: nothing but tests and the Driver's docs, trailer or not.
	factory_brief_lint "$brief" > /dev/null
	if factory_brief_is_test_only; then
		if factory_test_paths_load; then
			while IFS= read -r file; do
				factory_is_test_file "$file" || factory_is_driver_doc "$file" && continue
				factory_finding "$file" 1 test-only-product "changed under a test-only brief (Kind build, Phase green), which changes only test files ($FACTORY_TEST_PATHS) and the Driver's docs, with a trailer or without; a product change needs a red phase"
				bad=1
			done < "$tmp/others"
		else
			bad=1
		fi
	fi

	assert_drops "$base" || bad=1

	while IFS= read -r file; do
		factory_in_scope "$file" && continue
		declared=0
		for t in "${targets[@]}"; do
			if factory_glob_match "$t" "$file"; then
				declared=1
				break
			fi
		done
		if [ "$declared" -eq 0 ]; then
			factory_finding "$file" 1 deviation-undeclared "outside the brief's scope, and no commit has a 'Deviation: $file: <reason>' trailer"
			bad=1
		fi
	done < "$tmp/others"

	exit "$bad"
}

check | factory_sort_findings
exit "${PIPESTATUS[0]}"
