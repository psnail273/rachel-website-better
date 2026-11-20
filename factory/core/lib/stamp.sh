# The gate stamp: each verify run keeps its verdict with a key that names
# everything the verdict depends on, so `verify.sh --reuse` on the same inputs
# prints that verdict again instead of running every step. The Editor's gate
# runs verify after each round; the Driver and the Verifier then reuse its
# verdict instead of running the same steps on the same tree twice more, but in
# the green phase, where the Editor's gate exports FACTORY_GATE_LOOP (a lighter
# smoke and mutate) and so keys its verdict apart: there the Driver's runs
# fresh and the Verifier reuses the Driver's. Land
# never reuses. Sourced by verify.sh; needs steps.sh, brief.sh, diff.sh,
# run.sh and scenarios.sh.
#
# A stamp is a file in the checkout's own <git-dir>/factory/, beside the Build
# Brief, where the Editor's deny hook keeps the Editor's tools out:
# verify-<mode>.<steps>.stamp, one per mode (red or green, plus -keep-going)
# and step list (`all`, or the steps joined by +). It holds:
#   factory-verify-stamp 1
#   key <key>
#   exit <0|1>
#   at <UTC time of the run>
#   <the run's stdout, the verdict, ending in `verify: PASS|FAILED at step <s>`>
#
# The key is the git hash of these lines, each one `<name> <value>`:
#   version  the Core's VERSION
#   mode     the stamp's mode
#   steps    the steps the run takes
#   head     HEAD's commit, or none
#   tree     HEAD's tree, the index's changes from it (each path's mode and
#            blob), the sparse checkout's rule (factory_stamp_sparse), then
#            each path git status lists (changed, staged, deleted or untracked;
#            ignored files left out) with its status, mode and content
#            (factory_stamp_tree)
#   config   the repo's core.* settings, such as core.hooksPath, which prepare
#            checks, in git's order (the last value of a key wins)
#   brief    the Build Brief's hash, or none
#   base     the diff base's commit (lib/diff.sh), or none; a base that names no
#            commit gets no key
#   state    each run-state key=value of the checked-out branch but
#            rounds-<phase>, the gate's counts (gate-runs,
#            caught-<step>, seconds-<step>) and the Editor's gate stamp
#            (editor-gate), which no step reads: a run that counts itself, or
#            that the Editor's gate stamps as it passes, keeps its stamp
#   env      each exported FACTORY_ variable but FACTORY_CORE (the runner sets
#            it), FACTORY_RESULTS_FILE, FACTORY_SURVIVORS_FILE,
#            FACTORY_NO_STAMP and FACTORY_GATE_WAITS (the Editor's stop hook's
#            wait record for its gate, a folder of its own each run: lib/run.sh)
#   local    tools/verify/local.env's hash, or none: the machine's tool paths
# What the key leaves out is taken as unchanged: the tools installed (prepare's
# pin check guards their versions), ignored files such as an engine's caches,
# the rest of the git config and the rest of the environment. A checkout with a
# changed submodule or nested repo (whatever submodule.*.ignore says), or a
# tracked file marked assume-unchanged or skip-worktree, which git status stops
# reading, gets no key, so its runs are always fresh; but for an issue's
# worktree, whose sparse checkout skips the Scenario folder (start.sh): it is
# keyed while its rule is start.sh's own and every skipped file lies in that
# folder, which the gate's steps never read (lib/scenarios.sh). The rule is in
# the key, so a full checkout of the same commit keys apart from it.
#
# A run whose steps include mutate also keeps, beside its stamp, the survivors
# file as the run left it (lib/mutate.sh): <stamp>.survivors holds
#   factory-survivors-stamp 1
#   key <the stamp's key>
#   present | absent
#   <the file's bytes, when present>
# --reuse puts the file back that way before it prints the verdict, writing only
# when the file differs (so a read-only git dir is fine while it matches); when
# that can't be done, the run goes ahead fresh. Where the git dir is read-only, a
# caller sets FACTORY_SURVIVORS_FILE to a file of its own, where a fresh run writes
# it and --reuse puts it back.
#
# A stamp that can't be written, as in a read-only git dir, is skipped with one line on
# stderr: the run's verdict and exit code stand. A run in which a step failed for
# a transient cause (it exited FACTORY_TRANSIENT_EXIT, lib/steps.sh) writes none,
# so --reuse never keeps such a FAIL: the next run goes ahead fresh.
#
# Beside the stamps, <git-dir>/factory/gate-counted lists the key of each run
# verify.sh counted in the run state (gate-runs, caught-<step>, seconds-<step>:
# factory_gate_count in lib/run.sh), one a line: a run on inputs listed there
# counts nothing more, whichever stamp the folder holds by then.
#
# A stamp is only as honest as what can write the git dir: the Editor's deny
# hook reads its shell commands, not every program it runs. So nothing that
# can't be undone rests on a reused verdict: lock.sh record runs its gate fresh
# before the Lock, and Land always runs fresh.

