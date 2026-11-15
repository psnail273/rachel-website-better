# The vendored factory/, its record and the copies installed from it. Sourced by
# adopt.sh, sync.sh and amend.sh (needs steps.sh); defines no side effects. Run
# from the project root, inside git.
#
# tools/verify/factory-version records what the project vendors:
#   version <factory/VERSION>
#   adapter <the adapter it adopted>
#   tag <the factory release it holds>    (after an install, a sync or a release)
#   upstream <git url>                     the factory's own repo, when known
#   file <blob> <path>                     one per file under factory/
# A file line holds the git blob id of the file as vendored, hashed the way git
# would store it (so a CRLF checkout hashes the same), and its path from the
# project root. sync.sh compares them with factory/ to find local edits, and
# amend.sh to find a record an amend left stale.

FACTORY_VERSION_FILE="$FACTORY_STEPS_DIR/factory-version"
FACTORY_VENDOR_DIR="factory"

# factory_vendor_files: the files under factory/, tracked or untracked but not
# ignored, that exist on disk; sorted, one path per line.
factory_vendor_files() {
	git -c core.quotePath=false ls-files -co --exclude-standard -- "$FACTORY_VENDOR_DIR" |
		while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done |
		LC_ALL=C sort -u
}

# factory_vendor_manifest: a `file <blob> <path>` line per factory_vendor_files.
factory_vendor_manifest() {
	local files
	files="$(factory_vendor_files)"
	[ -n "$files" ] || return 0
	paste -d ' ' <(printf '%s\n' "$files" | git hash-object --stdin-paths) <(printf '%s\n' "$files") |
		sed 's/^/file /'
}

# factory_vendor_record <version> <adapter> [tag] [upstream]: write
# factory-version for the factory/ now on disk; an empty tag or upstream writes
# no line.
factory_vendor_record() {
	{
		printf 'version %s\nadapter %s\n' "$1" "$2"
		[ -z "${3:-}" ] || printf 'tag %s\n' "$3"
		[ -z "${4:-}" ] || printf 'upstream %s\n' "$4"
		factory_vendor_manifest
	} > "$FACTORY_VERSION_FILE"
}

# factory_vendor_field <key>: print the value of factory-version's <key> line;
# false when there is none.
factory_vendor_field() {
	[ -f "$FACTORY_VERSION_FILE" ] || return 1
	tr -d '\r' < "$FACTORY_VERSION_FILE" | awk -v k="$1" '$1 == k { sub(/^[^ ]+ /, ""); print; found = 1; exit } END { exit !found }'
}

# factory_version_is <v>: true for <major>.<minor>.<patch>, each a number without
# a leading zero.
factory_version_is() {
	[[ $1 =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

# factory_version_greater <a> <b>: true when version <a> is greater than <b>,
# comparing each part as a number (0.10.0 is greater than 0.9.0).
factory_version_greater() {
	local -a a b
	local i
	IFS=. read -r -a a <<< "$1"
	IFS=. read -r -a b <<< "$2"
	for i in 0 1 2; do
		[ "${a[i]}" -gt "${b[i]}" ] && return 0
		[ "${a[i]}" -lt "${b[i]}" ] && return 1
	done
	return 1
}

# factory_vendor_edits: print each local edit to factory/ since it was recorded,
# as `<path> changed|added|missing`, sorted by path. False when factory-version
# holds no file lines, so edits can't be told.
factory_vendor_edits() {
	local recorded
	recorded="$(tr -d '\r' < "$FACTORY_VERSION_FILE" | grep '^file ')" || return 1
	{
		printf '%s\n' "$recorded"
		printf '\001\n'
		factory_vendor_manifest
	} | awk '
		$0 == "\001" { now = 1; next }
		{ path = $0; sub(/^file [^ ]+ /, "", path) }
		!now { was[path] = $2; next }
		{ seen[path] = 1; if (!(path in was)) print path " added"; else if (was[path] != $2) print path " changed" }
		END { for (p in was) if (!(p in seen)) print p " missing" }
	' | LC_ALL=C sort
}

# factory_installed_copies <adapter> <project>: what adopt.sh installs into the
# project from the factory, and sync.sh and amend.sh refresh, one
# `<how> <source> <copy>` line each. <source> is relative to factory/, <copy> to
# the project root.
#   replace  a file adopt.sh always writes (the runner's entry point)
#   seed     a file adopt.sh writes unless the project has one
#   tree     a folder whose files adopt.sh seeds one by one (the factory's
#            skills, and a third-party skill from third-party/, as it came)
#   agent    a Claude Code subagent (the Sonnet Editor, the asset
#            fetcher, the per-issue Driver, the Verifier, the amend builder,
#            the designer):
#            its template filled in (factory_agent_render)
#   skill    the verify-<project> skill folder, written by the adapter's generator
#            (<source>) through factory/core/verify-skill.sh
factory_installed_copies() {
	printf '%s\n' \
		"replace core/templates/verify.sh tools/verify.sh" \
		"seed core/templates/verify.ps1 tools/verify.ps1" \
		"tree skills .claude/skills" \
		"tree adapters/$1/skills .claude/skills" \
		"tree third-party/frontend-design .claude/skills/frontend-design" \
		"agent agents/editor-sonnet.md .claude/agents/editor-sonnet.md" \
		"agent agents/asset-fetcher.md .claude/agents/asset-fetcher.md" \
		"agent agents/driver.md .claude/agents/driver.md" \
		"agent agents/verifier.md .claude/agents/verifier.md" \
		"agent agents/amend-builder.md .claude/agents/amend-builder.md" \
		"agent agents/designer.md .claude/agents/designer.md" \
		"skill adapters/$1/verify-skill.sh .claude/skills/verify-$2"
}

# factory_agent_render <template> <stack> <project>: print the Sonnet Editor's
# template with its <stack> and <project> filled in and its note on them dropped.
factory_agent_render() {
	grep -v '^# The template' "$1" | sed -e "s/<stack>/$2/g" -e "s/<project>/$3/g"
}

# factory_installed_files <factory dir> <list> <work dir> <adapter> <project>:
# `<copy>\t<file>` for each file the factory in <factory dir> installs by <list>
# (factory_installed_copies' lines, in their order): its source, or for an agent
# or a skill the copy rendered or generated under <work dir>. An entry whose
# source that factory lacks installs nothing, as does a generator that fails.
# False when <work dir> can't be made or an agent can't be rendered.
factory_installed_files() {
	local how source copy n=0
	mkdir -p "$3" || return 1
	while read -r how source copy; do
		n=$((n + 1))
		case "$how" in
			replace | seed) [ ! -f "$1/$source" ] || printf '%s\t%s\n' "$copy" "$1/$source" ;;
			tree) factory_tree_files "$1/$source" "$copy" ;;
			agent)
				factory_render_agent "$1" "$source" "$3/agent-$n" "$4" "$5" || return 1
				[ ! -f "$3/agent-$n" ] || printf '%s\t%s\n' "$copy" "$3/agent-$n"
				;;
			skill)
				factory_generate_skill "$1" "$3/skill-$n" "$4"
				factory_tree_files "$3/skill-$n" "$copy"
				;;
		esac
	done <<< "$2"
}

