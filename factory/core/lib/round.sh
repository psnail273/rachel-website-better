# The Editor's round, judged by what it changed: a snapshot of what the factory
# protects, taken when a round starts, and its compare when the round stops
# (#13, #17: ruled 2026-11-13). The command reader (lib/protect.sh) refuses the
# plain shapes of a protected write as they are asked; this sees the writes it
# can't read (`python3 -c`, `git apply`, a push from inside a script) by their
# effect. It can't see a read: the issue's worktree has no Scenario folder on
# disk (start.sh's sparse checkout).
#
# Sourced after steps.sh, findings.sh, brief.sh, diff.sh, run.sh, lock.sh,
# json.sh, scenarios.sh, protect.sh and bounded.sh; defines no side effects.
#
# Who calls it: the Editor's SubagentStart hook (hooks/claude-subagent-start.sh)
# takes the snapshot, and its SubagentStop hook (hooks/claude-subagent-stop.sh)
# compares, then takes a fresh one when the small lane moved the issue on to
# green (that hook's own Lock and phase), or when there was none.
#
# The snapshot, one line per item, tab-separated, sorted:
#   head    <root> <commit>        each checkout's HEAD (git worktree list)
#   branch  <root> <branch>        its branch (a rebase's, while one is stopped)
#   file    <root> <path> <state>  each protected file whose content on disk
#                                  is not HEAD's: its blob id, or `gone`; and
#                                  the Driver's files in its git dir (brief.md,
#                                  issue.md), always, by absolute path
#   rebase  <root> <path>          a protected file the stopped rebase's own
#                                  commits change (they were made before the round)
#   config  <key>=<value>          the repo's git config outside branch.*
#                                  (extensions.* and core.repositoryformatversion
#                                  left out: git sets them as worktrees are made)
#   state   <branch> <key>=<value> each branch's run state, its gate counts
#                                  (gate-runs, caught-*, seconds-*) left out, since
#                                  any verify run adds to them
#   ref     local|remote <ref> <commit or none>  dev (FACTORY_BASE_BRANCH) and main,
#                                  here and on FACTORY_REMOTE (git ls-remote);
#                                  `remote unreachable` when that fails or
#                                  takes longer than FACTORY_ROUND_REMOTE_TIMEOUT
# A protected file is one protect.sh's classes name (factory_gate_class: the
# factory, the Baseline, ratchet files, pins, the gate's scripts, local.env
# among them, the hook config), the Scenario folder, or a locked test. The
# main checkout's .claude/settings.local.json is left out: Claude Code writes it
# there when the human allows a command, whoever's round is running.
#
# The compare reads, for the Editor's worktree and the main checkout, every file
# line, and what the round's commits changed: the protected files that differ
# between the worktree's HEAD at the snapshot and now, less the rebase lines. It
# reads the config lines and the run state of the worktree's branch. A dev or
# main that moved here or on the remote is a change, unless it moved to a commit
# Land landed (a <git-common-dir>/factory/land-<n>.log whose gate exited 0), as a
# parallel issue's Land does. Other worktrees, which other issues own, are not
# compared.

# factory_round_dir: print <git-common-dir>/factory/round, absolute.
factory_round_dir() {
	local common
	common="$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null)" || return 1
	printf '%s/factory/round\n' "${common%/}"
}

# factory_round_file <agent_id>: print the snapshot's path for that subagent.
factory_round_file() {
	local dir
	dir="$(factory_round_dir)" || return 1
	printf '%s/%s\n' "$dir" "$(printf '%s' "${1:-unknown}" | tr -c 'A-Za-z0-9_.-' '_')"
}

