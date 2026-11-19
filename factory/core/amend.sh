#!/usr/bin/env bash
# An amend to the vendored factory/: record it, check it, land it. Run from the
# root of an Adopted project's checkout or worktree:
#   bash factory/core/amend.sh record   re-record factory/ and refresh what it installs
#   bash factory/core/amend.sh check    a finding for each thing record would change
#   bash factory/core/amend.sh land     check, test and verify HEAD, publish its
#                                       factory/ to the factory's repo, then push it to dev
#   bash factory/core/amend.sh land --all-tests   the same, with no adapter's suite or real-tool test skipped
#   bash factory/core/amend.sh release [patch|minor|<version>]   bump factory/VERSION for land
#
# An amend is a change to the factory the human approved (or the Driver, for the
# tests-or-docs class, below); the factory-amend skill builds them. It is built and verified in a real project's vendored factory/,
# and this script does for it what sync.sh does for a release. The factory has a
# repo of its own, which factory-version's `upstream` line names: land sends each
# amend there first (each land a release), then pushes the project, so the factory repo's main always holds the factory/ on dev, and
# the next sync.sh finds no local edit. Without an upstream line, land pushes the
# project alone.
#
# record:
#   - refreshes the copies factory/ installs (factory_installed_copies as
#     factory/ on disk lists them, through factory_installed_files; both in
#     lib/vendor.sh): each copy becomes the file factory/ installs there (a
#     skill's file, a rendered subagent, tools/verify.sh, the generated
#     verify-<project> skill), over any edit the project made to it; a copy
#     that is a symlink becomes a file, and its target is left alone. A seed
#     copy (tools/verify.ps1) is the project's: it is written only when
#     missing. A copy the factory as recorded installed, and factory/ on disk
#     no longer does, is removed, as is a file in the generated skill's folder
#     that its generator no longer writes. The factory as recorded is factory/
#     with each file changed or missing since read back from git by its
#     recorded blob. A generator that fails stops record before any change;
#   - regenerates the hook config (hooks.sh generate) and the factory's section
#     of AGENTS.md (agents.sh generate) from factory/ on disk;
#   - re-records tools/verify/factory-version for factory/ on disk, keeping its
#     version, adapter, tag and upstream lines, and writes each vendored file into git's
#     object store, so that the next record can read this one back.
#   stdout: `installed|refreshed|removed|regenerated|recorded <path>` for each
#   file it changed. It stages and commits nothing. The step scripts in
#   tools/verify/ are the project's, so it never writes them: for each of the
#   adapter's templates (factory/adapters/<adapter>/tools/verify/) changed or
#   added since the record that its tools/verify/ file differs from, it says on
#   stderr to port the change by hand.
# check: a finding per line (`file:line rule message`, sorted) for each file of
#   factory/ changed, added or missing since the record (factory-record), each
#   copy record would install, refresh or remove (factory-copy), the hook
#   config's drift (hooks.sh check), the AGENTS.md section's (agents.sh check)
#   and each skill over the size budget (skill-budget.sh). It changes nothing.
#   The generated skill reads the project's files, so a product change can leave
#   it stale too: record refreshes it.
# release: on the landing branch, after the amends: bumps factory/VERSION by
#   the release kind the amends make (below, "The release kind"), then records
#   as record does, with `version <new>` and `tag v<new>`. It refuses a project
#   with no upstream line. It commits nothing: commit it as
#   `Release factory <new>`.
# land: refuses a dirty tree, a HEAD that doesn't contain origin/dev once that
#   is fetched (rebase first), and a remote with more than one push URL. With an
#   upstream line it also fetches the factory repo's main and refuses when it
#   can't; when main's tree differs from origin/dev's factory/ (the project is
#   behind it or ahead: sync first); when factory/VERSION at HEAD is not greater
#   than main's VERSION (release first); and when the tag v<VERSION> is there
#   already on another tree; a batch that breaks the tests-or-docs class
#   (below, "The tests-or-docs class"); and a release of another kind than the
#   amends make (below, "The release kind"). Then,
#   printing each stage on stdout: check; the full factory/core/test.sh, with
#   every variable tools/verify/local.env sets, the environment winning (only
#   the suite's summary and the lines that aren't a PASS print), less the
#   adapters' suites and the real-tool tests its diff can't affect, refused when one it ran skipped for
#   a missing tool, and with its time against the budget (all below, "The full
#   suite at land"); FACTORY_BASE=HEAD
#   bash tools/verify.sh, since an amend has no Build Brief and dev will have
#   the same empty diff, or while the Baseline holds findings (Partial mode,
#   when the full verify is red by design) FACTORY_BASE=HEAD bash
#   factory/core/baseline.sh gate. Green, and with HEAD and every tracked file
#   as they were, and with an upstream line, it publishes first: each commit of
#   origin/dev..HEAD (first parents, oldest first) that changes factory/ becomes
#   a commit of the factory repo, its tree that commit's factory/, with the same
#   author, author date and message, on the factory repo's main (built with git
#   commit-tree in the project's repo); it pushes main, a fast-forward or
#   nothing, then an annotated tag v<VERSION> ("factory <VERSION>") on its tip.
#   A refused push there lands nothing anywhere. When main and the tag hold
#   HEAD's factory/ already (a rerun after a refused project push), it skips
#   publishing and says so; when main does and the tag is missing, it pushes
#   the tag alone. Then it pushes HEAD to origin/dev (FACTORY_REMOTE and
#   FACTORY_BASE_BRANCH, lib/run.sh): a fast-forward or nothing, so a refused
#   push lands nothing. Then it fast-forwards dev in the main checkout when that
#   is on dev with no uncommitted change, else says why it left it alone. On a
#   real project it takes longer than 10 minutes: run it in the background.
#   The factory repo's main may be in either layout (lib/vendor.sh,
#   factory_repo_tree): what land compares with origin/dev's factory/ is main's
#   factory/ in the workspace layout, and its root tree in the root layout. In
#   the workspace layout a replayed commit's tree is its parent's on main with
#   only factory/ replaced by that commit's factory/, so the workspace's files
#   stay as they are.
#
# In the factory's own repo (FACTORY_REPO_MARKER, .factory-repo, at the
# checkout's top, factory/core/amend.sh there and no factory-version), run from
# a checkout or a worktree of it, the same commands work on the repo itself:
#   record: installs and refreshes the workspace's copies (factory_repo_copies:
#     .claude/skills/factory-amend/ from factory/skills/factory-amend/,
#     .claude/skills/new-project/ from factory/workspace-skills/new-project/,
#     .claude/skills/frontend-design/ from factory/third-party/frontend-design/,
#     which the Verifier preloads, and the amend-builder and verifier subagents
#     in .claude/agents/), and removes a
#     file there that factory/ no longer has; and writes the workspace's hooks
#     (FACTORY_WORKSPACE_HOOKS: the wait guard alone, none of a project's), the
#     main session's model and effort, the effort cap and the Lock lift's allow
#     rule into the workspace's .claude/settings.json (factory_settings_render,
#     lib/hooks.sh; its other keys and allow rules kept). Same stdout as above.
#   check: a factory-copy finding for each copy record would change, a
#     hook-drift finding when the settings' hooks, model, effort or cap would, a
#     lift-rule finding when their allow list lacks the lift's rule, and each
#     skill over the size budget.
#   release [patch|minor|<version>]: bumps factory/VERSION as above. It commits nothing.
#   land: refuses a dirty tree, a HEAD that doesn't contain origin/main once
#     that is fetched, a HEAD that is origin/main (nothing to land), a remote
#     with more than one push URL, a factory/ changed since origin/main without
#     a factory/VERSION greater than origin/main's (release first), and a tag
#     v<VERSION> that is at origin on another commit, a batch that breaks the
#     tests-or-docs class, and a release of another kind than the amends make.
#     Then, printing each stage on stdout: check, and the
#     full factory/core/test.sh, with every variable the root's local.env sets,
#     the environment winning (only the summary and the lines that aren't a
#     PASS print), less the adapters' suites and real-tool tests its diff can't
#     affect, as below. There is no project verify. Green, with HEAD and every tracked
#     file as they were, it pushes HEAD to origin/main (a fast-forward or
#     nothing), and when factory/VERSION changed, the annotated tag v<VERSION>
#     ("factory <VERSION>") on it, in one atomic push: both land or neither
#     does, so no main is left untagged. A change to the workspace's files
#     alone lands with no tag. Then it fast-forwards main in the main checkout,
#     as above.
#
# The full suite at land, in both:
#   - Every core suite runs. An adapter's suites run only when the land's diff
#     (origin/dev..HEAD in a project, origin/main..HEAD in the factory's repo;
#     renames as a deletion and an addition) touches a path that can affect
#     them, by the rules stress.sh --since chooses its suites by (lib/suites.sh,
#     factory_suites_affected): a file in the adapter's folder; one in
#     factory/core/ outside core/tests/, or core/tests/lib.sh; another
#     factory/ file their tests name (a skill, an agent); in a project, its
#     ported tools/verify/ for its own adapter; a folder outside factory/ they
#     read (the Godot adapter's addons/gdUnit4/). So a batch that touches one
#     adapter alone runs that adapter's suites, and one that touches a core
#     script runs every adapter's. land says in one stage line which adapters'
#     suites it skips and why, before the suite, and passes test.sh
#     --skip-adapter <adapter> for each; the run is still a full run. A skipped
#     adapter's real-tool tests don't run, so they can't fail the land for a
#     missing tool. land --all-tests skips none.
#   - An adapter's real-tool tests (*_with_<tool>, test.sh's header) run only
#     when the land's diff (origin/dev..HEAD in a project, origin/main..HEAD in
#     the factory's repo; renames as a deletion and an addition) touches a path
#     they read. They read factory/adapters/<that adapter>/, factory/core/, and
#     the rest of factory/ too, as their adoption tests vendor the whole factory
#     and adopt it (its skills, agents, tools and docs), but not another
#     adapter's folder, which that adoption copies and never runs, nor
#     factory/VERSION, which they read only as a version string that land and
#     release check. The Godot adapter's also read addons/gdUnit4/ at the
#     project's root (the gdUnit4 its tests fall back on). For each adapter whose
#     paths the diff leaves alone, land says so in a stage line and passes
#     test.sh --skip-real <adapter>, which says how many it skipped; the run is
#     still a full run. land --all-tests skips none.
#   - A real-tool test that runs (its adapter not skipped) and skips for a
#     missing tool fails the land: a skip whose message names a variable
#     (GODOT_BIN, FACTORY_GDUNIT4, NODE_BIN, ...). land says how many skipped, by
#     adapter, tool and message, and dies naming the variables to set. A skip
#     that names none (a platform the test can't run on) doesn't.
#   - The suite gets every NAME=value the env file sets (factory_load_env,
#     lib/localenv.sh); a variable the environment sets, non-empty, keeps its value.
#   - The budget: when test.sh's last line (`test.sh: wall time <s> s, ...`)
#     gives a wall time over FACTORY_SUITE_BUDGET seconds (from the environment,
#     else the env file; default 1200), land warns on stderr with
#     the machine's load average, so a slow suite can be told from a busy
#     machine. It never fails the land.
#
# The tests-or-docs class, in both: a commit with the trailer
# `Amend-class: tests-or-docs` is an amend the Driver approved itself, which it
# may do for one that touches only the factory's tests/ folders and the docs no
# agent reads as instructions (the tests-or-docs list, tests_or_docs_paths
# below). land refuses, before its check stage, a batch (origin/<branch>..HEAD) in which
# such a commit touches any other path, a commit has an Amend-class trailer
# naming another class, or, when a commit claims the class, a test file
# (*_test.sh in factory/core/tests/ or an adapter's tests/) has fewer test_*
# functions at HEAD than at origin/<branch>. A batch that claims it says so in a
# stage line. The full suite still runs.
#
# The release kind, in both: each amend commit carries the trailer
# `Release: minor` or `Release: patch`, by the rule: a minor adds or tightens a
# check, changes a step the human does, changes how issues are filed, or needs a
# template ported by hand; anything else is a patch, which a project's session
# syncs without asking (hooks/claude-update-check.sh). An amend commit is a
# commit of origin/<branch>..HEAD (FACTORY_REMOTE and FACTORY_BASE_BRANCH; no
# merge) that changes factory/, other than one that changes only
# factory/VERSION there (the release's own commit); one that changes only the
# workspace or the project needs no trailer. The kind the amends make (release_kind):
#   - minor when any amend commit says minor, naming each;
#   - else minor when the floor holds: the diff origin/<branch>...HEAD changes
#     a path that only a minor changes (floor_reason): any file of an adapter's
#     templates, factory/adapters/<adapter>/tools/verify/ (a project ports it by
#     hand, sync.sh says, and a new step script is one); factory/core/skill-words
#     (the skills' word budgets); factory/core/lib/steps.sh (the gate's steps);
#     factory/core/lib/architecture.sh and factory/core/deviation.sh (checks the
#     gate runs); factory/core/hooks/claude-deny.sh, factory/core/lib/protect.sh
#     and factory/core/hooks/claude-wait-guard.sh (the hooks that refuse calls);
#     factory/core/hooks/pre-commit.sh and factory/core/hooks/githooks/ (the
#     pre-commit checks); factory/core/hooks/claude-hooks.json and
#     claude-workspace-hooks.json (which hooks run); and a file added to
#     factory/core/hooks/ (a new hook). The floor only raises: a check added
#     elsewhere is the trailer's to say;
#   - else patch.
# release with no argument bumps by that kind, from the factory/VERSION of
# origin/<branch> as last fetched (patch: x.y.z+1; minor: x.y+1.0), and says
# which commits or floor paths decided it; `release patch` or `release minor`
# is refused when the amends make the other kind; `release <version>`, greater
# than origin/<branch>'s, is the override for a version no plain step gives
# (1.0.0), refused when it is the plain step of the other kind. Each refuses an
# amend commit with no Release: trailer, or with a value other than minor or
# patch, naming it. land refuses them too, before its check stage, when
# factory/VERSION changed since origin/<branch> (in a project, only when it
# publishes the amends to the factory repo: with no upstream line, or a main
# that holds HEAD's factory/ already, as after a sync, there is no release to
# check), and a factory/VERSION that
# is the plain step of the other kind; one that is neither plain step was set
# by hand, and it says so in a stage line, as it says the kind it found.
#
# Problems go to stderr. Exit codes: 0 recorded, released, clean or landed; 1 refused, a
# finding or a failed stage; 2 usage.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/findings.sh"
. "$core/lib/vendor.sh"
. "$core/lib/project.sh"
. "$core/lib/run.sh"
. "$core/lib/hooks.sh"
. "$core/lib/agents.sh"
. "$core/lib/localenv.sh"
. "$core/lib/suites.sh"