# factory_tree_files <folder> <copy folder>: `<copy>\t<file>` for each file
# under <folder>, sorted; for a file, `<copy>\t<file>` alone.
factory_tree_files() {
	if [ -f "$1" ]; then
		printf '%s\t%s\n' "$2" "$1"
		return 0
	fi
	[ -d "$1" ] || return 0
	local f
	while IFS= read -r f; do
		printf '%s\t%s\n' "$2/$f" "$1/$f"
	done < <(cd "$1" && find . -type f | sed 's#^\./##' | LC_ALL=C sort)
}

# factory_render_agent <factory dir> <template> <out> <adapter> <project>: the
# subagent as that factory would install it, with its own factory_agent_render;
# no <out> without the template. False when it can't be rendered.
factory_render_agent() {
	rm -f "$3"
	[ -f "$1/$2" ] || return 0
	bash -c '. "$1/core/lib/steps.sh" && . "$1/core/lib/vendor.sh" && factory_agent_render "$1/$2" "$3" "$4"' _ "$1" "$2" "$4" "$5" > "$3"
}

# factory_generate_skill <factory dir> <out dir> <adapter>: the verify-<project>
# skill that factory's generator writes for the project as it is now; no
# <out dir> when it has no generator or the generator fails, and false when it
# fails.
factory_generate_skill() {
	rm -rf "$2"
	[ -f "$1/core/verify-skill.sh" ] && [ -f "$1/adapters/$3/verify-skill.sh" ] || return 0
	bash "$1/core/verify-skill.sh" --adapter "$3" --out "$2" < /dev/null > /dev/null 2>&1 || {
		rm -rf "$2"
		return 1
	}
}

# The factory's own repo has two layouts. In its first releases the factory is
# its root (VERSION and core/ at the top: a subtree split), the root layout; their
# tags still hold it. Since then it is a workspace: the factory under factory/,
# exactly what a project vendors, and only the workspace's own files at the top,
# beside a FACTORY_REPO_MARKER file.
# shellcheck disable=SC2034 # read by the scripts that source this lib
FACTORY_REPO_MARKER=".factory-repo"

# factory_repo_tree <commit>: the tree of the factory in a commit of the
# factory's repo: its factory/ in the workspace layout (factory/VERSION there),
# else its root tree in the root layout (VERSION and core/ there). False when it
# holds neither.
factory_repo_tree() {
	if git cat-file -e "$1:factory/VERSION" 2> /dev/null; then
		git rev-parse --verify -q "$1:factory"
	elif git cat-file -e "$1:VERSION" 2> /dev/null && git cat-file -e "$1:core" 2> /dev/null; then
		git rev-parse --verify -q "$1^{tree}"
	else
		return 1
	fi
}

# factory_repo_copies: what the factory installs into its own repo's workspace,
# and amend.sh record refreshes there, one `<source> <copy>` line each: a folder
# or a file under factory/, and the folder at the repo's top that holds a copy of
# each of its files, or the file's copy. The agents are copied as they are: they
# hold no <stack> or <project> to fill in. The Verifier preloads frontend-design,
# so its skill comes too.
factory_repo_copies() {
	printf '%s\n' \
		"skills/factory-amend .claude/skills/factory-amend" \
		"third-party/frontend-design .claude/skills/frontend-design" \
		"agents/amend-builder.md .claude/agents/amend-builder.md" \
		"agents/verifier.md .claude/agents/verifier.md"
}