# factory_round_is_protected <path> <lowercase locked list, newline-bounded>
# <main 1|0>: true when the root-relative path is one the round guards.
factory_round_is_protected() {
	local lower="${1,,}"
	[ "$3" = 1 ] && [ "$lower" = .claude/settings.local.json ] && return 1
	factory_gate_class "$lower" && return 0
	if [ -n "$PROTECT_SCENARIOS" ]; then
		case "$lower" in "$PROTECT_SCENARIOS" | "$PROTECT_SCENARIOS"/*) return 0 ;; esac
	fi
	[[ $2 == *$'\n'"$lower"$'\n'* ]]
}

# factory_round_filter <locked> <main 1|0>: keep the stdin paths that are protected.
factory_round_filter() {
	local path
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		factory_round_is_protected "$path" "$1" "$2" && printf '%s\n' "$path"
	done
}

# factory_round_root <root> <main 1|0>: print the head, branch, file and rebase
# lines of one checkout. Runs in a subshell of its own.
factory_round_root() (
	root="$1" main="$2"
	cd "$root" 2> /dev/null || exit 0
	tmp="$(mktemp -d)" || exit 1
	trap 'rm -rf "$tmp"' EXIT
	head="$(git rev-parse -q --verify HEAD 2> /dev/null)" || head=none
	printf 'head\t%s\t%s\n' "$root" "$head"
	gitdir="$(git rev-parse --path-format=absolute --git-dir 2> /dev/null)" || exit 0
	gitdir="${gitdir%/}"
	branch="$(git symbolic-ref -q HEAD 2> /dev/null)" ||
		branch="$(cat "$gitdir/rebase-merge/head-name" "$gitdir/rebase-apply/head-name" 2> /dev/null | head -n 1)" ||
		branch=""
	branch="${branch#refs/heads/}"
	[ -z "$branch" ] || [ "$branch" = detached ] || printf 'branch\t%s\t%s\n' "$root" "$branch"
	locked=$'\n'"$(factory_locked_files 2> /dev/null | tr -d '\r')"$'\n'
	locked="${locked,,}"
	# The candidates on disk: each class's top folder or file, in any case.
	(
		shopt -s nocaseglob nullglob
		set -- [f]actory [t]ools/[v]erify [t]ools/[v]erify.[s]h [t]ools/[v]erify.[p]s1 .[c]laude/[s]ettings.json .[c]laude/[s]ettings.local.json
		[ -z "$PROTECT_SCENARIO_DIR" ] || [ ! -e "$PROTECT_SCENARIO_DIR" ] || set -- "$@" "$PROTECT_SCENARIO_DIR"
		[ "$#" -eq 0 ] || find "$@" \( -type f -o -type l \) -print 2> /dev/null
		printf '%s' "$locked" | while IFS= read -r f; do [ -n "$f" ] && [ -e "$f" ] && printf '%s\n' "$f"; done
	) | sed 's|^\./||' | factory_round_filter "$locked" "$main" | LC_ALL=C sort -u > "$tmp/disk"
	# HEAD's protected blobs: `<path>\t<blob>`.
	if [ "$head" != none ]; then
		git -c core.quotePath=false ls-tree -r --full-tree HEAD 2> /dev/null | tr -d '\r' |
			awk -F '\t' '{ split($1, m, " "); print $2 "\t" m[3] }' > "$tmp/tree-all"
		cut -f 1 "$tmp/tree-all" | factory_round_filter "$locked" "$main" | LC_ALL=C sort -u > "$tmp/tree-paths"
		awk -F '\t' 'NR == FNR { want[$0] = 1; next } ($1 in want)' "$tmp/tree-paths" "$tmp/tree-all" > "$tmp/tree"
	else
		: > "$tmp/tree"
	fi
	# What is on disk: `<path>\t<blob>`, a symlink by its target's blob.
	: > "$tmp/files"
	: > "$tmp/hashed"
	while IFS= read -r f; do
		if [ -L "$f" ]; then
			printf '%s\t%s\n' "$f" "$(readlink "$f" | tr -d '\n' | git hash-object --stdin)" >> "$tmp/hashed"
		else
			printf '%s\n' "$f" >> "$tmp/files"
		fi
	done < "$tmp/disk"
	if [ -s "$tmp/files" ]; then
		if git hash-object --stdin-paths < "$tmp/files" > "$tmp/blobs" 2> /dev/null; then
			paste "$tmp/files" "$tmp/blobs" >> "$tmp/hashed"
		else
			while IFS= read -r f; do
				printf '%s\t%s\n' "$f" "$(git hash-object -- "$f" 2> /dev/null || echo unreadable)"
			done < "$tmp/files" >> "$tmp/hashed"
		fi
	fi
	awk -F '\t' -v root="$root" '
		NR == FNR { tree[$1] = $2; all[$1] = 1; next }
		{ disk[$1] = $2; all[$1] = 1 }
		END {
			for (p in all) {
				d = (p in disk) ? disk[p] : "gone"
				h = (p in tree) ? tree[p] : "gone"
				if (d != h) printf "file\t%s\t%s\t%s\n", root, p, d
			}
		}
	' "$tmp/tree" "$tmp/hashed"
	# The Driver's files in the git dir.
	for f in brief.md issue.md; do
		state=gone
		[ ! -f "$gitdir/factory/$f" ] || state="$(git hash-object --no-filters -- "$gitdir/factory/$f" 2> /dev/null)" || state=unreadable
		printf 'file\t%s\t%s\t%s\n' "$root" "$gitdir/factory/$f" "$state"
	done
	# A stopped rebase: what its own commits change.
	for d in rebase-merge rebase-apply; do
		[ -f "$gitdir/$d/orig-head" ] && [ -f "$gitdir/$d/onto" ] || continue
		git -c core.quotePath=false diff --name-only --no-renames "$(cat "$gitdir/$d/onto")...$(cat "$gitdir/$d/orig-head")" -- 2> /dev/null |
			tr -d '\r' | factory_round_filter "$locked" "$main" | sed "s|^|rebase\t$root\t|"
		break
	done
)

# factory_round_config: print the config and state lines of the repo's git config.
factory_round_config() {
	local common
	common="$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null)" || return 0
	git config --file "${common%/}/config" --null --list 2> /dev/null | tr '\n\0' '=\n' |
		awk '
			/^(extensions\.|core\.repositoryformatversion=)/ { next }
			/^branch\./ {
				eq = index($0, "="); name = substr($0, 1, eq - 1)
				k = name; sub(/.*\./, "", k)
				b = substr(name, 8, length(name) - 7 - length(k) - 1)
				if (k !~ /^factory-/) next
				if (k ~ /^factory-(gate-runs|caught-|seconds-)/) next
				printf "state\t%s\t%s%s\n", b, k, substr($0, eq)
				next
			}
			{ printf "config\t%s\n", $0 }
		'
}

# factory_round_refs: print the ref lines: dev and main, here and on the remote.
factory_round_refs() {
	factory_round_local_refs
	factory_round_remote_refs
}

# factory_round_local_refs: print the ref lines of the local dev and main.
factory_round_local_refs() {
	local name sha
	for name in "$FACTORY_BASE_BRANCH" main; do
		sha="$(git rev-parse -q --verify "refs/heads/$name" 2> /dev/null)" || sha=none
		printf 'ref\tlocal\trefs/heads/%s\t%s\n' "$name" "$sha"
	done | LC_ALL=C sort -u
}

# factory_round_remote_refs: print the ref lines of dev and main on the remote,
# or `remote unreachable`. The network is bounded as sync.sh bounds it: a limit
# of FACTORY_ROUND_REMOTE_TIMEOUT seconds (20) on ls-remote (factory_run_bounded,
# lib/bounded.sh: `timeout`, or a watchdog where there is none), ssh told to give
# up connecting after 5 seconds and never to prompt, and git never to prompt.
factory_round_remote_refs() {
	local name sha remote ssh limit="${FACTORY_ROUND_REMOTE_TIMEOUT:-20}"
	ssh="${GIT_SSH_COMMAND:-$(git config --get core.sshCommand 2> /dev/null)}"
	if [ -n "$ssh" ] || [ -z "${GIT_SSH:-}" ]; then
		ssh="${ssh:-ssh} -o ConnectTimeout=5 -o BatchMode=yes"
	else
		ssh=""
	fi
	if remote="$(
		export GIT_TERMINAL_PROMPT=0
		[ -z "$ssh" ] || export GIT_SSH_COMMAND="$ssh"
		factory_run_bounded "$limit" git ls-remote "$FACTORY_REMOTE" "refs/heads/$FACTORY_BASE_BRANCH" refs/heads/main < /dev/null 2> /dev/null
	)"; then
		for name in "$FACTORY_BASE_BRANCH" main; do
			sha="$(printf '%s\n' "$remote" | awk -v r="refs/heads/$name" '$2 == r { print $1; exit }')"
			printf 'ref\tremote\trefs/heads/%s\t%s\n' "$name" "${sha:-none}"
		done | LC_ALL=C sort -u
	else
		printf 'remote\tunreachable\n'
	fi
}

# factory_round_snapshot <file>: write the snapshot of every checkout of the
# repo the current folder is in, then the config, the run state and the refs.
factory_round_snapshot() {
	local main root tmp
	main="$(factory_main_checkout)" || return 1
	main="$(git -C "$main" rev-parse --show-toplevel 2> /dev/null)" || return 1
	factory_protect_scenarios_load
	mkdir -p "$(dirname "$1")" || return 1
	tmp="$1.tmp.$$"
	{
		git worktree list --porcelain 2> /dev/null | tr -d '\r' | sed -n 's/^worktree //p' |
			while IFS= read -r root; do
				root="$(git -C "$root" rev-parse --show-toplevel 2> /dev/null)" || continue
				factory_round_root "$root" "$([ "$root" = "$main" ] && echo 1 || echo 0)"
			done
		factory_round_config
		(cd "$main" && factory_round_local_refs)
	} | LC_ALL=C sort -u > "$tmp" && mv -f "$tmp" "$1" || {
		rm -f "$tmp"
		return 1
	}
	# The remote last, after the local snapshot is in place: a hook stopped while
	# it waits leaves a snapshot that compares all but the remote.
	(cd "$main" && factory_round_remote_refs) >> "$1"
}

# factory_round_landed <commit>: true when Land landed that commit from this repo:
# a land log in <git-common-dir>/factory/ names it and its gate exited 0.
factory_round_landed() {
	local common log
	common="$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null)" || return 1
	for log in "${common%/}"/factory/land-*.log; do
		[ -f "$log" ] || continue
		head -n 1 "$log" | grep -q " at $1\$" && grep -qxF 'land.sh: the gate exited 0; its verdict:' "$log" && return 0
	done
	return 1
}

# factory_round_compare <snapshot> <worktree>: compare the round's snapshot with
# now, from the worktree (the Editor's), as the header says. Print a
# `round-changed` finding for each difference on stdout, a note on stderr when
# the remote can't be reached (the remote's refs are then not compared), and
# return 1 when there is a difference.
factory_round_compare() {
	local snap="$1" wt main tmp branch h0 h1 status=0 kind where ref old new locked config
	wt="$(git -C "$2" rev-parse --show-toplevel 2> /dev/null)" || return 0
	main="$(cd "$wt" && factory_main_checkout)" || return 0
	main="$(git -C "$main" rev-parse --show-toplevel 2> /dev/null)" || return 0
	tmp="$(mktemp -d)" || return 0
	factory_protect_scenarios_load
	(cd "$wt" && factory_round_root "$wt" "$([ "$wt" = "$main" ] && echo 1 || echo 0)") > "$tmp/now"
	[ "$wt" = "$main" ] || (cd "$wt" && factory_round_root "$main" 1) >> "$tmp/now"
	(cd "$wt" && factory_round_config && factory_round_refs) >> "$tmp/now"
	LC_ALL=C sort -u -o "$tmp/now" "$tmp/now"
	if ! grep -q "^head	$wt	" "$snap"; then
		echo "round compare: the snapshot has no $wt (made after the round began), so its files were not compared" >&2
	fi
	branch="$(awk -F '\t' -v r="$wt" '$1 == "branch" && $2 == r { print $3; exit }' "$snap")"
	# The file, config and state lines, both ways.
	for f in "$snap" "$tmp/now"; do
		awk -F '\t' -v wt="$wt" -v main="$main" -v b="$branch" '
			($1 == "file" && ($2 == wt || $2 == main)) || $1 == "config" || ($1 == "state" && $2 == b)
		' "$f" | LC_ALL=C sort > "$f.cmp"
	done
	LC_ALL=C comm -3 "$snap.cmp" "$tmp/now.cmp" 2> /dev/null | sed 's/^\t//' |
		awk -F '\t' '
			$1 == "file" { p = ($3 ~ /^\//) ? $3 : $2 "/" $3; seen[p] = 1; next }
			$1 == "config" { k = $2; sub(/=.*/, "", k); seen["config\t" k] = 1; next }
			$1 == "state" { k = $3; sub(/=.*/, "", k); seen["state\tbranch." $2 "." k] = 1; next }
			END { for (p in seen) print p }
		' | LC_ALL=C sort > "$tmp/changed"
	rm -f "$snap.cmp" "$tmp/now.cmp"
	config="$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)/config"
	while IFS= read -r where; do
		case "$where" in
			config$'\t'*) factory_finding "$config" 1 round-changed "git config ${where#*$'\t'} changed this round: the git config is the Driver's; put it back as it was" ;;
			state$'\t'*) factory_finding "$config" 1 round-changed "the run state ${where#*$'\t'} changed this round: it is the Driver's; put it back as it was" ;;
			*) factory_finding "$where" 1 round-changed "changed this round, on disk and not committed: the factory protects it; put it back as it was" ;;
		esac
		status=1
	done < "$tmp/changed"
	# The round's commits.
	h0="$(awk -F '\t' -v r="$wt" '$1 == "head" && $2 == r { print $3; exit }' "$snap")"
	h1="$(git -C "$wt" rev-parse -q --verify HEAD 2> /dev/null)" || h1=none
	if [ -n "$h0" ] && [ "$h0" != none ] && [ "$h1" != none ] && [ "$h0" != "$h1" ]; then
		locked=$'\n'"$(cd "$wt" && factory_locked_files 2> /dev/null | tr -d '\r')"$'\n'
		awk -F '\t' -v r="$wt" '$1 == "rebase" && $2 == r { print $3 }' "$snap" | LC_ALL=C sort -u > "$tmp/rebase"
		git -C "$wt" -c core.quotePath=false diff --name-only --no-renames "$h0" "$h1" -- 2> /dev/null | tr -d '\r' |
			factory_round_filter "${locked,,}" 0 | LC_ALL=C sort -u |
			LC_ALL=C comm -23 - "$tmp/rebase" > "$tmp/committed"
		while IFS= read -r where; do
			factory_finding "$wt/$where" 1 round-changed "a commit this round changed it: the factory protects it; revert that change in a new commit"
			status=1
		done < "$tmp/committed"
	fi
	# dev and main, here and on the remote.
	if grep -qx 'remote	unreachable' "$snap" "$tmp/now"; then
		echo "round compare: $FACTORY_REMOTE could not be reached, so only the local $FACTORY_BASE_BRANCH and main were compared" >&2
	elif ! grep -q '^ref	remote	' "$snap"; then
		echo "round compare: the snapshot of the round's start has no refs from $FACTORY_REMOTE (its hook stopped before $FACTORY_REMOTE answered), so only the local $FACTORY_BASE_BRANCH and main were compared" >&2
	fi
	while IFS=$'\t' read -r kind where ref old; do
		[ "$kind" = ref ] || continue
		new="$(awk -F '\t' -v w="$where" -v r="$ref" '$1 == "ref" && $2 == w && $3 == r { print $4; exit }' "$tmp/now")"
		[ -n "$new" ] || continue
		[ "$old" != "$new" ] || continue
		[ "$new" = none ] || ! (cd "$wt" && factory_round_landed "$new") || continue
		if [ "$where" = remote ]; then where="on $FACTORY_REMOTE"; else where="here"; fi
		factory_finding "$ref" 1 round-changed "moved this round $where, from $old to $new: only Land moves it, after the gate and the Verifier; say so in your final message and stop"
		status=1
	done < "$snap"
	rm -rf "$tmp"
	return "$status"
}