say() { echo "amend: $*" >&2; }
die() {
	say "$*"
	exit 1
}
stage() { echo "amend: $*"; }

case "$#:${1:-}" in
	1:record | 1:check | 1:land | 1:release) true ;;
	2:release) [ "${2#-}" = "$2" ] && [ -n "$2" ] ;;
	2:land) [ "$2" = --all-tests ] ;;
	*) false ;;
esac || {
	echo "usage: bash factory/core/amend.sh record|check|land [--all-tests]|release [patch|minor|<version>]" >&2
	exit 2
}
cmd="$1"
release_to=""
all_tests=""
if [ "$cmd" = land ]; then
	all_tests="${2:-}"
else
	release_to="${2:-}"
fi

top="$(git rev-parse --show-toplevel 2> /dev/null)" || die "not inside a git checkout"
cd "$top" || die "cannot enter $top"
# The factory's own repo (see the header), else an Adopted project.
in_repo=""
if [ -f "$FACTORY_REPO_MARKER" ] && [ -f "$FACTORY_VENDOR_DIR/core/amend.sh" ] && [ ! -e "$FACTORY_VERSION_FILE" ]; then
	in_repo=1
	FACTORY_BASE_BRANCH=main
else
	[ -f "$FACTORY_VERSION_FILE" ] || die "not adopted (no $FACTORY_VERSION_FILE); run factory/core/adopt.sh first"
	adapter="$(factory_vendor_field adapter)" || die "$FACTORY_VERSION_FILE names no adapter"
	project="$(factory_project_name "$top")"
fi
again="run bash factory/core/amend.sh record"

tmp="$(mktemp -d)" || die "could not make a temp folder"
trap 'rm -rf "$tmp"' EXIT

# installs <factory dir>: the copies that factory lists (factory_installed_copies),
# read in a shell of its own.
installs() {
	bash -c '. "$1/core/lib/steps.sh" && . "$1/core/lib/vendor.sh" && factory_installed_copies "$2" "$3"' _ "$1" "$adapter" "$project"
}

# recorded_factory <edits> <dir>: the factory as factory-version records it, in
# <dir>: each file unchanged since, from factory/; each one changed or missing
# since (<edits>, factory_vendor_edits' lines), read back from git by its
# recorded blob. A blob git doesn't have leaves an empty file: what that file
# installed can't be told, and $unread counts it. It starts a few processes, not
# one per file: one mkdir for every folder, one cp per folder for the unchanged
# files (plain cp, so macOS and Git Bash run it too), and git cat-file only for
# each changed one.
recorded_factory() {
	local -A edited=() sources=()
	local -a dirs=() blobs=() dests=() srcs=()
	local line blob path dest dir i
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		path="${line% *}"
		edited[$path]=1
	done <<< "$1"
	unread=0
	while read -r blob path; do
		dest="$2/${path#"$FACTORY_VENDOR_DIR"/}"
		dir="${dest%/*}"
		if [ -z "${sources[$dir]+set}" ]; then
			dirs+=("$dir")
			sources[$dir]=""
		fi
		if [ -z "${edited[$path]+set}" ]; then
			sources[$dir]+="$path"$'\n'
		else
			blobs+=("$blob")
			dests+=("$dest")
		fi
	done < <(tr -d '\r' < "$FACTORY_VERSION_FILE" | sed -n 's/^file //p')
	[ "${#dirs[@]}" -eq 0 ] || mkdir -p -- "${dirs[@]}" || return 1
	for dir in "${dirs[@]}"; do
		[ -n "${sources[$dir]}" ] || continue
		mapfile -t srcs <<< "${sources[$dir]%$'\n'}"
		cp -- "${srcs[@]}" "$dir/" || return 1
	done
	for i in "${!blobs[@]}"; do
		if ! git cat-file blob "${blobs[$i]}" > "${dests[$i]}" 2> /dev/null; then
			: > "${dests[$i]}"
			unread=$((unread + 1))
		fi
	done
}

# generates <how>: true for a factory_installed_copies entry of the generated
# skill, when factory/ has its generator.
generates() {
	[ "$1" = skill ] && [ -f "$FACTORY_VENDOR_DIR/core/verify-skill.sh" ] && [ -f "$FACTORY_VENDOR_DIR/adapters/$adapter/verify-skill.sh" ]
}

