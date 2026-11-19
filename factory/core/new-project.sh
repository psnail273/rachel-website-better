#!/usr/bin/env bash
# Start a new project from the factory's own repo, in one step: its folder, its
# git repo on dev, its Gitea repo, and the factory installed from a release with
# the adapter's skeleton. Run in a checkout of the factory's repo (the workspace
# layout: .factory-repo beside factory/), where the /new-project skill runs it:
#   bash factory/core/new-project.sh <dir> <adapter> [--tag <vX.Y.Z>|latest]
#                                    [--repo [<owner>/]<name>] [--public]
#
# <dir> is the new project's folder: missing (its parent there) or an empty
# folder, outside this checkout. The Gitea repo is --repo's, its owner by default
# gt's logged-in user and its name <dir>'s folder name; private unless --public.
# The tag is a release of this checkout's origin, the factory's repo; latest (the
# default) is its highest v<major>.<minor>.<patch> tag, as sync.sh latest picks
# it (lib/release.sh).
#
# It refuses before it makes anything: a <dir> that is a file, a folder with
# anything in it, inside this checkout, or whose parent is missing; a checkout
# that is no factory repo or has no origin; gt missing or not logged in (gt exits
# 4: run `gt auth login`); a Gitea repo of that name that exists, or that gt
# can't say about; a tag the origin lacks; an adapter the tag's factory lacks, or
# one with no --new skeleton (adapters/<adapter>/new/), both usage errors as in
# install.sh. It reads the tag from a clone of the origin at it, in a temp folder
# removed at exit. Then it:
#   - makes <dir>, git inits it on dev and makes an empty first commit, `Start
#     <name>` (install.sh needs a HEAD); a failure here removes what it made;
#   - creates the Gitea repo (gt repo create, its default branch dev), adds it as
#     origin (its ssh URL when the factory's origin is ssh, else its https one)
#     and pushes dev;
#   - runs the clone's install.sh <dir> <adapter> --new, with FACTORY_LABEL_CMD a
#     script that creates the factory's labels in the new repo (gt label create
#     --force, so one there already counts; a label it could not create is no
#     failure, but named in a `could not create the labels` line before the
#     last): it lays the skeleton, adopts, stages
#     the adoption and records the factory's origin and the tag in
#     tools/verify/factory-version. It commits nothing: the /new-project skill
#     takes the project through the adopt skill's steps, then commits on dev and
#     pushes.
# Once the Gitea repo exists it removes nothing: a failure says what it made (the
# folder, the repo and its URL) and how to remove each, and never deletes the
# Gitea repo itself. An adoption that stopped at prepare (tool locations) is such
# a failure: fix what it says, then run bash factory/core/adopt.sh <adapter> in
# <dir>.
#
# Progress goes to stderr; stdout is install.sh's. Exit codes: 0 made and
# installed, 1 refused or failed, 2 usage (an unknown adapter, or one with no
# skeleton, too).
set -u
# cd resolves relative paths; CDPATH would send them elsewhere.
unset CDPATH
# Nothing here may wait on a prompt for a password: it fails instead.
export GIT_TERMINAL_PROMPT=0

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/vendor.sh"
. "$core/lib/bounded.sh"
. "$core/lib/release.sh"

say() { echo "new-project: $*" >&2; }
die() {
	say "$*"
	exit 1
}
usage() {
	echo "usage: bash factory/core/new-project.sh <dir> <adapter> [--tag <vX.Y.Z>|latest] [--repo [<owner>/]<name>] [--public]" >&2
	exit 2
}

[ "$#" -ge 2 ] || usage
dir="$1" adapter="$2"
shift 2
[ -n "$dir" ] && [ "${dir#-}" = "$dir" ] && [[ $adapter =~ ^[A-Za-z0-9._][A-Za-z0-9._-]*$ ]] || usage
tag=latest repo="" visibility=--private
while [ "$#" -gt 0 ]; do
	case "$1" in
		--tag | --repo)
			[ "$#" -ge 2 ] && [ -n "$2" ] || usage
			if [ "$1" = --tag ]; then tag="$2"; else repo="$2"; fi
			shift 2
			;;
		--public)
			visibility=--public
			shift
			;;
		*) usage ;;
	esac
done
[ "$tag" = latest ] || { [ "${tag#v}" != "$tag" ] && factory_version_is "${tag#v}"; } || usage

