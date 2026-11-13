#!/usr/bin/env bash
# Adopt the factory: seed a project from the vendored factory/ and an adapter,
# leaving it Adopted (the write deny refuses, pre-commit reports). Run from
# the project's checkout, with factory/ already in it:
#   bash factory/core/adopt.sh <adapter>        <adapter> names a factory/adapters/ folder
#   bash factory/core/adopt.sh <adapter> --new  start a new project from the
#                                               adapter's skeleton, and adopt it
# A clone of the factory's repo puts factory/ there and runs this in one step:
# core/install.sh. It sets FACTORY_INSTALL=1 (only it does), so the factory/ it
# just copied in is no dirt, and FACTORY_INSTALL_TAG and FACTORY_INSTALL_UPSTREAM,
# which become factory-version's tag and upstream lines.
#
# It refuses on a dirty tree and on a project that has adopted already (it has a
# tools/verify/factory-version). Then it:
#   - with --new, first lays down the adapter's skeleton, factory/adapters/<adapter>/new/:
#     each file is copied without its trailing .txt (stored so, the host project's
#     tools never read the templates) and with <project> filled in. A .gitignore
#     the project already has gets the skeleton's missing lines; any other skeleton
#     file already there is refused, before anything is written. The skeleton
#     verifies green, so the new project can be Armed at once;
#   - seeds tools/verify/ from factory/adapters/<adapter>/tools/verify/: step
#     scripts, pins, scope, test-paths, generated, local.env.example and the rest.
#     A file the project already has is kept, never overwritten;
#   - writes tools/verify/hook-mode (`report`), generates the hook config
#     (hooks.sh generate) and sets core.hooksPath to the Core's githooks;
#   - installs the copies lib/vendor.sh lists (factory_installed_copies), which
#     sync.sh later refreshes: tools/verify.sh becomes the runner's entry point
#     (replacing an older script there), tools/verify.ps1 is seeded, the factory's
#     skills (factory/skills/ and the adapter's skills/) go into .claude/skills/,
#     the factory's subagents (the Sonnet Editor, the asset fetcher)
#     into .claude/agents/ with their <stack> and <project> filled in, and the
#     verify-<project> skill is generated
#     (verify-skill.sh) when the adapter has a generator. Files already there are
#     kept, the entry point aside;
#   - creates docs/deviations.md and, when the project has none, ARCHITECTURE.md
#     (the adapter's default rules, else the Core's skeleton);
#   - writes the factory's section of AGENTS.md between its markers (agents.sh);
#   - gitignores tools/verify/local.env;
#   - runs the adapter's own adoption (factory/adapters/<adapter>/adopt.sh), if any,
#     passing it --new with --new;
#   - records the factory version, the adapter, install.sh's tag and upstream
#     and each vendored file's blob in tools/verify/factory-version
#     (lib/vendor.sh), which sync.sh checks;
#   - creates the factory labels (spec, approved, playtest) through
#     $FACTORY_LABEL_CMD, run as `$FACTORY_LABEL_CMD <name> <color> <description>`
#     (the tracker is not a seam); unset, it lists them for the human to create;
#   - runs the prepare step, records the Baseline from a full verify (baseline.sh
#     record), then stages everything: the seeded files, the Baseline and what
#     the verify made (files the stack's tools write on a first run, say),
#     which is why staging waits for it.
# It commits nothing.
#
# A step that fails before the Baseline undoes the run: the tree goes back to
# HEAD, files the run made are removed and core.hooksPath is restored, so a
# failed --new leaves no half-written skeleton. When prepare fails (say,
# local.env is missing) the seeded files stay: fix what it reports, then run
# adopt.sh <adapter> again, and it resumes at the Baseline.
#
# <project>, in the skeleton and in the Sonnet Editor's verify-<project> skill, is
# factory_project_name (lib/project.sh): $FACTORY_PROJECT when set, else the name
# of the origin remote's repo, else the checkout's folder.
#
# Progress goes to stderr; stdout is the Baseline's result line.
# Exit codes: 0 Adopted, 1 refused or a step failed, 2 usage.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/findings.sh"
. "$core/lib/hooks.sh"
. "$core/lib/vendor.sh"
. "$core/lib/project.sh"

FACTORY_BASELINE="$FACTORY_STEPS_DIR/ratchet/baseline.txt"

say() { echo "adopt: $*" >&2; }
# die <message>: stop, undoing the run first once it has begun to write.
die() {
	say "$*"
	[ "${writing:-0}" -eq 1 ] && undo
	exit 1
}