# plan <edits>: what record does to the copies, one `<action>\t<copy>\t<file>`
# line each, sorted by copy: install (missing), refresh (differs; never a copy
# factory/ seeds), remove (the factory as recorded installed it, factory/ on
# disk no longer does; never a copy either one seeds; no <file>). <edits> is
# factory_vendor_edits' output: with none, the factory as recorded is factory/
# itself. Dies when factory/'s copies can't be listed, rendered or generated,
# before any change.
plan() {
	local list old_list="" how source copy file
	list="$(installs "$FACTORY_VENDOR_DIR")" || die "could not read factory/'s list of installed copies (factory_installed_copies)"
	# A generator that fails installs nothing (factory_installed_files), which
	# would read as a dropped skill: it stops here instead.
	while read -r how source copy; do
		generates "$how" || continue
		rm -rf "$tmp/generator"
		bash "$FACTORY_VENDOR_DIR/core/verify-skill.sh" --adapter "$adapter" --out "$tmp/generator" < /dev/null > /dev/null 2> "$tmp/generator.err" || {
			cat "$tmp/generator.err" >&2
			die "could not generate $copy: the $adapter adapter's verify-skill generator fails"
		}
	done <<< "$list"
	factory_installed_files "$FACTORY_VENDOR_DIR" "$list" "$tmp/now" "$adapter" "$project" > "$tmp/now.list" ||
		die "could not render factory/'s subagents"

	if [ -z "$1" ]; then
		cp "$tmp/now.list" "$tmp/was.list"
	else
		: > "$tmp/was.list"
		if ! recorded_factory "$1" "$tmp/old" || ! old_list="$(installs "$tmp/old")" ||
			! factory_installed_files "$tmp/old" "$old_list" "$tmp/was" "$adapter" "$project" > "$tmp/was.list"; then
			say "could not tell every copy the factory as recorded installed, so a copy of a file factory/ dropped may stay; check .claude/ by hand"
		elif [ "$unread" -gt 0 ]; then
			say "git has $unread of the recorded files no more, so a copy of a file factory/ dropped may stay; check .claude/ by hand"
		fi
	fi
	# The generated skill's folder is its generator's alone: a file there that it
	# no longer writes, for the project as it is now, goes too.
	while read -r how source copy; do
		generates "$how" && [ -d "$copy" ] || continue
		find "$copy" -type f | LC_ALL=C sort | while IFS= read -r file; do printf '%s\t\n' "$file"; done >> "$tmp/was.list"
	done <<< "$list"

	local -A now=() was=() seeds=() seeded=()
	while IFS=$'\t' read -r copy file; do [ -n "${now[$copy]+set}" ] || now[$copy]="$file"; done < "$tmp/now.list"
	while IFS=$'\t' read -r copy file; do [ -n "${was[$copy]+set}" ] || was[$copy]="$file"; done < "$tmp/was.list"
	while read -r how source copy; do
		[ "$how" != seed ] || seeds[$copy]=1
	done <<< "$list"
	# shellcheck disable=SC2034 # source: a field the loop skips
	while read -r how source copy; do
		[ "$how" != seed ] || seeded[$copy]=1
	done <<< "$list"$'\n'"$old_list"
	while IFS= read -r copy; do
		if [ -n "${now[$copy]+set}" ]; then
			if [ ! -e "$copy" ] && [ ! -L "$copy" ]; then
				printf 'install\t%s\t%s\n' "$copy" "${now[$copy]}"
			elif [ -n "${seeds[$copy]+set}" ]; then
				continue
			elif [ ! -L "$copy" ] && [ ! -f "$copy" ]; then
				die "$copy is not a file; move it out of the way, then $again"
			elif [ -L "$copy" ] || ! cmp -s "${now[$copy]}" "$copy"; then
				# A symlink counts as changed: record replaces it with a file.
				printf 'refresh\t%s\t%s\n' "$copy" "${now[$copy]}"
			fi
		elif [ -z "${seeded[$copy]+set}" ] && { [ -e "$copy" ] || [ -L "$copy" ]; }; then
			printf 'remove\t%s\t\n' "$copy"
		fi
	done < <(cut -f 1 "$tmp/now.list" "$tmp/was.list" | LC_ALL=C sort -u)
}

# regenerate <hooks|agents> <file...>: run that Core script's generate, then
# print each of the files it changed or removed.
regenerate() {
	local what="$1" f i=0
	shift
	for f in "$@"; do
		i=$((i + 1))
		rm -f "$tmp/before-$what-$i"
		[ ! -f "$f" ] || cp "$f" "$tmp/before-$what-$i" || die "could not keep $f"
	done
	bash "$FACTORY_VENDOR_DIR/core/$what.sh" generate || die "could not regenerate $* ($what.sh generate)"
	i=0
	for f in "$@"; do
		i=$((i + 1))
		if [ ! -f "$f" ]; then
			[ ! -f "$tmp/before-$what-$i" ] || echo "removed $f"
			continue
		fi
		[ -f "$tmp/before-$what-$i" ] && cmp -s "$tmp/before-$what-$i" "$f" || echo "regenerated $f"
	done
}

# ports <edits>: say which of the adapter's templates changed or added since the
# record differ from the project's step script of the same name.
ports() {
	local line path templates="$FACTORY_VENDOR_DIR/adapters/$adapter/tools/verify/"
	while IFS= read -r line; do
		path="${line% *}"
		case "${line##* }" in changed | added) ;; *) continue ;; esac
		case "$path" in "$templates"*) ;; *) continue ;; esac
		cmp -s "$path" "$FACTORY_STEPS_DIR/${path#"$templates"}" ||
			say "port $path to $FACTORY_STEPS_DIR/${path#"$templates"} by hand: the gate runs the project's copy, which differs"
	done <<< "$1"
}

# record [<version> <tag>]: see the header; release passes the new version and
# tag to record in place of factory-version's.
record() {
	local edits version tag upstream action copy file
	edits="$(factory_vendor_edits)" || {
		edits=""
		say "$FACTORY_VERSION_FILE records no vendored files, so no copy of a file factory/ dropped can be found; check .claude/ by hand"
	}
	version="$(factory_vendor_field version)" || die "$FACTORY_VERSION_FILE names no version"
	tag="$(factory_vendor_field tag)" || tag=""
	upstream="$(factory_vendor_field upstream)" || upstream=""
	if [ "$#" -eq 2 ]; then
		version="$1"
		tag="$2"
	fi
	plan "$edits" > "$tmp/plan"
	while IFS=$'\t' read -r action copy file; do
		case "$action" in
			install | refresh)
				# A symlink is replaced, never written through.
				[ ! -L "$copy" ] || rm -f "$copy" || die "could not remove the symlink $copy"
				mkdir -p "$(dirname "$copy")" && cp "$file" "$copy" || die "could not write $copy"
				[ "$action" = install ] && echo "installed $copy" || echo "refreshed $copy"
				;;
			remove)
				rm -f "$copy" || die "could not remove $copy"
				rmdir -p "$(dirname "$copy")" 2> /dev/null
				echo "removed $copy"
				;;
		esac
	done < "$tmp/plan"

	# The retired Cursor files are named so that their removal is said.
	regenerate hooks "$FACTORY_CLAUDE_SETTINGS" .cursor/hooks.json .cursor/cli.json
	regenerate agents "$FACTORY_AGENTS_FILE"
	ports "$edits"

	cp "$FACTORY_VERSION_FILE" "$tmp/record" || die "could not keep $FACTORY_VERSION_FILE"
	factory_vendor_record "$version" "$adapter" "$tag" "$upstream" || die "could not write $FACTORY_VERSION_FILE"
	factory_vendor_files | git hash-object -w --stdin-paths > /dev/null || die "could not store factory/'s files in git"
	cmp -s "$tmp/record" "$FACTORY_VERSION_FILE" || echo "recorded $FACTORY_VERSION_FILE"
}

# check: print the findings, sorted; false when there is any.
check() {
	local edits line action copy file status=0
	if ! edits="$(factory_vendor_edits)"; then
		factory_finding "$FACTORY_VERSION_FILE" 1 factory-record "records no vendored files; $again" > "$tmp/findings"
		edits=""
		status=1
	fi
	plan "$edits" > "$tmp/plan"
	{
		while IFS= read -r line; do
			[ -n "$line" ] || continue
			factory_finding "${line% *}" 1 factory-record "${line##* } since $FACTORY_VERSION_FILE was recorded; $again"
			status=1
		done <<< "$edits"
		while IFS=$'\t' read -r action copy file; do
			case "$action" in
				install) factory_finding "$copy" 1 factory-copy "missing; factory/ installs it; $again" ;;
				refresh) factory_finding "$copy" 1 factory-copy "differs from what factory/ installs; $again" ;;
				remove) factory_finding "$copy" 1 factory-copy "factory/ no longer installs it; $again" ;;
			esac
			status=1
		done < "$tmp/plan"
		bash "$FACTORY_VENDOR_DIR/core/hooks.sh" check || status=1
		bash "$FACTORY_VENDOR_DIR/core/agents.sh" check || status=1
		bash "$FACTORY_VENDOR_DIR/core/skill-budget.sh" || status=1
	} >> "$tmp/findings"
	factory_sort_findings < "$tmp/findings"
	return "$status"
}

# release: bump factory/VERSION (bump, as $release_to says), then
# record with version <new> and tag v<new>.
release() {
	local new
	factory_vendor_field upstream > /dev/null ||
		die "$FACTORY_VERSION_FILE records no upstream (the factory's repo), so land publishes no release; it lands the project alone"
	bump
	record "$new" "v$new"
}