# The folder: absolute, its parent resolved; missing, or an empty folder.
case "$dir" in /*) ;; *) dir="$PWD/$dir" ;; esac
if [ -d "$dir" ] && [ ! -L "$dir" ]; then
	dir="$(cd "$dir" && pwd)"
	[ -z "$(ls -A "$dir")" ] || die "$dir is not empty; name a new folder, or an empty one"
	made_dir=0
elif [ -e "$dir" ] || [ -L "$dir" ]; then
	die "$dir exists and is no folder; name a new folder"
else
	dir="${dir%/}"
	[ -d "$(dirname "$dir")" ] || die "no folder $(dirname "$dir") to make $(basename "$dir") in"
	dir="$(cd "$(dirname "$dir")" && pwd)/$(basename "$dir")"
	made_dir=1
fi

# The factory's checkout, and its origin: the release comes from there.
factory_dir="$(cd "$core/.." && pwd)"
top="$(cd "$factory_dir/.." && pwd)"
cdup="$(git -C "$top" rev-parse --show-cdup 2> /dev/null)" && [ -z "$cdup" ] && [ -f "$top/$FACTORY_REPO_MARKER" ] ||
	die "run it in a checkout of the factory's repo ($FACTORY_REPO_MARKER beside factory/); $top is none"
case "$dir/" in "$top"/*) die "$dir is inside the factory's checkout $top; make the project outside it" ;; esac
upstream="$(git -C "$top" remote get-url origin 2> /dev/null)" || die "the factory's checkout $top has no origin to take a release from"
# A relative path (no scheme, no host:) names a repo from the checkout.
case "$upstream" in
	/* | *:*) ;;
	*) upstream="$(cd "$top" && cd "$(dirname "$upstream")" 2> /dev/null && pwd)/$(basename "$upstream")" ||
		die "the factory's origin, $upstream, names no folder from $top" ;;
esac

# The Gitea repo's name, then its owner.
owner="" name="$(basename "$dir")"
case "$repo" in
	*/*) owner="${repo%%/*}" name="${repo#*/}" ;;
	?*) name="$repo" ;;
esac
[[ $name =~ ^[A-Za-z0-9._-]+$ ]] && [[ -z $owner || $owner =~ ^[A-Za-z0-9._-]+$ ]] ||
	die "'${owner:+$owner/}$name' is no Gitea repo name (letters, digits, '.', '_' and '-'); name one with --repo [<owner>/]<name>"

tmp="$(mktemp -d)" || die "could not make a temp folder"
trap 'rm -rf "$tmp"' EXIT
cd "$top" || die "cannot enter $top"

# gt, logged in: its user owns the repo unless --repo names an owner.
command -v gt > /dev/null 2>&1 || die "gt is not on PATH; install it, then run \`gt auth login\`"
login="$(gt api user --jq .login 2> "$tmp/gt")"
case $? in
	0) ;;
	4) die "gt is not logged in to Gitea: run \`gt auth login\`, then run this again" ;;
	*)
		sed 's/^/  /' "$tmp/gt" >&2
		die "gt could not tell who is logged in (gt api user)"
		;;
esac
[ -n "$login" ] || die "gt named no logged-in user (gt api user)"
owner="${owner:-$login}"

# No Gitea repo by that name yet: gt answers 404.
gt api "repos/$owner/$name" --silent --include > /dev/null 2> "$tmp/gt"
case $? in
	0) die "the Gitea repo $owner/$name exists already; name another with --repo" ;;
	4) die "gt is not logged in to Gitea: run \`gt auth login\`, then run this again" ;;
	*)
		grep -Eq '(^|[^0-9])404([^0-9]|$)' "$tmp/gt" || {
			sed 's/^/  /' "$tmp/gt" >&2
			die "could not tell whether the Gitea repo $owner/$name exists (gt api repos/$owner/$name)"
		}
		;;
esac

# The release, cloned at its tag.
if [ "$tag" = latest ]; then
	tag="$(factory_latest_release "$upstream")" || die "no release of the factory to install"
	say "the latest release is $tag"
