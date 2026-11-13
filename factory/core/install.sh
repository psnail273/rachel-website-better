#!/usr/bin/env bash
# Install the factory into a project in one step, from a clone of the factory's
# own repo (a tagged checkout, say `git clone -b <tag> <factory repo>`):
#   bash <clone>/factory/core/install.sh <project dir> <adapter>        an existing project
#   bash <clone>/factory/core/install.sh <project dir> <adapter> --new  a new one, from
#                                                                       the adapter's skeleton
# (<clone>/core/install.sh in a release of the root layout, whose factory is the
# repo's root: lib/vendor.sh). Not tools/install.sh, which installs the machine's
# tools.
#
# It refuses a clone with uncommitted or untracked files, a clone that is no
# factory repo (in the workspace layout, .factory-repo and factory/VERSION at the
# top of its checkout; in the root layout, VERSION and core/), a project that is
# not the top of a git checkout, one that has a factory/ or a
# tools/verify/factory-version already (sync.sh updates an Adopted project), and
# an adapter the clone lacks. Then it:
#   - copies the clone's tracked factory at HEAD (git archive of HEAD:factory in
#     the workspace layout, never the workspace's own files; of HEAD in the root
#     layout: no .git, nothing untracked) into <project>/factory/, and stages them
#     with the clone's file
#     modes, which a project whose git ignores the executable bit
#     (core.filemode false) would otherwise lose: its factory/ tree is then the
#     factory repo's, as amend.sh land needs;
#   - runs factory/core/adopt.sh <adapter> [--new] in the project, which records
#     upstream <the clone's origin URL; a relative path made absolute> and
#     tag <the tag at the clone's HEAD>
#     in tools/verify/factory-version (no line for one the clone lacks), and
#     stages the adoption. It commits nothing.
# A failed adoption that recorded nothing leaves the project as it was, factory/
# removed. One that stopped at prepare (tool locations) keeps what it seeded:
# fix what it says, then run bash factory/core/adopt.sh <adapter> in the project.
#
# Progress goes to stderr; stdout is adopt.sh's. Exit codes: 0 installed and
# Adopted, 1 refused or failed, 2 usage.
set -u
# cd resolves the clone's relative origin; CDPATH would send it elsewhere.
unset CDPATH

say() { echo "install: $*" >&2; }
die() {
	say "$*"
	exit 1
}

new=()
[ "$#" -eq 3 ] && [ "$3" = --new ] && new=(--new)
{ [ "$#" -eq 2 ] || [ "${#new[@]}" -eq 1 ]; } && [ -n "$1" ] && [ "${2#-}" = "$2" ] && [ -n "$2" ] || {
	echo "usage: bash <factory clone>/core/install.sh <project dir> <adapter> [--new]" >&2
	exit 2
}
adapter="$2"

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The factory's folder in the clone: factory/ in the workspace layout, the
# clone's top in the root layout; $tree is it at HEAD.
factory_dir="$(cd "$core/.." && pwd)"
if [ -f "$factory_dir/../.factory-repo" ]; then
	clone="$(cd "$factory_dir/.." && pwd)"
	tree="HEAD:factory"
else
	clone="$factory_dir"
	tree="HEAD"
fi
cdup="$(git -C "$clone" rev-parse --show-cdup 2> /dev/null)" && [ -z "$cdup" ] && [ -f "$factory_dir/VERSION" ] &&
	git -C "$clone" cat-file -e "$tree" 2> /dev/null ||
	die "$clone is no clone of the factory repo (.factory-repo and factory/VERSION, or VERSION and core/, at the top of a git checkout); run install.sh from one"
[ -z "$(git -C "$clone" status --porcelain)" ] || die "the clone $clone has uncommitted or untracked files; install a clean checkout of a tag"
[ -d "$factory_dir/adapters/$adapter/tools/verify" ] || {
	echo "install: no adapter '$adapter' in the factory (no $factory_dir/adapters/$adapter/tools/verify)" >&2
	exit 2
}

[ -d "$1" ] || die "no folder $1"
project="$(cd "$1" && pwd)"
cdup="$(git -C "$project" rev-parse --show-cdup 2> /dev/null)" || die "$project is not a git checkout; git init it first"
[ -z "$cdup" ] || die "$project is not the top of its git checkout; install into $(cd "$project/$cdup" && pwd)"
[ "$project" != "$clone" ] || die "$project is the factory clone itself"
[ ! -e "$project/factory" ] || die "$project has a factory/ already; bash factory/core/sync.sh <tag> updates an Adopted project"
[ ! -e "$project/tools/verify/factory-version" ] || die "$project has adopted already (tools/verify/factory-version); bash factory/core/sync.sh <tag> updates it"
[ -z "$(git -C "$project" status --porcelain)" ] || die "the project's tree is dirty; commit or stash first"

upstream="$(git -C "$clone" remote get-url origin 2> /dev/null)" || {
	upstream=""
	say "the clone has no origin remote, so no upstream is recorded; sync.sh will need FACTORY_UPSTREAM"
}
# A relative path (no scheme, no host:) names a repo or a bundle from the clone;
# the project would read it from its own root.
case "$upstream" in
	'' | /* | *:*) ;;
	*)
		if folder="$(cd "$clone" && cd "$(dirname "$upstream")" 2> /dev/null && pwd)"; then
			upstream="$folder/$(basename "$upstream")"
		else
			say "the clone's origin, $upstream, is a relative path with no folder from $clone; recorded as it is"
		fi
		;;
esac
tag="$(git -C "$clone" describe --tags --exact-match HEAD 2> /dev/null)" || {
	tag=""
	say "the clone's HEAD is no tag, so no tag is recorded; install a tagged release to record one"
}

# unvendor: take the copied factory/ out of the project's index and tree.
unvendor() {
	git -C "$project" rm -r -q --cached --ignore-unmatch -- factory > /dev/null 2>&1
	rm -rf "$project/factory"
}

mkdir "$project/factory" || die "could not make $project/factory"
if ! git -C "$clone" archive --format=tar "$tree" | tar -x -C "$project/factory"; then
	unvendor
	die "could not copy the factory into $project/factory"
fi
if ! git -C "$project" add -- factory ||
	! git -C "$clone" ls-tree -r -z "$tree" | while IFS= read -r -d '' entry; do
		[ "${entry%% *}" != 100755 ] || printf 'factory/%s\0' "${entry#*$'\t'}"
	done | git -C "$project" update-index -z --chmod=+x --stdin; then
	unvendor
	die "could not stage the factory in $project"
fi
say "copied the factory $(tr -d '\r\n' < "$project/factory/VERSION")${tag:+ ($tag)} into $project/factory"

cd "$project" || die "cannot enter $project"
FACTORY_INSTALL=1 FACTORY_INSTALL_TAG="$tag" FACTORY_INSTALL_UPSTREAM="$upstream" \
	bash factory/core/adopt.sh "$adapter" ${new[@]+"${new[@]}"}
status=$?
if [ "$status" -ne 0 ]; then
	if [ ! -e tools/verify/factory-version ]; then
		unvendor
		die "the adoption failed (exit $status); the project is as it was, without factory/"
	fi
	die "the adoption stopped (exit $status); fix what it says, then run bash factory/core/adopt.sh $adapter in $project"
fi
say "installed; review and commit the result"