# bump: write the new factory/VERSION and say so (the header's "The release
# kind"); sets $new. From the factory/VERSION of $FACTORY_REMOTE/
# $FACTORY_BASE_BRANCH, by the kind the amends make when $release_to is empty;
# patch or minor only when it is that kind; a <version> greater than the base's,
# unless it is the plain step of the other kind.
bump() {
	local base was current kind kind_why step how stop="nothing released"
	base="refs/remotes/$FACTORY_REMOTE/$FACTORY_BASE_BRANCH"
	git rev-parse --verify -q "$base^{commit}" > /dev/null ||
		die "no $FACTORY_REMOTE/$FACTORY_BASE_BRANCH to read the amends since; git fetch $FACTORY_REMOTE, then release again"
	was="$(git show "$base:$FACTORY_VENDOR_DIR/VERSION" 2> /dev/null | tr -d '\r\n')"
	factory_version_is "$was" || die "$FACTORY_REMOTE/$FACTORY_BASE_BRANCH has $FACTORY_VENDOR_DIR/VERSION '$was', not <major>.<minor>.<patch>"
	current="$(tr -d '\r\n' < "$FACTORY_VENDOR_DIR/VERSION")" || die "no $FACTORY_VENDOR_DIR/VERSION"
	factory_version_is "$current" || die "$FACTORY_VENDOR_DIR/VERSION is '$current', not <major>.<minor>.<patch>"
	case "$release_to" in
		'' | patch | minor) ;;
		*)
			factory_version_is "$release_to" || die "'$release_to' is not patch, minor or <major>.<minor>.<patch>"
			factory_version_greater "$release_to" "$was" ||
				die "$release_to is not greater than $FACTORY_VENDOR_DIR/VERSION on $FACTORY_REMOTE/$FACTORY_BASE_BRANCH ($was)"
			;;
	esac
	release_kind "$base" HEAD
	step="$(release_step "$was" "$kind")"
	how="$kind, $kind_why"
	case "$release_to" in
		'') new="$step" ;;
		patch | minor)
			[ "$release_to" = "$kind" ] || disagree "$release_to" "release $release_to" ""
			new="$step"
			;;
		*)
			new="$release_to"
			if [ "$new" != "$step" ]; then
				[ "$new" != "$(release_step "$was" "$(other_kind)")" ] || disagree "$(other_kind)" "release $new" ""
				how="set by hand, over the amends' $kind ($kind_why)"
			fi
			;;
	esac
	printf '%s\n' "$new" > "$FACTORY_VENDOR_DIR/VERSION" || die "could not write $FACTORY_VENDOR_DIR/VERSION"
	echo "released $new (was $was): $how; commit it as: Release factory $new"
}

# release_step <version> <patch|minor>: <version> bumped by that kind.
release_step() {
	local major minor patch
	IFS=. read -r major minor patch <<< "$1"
	case "$2" in
		patch) echo "$major.$minor.$((10#$patch + 1))" ;;
		minor) echo "$major.$((10#$minor + 1)).0" ;;
	esac
}

# other_kind: the kind $kind is not.
other_kind() {
	if [ "$kind" = minor ]; then echo patch; else echo minor; fi
}

# disagree <its kind> <what> <then>: die, as <what> (a release's argument, or
# land's factory/VERSION) makes a release of <its kind>, and the amends make
# $kind; <then> says what follows the fix.
disagree() {
	local fix="run bash factory/core/amend.sh release, which bumps by the amends' trailers${3:+, $3}"
	[ "$1" = patch ] ||
		fix="if one of the amends is a minor, give it the trailer Release: minor; else $fix; for a version no patch or minor step gives (such as 1.0.0), use release <version>"
	die "$2 makes a $1, and the amends make a $kind ($kind_why): $fix; $stop"
}

