#!/usr/bin/env bash
# Update an Adopted project's vendored factory/ to a tagged release. Run from the
# project's checkout:
#   bash factory/core/sync.sh <tag>     sync to that tag
#   bash factory/core/sync.sh latest    sync to the upstream's highest release
#   bash factory/core/sync.sh check     say whether the upstream has a newer one
#
# check changes nothing. It lists the upstream's tags (git ls-remote, bounded:
# $FACTORY_SYNC_TIMEOUT seconds, 10 by default, and ssh with ConnectTimeout and
# BatchMode, so it never prompts), takes the highest v<major>.<minor>.<patch>
# (compared part by part as numbers; any other tag is ignored) and compares it
# with factory-version's `version`. On stdout: `newer v<x> (on <version>)` when
# the release is greater, else `current <version>`; both exit 0. It exits 1, the
# reason on stderr, when it can't tell: no upstream, or ls-remote failed or timed
# out. latest resolves the same tag, refuses when the project is on it or past
# it, and then syncs to it as `sync.sh <tag>` does. Both need an upstream
# ($FACTORY_UPSTREAM or the `upstream` line); a project's own tags don't count.
#
# The tag is read from the factory's repo (a git URL or path, fetched with
# `git fetch`): $FACTORY_UPSTREAM when set, else factory-version's `upstream`
# line (install.sh records it), else the project's own repo. The factory is the
# tag's factory/ folder alone (a project's layout, and the factory repo's
# workspace layout, whose own files at the top never reach the project), or the
# whole tree when the factory is the repo's root (the root layout, with VERSION
# and core/ there; lib/vendor.sh).
#
# It refuses on a project that hasn't adopted (no tools/verify/factory-version),
# when factory/ has local edits since it was recorded (naming each file: an edit to
# the factory is an amend that goes upstream), and on a dirty tree. Then it:
#   - re-copies factory/ from the tag, so it holds exactly the tag's files;
#   - rewrites the hook config (hooks.sh generate) and the factory's section of
#     AGENTS.md (agents.sh generate) from the new Core;
#   - refreshes the copies adopt.sh installed from the factory (the one list in
#     lib/vendor.sh, factory_installed_copies, as the new factory gives it, plus
#     what the old one listed that the new one dropped): tools/verify.sh, tools/verify.ps1,
#     the skills in .claude/skills/, the subagents in .claude/agents/ (each
#     template filled in as adopt.sh fills it) and the verify-<project> skill (as
#     the old and the new generator write it for the project as it is now). A copy
#     the project left as it was is replaced (or removed, when the tag drops it);
#     a copy the project changed is kept, and its diff goes into the port below;
#   - records the new version, the tag and the vendored files in factory-version,
#     keeping its upstream line;
#   - stages everything. It commits nothing.
# It never touches the step scripts, pins or anything else in tools/verify/ but
# factory-version: they belong to the project. Instead it prints on stdout the diff
# of the adapter's templates (factory/adapters/<adapter>/tools/verify/) between the
# old and the new factory, for the project to port by hand.
#
# Progress goes to stderr. Exit codes: 0 synced (or checked), 1 refused or failed,
# 2 usage.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/vendor.sh"
. "$core/lib/project.sh"
. "$core/lib/bounded.sh"
. "$core/lib/release.sh"

say() { echo "sync: $*" >&2; }
die() {
	say "$*"
	exit 1
}