FACTORY_LABELS=(
	"spec 1d76db A Spec: the index issue of Features and Slices"
	"approved 0e8a16 The human approved this Spec"
	"playtest fbca04 A Feature's Playtest, for the human"
)

new=0
[ "$#" -eq 2 ] && [ "$2" = --new ] && new=1
{ [ "$#" -eq 1 ] || [ "$new" -eq 1 ]; } && [ "${1#-}" = "$1" ] || {
	echo "usage: bash factory/core/adopt.sh <adapter> [--new]" >&2
	exit 2
}
adapter="$1"
factory="$(cd "$core/.." && pwd)"
adapter_dir="$factory/adapters/$adapter"
[ -d "$adapter_dir/tools/verify" ] || {
	echo "adopt: no adapter '$adapter' (no $adapter_dir/tools/verify)" >&2
	exit 2
}
skeleton="$adapter_dir/new"
[ "$new" -eq 0 ] || [ -d "$skeleton" ] || {
	echo "adopt: the $adapter adapter has no --new skeleton (no $skeleton)" >&2
	exit 2
}

top="$(git rev-parse --show-toplevel 2> /dev/null)" || die "not inside a git checkout"
cd "$top" || die "cannot enter $top"
local_env="$FACTORY_STEPS_DIR/local.env"

# prepare_and_record: run prepare, then record the Baseline and stage everything.
prepare_and_record() {
	local prepare
	prepare="$(bash "$core/verify.sh" prepare 2> /dev/null)"
	if [ "$?" -ne 0 ]; then
		printf '%s\n' "$prepare" | sed 's/^/  /' >&2
		say "prepare fails, so no Baseline yet; fix it (tool locations go in $local_env), then run bash factory/core/adopt.sh $adapter again to record it"
		exit 1
	fi
	# The adoption isn't committed yet, so the deviation step diffs HEAD against itself.
	FACTORY_BASE=HEAD bash "$core/baseline.sh" record || die "could not record the Baseline"
	git add -A || die "could not stage the adoption"
	say "Adopted; commit the result"
}

# An adoption that stopped at prepare resumes at the Baseline.
if [ -f "$FACTORY_VERSION_FILE" ]; then
	if [ ! -f "$FACTORY_BASELINE" ] && [ "$(factory_vendor_field adapter)" = "$adapter" ]; then
		say "resuming: the project is seeded but has no Baseline yet"
		prepare_and_record
		exit 0
	fi
	die "already adopted ($FACTORY_VERSION_FILE: version $(factory_vendor_field version)); use sync.sh to update"
fi
# install.sh copied factory/ in uncommitted; everything else must be clean.
if [ "${FACTORY_INSTALL:-}" = 1 ]; then
	[ -z "$(git status --porcelain -- . ":(exclude)$FACTORY_VENDOR_DIR")" ] || die "the tree is dirty outside $FACTORY_VENDOR_DIR/; commit or stash first"
else
	[ -z "$(git status --porcelain)" ] || die "the tree is dirty; commit or stash first"
fi

# undo: put the tree back as the run found it: clean, at HEAD, with its
# core.hooksPath.
hooks_path="$(git config --get core.hooksPath)" || hooks_path=""
undo() {
	say "undoing the adoption: the tree goes back to HEAD"
	git reset -q --hard HEAD 2> /dev/null
	git clean -fdq
	if [ -n "$hooks_path" ]; then
		git config core.hooksPath "$hooks_path"
	else
		git config --unset core.hooksPath 2> /dev/null
	fi
}

# seed <source> <dest>: copy the file unless dest exists, which it keeps.
seed() {
	if [ -e "$2" ]; then
		say "kept $2"
		return 0
	fi
	mkdir -p "$(dirname "$2")" && cp -p "$1" "$2" || die "could not write $2"
}

# seed_tree <source dir> <dest dir>: seed every file under the source.
seed_tree() {
	local f
	while IFS= read -r f; do
		seed "$1/$f" "$2/$f"
	done < <(cd "$1" && find . -type f | sed 's#^\./##' | LC_ALL=C sort)
}

# skeleton_files: the skeleton's files, relative to it, as stored (with .txt).
skeleton_files() {
	(cd "$skeleton" && find . -type f | sed 's#^\./##' | LC_ALL=C sort)
}