fi
git clone -q --branch "$tag" "$upstream" "$tmp/factory" > /dev/null 2> "$tmp/clone" || {
	sed 's/^/  /' "$tmp/clone" >&2
	die "could not clone the factory at $tag from $upstream (has it that tag?)"
}
tagged="$tmp/factory"
[ ! -f "$tmp/factory/$FACTORY_REPO_MARKER" ] || tagged="$tmp/factory/factory"
[ -f "$tagged/core/install.sh" ] || die "the factory at $tag has no core/install.sh"
[ -d "$tagged/adapters/$adapter/tools/verify" ] || {
	say "the factory at $tag has no adapter '$adapter' (it has:$(find "$tagged/adapters" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort | tr '\n' ' ' | sed 's/^/ /;s/ $//'))"
	exit 2
}
[ -d "$tagged/adapters/$adapter/new" ] || {
	say "the $adapter adapter at $tag has no --new skeleton (no adapters/$adapter/new/)"
	exit 2
}

# The local repo. A failure here removes what it made: nothing is outside yet.
undo_local() {
	if [ "$made_dir" -eq 1 ]; then
		rm -rf "$dir"
	else
		find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
	fi
}
fail_local() {
	say "$*"
	undo_local
	die "removed what it made in $dir; nothing was made on Gitea"
}
if [ "$made_dir" -eq 1 ]; then mkdir "$dir" || die "could not make $dir"; fi
git init -q -b dev "$dir" > /dev/null 2> "$tmp/git" && git -C "$dir" commit -q --allow-empty -m "Start $name" 2>> "$tmp/git" || {
	sed 's/^/  /' "$tmp/git" >&2
	fail_local "could not make the git repo in $dir"
}
say "made $dir: a git repo on dev with an empty first commit"

# The Gitea repo: its URL by the factory origin's scheme. From here on nothing
# is removed.
case "$upstream" in
	http://* | https://* | file://* | /*) field=clone_url ;;
	ssh://* | *:*) field=ssh_url ;;
	*) field=clone_url ;;
esac
spec="$name"
[ "$owner" = "$login" ] || spec="$owner/$name"
url="$(gt repo create "$spec" "$visibility" --default-branch dev --jq ".$field" 2> "$tmp/gt")" || {
	status=$?
	sed 's/^/  /' "$tmp/gt" >&2
	undo_local
	die "gt repo create failed (exit $status), so the Gitea repo $owner/$name should not exist; removed what it made in $dir. Should gt repo view $owner/$name show it, it is empty: gt repo delete $owner/$name removes it"
}
fail_made() {
	say "$*"
	say "it made, and removes neither: the folder $dir (rm -rf $dir removes it) and the Gitea repo $owner/$name${url:+ at $url} (gt repo delete $owner/$name removes it with all it holds; that can't be undone)"
	exit 1
}
[ -n "$url" ] || fail_made "gt repo create named no URL for $owner/$name"
say "created the Gitea repo $owner/$name (${visibility#--}): $url"
git -C "$dir" remote add origin "$url" || fail_made "could not add $url as $dir's origin"
git -C "$dir" push -q -u origin dev > /dev/null 2> "$tmp/push" || {
	sed 's/^/  /' "$tmp/push" >&2
	fail_made "could not push dev to $url"
}
say "pushed dev to $url"

# The factory, from the release, with the skeleton; the labels made in the new
# repo by gt.
{
	printf '#!/usr/bin/env bash\n'
	printf '# <name> <color> <description>: that label in %s; --force updates one there.\n' "$owner/$name"
	printf '# A label it could not create is listed in %s.\n' "$tmp/labels-failed"
	printf 'gt label create "$1" --repo %q --color "$2" --description "$3" --force && exit 0\n' "$owner/$name"
	printf 'echo "$1" >> %q\n' "$tmp/labels-failed"
	printf 'exit 1\n'
} > "$tmp/label.sh" || fail_made "could not write the label script"
unset FACTORY_PROJECT
FACTORY_LABEL_CMD="bash $tmp/label.sh" bash "$tagged/core/install.sh" "$dir" "$adapter" --new
status=$?
[ "$status" -eq 0 ] || fail_made "the install stopped (exit $status); fix what it says above (an adoption stopped at prepare: run bash factory/core/adopt.sh $adapter in $dir)"
if [ -s "$tmp/labels-failed" ]; then
	say "could not create the labels $(tr '\n' ' ' < "$tmp/labels-failed" | sed 's/ $//') in $owner/$name: create them by hand, or with the adopt skill's label script"
fi
say "made $dir: a new $adapter project on dev, pushed to $url, with the factory $tag installed and its adoption staged; take it through the adopt skill's steps, then commit on dev and push"