# The whole run is one function, so bash has read all of it before the copy below
# overwrites this very file.
main() {
	[ "$#" -eq 1 ] && [ -n "$1" ] && [ "${1#-}" = "$1" ] || {
		echo "usage: bash factory/core/sync.sh <tag>|latest|check" >&2
		exit 2
	}
	local tag="$1" top adapter old_version edits rev prefix new_version recorded_upstream upstream
	top="$(git rev-parse --show-toplevel 2> /dev/null)" || die "not inside a git checkout"
	cd "$top" || die "cannot enter $top"

	[ -f "$FACTORY_VERSION_FILE" ] || die "not adopted (no $FACTORY_VERSION_FILE); run factory/core/adopt.sh first"
	old_version="$(factory_vendor_field version)" || old_version=unknown
	recorded_upstream="$(factory_vendor_field upstream)" || recorded_upstream=""
	upstream="${FACTORY_UPSTREAM:-$recorded_upstream}"

	if [ "$tag" = check ] || [ "$tag" = latest ]; then
		local mode="$tag" newest
		[ -n "$upstream" ] || die "no upstream: $FACTORY_VERSION_FILE has no upstream line, and FACTORY_UPSTREAM is unset"
		newest="$(factory_latest_release "$upstream")" || exit 1
		factory_version_is "$old_version" || die "$FACTORY_VERSION_FILE records version '$old_version', not <major>.<minor>.<patch>, so it can't be compared with $newest"
		if [ "$mode" = check ]; then
			if factory_version_greater "${newest#v}" "$old_version"; then
				echo "newer $newest (on $old_version)"
			else
				echo "current $old_version"
			fi
			exit 0
		fi
		[ "${newest#v}" != "$old_version" ] || die "already on $newest"
		factory_version_greater "${newest#v}" "$old_version" || die "already on $old_version, past the latest release $newest"
		tag="$newest"
		say "the latest release is $tag"
	fi

	adapter="$(factory_vendor_field adapter)" || die "$FACTORY_VERSION_FILE names no adapter"
	edits="$(factory_vendor_edits)" || die "$FACTORY_VERSION_FILE records no vendored files, so local edits to factory/ can't be ruled out"
	if [ -n "$edits" ]; then
		say "factory/ has local edits since version $old_version was recorded:"
		printf '%s\n' "$edits" | sed 's/^/  /' >&2
		die "refused; send them upstream as an amend, or restore them, then sync again"
	fi
	[ -z "$(git status --porcelain)" ] || die "the tree is dirty; commit or stash first"

	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' EXIT

	# The tag's commit.
	if [ -n "$upstream" ]; then
		git fetch -q --no-tags "$upstream" "refs/tags/$tag" 2> "$tmp/fetch" || {
			sed 's/^/  /' "$tmp/fetch" >&2
			die "no tag $tag at $upstream"
		}
		rev="$(git rev-parse --verify -q "FETCH_HEAD^{commit}")" || die "the tag $tag names no commit"
	else
		rev="$(git rev-parse --verify -q "refs/tags/$tag^{commit}")" || die "no tag $tag here; fetch it, or set FACTORY_UPSTREAM to the factory's repo (or record it: an upstream line in $FACTORY_VERSION_FILE)"
	fi
	if git cat-file -e "$rev:factory/VERSION" 2> /dev/null; then
		prefix="factory"
	elif git cat-file -e "$rev:VERSION" 2> /dev/null && git cat-file -e "$rev:core/verify.sh" 2> /dev/null; then
		prefix=""
	else
		die "the tag $tag holds no factory (no factory/VERSION, and no VERSION and core/ at its root)"
	fi

	# The new factory into $tmp/new, checked out as git would; the old one kept in
	# $tmp/old for the diffs.
	GIT_INDEX_FILE="$tmp/index" git read-tree "$rev:$prefix" &&
		GIT_INDEX_FILE="$tmp/index" git checkout-index --all --prefix="$tmp/new/" ||
		die "could not read the factory from the tag $tag"
	mkdir -p "$tmp/old"
	cp -R "$FACTORY_VENDOR_DIR/." "$tmp/old/" || die "could not keep the old factory"
	new_version="$(tr -d '\r\n' < "$tmp/new/VERSION")"
	[ -d "$tmp/new/adapters/$adapter/tools/verify" ] || say "the tag $tag has no '$adapter' adapter templates"

	# Re-copy: drop every vendored file, then copy the tag's.
	factory_vendor_files | while IFS= read -r f; do rm -f "$f"; done
	find "$FACTORY_VENDOR_DIR" -depth -type d -empty -delete 2> /dev/null
	mkdir -p "$FACTORY_VENDOR_DIR" && cp -R "$tmp/new/." "$FACTORY_VENDOR_DIR/" || die "could not copy the new factory into $FACTORY_VENDOR_DIR/"
	say "factory/ is now version $new_version (tag $tag; was $old_version)"

	# The generated files, from the new Core.
	bash "$FACTORY_VENDOR_DIR/core/hooks.sh" generate || die "could not regenerate the hook config"
	bash "$FACTORY_VENDOR_DIR/core/agents.sh" generate || die "could not rewrite the factory section of AGENTS.md"

	# The installed copies (factory_installed_copies, the list adopt.sh installs),
	# matched file by file on the copy's path: the old release's file for each copy
	# against the new one's, as each installs it (factory_installed_files: an agent
	# rendered, a skill generated). So a template or folder a release renames keeps
	# its copy, and a copy only the old release installs goes when untouched. Where
	# two entries install one path, the first wins, as it does in adopt.sh. This
	# shell sourced the old factory's lib/vendor.sh, which gives the old list; the
	# new one is read in a shell of its own.
	: > "$tmp/port"
	local project copy file new_list
	project="$(factory_project_name "$top")"
	new_list="$(bash -c '. "$1/core/lib/steps.sh" && . "$1/core/lib/vendor.sh" && factory_installed_copies "$2" "$3"' _ "$FACTORY_VENDOR_DIR" "$adapter" "$project")" ||
		die "could not read the new factory's installed copies"
	factory_installed_files "$tmp/old" "$(factory_installed_copies "$adapter" "$project")" "$tmp/was-copies" "$adapter" "$project" > "$tmp/was.list" ||
		die "could not render the old factory's subagents"
	factory_installed_files "$FACTORY_VENDOR_DIR" "$new_list" "$tmp/now-copies" "$adapter" "$project" > "$tmp/now.list" ||
		die "could not render the new factory's subagents"
	local -A was=() now=()
	while IFS=$'\t' read -r copy file; do [ -n "${was[$copy]+set}" ] || was[$copy]="$file"; done < "$tmp/was.list"
	while IFS=$'\t' read -r copy file; do [ -n "${now[$copy]+set}" ] || now[$copy]="$file"; done < "$tmp/now.list"
	while IFS= read -r copy; do
		refresh "${was[$copy]:-$tmp/none}" "${now[$copy]:-$tmp/none}" "$copy"
	done < <(cut -f 1 "$tmp/was.list" "$tmp/now.list" | LC_ALL=C sort -u)

	factory_vendor_record "$new_version" "$adapter" "$tag" "$recorded_upstream" || die "could not write $FACTORY_VERSION_FILE"
	git add -A || die "could not stage the sync"

	# The port: the adapter templates' diff, then the kept copies'.
	mkdir -p "$tmp/was/tools" "$tmp/now/tools"
	[ -d "$tmp/old/adapters/$adapter/tools/verify" ] && cp -R "$tmp/old/adapters/$adapter/tools/verify" "$tmp/was/tools/"
	[ -d "$tmp/new/adapters/$adapter/tools/verify" ] && cp -R "$tmp/new/adapters/$adapter/tools/verify" "$tmp/now/tools/"
	(cd "$tmp" && git diff --no-index --no-color --src-prefix= --dst-prefix= was now) > "$tmp/templates"
	if [ -s "$tmp/templates" ]; then
		say "the $adapter adapter's templates changed; port what fits into tools/verify/ by hand (diff on stdout)"
		cat "$tmp/templates"
	else
		say "the $adapter adapter's templates did not change"
	fi
	cat "$tmp/port"
	say "synced; review and commit the result"
}