# floor_reason <status> <path>: why a change to <path> (git's --name-status
# letter <status>) makes a minor, the floor in the header's "The release kind";
# nothing when it doesn't.
floor_reason() {
	local f="$FACTORY_VENDOR_DIR"
	if [[ $2 == "$f"/adapters/* ]] && [[ ${2#"$f"/adapters/} =~ ^[^/]+/tools/verify/ ]]; then
		echo "an adapter template, which a project ports by hand"
		return 0
	fi
	case "$2" in
		"$f/core/skill-words") echo "the skills' word budgets" ;;
		"$f/core/lib/steps.sh") echo "the gate's steps" ;;
		"$f/core/lib/architecture.sh" | "$f/core/deviation.sh") echo "a check the gate runs" ;;
		"$f/core/hooks/claude-deny.sh" | "$f/core/lib/protect.sh" | "$f/core/hooks/claude-wait-guard.sh") echo "a hook that refuses calls" ;;
		"$f/core/hooks/pre-commit.sh" | "$f/core/hooks/githooks/"*) echo "the pre-commit checks" ;;
		"$f/core/hooks/claude-hooks.json" | "$f/core/hooks/claude-workspace-hooks.json") echo "which hooks run" ;;
		"$f/core/hooks/"*) [ "$1" != A ] || echo "a new hook" ;;
	esac
}

# release_kind <base> <head>: the kind of release the amends of <base>..<head>
# make (the header's "The release kind"): sets $kind (patch or minor) and
# $kind_why, which says what decided it. Dies, ending with $stop, naming an
# amend commit with no Release: trailer or one with another value.
release_kind() {
	local c value subject minors="" n=0 status path reason floor="" paths=0
	local -A seen=()
	git log --no-merges --reverse --format='%H%x09%(trailers:key=Release,valueonly,separator=%x2C)' "$1..$2" > "$tmp/kinds" ||
		die "could not read the commits since $FACTORY_REMOTE/$FACTORY_BASE_BRANCH; $stop"
	while IFS=$'\t' read -r c value; do
		git diff-tree --root --no-commit-id --name-only -r --no-renames "$c" -- "$FACTORY_VENDOR_DIR/" > "$tmp/kind-paths" ||
			die "could not list the paths ${c:0:7} touches; $stop"
		# None in factory/, or factory/VERSION alone (the release's commit): no amend.
		grep -qvxF "$FACTORY_VENDOR_DIR/VERSION" "$tmp/kind-paths" || continue
		subject="$(git show -s --format=%s "$c")"
		case "$value" in
			minor) minors="$minors${minors:+, }${c:0:7}" ;;
			patch) ;;
			'') die "${c:0:7} (\"$subject\") changes $FACTORY_VENDOR_DIR/ and has no Release: trailer; give it Release: minor when it adds or tightens a check, changes a step the human does, changes how issues are filed or needs a template ported by hand, else Release: patch (git commit --amend, or a rebase); $stop" ;;
			*) die "${c:0:7} (\"$subject\") has the trailer Release: $value; it takes one, minor or patch; $stop" ;;
		esac
		n=$((n + 1))
	done < "$tmp/kinds"
	if [ -n "$minors" ]; then
		kind=minor
		kind_why="from $minors (Release: minor)"
		return 0
	fi
	git diff --name-status --no-renames -z "$1...$2" -- "$FACTORY_VENDOR_DIR/" > "$tmp/floor" ||
		die "could not list the diff since $FACTORY_REMOTE/$FACTORY_BASE_BRANCH; $stop"
	while IFS= read -r -d '' status && IFS= read -r -d '' path; do
		reason="$(floor_reason "$status" "$path")"
		[ -n "$reason" ] || continue
		paths=$((paths + 1))
		[ -z "${seen[$reason]+set}" ] || continue
		seen[$reason]=1
		floor="$floor${floor:+, }$path ($reason)"
	done < "$tmp/floor"
	if [ -n "$floor" ]; then
		kind=minor
		kind_why="from the floor, where the trailers say patch: $floor changed"
		[ "$paths" -le "${#seen[@]}" ] || kind_why="$kind_why ($paths such paths in all)"
	elif [ "$n" -eq 0 ]; then
		kind="patch"
		kind_why="no amend commit since $FACTORY_REMOTE/$FACTORY_BASE_BRANCH"
	else
		kind="patch"
		kind_why="each of the $n amend commits says Release: patch"
		[ "$n" -ne 1 ] || kind_why="the one amend commit says Release: patch"
	fi
}

# release_check <base> <head> <base version> <version>: land's check of the
# release kind (the header's "The release kind"), when <version> differs from
# <base version>: dies on an amend commit with no valid Release: trailer, or a
# <version> that is the plain step of the other kind; says the kind in a stage
# line, and that <version> was set by hand when it is neither plain step.
release_check() {
	local kind kind_why step stop="$FACTORY_BASE_BRANCH not moved"
	[ "$4" != "$3" ] || return 0
	factory_version_is "$3" || die "$FACTORY_REMOTE/$FACTORY_BASE_BRANCH has $FACTORY_VENDOR_DIR/VERSION '$3', not <major>.<minor>.<patch>; $stop"
	release_kind "$1" "$2"
	step="$(release_step "$3" "$kind")"
	if [ "$4" = "$step" ]; then
		stage "the release, $4: a $kind from $3, as the amends make ($kind_why)"
	elif [ "$4" = "$(release_step "$3" "$(other_kind)")" ]; then
		disagree "$(other_kind)" "$FACTORY_VENDOR_DIR/VERSION $4 (from $3)" "commit it as Release factory <new>, then land again"
	else
		stage "the release, $4: no patch or minor step from $3, so set by hand (release <version>), over the amends' $kind ($kind_why)"
	fi
}

# upstream_check <head>: land's refusals when factory-version names the
# factory's repo ($upstream), before any stage. Sets $up_main (its main),
# $up_tag (v<factory/VERSION at <head>>) and $publish_how: all (replay the amend's
# commits, then tag), tag (main has <head>'s factory/ already; tag it) or none
# (main and the tag have it: a rerun after a refused project push), and
# $up_layout: workspace (main holds the factory under factory/) or root.
upstream_check() {
	local head="$1" refs version up_version head_tree up_tree dev_tree tag_tree=""
	stage "fetch the factory repo's main ($upstream)"
	version="$(git show "$head:$FACTORY_VENDOR_DIR/VERSION" 2> /dev/null | tr -d '\r\n')"
	factory_version_is "$version" || die "$FACTORY_VENDOR_DIR/VERSION is '$version', not <major>.<minor>.<patch>"
	up_tag="v$version"
	refs="$(git ls-remote "$upstream" refs/heads/main "refs/tags/$up_tag" 2> "$tmp/ls")" || {
		sed 's/^/  /' "$tmp/ls" >&2
		die "could not fetch the factory repo ($upstream); $FACTORY_BASE_BRANCH not moved"
	}
	printf '%s\n' "$refs" | awk '$2 == "refs/heads/main" { found = 1 } END { exit !found }' ||
		die "the factory repo ($upstream) has no main branch; $FACTORY_BASE_BRANCH not moved"
	git fetch -q --no-tags "$upstream" refs/heads/main 2> "$tmp/fetch" && up_main="$(git rev-parse --verify -q 'FETCH_HEAD^{commit}')" || {
		sed 's/^/  /' "$tmp/fetch" >&2
		die "could not fetch the factory repo's main ($upstream); $FACTORY_BASE_BRANCH not moved"
	}
	if printf '%s\n' "$refs" | awk -v r="refs/tags/$up_tag" '$2 == r { found = 1 } END { exit !found }'; then
		git fetch -q --no-tags "$upstream" "refs/tags/$up_tag" 2> "$tmp/fetch" && tag_tree="$(factory_repo_tree 'FETCH_HEAD^{commit}')" || {
			sed 's/^/  /' "$tmp/fetch" >&2
			die "could not fetch the factory repo's tag $up_tag ($upstream); $FACTORY_BASE_BRANCH not moved"
		}
	fi
	head_tree="$(git rev-parse --verify -q "$head:$FACTORY_VENDOR_DIR")" || die "HEAD has no $FACTORY_VENDOR_DIR/"
	up_tree="$(factory_repo_tree "$up_main")" || die "the factory repo's main holds no factory (no factory/VERSION, and no VERSION and core/ at its root); $FACTORY_BASE_BRANCH not moved"
	if git cat-file -e "$up_main:factory/VERSION" 2> /dev/null; then up_layout=workspace; else up_layout=root; fi
	if [ "$up_tree" = "$head_tree" ]; then
		if [ -z "$tag_tree" ]; then
			publish_how=tag
		elif [ "$tag_tree" = "$head_tree" ]; then
			publish_how=none
		else
			die "the factory repo's main has HEAD's $FACTORY_VENDOR_DIR/, but its tag $up_tag is on a different tree; $FACTORY_BASE_BRANCH not moved"
		fi
		return 0
	fi
	dev_tree="$(git rev-parse --verify -q "$remote_ref:$FACTORY_VENDOR_DIR")" || dev_tree=""
	[ "$up_tree" = "$dev_tree" ] ||
		die "the factory repo's main differs from $FACTORY_VENDOR_DIR/ on $FACTORY_REMOTE/$FACTORY_BASE_BRANCH: the project is behind it or ahead of it; sync first (bash factory/core/sync.sh <the factory repo's latest tag>), then land again; $FACTORY_BASE_BRANCH not moved"
	up_version="$(git show "$up_tree:VERSION" 2> /dev/null | tr -d '\r\n')"
	factory_version_is "$up_version" || die "the factory repo's main has VERSION '$up_version', not <major>.<minor>.<patch>"
	factory_version_greater "$version" "$up_version" ||
		die "$FACTORY_VENDOR_DIR/VERSION ($version) is not greater than the factory repo's ($up_version); run bash factory/core/amend.sh release, commit it as Release factory <new>, then land again; $FACTORY_BASE_BRANCH not moved"
	[ -z "$tag_tree" ] ||
		die "the factory repo has the tag $up_tag already, on a different tree; release a greater version (bash factory/core/amend.sh release <version>), commit, then land again; $FACTORY_BASE_BRANCH not moved"
	publish_how=all
}

# publish <head>: send the amend to the factory's repo, as $publish_how says: each
# commit of $remote_ref..<head> (first parents, oldest first) that changes
# factory/, replayed as a commit whose tree is its factory/, with its author,
# author date and message, on the factory repo's main; then main pushed (a
# fast-forward or nothing) and the annotated tag $up_tag on its tip. In the
# workspace layout each replayed commit's tree is its parent's with only
# factory/ replaced (workspace_tree).
publish() {
	local head="$1" parent last c tree before n=0 tag
	case "$publish_how" in
		none)
			stage "the factory repo has $up_tag already (main and the tag hold HEAD's $FACTORY_VENDOR_DIR/); skipped publishing"
			return 0
			;;
		tag)
			last="$up_main"
			stage "publish to the factory repo: its main holds HEAD's $FACTORY_VENDOR_DIR/ already; tag it $up_tag"
			;;
		all)
			parent="$up_main"
			while IFS= read -r c; do
				tree="$(git rev-parse --verify -q "$c:$FACTORY_VENDOR_DIR")" || continue
				before="$(git rev-parse --verify -q "$c^:$FACTORY_VENDOR_DIR")" || before=""
				[ "$tree" != "$before" ] || continue
				git cat-file commit "$c" | sed '1,/^$/d' > "$tmp/message" || die "could not read the message of $c"
				if [ "$up_layout" = workspace ]; then
					tree="$(workspace_tree "$parent" "$tree")" || die "could not build the factory repo's tree for $c; nothing landed"
				fi
				parent="$(
					GIT_AUTHOR_NAME="$(git show -s --format=%an "$c")" \
					GIT_AUTHOR_EMAIL="$(git show -s --format=%ae "$c")" \
					GIT_AUTHOR_DATE="$(git show -s --format=%ad --date=raw "$c")" \
						git commit-tree "$tree" -p "$parent" -F "$tmp/message"
				)" || die "could not replay $c for the factory repo; nothing landed"
				n=$((n + 1))
			done < <(git rev-list --reverse --first-parent "$remote_ref..$head")
			last="$parent"
			stage "publish to the factory repo ($upstream): $n commits on its main, then the tag $up_tag"
			if ! git push -q "$upstream" "$last:refs/heads/main" 2> "$tmp/push"; then
				sed 's/^/  /' "$tmp/push" >&2
				die "the push to the factory repo's main was refused (did it move?); nothing landed; sync to its latest tag, then land again"
			fi
			;;
	esac
	tag="$(printf 'object %s\ntype commit\ntag %s\ntagger %s\n\nfactory %s\n' "$last" "$up_tag" "$(git var GIT_COMMITTER_IDENT)" "${up_tag#v}" | git mktag)" ||
		die "could not make the tag $up_tag; the factory repo's main may hold the amend: land again to tag it; $FACTORY_BASE_BRANCH not moved"
	if ! git push -q "$upstream" "$tag:refs/tags/$up_tag" 2> "$tmp/push"; then
		sed 's/^/  /' "$tmp/push" >&2
		die "the push of the tag $up_tag to the factory repo was refused; land again to tag it; $FACTORY_BASE_BRANCH not moved"
	fi
	stage "published $up_tag to the factory repo: main at $last"
}

# workspace_tree <commit> <tree>: a tree of the factory repo in the workspace
# layout: <commit>'s tree with its factory/ replaced by <tree>.
workspace_tree() {
	{
		git ls-tree -z "$1^{tree}" | while IFS= read -r -d '' entry; do
			[ "${entry#*$'\t'}" = "$FACTORY_VENDOR_DIR" ] || printf '%s\0' "$entry"
		done
		printf '040000 tree %s\t%s\0' "$2" "$FACTORY_VENDOR_DIR"
	} | git mktree -z
}

# local_env <file> <name>: the variable <name> as the env file <file> sets it,
# read in a shell of its own; nothing when it sets none or there is no <file>.
local_env() {
	[ -f "$1" ] || return 0
	(
		unset "$2"
		set -a
		# shellcheck disable=SC1090
		. "./$1" > /dev/null 2>&1
		printf '%s' "${!2:-}"
	)
}

# fast_forward <commit>: move dev in the main checkout to <commit>, when that
# checkout is on dev with no uncommitted change; else say why not.
fast_forward() {
	local main branch
	main="$(factory_main_checkout)" || {
		stage "could not find the main checkout; left $FACTORY_BASE_BRANCH alone"
		return 0
	}
	branch="$(git -C "$main" symbolic-ref --short -q HEAD)"
	if [ "$branch" != "$FACTORY_BASE_BRANCH" ]; then
		stage "left $FACTORY_BASE_BRANCH alone: the main checkout ($main) is on ${branch:-a detached HEAD}"
	elif [ -n "$(git -C "$main" status --porcelain --untracked-files=no)" ]; then
		stage "left $FACTORY_BASE_BRANCH alone: the main checkout ($main) has uncommitted changes; once they are put away, git merge --ff-only $1 there"
	elif git -C "$main" merge --ff-only -q "$1" >&2; then
		stage "fast-forwarded $FACTORY_BASE_BRANCH in the main checkout ($main) to $1"
	else
		stage "left $FACTORY_BASE_BRANCH alone: it would not fast-forward to $1 in the main checkout ($main)"
	fi
}

# real_tool_reads <adapter> <path>: true when that adapter's real-tool tests
# read <path> (the header's "The full suite at land").
real_tool_reads() {
	local folder
	case "$2" in
		"$FACTORY_VENDOR_DIR/adapters/$1/"*) return 0 ;;
		"$FACTORY_VENDOR_DIR/adapters/"* | "$FACTORY_VENDOR_DIR/VERSION") return 1 ;;
		"$FACTORY_VENDOR_DIR/"*) return 0 ;;
	esac
	while IFS= read -r folder; do
		[ -z "$folder" ] || [ "${2#"$folder"}" = "$2" ] || return 0
	done < <(factory_suites_outside "$1")
	return 1
}

# suite_skips <base> <head>: set $skip_adapters to the adapters whose suites no
# path the diff <base>..<head> touches can affect, by lib/suites.sh's rules
# (factory_suites_affected, as stress.sh --since chooses), saying so in one
# stage line; none with --all-tests, or when git can't list the diff.
suite_skips() {
	local dir a in_use="" chosen list
	skip_adapters=()
	[ -z "$all_tests" ] || return 0
	if ! git diff --name-only --no-renames -z "$1" "$2" -- > "$tmp/scope" 2> "$tmp/scope.err"; then
		sed 's/^/  /' "$tmp/scope.err" >&2
		say "could not list the diff since $FACTORY_REMOTE/$FACTORY_BASE_BRANCH, so every adapter's suites run"
		return 0
	fi
	# A project's ported tools/verify/ is its adapter's.
	[ -n "$in_repo" ] || in_use="$adapter"
	chosen="$(tr '\0' '\n' < "$tmp/scope" | factory_suites_affected "$FACTORY_VENDOR_DIR/" "$in_use")"
	for dir in "$FACTORY_VENDOR_DIR"/adapters/*/; do
		a="$(basename "$dir")"
		[ -d "$dir/tests" ] || continue
		grep -q "^$a/" <<< "$chosen" || skip_adapters+=("$a")
	done
	case "${#skip_adapters[@]}" in
		0) return 0 ;;
		1) list="the ${skip_adapters[0]} adapter" ;;
		*)
			list="$(printf '%s, ' "${skip_adapters[@]:0:${#skip_adapters[@]}-1}")"
			list="the ${list%, } and ${skip_adapters[-1]} adapters"
			;;
	esac
	stage "skip the suites of $list: the diff since $FACTORY_REMOTE/$FACTORY_BASE_BRANCH touches no path that can affect them (lib/suites.sh, as stress.sh --since chooses: the adapter's folder, $FACTORY_VENDOR_DIR/core/ outside core/tests/ or core/tests/lib.sh, a $FACTORY_VENDOR_DIR/ file its tests name, a folder outside $FACTORY_VENDOR_DIR/ they read); every core suite runs; land --all-tests runs them"
}

# real_tool_skips <base> <head>: set $skip_real to test.sh's --skip-real
# arguments for each adapter whose real-tool tests read no path the diff
# <base>..<head> touches, saying so in a stage line each; none with --all-tests,
# nor for an adapter in $skip_adapters, whose suites don't run at all.
real_tool_skips() {
	local dir adapter path reads outside
	local -a changed=()
	skip_real=()
	[ -z "$all_tests" ] || return 0
	if ! git diff --name-only --no-renames -z "$1" "$2" -- > "$tmp/changed" 2> "$tmp/changed.err"; then
		sed 's/^/  /' "$tmp/changed.err" >&2
		say "could not list the diff since $FACTORY_REMOTE/$FACTORY_BASE_BRANCH, so every real-tool test runs"
		return 0
	fi
	while IFS= read -r -d '' path; do
		changed+=("$path")
	done < "$tmp/changed"
	for dir in "$FACTORY_VENDOR_DIR"/adapters/*/; do
		adapter="$(basename "$dir")"
		[ -d "$dir/tests" ] || continue
		[[ " ${skip_adapters[*]-} " != *" $adapter "* ]] || continue
		reads=""
		for path in ${changed[@]+"${changed[@]}"}; do
			real_tool_reads "$adapter" "$path" && reads=1 && break
		done
		[ -z "$reads" ] || continue
		skip_real+=(--skip-real "$adapter")
		outside="$(factory_suites_outside "$adapter" | tr '\n' ' ')"
		stage "skip the $adapter adapter's real-tool tests (*_with_<tool>): the diff since $FACTORY_REMOTE/$FACTORY_BASE_BRANCH touches no path they read ($FACTORY_VENDOR_DIR/ but the other adapters' folders and $FACTORY_VENDOR_DIR/VERSION${outside:+; ${outside% }}); land --all-tests runs them"
	done
}

# load_average: the machine's load average over 1, 5 and 15 minutes, and its
# thread count; "unknown" where neither /proc/loadavg nor uptime gives it.
load_average() {
	local one five fifteen rest threads
	if read -r one five fifteen rest 2> /dev/null < /proc/loadavg; then
		:
	elif rest="$(uptime 2> /dev/null)" && [[ $rest =~ load\ averages?:\ *([0-9.]+),?\ +([0-9.]+),?\ +([0-9.]+) ]]; then
		one="${BASH_REMATCH[1]}" five="${BASH_REMATCH[2]}" fifteen="${BASH_REMATCH[3]}"
	else
		echo unknown
		return 0
	fi
	threads="$(nproc 2> /dev/null || getconf _NPROCESSORS_ONLN 2> /dev/null)" || threads=""
	echo "$one $five $fifteen (1, 5 and 15 minutes${threads:+, on $threads threads})"
}

# budget <env file>: warn when the suite's wall time (test.sh's last line, in
# $tmp/suite) is over FACTORY_SUITE_BUDGET seconds, from the environment, else
# <env file>, else 1200. Never fails.
budget() {
	local wall limit
	wall="$(sed -n 's/^test\.sh: wall time \([0-9][0-9]*\)\(\.[0-9]*\)\{0,1\} s, .*/\1\2/p' "$tmp/suite" | tail -n 1)"
	[ -n "$wall" ] || return 0
	limit="${FACTORY_SUITE_BUDGET:-}"
	[ -n "$limit" ] || limit="$(local_env "$1" FACTORY_SUITE_BUDGET)"
	case "$limit" in
		'') limit=1200 ;;
		*[!0-9]*)
			say "FACTORY_SUITE_BUDGET is '$limit', not a number of seconds; the budget is 1200 s"
			limit=1200
			;;
	esac
	limit=$((10#$limit))
	# Over the budget: more whole seconds, or as many and a fraction.
	if [ "${wall%%.*}" -gt "$limit" ] || { [ "${wall%%.*}" -eq "$limit" ] && [[ $wall == *.*[1-9]* ]]; }; then
		say "warning: the full suite took $wall s, over its budget of $limit s (FACTORY_SUITE_BUDGET); the load average is $(load_average): a busy machine slows it too"
	fi
	return 0
}

# full_suite <env file>: the stage that runs the full factory/core/test.sh with
# every variable <env file> sets (the environment winning: factory_load_env,
# lib/localenv.sh), with --skip-adapter for each of $skip_adapters and
# $skip_real; prints the summary and every line that isn't a PASS, dies when the
# suite fails, warns when it is over the budget, and dies when a real-tool test
# it ran skipped for a missing tool (real_tool_missing).
full_suite() {
	local file="$1" status a
	local -a args=()
	for a in ${skip_adapters[@]+"${skip_adapters[@]}"}; do
		args+=(--skip-adapter "$a")
	done
	args+=(${skip_real[@]+"${skip_real[@]}"})
	stage "the full suite (bash factory/core/test.sh${args[*]:+ ${args[*]}})"
	(
		factory_load_env "$file"
		exec bash "$FACTORY_VENDOR_DIR/core/test.sh" ${args[@]+"${args[@]}"}
	) < /dev/null > "$tmp/suite" 2>&1
	status=$?
	grep -v '^PASS ' "$tmp/suite"
	[ "$status" -eq 0 ] || die "the full suite failed (exit $status; 2 is a refusal, such as another full run in progress); $FACTORY_BASE_BRANCH not moved"
	budget "$file"
	real_tool_missing "$file"
}

# real_tool_missing <env file>: die when an adapter's real-tool test
# (*_with_<tool>) that the suite in $tmp/suite ran (its adapter in neither
# $skip_real nor $skip_adapters) skipped for a missing tool: a skip whose reason (the last
# indented line under its SKIP line, skip's message) names a variable
# (GODOT_BIN, NODE_BIN, FACTORY_GDUNIT4, ...). It
# says on stderr how many skipped, by adapter, tool and reason, and names the
# variables to set. A skip that names none (a platform the test can't run on)
# is no missing tool, and land goes on.
real_tool_missing() {
	local adapter tool reason n vars
	awk -v skipped=" ${skip_real[*]+${skip_real[*]}} ${skip_adapters[*]+${skip_adapters[*]}} " '
		function flush() {
			if (key != "" && !((key, reason) in count)) order[++n] = key SUBSEP reason
			if (key != "") count[key, reason]++
			key = ""
			reason = ""
			named = 0
		}
		/^(PASS|SKIP|FAIL) / || /^== / || /^test\.sh: / { flush() }
		key != "" {
			# The reason of the skip comes first (its stderr follows its line); the
			# stdout of the next test could follow, before the result line of that test,
			# so the first indented line that names a variable is kept.
			if ($0 ~ /^    / && !named) {
				reason = substr($0, 5)
				named = reason ~ /[A-Z][A-Z0-9]*_[A-Z0-9_]*[A-Z0-9]/
			}
			next
		}
		$1 == "SKIP" && $2 ~ /^[^\/]+\/./ && $3 ~ /_with_[a-z0-9]+$/ {
			adapter = $2
			sub(/\/.*/, "", adapter)
			if (index(skipped, " " adapter " ")) next
			tool = $3
			sub(/.*_with_/, "", tool)
			key = adapter "\t" tool
		}
		END {
			flush()
			for (i = 1; i <= n; i++) {
				split(order[i], part, SUBSEP)
				print count[part[1], part[2]] "\t" part[1] "\t" part[2]
			}
		}
	' "$tmp/suite" > "$tmp/missing"
	vars="$(cut -f 4- "$tmp/missing" | grep -o '[A-Z][A-Z0-9]*_[A-Z0-9_]*[A-Z0-9]' | awk '!seen[$0]++' | paste -sd ' ')"
	[ -n "$vars" ] || return 0
	say "real-tool tests that ran (their adapter's paths changed, or --all-tests) skipped for a missing tool:"
	while IFS=$'\t' read -r n adapter tool reason; do
		[[ $reason =~ [A-Z][A-Z0-9]*_[A-Z0-9_]*[A-Z0-9] ]] || continue
		say "  the $adapter adapter's $tool tests: $n skipped: $reason"
	done < "$tmp/missing"
	die "set $vars (in the environment or $file) so they run, then land again; $FACTORY_BASE_BRANCH not moved"
}

# tests_or_docs_paths: the tests-or-docs list: the paths a commit that claims
# the class (the trailer `Amend-class: tests-or-docs`) may touch, as extended
# regular expressions, one per line. The factory's test folders (not an
# adapter's skeleton, new/, whose tests/ a project gets) and the docs no agent
# reads as instructions; not a skill, an agent, CONTEXT.md, CLAUDE.md, AGENTS.md,
# a template, a brief or a rubric. In a project, also factory-version, which
# record re-records for any change to factory/.
tests_or_docs_paths() {
	echo "^$FACTORY_VENDOR_DIR/core/tests/"
	echo "^$FACTORY_VENDOR_DIR/adapters/[^/]+/tests/"
	echo "^$FACTORY_VENDOR_DIR/README\\.md\$"
	if [ -n "$in_repo" ]; then
		echo '^README\.md$'
		echo '^local\.env\.example$'
	else
		echo "^${FACTORY_VERSION_FILE//./\\.}\$"
	fi
}

# test_counts <commit>: `<path> <n>` for each test file (*_test.sh in
# factory/core/tests/ and an adapter's tests/) at <commit>, <n> its test_*
# functions; one with none is left out.
test_counts() {
	local status
	git grep -c -E '^(function[[:space:]]+)?test_[A-Za-z0-9_]+[[:space:]]*(\(\)|\{)' "$1" -- \
		":(glob)$FACTORY_VENDOR_DIR/core/tests/*_test.sh" ":(glob)$FACTORY_VENDOR_DIR/adapters/*/tests/*_test.sh" > "$tmp/counts" 2> "$tmp/counts.err"
	status=$?
	if [ "$status" -gt 1 ]; then
		sed 's/^/  /' "$tmp/counts.err" >&2
		die "could not count the tests at $1; $FACTORY_BASE_BRANCH not moved"
	fi
	# git grep prints <commit>:<path>:<n>; a commit here is a SHA or a ref, with no colon.
	sed 's/^[^:]*://; s/:\([0-9]*\)$/ \1/' "$tmp/counts"
}

# amend_class <base> <head>: the class check. Each commit of <base>..<head>
# with an Amend-class trailer must claim tests-or-docs (the only class) and
# touch only paths tests_or_docs_paths allows; and when one claims it, no test
# file may have fewer test_* functions at <head> than at <base> (one removed has
# none). Dies naming the commit or the file; says nothing when no commit claims it.
amend_class() {
	local c class subject outside claimed=0 path was now
	git log --format='%H%x09%(trailers:key=Amend-class,valueonly,separator=%x2C)' "$1..$2" > "$tmp/classes" ||
		die "could not read the commits since $FACTORY_REMOTE/$FACTORY_BASE_BRANCH; $FACTORY_BASE_BRANCH not moved"
	tests_or_docs_paths > "$tmp/allowed"
	while IFS=$'\t' read -r c class; do
		[ -n "$class" ] || continue
		subject="$(git show -s --format=%s "$c")"
		[ "$class" = tests-or-docs ] ||
			die "${c:0:12} (\"$subject\") has the trailer Amend-class: $class, and the only class is tests-or-docs; $FACTORY_BASE_BRANCH not moved"
		git diff --name-only --no-renames "$c^" "$c" -- > "$tmp/touched" ||
			die "could not list the paths ${c:0:12} touches; $FACTORY_BASE_BRANCH not moved"
		outside="$(grep -Ev -f "$tmp/allowed" "$tmp/touched" | paste -sd ' ')"
		[ -z "$outside" ] ||
			die "${c:0:12} (\"$subject\") claims Amend-class: tests-or-docs and touches $outside: outside the factory's tests/ folders and the tests-or-docs doc list (tests_or_docs_paths, amend.sh), so the human approves it; drop the trailer once they have, or split the commit; $FACTORY_BASE_BRANCH not moved"
		claimed=$((claimed + 1))
	done < "$tmp/classes"
	[ "$claimed" -gt 0 ] || return 0
	test_counts "$1" > "$tmp/counts.base"
	test_counts "$2" > "$tmp/counts.head"
	while read -r path was; do
		now="$(awk -v p="$path" '$1 == p { print $2 }' "$tmp/counts.head")"
		[ "${now:-0}" -ge "$was" ] ||
			die "$path has ${now:-0} tests at HEAD, fewer than its $was at $FACTORY_REMOTE/$FACTORY_BASE_BRANCH, in a batch that claims Amend-class: tests-or-docs, which removes no test; $FACTORY_BASE_BRANCH not moved"
	done < "$tmp/counts.base"
	stage "the tests-or-docs class, claimed by $claimed commits: they touch only the factory's tests/ folders and the doc list, and no test file lost a test"
}

land() {
	local remote_ref head status baseline upstream up_main="" up_tag="" publish_how="" up_layout=""
	local -a skip_real=() skip_adapters=()
	[ -z "$(git status --porcelain)" ] || die "the tree is dirty; commit or stash first"
	remote_ref="refs/remotes/$FACTORY_REMOTE/$FACTORY_BASE_BRANCH"
	stage "fetch $FACTORY_REMOTE/$FACTORY_BASE_BRANCH"
	git fetch -q "$FACTORY_REMOTE" "$FACTORY_BASE_BRANCH" || die "could not fetch $FACTORY_BASE_BRANCH from $FACTORY_REMOTE"
	git merge-base --is-ancestor "$remote_ref" HEAD 2> /dev/null ||
		die "HEAD does not contain $FACTORY_REMOTE/$FACTORY_BASE_BRANCH; rebase onto it (on a conflict in $FACTORY_VERSION_FILE or an installed copy, take either side and $again), then land again"
	head="$(git rev-parse HEAD)" || die "no HEAD"
	[ "$head" != "$(git rev-parse "$remote_ref")" ] || die "HEAD is $FACTORY_REMOTE/$FACTORY_BASE_BRANCH; commit the amend first"
	# A push to two URLs can land on one and be refused by the other.
	[ "$(git remote get-url --push --all "$FACTORY_REMOTE" | grep -c .)" -eq 1 ] ||
		die "$FACTORY_REMOTE has more than one push URL, and land pushes to one, so that a refused push lands nothing"
	upstream="$(factory_vendor_field upstream)" || upstream=""
	[ -z "$upstream" ] || upstream_check "$head"
	amend_class "$remote_ref" "$head"
	# Land checks the release kind only when it publishes the amends: with no
	# upstream line, or a factory repo that holds HEAD's factory/ already (a
	# synced project), it makes no release, and needs no Release: trailer.
	[ "$publish_how" != all ] || release_check "$remote_ref" "$head" \
		"$(git show "$remote_ref:$FACTORY_VENDOR_DIR/VERSION" 2> /dev/null | tr -d '\r\n')" \
		"$(git show "$head:$FACTORY_VENDOR_DIR/VERSION" 2> /dev/null | tr -d '\r\n')"

	stage "check (bash factory/core/amend.sh check)"
	if ! check > "$tmp/check"; then
		cat "$tmp/check"
		die "check failed; $again, commit, then land again; $FACTORY_BASE_BRANCH not moved"
	fi

	suite_skips "$remote_ref" "$head"
	real_tool_skips "$remote_ref" "$head"
	full_suite "$FACTORY_STEPS_DIR/local.env"

	baseline="$FACTORY_STEPS_DIR/ratchet/baseline.txt"
	if [ -f "$baseline" ] && [ "$(tr -d '\r' < "$baseline" | grep -cv '^[[:space:]]*\(#.*\)\{0,1\}$')" -gt 0 ]; then
		stage "the Baseline gate (FACTORY_BASE=HEAD bash factory/core/baseline.sh gate): the Baseline holds findings, so the full verify is red by design"
		FACTORY_BASE=HEAD bash "$FACTORY_VENDOR_DIR/core/baseline.sh" gate < /dev/null > "$tmp/verify" 2> "$tmp/verify.err"
	else
		stage "verify (FACTORY_BASE=HEAD bash tools/verify.sh)"
		FACTORY_BASE=HEAD bash tools/verify.sh < /dev/null > "$tmp/verify" 2> "$tmp/verify.err"
	fi
	status=$?
	cat "$tmp/verify"
	if [ "$status" -ne 0 ]; then
		tail -n 40 "$tmp/verify.err" >&2
		die "the gate is red; $FACTORY_BASE_BRANCH not moved"
	fi

	# What the stages checked is the tree; what the push sends is $head.
	[ "$(git rev-parse HEAD)" = "$head" ] && [ -z "$(git status --porcelain --untracked-files=no)" ] ||
		die "a stage changed HEAD or a tracked file, so the checks did not see $head; $FACTORY_BASE_BRANCH not moved"
	local published=""
	if [ -n "$upstream" ]; then
		publish "$head"
		published=" (the factory repo has $up_tag already, and a rerun skips publishing)"
	fi
	stage "push to $FACTORY_REMOTE/$FACTORY_BASE_BRANCH"
	if ! git push -q "$FACTORY_REMOTE" "$head:refs/heads/$FACTORY_BASE_BRANCH" 2> "$tmp/push"; then
		sed 's/^/  /' "$tmp/push" >&2
		die "the push to $FACTORY_REMOTE/$FACTORY_BASE_BRANCH was refused (did it move?); fetch, rebase onto it and land again$published; $FACTORY_BASE_BRANCH not moved"
	fi
	stage "landed $head on $FACTORY_REMOTE/$FACTORY_BASE_BRANCH"
	fast_forward "$head"
}

# --- the factory's own repo (see the header) ---

# repo_plan: what record does to the workspace's copies, one
# `<action>\t<copy>\t<file>` line each, sorted by copy: install (missing),
# refresh (differs, or a symlink), remove (a file in a copy's folder that
# factory/ has no source for; no <file>).
repo_plan() {
	local source copy file
	local -A now=()
	: > "$tmp/repo-now.list"
	: > "$tmp/repo-was.list"
	while read -r source copy; do
		factory_tree_files "$FACTORY_VENDOR_DIR/$source" "$copy" >> "$tmp/repo-now.list"
		{ [ -e "$copy" ] || [ -L "$copy" ]; } || continue
		find "$copy" \( -type f -o -type l \) | while IFS= read -r file; do printf '%s\t\n' "$file"; done >> "$tmp/repo-was.list"
	done < <(factory_repo_copies)
	while IFS=$'\t' read -r copy file; do now[$copy]="$file"; done < "$tmp/repo-now.list"
	while IFS= read -r copy; do
		if [ -z "${now[$copy]+set}" ]; then
			printf 'remove\t%s\t\n' "$copy"
		elif [ ! -e "$copy" ] && [ ! -L "$copy" ]; then
			printf 'install\t%s\t%s\n' "$copy" "${now[$copy]}"
		elif [ ! -L "$copy" ] && [ ! -f "$copy" ]; then
			die "$copy is not a file; move it out of the way, then $again"
		elif [ -L "$copy" ] || ! cmp -s "${now[$copy]}" "$copy"; then
			printf 'refresh\t%s\t%s\n' "$copy" "${now[$copy]}"
		fi
	done < <(cut -f 1 "$tmp/repo-now.list" "$tmp/repo-was.list" | LC_ALL=C sort -u)
}

# repo_settings <settings-file>: the workspace's settings as record writes them
# (factory_settings_render with the workspace's hooks); false as it is.
repo_settings() {
	factory_settings_render "$1" "$FACTORY_WORKSPACE_HOOKS"
}

repo_record() {
	local action copy file
	repo_plan > "$tmp/plan"
	while IFS=$'\t' read -r action copy file; do
		case "$action" in
			install | refresh)
				[ ! -L "$copy" ] || rm -f "$copy" || die "could not remove the symlink $copy"
				mkdir -p "$(dirname "$copy")" && cp "$file" "$copy" || die "could not write $copy"
				[ "$action" = install ] && echo "installed $copy" || echo "refreshed $copy"
				;;
			remove)
				rm -f "$copy" || die "could not remove $copy"
				rmdir -p "$(dirname "$copy")" 2> /dev/null
				echo "removed $copy"
				;;
		esac
	done < "$tmp/plan"
	repo_settings "$FACTORY_CLAUDE_SETTINGS" > "$tmp/settings" ||
		die "$FACTORY_CLAUDE_SETTINGS is not a JSON object, or its \"permissions\" or their \"allow\" is of another type; fix it by hand, then $again"
	if [ ! -f "$FACTORY_CLAUDE_SETTINGS" ] || ! cmp -s "$tmp/settings" "$FACTORY_CLAUDE_SETTINGS"; then
		mkdir -p "$(dirname "$FACTORY_CLAUDE_SETTINGS")" && cp "$tmp/settings" "$FACTORY_CLAUDE_SETTINGS" || die "could not write $FACTORY_CLAUDE_SETTINGS"
		echo "regenerated $FACTORY_CLAUDE_SETTINGS"
	fi
}