# The Core's VERSION file (factory/VERSION).
FACTORY_STAMP_VERSION="$(dirname "${BASH_SOURCE[0]}")/../../VERSION"

# factory_stamp_tree: print the working tree's part of the key: HEAD's tree id,
# the hash of the index's changes from HEAD (modes and blob ids), the sparse
# line (factory_stamp_sparse), then a
# `<path> <status> <mode> <hash>` line for each path git status lists (changed,
# staged, deleted or untracked; ignored files left out), its content hashed as
# written. It writes nothing to the repo, so it works where .git is read-only.
# False when git can't say, a listed path is a folder
# (a submodule or a nested repo), whose contents it doesn't read, or
# factory_stamp_sparse finds a tracked file git status doesn't read.
factory_stamp_tree() {
	local top list entry path mode hash index sparse status=0
	top="$(git rev-parse --show-toplevel 2> /dev/null)" || return 1
	list="$(mktemp)" || return 1
	git -C "$top" --no-optional-locks status --porcelain=v1 -z --untracked-files=all --no-renames --ignore-submodules=none > "$list" 2> /dev/null || status=1
	if [ "$status" -eq 0 ]; then
		index="$(git -C "$top" --no-optional-locks diff --cached --raw -z --no-renames --no-abbrev --ignore-submodules=none 2> /dev/null | git hash-object --stdin)" || status=1
	fi
	if [ "$status" -eq 0 ]; then
		sparse="$(factory_stamp_sparse "$top")" || status=1
	fi
	if [ "$status" -eq 0 ]; then
		printf 'tree %s\n' "$(git rev-parse -q --verify 'HEAD^{tree}' 2> /dev/null || echo none)"
		printf 'index %s\n' "$index"
		printf 'sparse %s\n' "$sparse"
		while IFS= read -r -d '' entry; do
			path="${entry:3}"
			if [ -L "$top/$path" ]; then
				mode="link"
				hash="$(readlink -- "$top/$path")"
			elif [ -d "$top/$path" ]; then
				status=1
				break
			elif [ -f "$top/$path" ]; then
				mode="file"
				[ -x "$top/$path" ] && mode="exec"
				hash="$(git -C "$top" hash-object --no-filters -- "$path")" || {
					status=1
					break
				}
			else
				mode=gone
				hash=none
			fi
			printf '%q %q %s %s\n' "$path" "${entry:0:2}" "$mode" "$hash"
		done < "$list"
	fi
	rm -f "$list"
	return "$status"
}

# factory_stamp_sparse <top>: print the sparse checkout's part of the key: none
# when the checkout isn't sparse (core.sparseCheckout), else the hash of its rule
# (<git-dir>/info/sparse-checkout). False when git can't list the tracked files,
# or one is marked so that git status doesn't read it (git ls-files -v tags it
# with a lowercase letter or S): any file marked assume-unchanged, and any file
# skipped (skip-worktree) unless the rule is start.sh's own, `/*` then
# `!/<folder>/` for the Scenario folder tools/verify/scenario-folder names
# (lib/scenarios.sh), and the file lies in that folder (a path git quotes, one
# with a control character, a quote or a backslash, never does).
factory_stamp_sparse() {
	local top="$1" files marked on rule="" file folder line
	files="$(git -C "$top" --no-optional-locks -c core.quotePath=false ls-files -v 2> /dev/null)" || return 1
	marked="$(printf '%s\n' "$files" | grep -e '^[a-z] ' -e '^S ')"
	on="$(git -C "$top" config --bool core.sparseCheckout 2> /dev/null)" || on=false
	if [ "$on" = true ]; then
		file="$(git -C "$top" rev-parse --path-format=absolute --git-path info/sparse-checkout 2> /dev/null)" || return 1
		if [ -e "$file" ]; then
			rule="$(cat -- "$file")" || return 1
		fi
	fi
	if [ -n "$marked" ]; then
		[ "$on" = true ] && folder="$(factory_scenario_folder "$top")" &&
			[ "$rule" = "$(printf '/*\n!/%s/' "$folder")" ] || return 1
		while IFS= read -r line; do
			case "$line" in
				"S $folder/"?*) ;;
				*) return 1 ;;
			esac
		done <<< "$marked"
	fi
	if [ "$on" = true ]; then
		printf '%s\n' "$rule" | git hash-object --stdin
	else
		echo none
	fi
}