# lay_skeleton: copy the skeleton in (see the header), or refuse.
lay_skeleton() {
	local f dest project line
	while IFS= read -r f; do
		dest="${f%.txt}"
		if [ -e "$dest" ] && [ "${dest##*/}" != .gitignore ]; then
			die "--new is for a new project, and $dest exists"
		fi
	done < <(skeleton_files)
	writing=1
	project="$(factory_project_name "$top")"
	while IFS= read -r f; do
		dest="${f%.txt}"
		mkdir -p "$(dirname "$dest")" || die "could not write $dest"
		if [ ! -e "$dest" ]; then
			sed "s/<project>/$project/g" "$skeleton/$f" > "$dest" || die "could not write $dest"
			continue
		fi
		while IFS= read -r line; do
			[ -z "$line" ] && continue
			grep -qxF -- "$line" "$dest" && continue
			if [ -s "$dest" ] && [ -n "$(tail -c 1 "$dest")" ]; then echo >> "$dest"; fi
			printf '%s\n' "$line" >> "$dest"
			say "added '$line' to $dest"
		done < "$skeleton/$f"
	done < <(skeleton_files)
}

# 0. The skeleton, with --new.
[ "$new" -eq 1 ] && lay_skeleton
writing=1

# 1. tools/verify/.
seed_tree "$adapter_dir/tools/verify" "$FACTORY_STEPS_DIR"

# 2. Hooks, with pre-commit in report mode.
factory_hook_mode_write report || die "could not write $FACTORY_HOOK_MODE_FILE"
bash "$core/hooks.sh" generate || die "could not generate the hook config"
git config core.hooksPath "$FACTORY_GITHOOKS_DIR" || die "could not set core.hooksPath"

# 3. The copies installed from the factory, which sync.sh refreshes.
project="$(factory_project_name "$top")"
while read -r how source copy; do
	case "$how" in
		replace)
			if [ -f "$copy" ] && ! cmp -s "$factory/$source" "$copy"; then
				say "replaced $copy with the factory's $source"
			fi
			mkdir -p "$(dirname "$copy")" && cp "$factory/$source" "$copy" || die "could not write $copy"
			;;
		seed) seed "$factory/$source" "$copy" ;;
		tree) [ ! -d "$factory/$source" ] || seed_tree "$factory/$source" "$copy" ;;
		agent)
			if [ -e "$copy" ]; then
				say "kept $copy"
			else
				mkdir -p "$(dirname "$copy")" &&
					factory_agent_render "$factory/$source" "$adapter" "$project" > "$copy" || die "could not write $copy"
			fi
			;;
		skill)
			if [ -e "$copy" ]; then
				say "kept $copy"
			elif [ -f "$factory/$source" ]; then
				bash "$core/verify-skill.sh" --adapter "$adapter" --out "$copy" < /dev/null > /dev/null || die "could not generate $copy"
			fi
			;;
	esac
done < <(factory_installed_copies "$adapter" "$project")

# 4. Docs.
seed "$core/templates/deviations.md" docs/deviations.md
if [ -f "$adapter_dir/ARCHITECTURE.md" ]; then
	seed "$adapter_dir/ARCHITECTURE.md" ARCHITECTURE.md
else
	seed "$core/templates/ARCHITECTURE.md" ARCHITECTURE.md
fi
bash "$core/agents.sh" generate || die "could not write the factory section of AGENTS.md"

# 5. local.env stays on this machine.
if ! git check-ignore -q "$local_env"; then
	if [ -s .gitignore ] && [ -n "$(tail -c 1 .gitignore)" ]; then echo >> .gitignore; fi
	printf '\n# The factory: this machine'"'"'s tool locations\n/%s\n' "$local_env" >> .gitignore
fi

# 6. The adapter's own adoption.
if [ -f "$adapter_dir/adopt.sh" ]; then
	new_flag=()
	[ "$new" -eq 1 ] && new_flag=(--new)
	FACTORY_CORE="$core" bash "$adapter_dir/adopt.sh" "${new_flag[@]}" || die "the $adapter adapter's adopt.sh failed"
fi

# 7. The version, and the labels.
factory_vendor_record "$(tr -d '\r\n' < "$factory/VERSION")" "$adapter" "${FACTORY_INSTALL_TAG:-}" "${FACTORY_INSTALL_UPSTREAM:-}" || die "could not write $FACTORY_VERSION_FILE"
for label in "${FACTORY_LABELS[@]}"; do
	read -r name color description <<< "$label"
	if [ -n "${FACTORY_LABEL_CMD:-}" ]; then
		# shellcheck disable=SC2086
		$FACTORY_LABEL_CMD "$name" "$color" "$description" >&2 || say "could not create the label $name; create it by hand"
	else
		say "create the label '$name' (#$color, \"$description\") in the issue tracker"
	fi
done

# 8. The Baseline, from a full verify, once prepare passes. From here a failure
# keeps what is seeded, and a rerun resumes here.
writing=0
prepare_and_record