repo_check() {
	local action copy file status=0
	repo_plan > "$tmp/plan"
	{
		while IFS=$'\t' read -r action copy file; do
			case "$action" in
				install) factory_finding "$copy" 1 factory-copy "missing; factory/ installs it; $again" ;;
				refresh) factory_finding "$copy" 1 factory-copy "differs from what factory/ installs; $again" ;;
				remove) factory_finding "$copy" 1 factory-copy "factory/ no longer installs it; $again" ;;
			esac
			status=1
		done < "$tmp/plan"
		if ! repo_settings "$FACTORY_CLAUDE_SETTINGS" > "$tmp/settings"; then
			factory_finding "$FACTORY_CLAUDE_SETTINGS" 1 hook-drift "not a JSON object, or its \"permissions\" or their \"allow\" is of another type; fix it by hand, then $again"
			status=1
		elif [ ! -f "$FACTORY_CLAUDE_SETTINGS" ] || ! cmp -s "$tmp/settings" "$FACTORY_CLAUDE_SETTINGS"; then
			# One finding, as in hooks.sh check: the keys are judged with the lift
			# rule in place, and settings whose keys are right lack only that rule.
			status=1
			if [ -f "$FACTORY_CLAUDE_SETTINGS" ] && factory_json_allow "$FACTORY_CLAUDE_SETTINGS" "$FACTORY_LIFT_RULE" > "$tmp/allowed" &&
				repo_settings "$tmp/allowed" | cmp -s - "$tmp/allowed"; then
				factory_finding "$FACTORY_CLAUDE_SETTINGS" 1 lift-rule "its \"permissions\" \"allow\" list lacks the factory's rule for the Lock lift, $FACTORY_LIFT_RULE (lib/hooks.sh); $again"
			else
				factory_finding "$FACTORY_CLAUDE_SETTINGS" 1 hook-drift "its \"hooks\", \"model\", \"effortLevel\" or \"maxEffortLevel\" key differs from what the factory writes ($FACTORY_WORKSPACE_HOOKS, lib/hooks.sh); $again"
			fi
		fi
		bash "$FACTORY_VENDOR_DIR/core/skill-budget.sh" || status=1
	} > "$tmp/findings"
	factory_sort_findings < "$tmp/findings"
	return "$status"
}