# factory_stamp_env: the exported FACTORY_ variables the key holds, one
# `name=value` per line (the value shell-quoted, so it keeps to one line),
# sorted by name.
factory_stamp_env() {
	local name
	while IFS= read -r name; do
		case "$name" in
			FACTORY_CORE | FACTORY_RESULTS_FILE | FACTORY_SURVIVORS_FILE | FACTORY_NO_STAMP | FACTORY_GATE_WAITS) continue ;;
		esac
		printf '%s=%q\n' "$name" "${!name}"
	done < <(compgen -e | grep '^FACTORY_' | LC_ALL=C sort)
}

# factory_stamp_key <mode> <step...>: print the key for a run of these steps in
# this mode here and now; false outside a git repo or when the tree can't be read.
factory_stamp_key() {
	local mode="$1" head tree brief hash base branch local_env
	shift
	git rev-parse --git-dir > /dev/null 2>&1 || return 1
	tree="$(factory_stamp_tree)" || return 1
	head="$(git rev-parse -q --verify HEAD 2> /dev/null)" || head=none
	hash=none
	if brief="$(factory_brief_path)" && [ -f "$brief" ]; then
		hash="$(factory_brief_hash "$brief")" || return 1
	fi
	if base="$(factory_diff_base)"; then
		base="$(git rev-parse -q --verify "$base^{commit}" 2> /dev/null)" || return 1
	else
		base=none
	fi
	local_env=none
	if [ -f "$FACTORY_STEPS_DIR/local.env" ]; then
		local_env="$(git hash-object --no-filters -- "$FACTORY_STEPS_DIR/local.env")" || return 1
	fi
	{
		printf 'version %s\n' "$(cat "$FACTORY_STAMP_VERSION" 2> /dev/null)"
		printf 'mode %s\n' "$mode"
		printf 'steps %s\n' "$*"
		printf 'head %s\n' "$head"
		printf '%s\n' "$tree"
		git config --get-regexp '^core\.' 2> /dev/null | sed 's/^/config /'
		printf 'brief %s\n' "$hash"
		printf 'base %s\n' "$base"
		if branch="$(factory_current_branch)"; then
			factory_state_list "$branch" | grep -v -e '^rounds-' \
				-e '^gate-runs=' -e '^caught-' -e '^seconds-' -e '^editor-gate=' | sed 's/^/state /'
		fi
		factory_stamp_env | sed 's/^/env /'
		printf 'local %s\n' "$local_env"
	} | git hash-object --stdin
}

# factory_stamp_file <mode> <step...>: print the stamp's path; false outside git.
factory_stamp_file() {
	local mode="$1" dir name
	shift
	dir="$(git rev-parse --path-format=relative --git-dir 2> /dev/null)" || return 1
	if [ "$*" = "${FACTORY_STEPS[*]}" ]; then
		name=all
	else
		name="$(printf '%s+' "$@")"
		name="${name%+}"
	fi
	printf '%s/factory/verify-%s.%s.stamp\n' "$dir" "$mode" "$name"
}

# factory_stamp_counted_file: print the counted keys' path; false outside git.
factory_stamp_counted_file() {
	local dir
	dir="$(git rev-parse --path-format=relative --git-dir 2> /dev/null)" || return 1
	printf '%s/factory/gate-counted\n' "$dir"
}

# factory_stamp_counted <key>: true when a counted run had this key.
factory_stamp_counted() {
	local file
	file="$(factory_stamp_counted_file)" && grep -qxF -- "$1" "$file" 2> /dev/null
}

# factory_stamp_mark_counted <key>: list the key as counted; false when it can't.
factory_stamp_mark_counted() {
	local file
	file="$(factory_stamp_counted_file)" || return 1
	mkdir -p "$(dirname "$file")" 2> /dev/null && printf '%s\n' "$1" 2> /dev/null >> "$file"
}