# refresh <old> <new> <copy>: update the project's copy of a factory file. A copy
# that is missing while the old factory had the file was removed on purpose, and
# stays removed; one equal to the old file follows the new (or goes, when the new
# factory lacks it, and any folder it leaves empty with it); any other copy is
# kept, and its old-to-new diff joins the port.
refresh() {
	local old="$1" new="$2" copy="$3"
	if [ ! -f "$copy" ]; then
		if [ -f "$new" ] && [ ! -f "$old" ]; then
			mkdir -p "$(dirname "$copy")" && cp "$new" "$copy" || die "could not write $copy"
		fi
		return 0
	fi
	[ -f "$new" ] && cmp -s "$new" "$copy" && return 0
	if [ -f "$old" ] && cmp -s "$old" "$copy"; then
		if [ -f "$new" ]; then
			cp "$new" "$copy" || die "could not write $copy"
		else
			rm -f "$copy" || die "could not remove $copy"
			rmdir -p "$(dirname "$copy")" 2> /dev/null
		fi
		return 0
	fi
	[ -f "$old" ] && [ -f "$new" ] && cmp -s "$old" "$new" && return 0
	say "kept $copy, which the project changed; the factory's change to it is on stdout"
	[ -f "$old" ] || old=/dev/null
	[ -f "$new" ] || new=/dev/null
	diff -u --label "was/$copy" --label "now/$copy" "$old" "$new" >> "$tmp/port"
}

main "$@"
exit