# repo_tag_at <tag>: the commit the tag names at $FACTORY_REMOTE; nothing when it
# has no such tag. Dies when the remote can't be listed.
repo_tag_at() {
	local refs
	refs="$(git ls-remote "$FACTORY_REMOTE" "refs/tags/$1" "refs/tags/$1^{}" 2> "$tmp/ls")" || {
		sed 's/^/  /' "$tmp/ls" >&2
		die "could not list the tags at $FACTORY_REMOTE; main not moved"
	}
	# An annotated tag's peeled line (^{}) names its commit; a light one's only line does.
	printf '%s\n' "$refs" | awk -v r="refs/tags/$1" '$2 == r "^{}" { peeled = $1 } $2 == r { plain = $1 } END { print (peeled != "" ? peeled : plain) }'
}

repo_land() {
	local remote_ref head main version main_tree head_tree main_version tag="" at
	local -a skip_real=() skip_adapters=()
	[ -z "$(git status --porcelain)" ] || die "the tree is dirty; commit first"
	remote_ref="refs/remotes/$FACTORY_REMOTE/main"
	stage "fetch $FACTORY_REMOTE/main"
	git fetch -q "$FACTORY_REMOTE" main || die "could not fetch main from $FACTORY_REMOTE"
	git merge-base --is-ancestor "$remote_ref" HEAD 2> /dev/null ||
		die "HEAD does not contain $FACTORY_REMOTE/main; rebase onto it (on a conflict in an installed copy, take either side and $again), then land again"
	head="$(git rev-parse HEAD)" || die "no HEAD"
	main="$(git rev-parse "$remote_ref")" || die "no $FACTORY_REMOTE/main"
	[ "$(git remote get-url --push --all "$FACTORY_REMOTE" | grep -c .)" -eq 1 ] ||
		die "$FACTORY_REMOTE has more than one push URL, and land pushes to one, so that a refused push lands nothing"
	head_tree="$(git rev-parse --verify -q "HEAD:$FACTORY_VENDOR_DIR")" || die "HEAD has no $FACTORY_VENDOR_DIR/"
	version="$(git show "HEAD:$FACTORY_VENDOR_DIR/VERSION" 2> /dev/null | tr -d '\r\n')"
	factory_version_is "$version" || die "$FACTORY_VENDOR_DIR/VERSION is '$version', not <major>.<minor>.<patch>"
	main_tree="$(factory_repo_tree "$main")" || die "$FACTORY_REMOTE/main holds no factory"
	main_version="$(git show "$main_tree:VERSION" 2> /dev/null | tr -d '\r\n')"

	[ "$head" != "$main" ] || die "HEAD is $FACTORY_REMOTE/main; nothing to land"
	if [ "$head_tree" != "$main_tree" ]; then
		factory_version_is "$main_version" || die "$FACTORY_REMOTE/main has $FACTORY_VENDOR_DIR/VERSION '$main_version', not <major>.<minor>.<patch>"
		factory_version_greater "$version" "$main_version" ||
			die "$FACTORY_VENDOR_DIR/ changed since $FACTORY_REMOTE/main, and $FACTORY_VENDOR_DIR/VERSION ($version) is not greater than its ($main_version); run bash factory/core/amend.sh release, commit it as Release factory <new>, then land again; main not moved"
	fi
	if [ "$version" != "$main_version" ]; then
		tag="v$version"
		at="$(repo_tag_at "$tag")" || exit 1
		if [ "$at" = "$head" ]; then
			stage "$FACTORY_REMOTE has the tag $tag on HEAD already"
			tag=""
		elif [ -n "$at" ]; then
			die "$FACTORY_REMOTE has the tag $tag already, on another commit ($at); release a greater version (bash factory/core/amend.sh release <version>), commit, then land again; main not moved"
		fi
	fi

	amend_class "$remote_ref" "$head"
	release_check "$remote_ref" "$head" "$main_version" "$version"
	stage "check (bash factory/core/amend.sh check)"
	if ! repo_check > "$tmp/check"; then
		cat "$tmp/check"
		die "check failed; $again, commit, then land again; main not moved"
	fi
	suite_skips "$remote_ref" "$head"
	real_tool_skips "$remote_ref" "$head"
	full_suite local.env

	[ "$(git rev-parse HEAD)" = "$head" ] && [ -z "$(git status --porcelain --untracked-files=no)" ] ||
		die "a stage changed HEAD or a tracked file, so the checks did not see $head; main not moved"
	# main and its tag go in one atomic push: both land, or neither does.
	local -a refs=("$head:refs/heads/main")
	if [ -n "$tag" ]; then
		at="$(printf 'object %s\ntype commit\ntag %s\ntagger %s\n\nfactory %s\n' "$head" "$tag" "$(git var GIT_COMMITTER_IDENT)" "$version" | git mktag)" ||
			die "could not make the tag $tag; main not moved"
		refs+=("$at:refs/tags/$tag")
	fi
	stage "push to $FACTORY_REMOTE/main${tag:+, with the tag $tag}"
	if ! git push -q --atomic "$FACTORY_REMOTE" "${refs[@]}" 2> "$tmp/push"; then
		sed 's/^/  /' "$tmp/push" >&2
		die "the push to $FACTORY_REMOTE/main${tag:+ and its tag $tag} was refused (did main move?); fetch, rebase onto it and land again; nothing landed"
	fi
	stage "landed $head on $FACTORY_REMOTE/main${tag:+, tagged $tag}"
	fast_forward "$head"
}

repo_release() {
	local new
	bump
}

if [ -n "$in_repo" ]; then
	case "$cmd" in
		record) repo_record ;;
		check) repo_check ;;
		land) repo_land ;;
		release) repo_release ;;
	esac
	exit
fi

case "$cmd" in
	record) record ;;
	check) check ;;
	land) land ;;
	release) release ;;
esac