# factory_stamp_write <stamp> <key> <exit> <verdict-file>: keep the verdict.
# Best effort: a stamp that can't be written is skipped, with a note on stderr.
factory_stamp_write() {
	local stamp="$1" part
	part="$stamp.$$"
	if mkdir -p "$(dirname "$stamp")" 2> /dev/null &&
		{
			printf 'factory-verify-stamp 1\nkey %s\nexit %s\nat %s\n' "$2" "$3" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
			cat "$4"
		} 2> /dev/null > "$part" && mv -f "$part" "$stamp" 2> /dev/null; then
		return 0
	fi
	rm -f "$part" 2> /dev/null
	echo "verify: could not write the gate stamp $stamp; --reuse will run fresh" >&2
	return 0
}

# factory_stamp_read <stamp> <key> <verdict-out>: when <stamp> is whole and was
# kept under <key>, write its verdict to <verdict-out>, set STAMP_EXIT and
# STAMP_AT, and succeed. A verdict whose last line disagrees with its exit code
# is not whole. It copies the stamp through one open first, so a run that
# replaces it meanwhile can't mix one stamp's key with another's verdict.
factory_stamp_read() {
	local stamp="$1" key="$2" out="$3" magic line_key line_exit line_at last
	[ -f "$stamp" ] || return 1
	cat -- "$stamp" > "$out.whole" 2> /dev/null || return 1
	{
		IFS= read -r magic && IFS= read -r line_key && IFS= read -r line_exit && IFS= read -r line_at
	} < "$out.whole" || return 1
	[ "$magic" = "factory-verify-stamp 1" ] && [ "$line_key" = "key $key" ] || return 1
	case "$line_exit" in "exit 0" | "exit 1") ;; *) return 1 ;; esac
	case "$line_at" in "at "?*) ;; *) return 1 ;; esac
	tail -n +5 "$out.whole" > "$out" || return 1
	last="$(tail -n 1 "$out")"
	case "$line_exit:$last" in
		"exit 0:verify: PASS" | "exit 1:verify: FAILED at step "?*) ;;
		*) return 1 ;;
	esac
	# shellcheck disable=SC2034 # read by verify.sh, which sources this lib
	STAMP_EXIT="${line_exit#exit }"
	# shellcheck disable=SC2034 # read by verify.sh, which sources this lib
	STAMP_AT="${line_at#at }"
}

# factory_stamp_write_survivors <stamp> <key> <survivors file>: keep the file's
# state beside the stamp, before the stamp itself is written. False when it
# can't be kept, and then no stamp should be.
factory_stamp_write_survivors() {
	local part="$1.survivors.$$"
	if mkdir -p "$(dirname "$1")" 2> /dev/null &&
		{
			printf 'factory-survivors-stamp 1\nkey %s\n' "$2"
			if [ -f "$3" ]; then
				echo present
				cat -- "$3"
			else
				echo absent
			fi
		} 2> /dev/null > "$part" && mv -f "$part" "$1.survivors" 2> /dev/null; then
		return 0
	fi
	rm -f "$part" 2> /dev/null
	echo "verify: could not write the gate stamp $1; --reuse will run fresh" >&2
	return 1
}

# factory_stamp_restore_survivors <stamp> <key> <survivors file>: put the file
# back as the stamp's run left it; false when the copy is missing, was kept
# under another key, or the file can't be put back.
factory_stamp_restore_survivors() {
	local kept="$1.survivors" whole magic line_key state
	whole="$(mktemp)" || return 1
	if ! cat -- "$kept" > "$whole" 2> /dev/null ||
		! { IFS= read -r magic && IFS= read -r line_key && IFS= read -r state; } < "$whole" ||
		[ "$magic" != "factory-survivors-stamp 1" ] || [ "$line_key" != "key $2" ]; then
		rm -f "$whole"
		return 1
	fi
	case "$state" in
		absent)
			rm -f "$whole"
			[ ! -e "$3" ] || rm -f -- "$3" 2> /dev/null
			return
			;;
		present)
			tail -n +4 "$whole" > "$whole.body" && rm -f "$whole" || {
				rm -f "$whole" "$whole.body"
				return 1
			}
			if ! cmp -s "$whole.body" "$3"; then
				mkdir -p "$(dirname "$3")" 2> /dev/null && cp -- "$whole.body" "$3.$$" 2> /dev/null &&
					mv -f -- "$3.$$" "$3" 2> /dev/null || {
					rm -f "$whole.body" "$3.$$" 2> /dev/null
					return 1
				}
			fi
			rm -f "$whole.body"
			;;
		*)
			rm -f "$whole"
			return 1
			;;
	esac
}
