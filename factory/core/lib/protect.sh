# What the Editor may not write, and the one folder it may not read either: the
# protected path classes behind the Editor's deny, the Sonnet Editor's PreToolUse
# hook (hooks/claude-deny.sh). Sourced after steps.sh, findings.sh, brief.sh, diff.sh,
# run.sh, lock.sh, json.sh and scenarios.sh; defines no side effects. Run from
# inside the repo: the issue's worktree or the main checkout.
#
# The classes, first match wins:
#   brief         a worktree's <git-dir>/factory/ (the Build Brief; never lands)
#   run-state     the repo's git config, where the run state lives (lib/run.sh)
#   factory       factory/ (the vendored Core and adapters; a change is an amend)
#   baseline      tools/verify/ratchet/baseline.txt
#   ratchet       the rest of tools/verify/ratchet/ (allowlists and excludes)
#   pins          tools/verify/pins
#   gate-script   the rest of tools/verify/, and tools/verify.sh and .ps1
#   hook-config   .claude/settings*.json (generated from the Core)
#   scenarios     the Scenario folder the main checkout's
#                 tools/verify/scenario-folder names (lib/scenarios.sh): the
#                 Editor may not read it either (factory_protect_reads)
#   locked-test   a test file the Lock of the worktree's branch holds (lib/lock.sh)
# The project paths count in every worktree of the repo (the main checkout's
# .claude/worktrees/issue-<n>/ among them), each against its own root; a path
# outside them all is in no class but the first two. Matching ignores case, since
# Windows and macOS do. A shell command that runs one of the Core's writing
# subcommands (baseline.sh shrink, record and add, brief.sh seal, hooks.sh
# generate, lock.sh record and lift, state.sh set, unset and incr, and land.sh
# however it is run) counts as a write to what it rewrites: baseline, run-state
# or hook-config.

# Filled by factory_protect_init: the repo's git dir and its worktrees' roots,
# normalized and lowercased, the roots deepest first, with each root's path as
# git gives it in PROTECT_ROOT_DIRS; and each root's locked files, lowercased,
# once factory_protect_class has looked them up.
PROTECT_ROOTS=() PROTECT_ROOT_DIRS=() PROTECT_COMMON_DIR="" PROTECT_LOCKED=()

# Filled by factory_protect_scenarios_load, once per process: the Scenario folder
# the main checkout's tools/verify/scenario-folder names, relative to a root, as
# written in PROTECT_SCENARIO_DIR and lowercased in PROTECT_SCENARIOS; both empty
# when it names none (or lib/scenarios.sh isn't loaded), and then nothing is in
# the scenarios class. The main checkout's copy counts, as the Scenarios' writer
# reads it: the Editor can't change that one.
PROTECT_SCENARIOS="" PROTECT_SCENARIO_DIR="" PROTECT_SCENARIOS_LOADED=""

# Whether cygpath is on PATH, 1 or 0, looked up the first time
# factory_path_normalize needs it and kept for the rest of the process: the lookup
# walks PATH, which in WSL holds the Windows folders too, so each one costs tens
# of ms. A PATH changed later in the process keeps the first answer.
PROTECT_CYGPATH=""

# factory_path_normalize <path>: set NORMALIZED to the path made absolute,
# /-separated, lowercased and free of . and .. segments. A Windows drive C:\
# becomes /c/, and under Git Bash a mount such as /tmp becomes the drive path it
# names. Relative paths are taken from the current folder. Runs in this shell (no
# subshell) unless it has to ask cygpath, since a hook runs it for every path, and
# looks cygpath up once per process (PROTECT_CYGPATH).
factory_path_normalize() {
	local p="${1//\\//}" seg parts out=()
	[ "${p#/}" != "$p" ] || [[ $p =~ ^[A-Za-z]: ]] || p="$PWD/$p"
	if [[ $p =~ ^/[^/]+(/|$) ]] && ! [[ $p =~ ^/[A-Za-z](/|$) ]]; then
		if [ -z "$PROTECT_CYGPATH" ]; then
			PROTECT_CYGPATH=0
			command -v cygpath > /dev/null && PROTECT_CYGPATH=1
		fi
		[ "$PROTECT_CYGPATH" = 0 ] || p="$(cygpath -m -- "$p")"
	fi
	if [[ $p =~ ^([A-Za-z]):(/.*)?$ ]]; then
		p="/${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
	fi
	IFS=/ read -ra parts <<< "$p"
	for seg in "${parts[@]}"; do
		case "$seg" in
			'' | .) ;;
			..) [ "${#out[@]}" -eq 0 ] || unset 'out[${#out[@]}-1]' ;;
			*) out+=("$seg") ;;
		esac
	done
	p=""
	for seg in "${out[@]}"; do
		p+="/$seg"
	done
	p="${p:-/}"
	NORMALIZED="${p,,}"
}

# factory_protect_scenarios_load: find the Scenario folder (PROTECT_SCENARIOS), the
# first time it is called in the process; one git call.
factory_protect_scenarios_load() {
	local main
	[ -z "$PROTECT_SCENARIOS_LOADED" ] || return 0
	PROTECT_SCENARIOS_LOADED=1 PROTECT_SCENARIOS="" PROTECT_SCENARIO_DIR=""
	declare -F factory_scenario_folder > /dev/null || return 0
	if main="$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null)"; then
		main="${main%/}"
		[ "${main##*/}" = .git ] || return 0
		main="${main%/.git}"
	else
		main="$PWD"
	fi
	PROTECT_SCENARIO_DIR="$(factory_scenario_folder "$main")" || PROTECT_SCENARIO_DIR=""
	PROTECT_SCENARIOS="${PROTECT_SCENARIO_DIR,,}"
}

# factory_protect_init: read the git dir, the worktrees' roots and the Scenario
# folder.
factory_protect_init() {
	local common dir norm entries=()
	PROTECT_ROOTS=() PROTECT_ROOT_DIRS=() PROTECT_COMMON_DIR="" PROTECT_LOCKED=()
	factory_protect_scenarios_load
	if ! common="$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null)"; then
		factory_path_normalize "$PWD"
		PROTECT_ROOTS=("$NORMALIZED") PROTECT_ROOT_DIRS=("$PWD")
		return 0
	fi
	factory_path_normalize "$common"
	PROTECT_COMMON_DIR="$NORMALIZED"
	while IFS= read -r dir; do
		[ -n "$dir" ] || continue
		factory_path_normalize "$dir"
		entries+=("${#NORMALIZED}"$'\t'"$NORMALIZED"$'\t'"$dir")
	done < <(
		git worktree list --porcelain 2> /dev/null | tr -d '\r' | sed -n 's/^worktree //p'
		git rev-parse --show-toplevel 2> /dev/null
	)
	while IFS=$'\t' read -r _ norm dir; do
		PROTECT_ROOTS+=("$norm") PROTECT_ROOT_DIRS+=("$dir")
	done < <(printf '%s\n' "${entries[@]}" | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 -u)
}

# factory_protect_class <path>: set PROTECT_CLASS to the path's class; false when
# it is in none. Needs factory_protect_init.
factory_protect_class() {
	local i rel="" locked
	PROTECT_CLASS=""
	factory_path_normalize "$1"
	if [ -n "$PROTECT_COMMON_DIR" ]; then
		case "$NORMALIZED/" in "$PROTECT_COMMON_DIR"/factory/* | "$PROTECT_COMMON_DIR"/worktrees/*/factory/*)
			PROTECT_CLASS=brief
			return 0
			;;
		esac
		[ "$NORMALIZED" = "$PROTECT_COMMON_DIR/config" ] && {
			PROTECT_CLASS=run-state
			return 0
		}
	fi
	for i in "${!PROTECT_ROOTS[@]}"; do
		case "$NORMALIZED" in "${PROTECT_ROOTS[i]}"/*)
			rel="${NORMALIZED#"${PROTECT_ROOTS[i]}"/}"
			break
			;;
		esac
	done
	[ -n "$rel" ] || return 1
	factory_gate_class "$rel" && return 0
	if [ -n "$PROTECT_SCENARIOS" ]; then
		case "$rel" in "$PROTECT_SCENARIOS" | "$PROTECT_SCENARIOS"/*)
			PROTECT_CLASS=scenarios
			return 0
			;;
		esac
	fi
	if [ -z "${PROTECT_LOCKED[i]+set}" ]; then
		locked="$(cd "${PROTECT_ROOT_DIRS[i]}" 2> /dev/null && factory_locked_files)"
		PROTECT_LOCKED[i]=$'\n'"${locked,,}"$'\n'
	fi
	[[ ${PROTECT_LOCKED[i]} == *$'\n'"$rel"$'\n'* ]] || return 1
	PROTECT_CLASS="locked-test"
}

# factory_gate_class <path>: set PROTECT_CLASS to the class of a path relative to
# a checkout's root, lowercased, when the gate holds it (factory, baseline,
# ratchet, pins, gate-script, hook-config); false otherwise. Needs nothing.
factory_gate_class() {
	case "$1" in
		factory | factory/*) PROTECT_CLASS=factory ;;
		tools/verify/ratchet/baseline.txt) PROTECT_CLASS=baseline ;;
		tools/verify/ratchet | tools/verify/ratchet/*) PROTECT_CLASS=ratchet ;;
		tools/verify/pins) PROTECT_CLASS=pins ;;
		tools/verify | tools/verify/* | tools/verify.sh | tools/verify.ps1) PROTECT_CLASS=gate-script ;;
		.claude/settings.json | .claude/settings.local.json) PROTECT_CLASS=hook-config ;;
		*) return 1 ;;
	esac
}

# factory_gate_changes <base>: print each file the checked-out branch's commits
# changed since <base> that is the gate's own code or config: the factory, pins,
# gate-script and hook-config classes, one path per line, relative to the root
# (a rename counts as both its paths; a submodule counts whatever .gitmodules
# says). Ratchet files and the Baseline are left out while they stay regular
# files, as locked tests are: the deviation step checks those as text, and while
# this prints nothing it runs as <base> has it. A ratchet path that is or was a
# symlink or a submodule prints, since the deviation step can't read through it.
# Land refuses what this prints unless the issue is an amend, since the verify it
# runs is the branch's own copy of the gate. Needs nothing; false when git can't
# diff.
factory_gate_changes() {
	local list meta path modes status=0
	list="$(mktemp)" || return 1
	git -c diff.relative=false diff -z --raw --no-abbrev --no-renames --no-ext-diff --ignore-submodules=none "$1" HEAD -- > "$list" 2> /dev/null || status=1
	if [ "$status" -eq 0 ]; then
		while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
			factory_gate_class "${path,,}" || continue
			modes="${meta:1:13}"
			case "$PROTECT_CLASS:$modes" in
				factory:* | pins:* | gate-script:* | hook-config:* | *120000* | *160000*) printf '%s\n' "$path" ;;
			esac
		done < "$list"
	fi
	rm -f "$list"
	return "$status"
}

# factory_protect_reason <class>: why the Editor may not write it.
factory_protect_reason() {
	case "$1" in
		brief) echo "the Build Brief is the Driver's" ;;
		run-state) echo "the run state in git config is the Driver's" ;;
		factory) echo "factory/ is the vendored factory; a change to it is an amend, not this issue's work" ;;
		baseline) echo "the Baseline only shrinks, and the Driver shrinks it at Land" ;;
		ratchet) echo "ratchet files (allowlists and excludes) only shrink, and they are the Driver's" ;;
		pins) echo "the tool pins are the Driver's" ;;
		gate-script) echo "the gate's scripts are the Driver's" ;;
		hook-config) echo "the hook config is generated from factory/core/hooks" ;;
		scenarios) echo "the Scenarios check the Feature at its end, so the Editor neither reads nor writes them" ;;
		locked-test) echo "this test has been locked since the red phase; make the code pass it as it is" ;;
	esac
}

# factory_read_only_tool <tool>: true when the tool, named in lowercase, only reads.
factory_read_only_tool() {
	case "$1" in
		read | readfile | read_file | notebookread | grep | glob | ls | list_dir | listdir | search | codebase_search | semanticsearch | file_search | websearch | webfetch | fetch) return 0 ;;
	esac
	return 1
}

# factory_protect_call <json>: check an agent's tool call, a hook's JSON input
# with tool_name and tool_input, against the classes. Sets PROTECT_DENIED to each
# protected path it would write, as `<path> (<class>): <reason>` joined by "; ",
# and each read of the Scenario folder (factory_protect_reads), or to nothing.
# A read-only tool writes nothing. Any other tool is checked on
# every tool_input string whose key names a path or file, taken literally (a $ in
# it is part of the name), and a shell command (tool_input.command) on the paths
# it looks set to write (factory_shell_targets), and on each Core script it runs
# that rewrites a gate file (factory_protect_core). Relative paths are taken from the
# current folder. A shell target with a glob counts every file it matches. One
# that still holds a variable or a command the hook can't resolve is refused
# when its end, from any / on, names a protected path (`$d/factory/brief.md`), or
# when its literal start could reach one: each unknown part is read as `*`, and
# that pattern is checked as written (`tools/verify/*`) and against the files it
# matches. One with no literal start (`$out`, `$TMPDIR/x`) passes on its end alone.
# A word with more values than the parser follows, or a $( it can't close, is
# refused whatever it names: the hook fails closed where it can't read.
factory_protect_call() {
	local tool="" has_command=0 key value target init command="" read_only=0 inited=0 workdir=""
	local -a paths=() shell=() globs=()
	PROTECT_DENIED=""
	while IFS=$'\t' read -r key value; do
		case "$key" in
			tool_name) tool="${value,,}" ;;
			tool_input.command) has_command=1 ;;
			tool_input.*)
				key="${key,,}"
				while [[ $key =~ \.[0-9]+$ ]]; do key="${key%.*}"; done
				key="${key##*.}"
				case "$key" in *cwd* | *working*)
					[ -n "$workdir" ] || workdir="$value"
					continue
					;;
				esac
				case "$key" in pattern | glob_pattern) [ -n "$value" ] && globs+=("$value") ;; esac
				case "$key" in *path* | *file* | *target* | *dir* | *destination*) [ -n "$value" ] && paths+=("$value") ;; esac
				;;
		esac
	done < <(printf '%s' "$1" | factory_json_flatten)
	[ "$has_command" -eq 0 ] || command="$(printf '%s' "$1" | factory_json_get tool_input.command)"
	factory_read_only_tool "$tool" && read_only=1
	factory_protect_scenarios_load
	# A shell call runs where its working directory says: its relative words
	# count from there. The repo is read
	# first, from the hook's own folder.
	if [ "$has_command" -eq 1 ] && [ -n "$workdir" ]; then
		factory_protect_init
		inited=1
		# shellcheck disable=SC2164 # best effort: a folder that is gone leaves the hook where it is
		cd -- "${workdir//\\//}" 2> /dev/null
	fi
	if [ -n "$PROTECT_SCENARIOS" ]; then
		[ "$inited" -eq 1 ] || factory_protect_init
		inited=1
		factory_protect_reads "$tool" "$read_only" "$command" "${#globs[@]}" "${globs[@]}" "${paths[@]}"
	fi
	[ "$read_only" -eq 0 ] || return 0
	if [ "$has_command" -eq 1 ]; then
		while IFS= read -r target; do
			shell+=("$target")
		done < <(factory_shell_targets "$command")
	fi
	[ "${#paths[@]}" -gt 0 ] || [ "${#shell[@]}" -gt 0 ] || return 0
	# Only a path needs the classes: a call whose shell targets are all words the
	# parser made (::core and the like) skips reading the worktrees.
	init=${#paths[@]}
	for target in "${shell[@]}"; do
		case "$target" in ::run-state | "::exhausted "* | "::doubt "* | "::core "* | "::git "*) ;; *) init=1 ;; esac
	done
	[ "$init" -eq 0 ] || [ "$inited" -eq 1 ] || factory_protect_init
	for target in "${paths[@]}"; do
		[ -n "$target" ] || continue
		factory_protect_class "$target" || continue
		factory_protect_deny "$target ($PROTECT_CLASS): $(factory_protect_reason "$PROTECT_CLASS")"
	done
	for target in "${shell[@]}"; do
		[ -n "$target" ] || continue
		if [ "$target" = "::run-state" ]; then
			factory_protect_deny "git config (run-state): $(factory_protect_reason run-state)"
		elif [[ $target == "::exhausted "* ]]; then
			factory_protect_deny "${target#::exhausted } (unresolved): it can take more values than the hook checks; write to a literal path"
		elif [[ $target == "::doubt "* ]]; then
			factory_protect_deny "the command (unread): the hook can't follow ${target#::doubt }; write it more simply"
		elif [[ $target == "::core "* ]]; then
			factory_protect_core "${target#::core }"
		elif [[ $target == "::git "* ]]; then
			factory_protect_git "${target#::git }"
		elif factory_shell_unresolved "$target"; then
			factory_protect_unresolved "$target"
		elif factory_protect_class "$target"; then
			factory_protect_deny "$target ($PROTECT_CLASS): $(factory_protect_reason "$PROTECT_CLASS")"
		elif [[ $target == *[*?[]* ]] && factory_protect_glob "$target"; then
			factory_protect_deny "$target matches $PROTECT_MATCH ($PROTECT_CLASS): $(factory_protect_reason "$PROTECT_CLASS")"
		fi
	done
}

# factory_protect_reads <tool> <read-only 1|0> <command> <n> <n globs...> <paths...>:
# refuse what the call would read of the Scenario folder, the factory's one read
# deny. Needs factory_protect_init, with a Scenario folder. It adds to
# PROTECT_DENIED, as factory_protect_deny does:
#   - a read-only tool's path (Read's file_path, Grep's path, and any other
#     tool_input key naming a path or file) inside the folder of any worktree;
#   - a search, which reads every file below where it starts (grep, glob, search,
#     codebase_search, semanticsearch, file_search): where it starts, its path or
#     the current folder, when a worktree's Scenario folder is on disk at or below
#     it; a glob starts at its path joined to its pattern's literal folders
#     (`src/**/*.gd` starts at src), so a pattern into the folder counts too;
#   - a shell command's reads (factory_protect_shell_reads).
# An issue's worktree has no Scenario folder on disk (start.sh), so a search of it
# passes; one of the main checkout, which has the folder, is refused.
factory_protect_reads() {
	local tool="$1" read_only="$2" command="$3" n="$4" path glob base prefix
	shift 4
	local -a globs=("${@:1:n}") paths=("${@:n+1}")
	if [ "$read_only" -eq 1 ]; then
		for path in "${paths[@]}"; do
			factory_protect_read_path "$path" "$path"
		done
		case "$tool" in
			glob)
				base="${paths[0]:-$PWD}"
				[ "${#globs[@]}" -gt 0 ] || globs=("")
				for glob in "${globs[@]}"; do
					prefix="${glob//\\//}"
					prefix="${prefix%%[*?[{]*}"
					[[ $prefix == */* ]] && prefix="${prefix%/*}" || prefix=""
					case "$glob" in /* | [A-Za-z]:[/\\]*) path="${prefix:-/}" ;; *) path="$base${prefix:+/$prefix}" ;; esac
					factory_protect_read_path "$path" "${glob:-$base}" || factory_protect_search "$path" "${glob:-$base}"
				done
				;;
			grep | search | codebase_search | semanticsearch | file_search)
				[ "${#paths[@]}" -gt 0 ] || paths=("$PWD")
				for path in "${paths[@]}"; do
					factory_protect_search "$path" "$path"
				done
				;;
		esac
	fi
	[ -z "$command" ] || factory_protect_shell_reads "$command"
}

# factory_protect_in_scenarios <path>: true when the path is a worktree's Scenario
# folder or inside it.
factory_protect_in_scenarios() {
	local i rel
	factory_path_normalize "$1"
	for i in "${!PROTECT_ROOTS[@]}"; do
		case "$NORMALIZED" in "${PROTECT_ROOTS[i]}"/*)
			rel="${NORMALIZED#"${PROTECT_ROOTS[i]}"/}"
			case "$rel" in "$PROTECT_SCENARIOS" | "$PROTECT_SCENARIOS"/*) return 0 ;; esac
			return 1
			;;
		esac
	done
	return 1
}

# factory_protect_read_path <path> <as named>: refuse a read of the path when it is
# in the Scenario folder, naming it as the call did; false when it is not.
factory_protect_read_path() {
	[ -n "$1" ] && factory_protect_in_scenarios "$1" || return 1
	factory_protect_deny "$2 (scenarios): $(factory_protect_reason scenarios)"
}

# factory_protect_search <path> <as named>: refuse a search that starts at the path
# when a worktree's Scenario folder is on disk there or below it; false when none is.
factory_protect_search() {
	local i base folder
	factory_path_normalize "$1"
	base="$NORMALIZED"
	for i in "${!PROTECT_ROOTS[@]}"; do
		folder="${PROTECT_ROOTS[i]}/$PROTECT_SCENARIOS"
		[ "$base" = / ] || [ "$folder" = "$base" ] || [[ $folder == "$base"/* ]] || continue
		[ -e "${PROTECT_ROOT_DIRS[i]}/$PROTECT_SCENARIO_DIR" ] || continue
		factory_protect_deny "$2 (scenarios): it holds ${PROTECT_ROOT_DIRS[i]}/$PROTECT_SCENARIO_DIR, and $(factory_protect_reason scenarios); search a folder that doesn't hold it"
		return 0
	done
	return 1
}

# factory_protect_shell_reads <command>: refuse what a shell command would read of
# the Scenario folder. It reads words, not the shell's grammar, so it is a
# backstop, as factory_shell_targets is: it closes the plain ways, not every way.
# It refuses:
#   - any word, wherever it stands (an operand, a redirect's file, an option's
#     --x=<value>), that names the folder or a path in it on disk, from the
#     current folder or any folder the command cds to, or a file a glob word
#     matches there (`cat scenarios/a.gd`, `grep -n x < scenarios/a.gd`,
#     `cd scenarios`); in an issue's worktree, which has no folder on disk, such a
#     word reads nothing and passes;
#   - a git object path, <rev>:<path> or :<stage>:<path>, inside the folder, taken
#     from the root as git takes it (`git show HEAD:scenarios/a.gd`);
#   - in a git command, any word naming the folder or a path in it, from git's -C
#     folder, on disk or not, since a pathspec reads git's objects
#     (`git log -p -- scenarios`); and git sparse-checkout but its list, which
#     could check the folder out into an issue's worktree;
#   - a recursive search (grep or egrep with -r, -R, --recursive or
#     --directories=recurse; rgrep, rg, ag, ack; git grep) that starts where a
#     worktree's Scenario folder is on disk at or below it (factory_protect_search):
#     at each of its words that is on disk but its pattern, else the current
#     folder, as the command's cds before it left it (`cd <worktree> && grep -r
#     x .` searches the worktree). A shell call's working_directory is its
#     current folder.
# Misses, on purpose: a path held in a variable or built by a command, a find or
# xargs that reads what it lists, an archive or copy of a parent folder, and git's
# history read without naming the folder (`git log -p`, `git show <commit>`,
# `git grep <pattern> <rev>`): digging through git's objects on purpose. Refused
# though it reads nothing there: a pattern that is the folder's name, where the
# folder is on disk (`grep -rn scenarios src` from the main checkout; an issue's
# worktree has no folder on disk), and a plain `grep -r` or `rg` from a folder
# holding the folder on disk, the main checkout's root say, since it would read it.
factory_protect_shell_reads() {
	local cmd segment word name sub dir here="$PWD" i n recursive
	local -a words=() segments=() dirs=("$PWD")
	cmd="$(factory_shell_resolve "$1")"
	mapfile -t segments < <(factory_shell_segments "$cmd")
	# The folders the command cds to, in order, for the words below.
	for segment in "${segments[@]}"; do
		read -r -a words <<< "${segment//[\"\']/}"
		case "${words[0]:-}" in cd | pushd | set-location | sl | chdir)
			[ -n "${words[1]:-}" ] && [ "${words[1]}" != - ] || continue
			factory_protect_join "$here" "${words[1]}"
			here="$JOINED"
			dirs+=("$here")
			;;
		esac
	done
	read -r -d '' -a words < <(printf '%s' "$cmd" | tr '|&;<>(){}`\n\r\t' '              ')
	for word in "${words[@]}"; do
		for dir in "${dirs[@]}"; do
			factory_protect_read_word "$word" "$dir" 0
		done
	done
	here="$PWD"
	for segment in "${segments[@]}"; do
		read -r -a words <<< "$segment"
		n=${#words[@]}
		for i in "${!words[@]}"; do
			words[i]="${words[i]//[\"\']/}"
		done
		i=0
		while [ "$i" -lt "$n" ]; do
			case "${words[i]}" in
				[A-Za-z_]*=* | sudo | env | command | exec | nice | nohup | time | builtin) i=$((i + 1)) ;;
				*) break ;;
			esac
		done
		[ "$i" -lt "$n" ] || continue
		name="${words[i]##*/}"
		name="${name,,}"
		name="${name%.exe}"
		i=$((i + 1))
		recursive=0 dir="$here"
		case "$name" in
			cd | pushd | set-location | sl | chdir)
				if [ -n "${words[i]:-}" ] && [ "${words[i]}" != - ]; then
					factory_protect_join "$here" "${words[i]}"
					here="$JOINED"
				fi
				;;
			git)
				while [ "$i" -lt "$n" ]; do
					case "${words[i]}" in
						-C)
							factory_protect_join "$dir" "${words[i + 1]:-.}"
							dir="$JOINED"
							i=$((i + 2))
							;;
						-c | --git-dir | --work-tree | --namespace | --exec-path | --config-env) i=$((i + 2)) ;;
						-*) i=$((i + 1)) ;;
						*) break ;;
					esac
				done
				sub="${words[i]:-}"
				i=$((i + 1))
				if [ "$sub" = sparse-checkout ] && [ "$i" -lt "$n" ] && [ "${words[i]}" != list ]; then
					factory_protect_deny "git sparse-checkout ${words[i]} (scenarios): it could check the Scenario folder out, and $(factory_protect_reason scenarios)"
				fi
				for word in "${words[@]:i}"; do
					[[ $word == -* ]] || factory_protect_read_word "$word" "$dir" 1
				done
				[ "$sub" != grep ] || recursive=1
				;;
			grep | egrep | fgrep | zgrep)
				for word in "${words[@]:i}"; do
					case "$word" in --recursive | --dereference-recursive | --directories=recurse | recurse) recursive=1 ;; --*) ;; -*[rR]*) recursive=1 ;; esac
				done
				;;
			rgrep | rg | ag | ack | ack-grep) recursive=1 ;;
		esac
		[ "$recursive" -eq 1 ] || continue
		# Its pattern is its first operand, unless an option gave it (-e, -f,
		# --regexp, --file) or it takes none (rg --files): a pattern that names a
		# folder is no place to search.
		local -a bases=()
		local pattern=1
		for word in "${words[@]:i}"; do
			case "$word" in -e | -f | --regexp | --regexp=* | --file | --file=* | -e?* | -f?* | --files) pattern=0 ;; esac
		done
		for word in "${words[@]:i}"; do
			[[ $word == -* ]] && continue
			if [ "$pattern" -eq 1 ]; then
				pattern=0
				continue
			fi
			factory_protect_join "$dir" "$word"
			[ -e "$JOINED" ] && bases+=("$JOINED")
		done
		[ "${#bases[@]}" -gt 0 ] || bases=("$dir")
		for word in "${bases[@]}"; do
			factory_protect_search "$word" "$word"
		done
	done
}

# factory_protect_join <folder> <path>: set JOINED to the path taken from the
# folder (an absolute path, a Windows drive path or ~/ as itself).
factory_protect_join() {
	case "$2" in
		/* | [A-Za-z]:[/\\]*) JOINED="$2" ;;
		\~) JOINED="$HOME" ;;
		\~/*) JOINED="$HOME/${2#\~/}" ;;
		*) JOINED="$1/$2" ;;
	esac
}

# factory_protect_read_word <word> <folder> <git 1|0>: refuse a shell word that
# reads the Scenario folder (factory_protect_shell_reads), taken from the folder.
# With git 1 a word counts on disk or not.
factory_protect_read_word() {
	local word="$1" path m count=0
	word="${word//[\"\']/}"
	word="${word//$'\034'/ }"
	[ -n "$word" ] || return 0
	[[ $word == -*=* ]] && word="${word#*=}"
	[ -n "$word" ] || return 0
	if ! [[ $word =~ ^[A-Za-z]:[/\\] ]] && [[ $word =~ ^[^:]*:([0-3]:)?(.+)$ ]]; then
		path="${BASH_REMATCH[2]//\\//}"
		while [[ $path == /* ]]; do path="${path#/}"; done
		case "$path" in
			./* | ../*) factory_protect_join "$2" "$path" && factory_protect_read_path "$JOINED" "$1" ;;
			*)
				case "${path,,}" in "$PROTECT_SCENARIOS" | "$PROTECT_SCENARIOS"/*)
					factory_protect_deny "$1 (scenarios): $(factory_protect_reason scenarios)"
					;;
				esac
				;;
		esac
	fi
	factory_protect_join "$2" "$word"
	if [ "$3" = 1 ] || [ -e "$JOINED" ]; then
		factory_protect_read_path "$JOINED" "$1" && return 0
	fi
	[[ $word == *[*?[]* ]] || return 0
	while IFS= read -r m; do
		if factory_protect_in_scenarios "$m"; then
			factory_protect_deny "$1 matches $m (scenarios): $(factory_protect_reason scenarios)"
			return 0
		fi
		count=$((count + 1))
		[ "$count" -lt 2000 ] || break
	done < <(compgen -G "$JOINED" 2> /dev/null)
}

# factory_protect_deny <text>: add one refusal to PROTECT_DENIED, once.
factory_protect_deny() {
	case "; $PROTECT_DENIED; " in *"; $1; "*) return 0 ;; esac
	PROTECT_DENIED+="${PROTECT_DENIED:+; }$1"
}

# factory_protect_core <script> [subcommand]: refuse a run of a Core script's
# writing subcommand (factory_shell_targets prints them), which rewrites what the
# Driver owns: the Baseline (baseline.sh shrink, record and add), the hook config
# (hooks.sh generate), or the run state in git config (state.sh set, unset and
# incr; lock.sh record and lift, which move the Lock kept there; brief.sh seal,
# which seals the brief there; and land.sh, which moves dev and drops the
# branch with its run state).
factory_protect_core() {
	local class what
	case "$1" in
		baseline.sh\ *) class=baseline what="the Baseline" ;;
		hooks.sh\ *) class=hook-config what="the hook config" ;;
		lock.sh\ *) class=run-state what="the Lock in the run state" ;;
		brief.sh\ *) class=run-state what="the brief's seal in the run state" ;;
		land.sh) class=run-state what="dev, and drops the branch with its run state" ;;
		*) class=run-state what="the run state" ;;
	esac
	factory_protect_deny "factory/core/$1 ($class): it rewrites $what; $(factory_protect_reason "$class")"
}

# factory_protect_git <what>: refuse a git command that puts work past the gate
# (factory_shell_targets prints `::git <what>`): a push, an update-ref, a branch
# command that deletes, moves or overwrites dev or main, and a commit that skips
# the pre-commit hook (--no-verify, or a core.hooksPath set by -c or
# --config-env; one set through GIT_CONFIG_* variables is not read, and the
# gate still runs the checks). The command reader's last shapes (#13, ruled
# 2026-11-13):
# what a script does, it can't see, so the Editor's stop hook compares where dev
# and main point, and the protected files, before and after the round
# (lib/round.sh).
factory_protect_git() {
	case "$1" in
		"commit --no-verify" | "-c core.hooksPath") factory_protect_deny "git $1 (hooks): the pre-commit hook runs on every commit; fix what it reports" ;;
		*) factory_protect_deny "git $1 (branches): the Editor commits on its own branch; dev, main and the remote move only through the gate, the Verifier and Land, which are the Driver's" ;;
	esac
}

# factory_protect_glob <pattern>: true when a file the pattern matches is
# protected; PROTECT_MATCH and PROTECT_CLASS name the first one.
factory_protect_glob() {
	local m n=0
	PROTECT_MATCH=""
	while IFS= read -r m; do
		if factory_protect_class "$m"; then
			PROTECT_MATCH="$m"
			return 0
		fi
		n=$((n + 1))
		[ "$n" -lt 2000 ] || break
	done < <(compgen -G "$1" 2> /dev/null)
	return 1
}

# factory_protect_unresolved <target>: refuse a shell target the hook can't
# resolve when its end names a protected path, or its literal start could reach one.
factory_protect_unresolved() {
	local target="$1" tail="$1" pattern
	while [[ $tail == */* ]]; do
		tail="${tail#*/}"
		[ -n "$tail" ] || break
		factory_shell_unresolved "$tail" && continue
		if factory_protect_class "$tail"; then
			factory_protect_deny "$target (unresolved): the hook can't tell where this lands, and its end $tail is protected ($PROTECT_CLASS); write to a literal path"
			return 0
		fi
	done
	pattern="$(factory_shell_glob "$target")"
	[ -n "${pattern%%\**}" ] || return 0
	PROTECT_MATCH="$pattern"
	if factory_protect_class "$pattern" || factory_protect_glob "$pattern"; then
		factory_protect_deny "$target (unresolved): the hook can't tell where this lands, and it could be $PROTECT_MATCH ($PROTECT_CLASS); write to a literal path"
	fi
}

# factory_shell_unresolved <word>: true when the word still holds a variable, a
# command substitution or a backtick after factory_shell_targets resolved it.
factory_shell_unresolved() {
	local re='\$[A-Za-z0-9_{(@*#?!$-]'
	[[ $1 =~ $re ]] || [[ $1 == *'`'* ]]
}

# factory_shell_glob <word>: the word with each part factory_shell_unresolved
# finds (a variable, a ${...}, a $(...) or a backtick) made `*`.
factory_shell_glob() {
	printf '%s' "$1" | sed -E 's/\$\{[^}]*\}/*/g; s/\$\([^)]*\)/*/g; s/`[^`]*`/*/g; s/\$([A-Za-z_][A-Za-z0-9_]*|[0-9@*#?!$-])/*/g'
}

# factory_shell_resolve <command>: print the command with each
# `$(git rev-parse [--path-format=<f>] <option>)` (or its backtick form) replaced
# by what that same git command prints here, for the options --git-dir,
# --absolute-git-dir, --git-common-dir and --show-toplevel: the way an agent finds
# the brief's folder. A blank in the path becomes \034, so the path stays one
# word; factory_shell_targets turns it back. Anything else is left as written.
factory_shell_resolve() {
	local cmd="$1" resolved="" value
	local -a args
	local re='(\$\(|`)git rev-parse( --path-format=(absolute|relative))? (--git-dir|--absolute-git-dir|--git-common-dir|--show-toplevel)(\)|`)'
	while [[ $cmd =~ $re ]]; do
		args=()
		[ -z "${BASH_REMATCH[2]}" ] || args+=("${BASH_REMATCH[2]# }")
		args+=("${BASH_REMATCH[4]}")
		value="$(git rev-parse "${args[@]}" 2> /dev/null)" || value=""
		resolved+="${cmd%%"${BASH_REMATCH[0]}"*}"
		if [ -n "$value" ]; then
			resolved+="${value// /$'\034'}"
		else
			resolved+="${BASH_REMATCH[0]}"
		fi
		cmd="${cmd#*"${BASH_REMATCH[0]}"}"
	done
	printf '%s' "$resolved$cmd"
}

# factory_shell_segments <command>: print, one per line and with its blanks single,
# each simple command of a shell command, its redirects removed. It splits on |, &,
# ; and newlines wherever they stand, ignoring quotes on purpose: it can then only
# split too much, and refuse a `grep 'a|b'`, where a reader of quotes can be fooled
# (`echo \"; rm x; echo \"` runs rm) into splitting too little.
factory_shell_segments() {
	printf '%s' "$1" | awk '
		{ text = text (NR > 1 ? "\n" : "") $0 }
		END {
			word = "[^ \t\n;|&<>]+"
			gsub(/[0-9]*[<>]&[0-9-]+/, " ", text)
			gsub("&>>?[ \t]*" word, " ", text)
			gsub("[0-9]*(>>?[|]?|<<?<?)[ \t]*" word, " ", text)
			n = split(text, parts, /[|&;\n]/)
			for (i = 1; i <= n; i++) {
				gsub(/[ \t]+/, " ", parts[i])
				sub(/^ /, "", parts[i])
				sub(/ $/, "", parts[i])
				if (parts[i] != "") print parts[i]
			}
		}
	'
}

# factory_shell_targets <command>: print, one per line, the paths a shell command
# looks set to write: redirect targets, the operands of rm, mv, touch, tee, sed -i,
# the PowerShell *-Item and *-Content cmdlets and the like, the destination of cp
# and ln, git checkout/restore/rm/mv's paths, the start paths of a find that
# deletes, the file of its -fprint, and what each of its -exec commands writes,
# read with {} as each start path; `bash -c` strings (their $0, $1 ... the words
# after them), `eval`'s words joined, `powershell -Command` strings, $(...),
# ${...} and backticks are read too. A # that starts a word starts a comment;
# { and } part commands only as whole words. A here-document's body is
# data: skipped when its delimiter is quoted, read only for $(...) and backticks
# when it isn't, and read as commands when it feeds a shell (`bash <<EOF`). A
# `git config` naming a factory- key prints the word ::run-state; a git
# command that puts work past the gate prints `::git <what>`: any push, any
# update-ref, a branch -d/-D/-m/-M/-c/-C/-f naming dev or main as the branch it
# deletes, moves or overwrites, a commit with --no-verify or -n, and a
# core.hooksPath set by -c or --config-env.
#
# The Core's writing subcommands print `::core <script> <subcommand>`:
# baseline.sh shrink, record and add, brief.sh seal, hooks.sh generate, lock.sh
# record and lift, state.sh set, unset and incr (in #159 the Editor ran
# baseline.sh shrink, which rewrote the Baseline); and land.sh, which has no
# read-only form, prints `::core land.sh` however it is run. The script
# is known by its name, in any folder, since after a cd the hook cannot tell which
# folder a relative path starts from. It counts run as the command (by a relative
# or absolute path, ./, or after sudo, env, exec and the like), as the script a
# shell runs (`bash [options] <script>`, sh and the rest; a -c string is read as
# commands, so a run inside one counts too) and through source or `.`. Its
# subcommand is its first word after the options it reads first (--reuse for
# baseline.sh; --branch and --issue with their values for state.sh). Any other
# subcommand prints nothing; gate, check, files, get, list, stats and brief.sh's
# listings (scope, tests, seams, removes, grows) only read.
# Whose call it is the hook decides: it refuses the Editor and the asset-fetcher,
# never the Driver (hooks/claude-deny.sh).
#
# Variables: every word prints, or is judged, once for every value it can take,
# the command name, an option and a git subcommand as much as a target. A
# variable takes every value the command gives it anywhere (`X=...`, export,
# declare, local, readonly, typeset, a command's prefix, a `for X in` list, a
# subshell, a nested `bash -c`), whatever the order or scope, so a hidden
# protected value is never missed; at worst a path is checked that the command
# never writes. Inside its own value (`d=$d/x`) a variable takes its values a few
# levels deep, then only those that don't use it. ${X:-w}, ${X=w} and the like
# add w; ${X:+w} is w or nothing; any other ${X...} keeps X's values too. A
# here-string (<<<) is data. $HOME, $PWD and a leading ~ take theirs, and the
# git rev-parse paths factory_shell_resolve knows are filled in. A value made by a command is
# unknown: its $(...) or backtick prints as $(?). Any other variable prints as
# written, and factory_protect_call decides from what is left.
#
# It fails closed where it can't follow the command: a word with more than 256
# values (or an eval with more than 256 ways to read), variables chained more
# than 64 deep, commands nested more than NEST deep or more than 4096 of them to
# read, or an awk that stops early, prints `::exhausted <what>`;
# a $( or ${ that never closes prints `::doubt <what>`. It reads words, not the
# shell's grammar, so it is a backstop: the gates still check whatever lands.
#
# Accepted gaps (#161, ruled 2026-11-04): it reads these forms wrongly, on
# purpose, and none has come up in a Run. A write to a gate file it misses cannot
# land: Land refuses a branch that changes the gate's files unless its sealed
# brief is Kind: amend.
# Misses, a write it lets by:
#   - an abbreviated long option of cp or install that takes a value (--mo for
#     --mode, --suf for --suffix, --sp for --sparse, any prefix getopt takes):
#     not seen to take one, so its value reads as the destination
#     (`install src/a.txt tools/verify/pins --mo 644`).
#   - `install -d tools/verify/new-dir /tmp/new-dir`: every operand is a folder it
#     makes, but only the last is checked.
#   - a PowerShell parameter with a value after the operands: the value reads as
#     the destination (`Copy-Item src/a.txt tools/verify/pins -ErrorAction Stop`).
#   - operands split from one unquoted variable (`args='src/a.txt tools/verify/pins';
#     cp $args`): the whole value reads as one destination.
#   - a shell option a variable holds, after a literal -c or before a cluster that
#     ends in o (`bash -c "$opt" 'touch tools/verify/pins'`,
#     `bash "$opt" -co pipefail 'touch tools/verify/pins'`): the commands are read
#     from the wrong word.
#   - a shell's -c and its commands in one variable (`flags='-c >tools/verify/pins';
#     bash $flags`): the commands are not read.
#   - cmd's copy with a trailing switch (`copy src\a.txt tools\verify\pins /Y`, alone
#     or inside `cmd /c "..."`): the switch reads as the destination.
#   - a match below a start path (`find . -name X -exec touch {} \;`): {} reads as
#     the start path only (accepted in #158: Land checks what lands).
# False refusals, a read it refuses:
#   - the same abbreviated long options before a word that looks like an option
#     (`cp --suf -t factory/VERSION /tmp/x`): that word reads as an option, here a
#     -t whose folder is a destination, though it is the suffix.
#   - a -c-like word among a shell's arguments after its commands
#     (`bash -c 'grep "$@"' _ -c 'touch tools/verify/pins' factory/VERSION`): the word
#     after it reads as commands too (accepted in #158: narrower readings kept
#     missing a -c that a variable or an unknown option hid).
#   - cp, install or ln with a word that may expand to an option
#     (`opt=-v; cp "$opt" factory/VERSION /tmp/x`): every operand counts as a
#     destination (accepted in #158: an exact reading through the values of a
#     variable kept missing forms).
#   - a GNU cp with a -t and a word that also spells a Copy-Item parameter
#     (`cp -lp -t /tmp/x tools/verify/pins`): it reads as PowerShell too, so its
#     last operand counts as a destination (accepted in #158: in PowerShell cp is
#     Copy-Item).
#   - a shell an -execdir starts that writes only outside its start paths, under a
#     protected start path (`find tools/verify -name pins -execdir sh -c
#     'cp "$1" /tmp/x' _ {} \;`): the start path counts (accepted in #158: the hook
#     cannot follow $PWD through the stages a string is expanded in).
# The Core's writing subcommands have two of their own, kept as the cost of reading
# the runs #161 names (alone, after cd, through a shell, by path) and no more:
#   - a miss: a run hidden from the words, through a variable holding an option
#     before the script or the fields of its subcommand, eval-built or aliased
#     names, a function, a copy under another name, a script fed on stdin
#     (`bash -s set phase red < factory/core/state.sh`), or a script the Editor
#     writes that runs one.
#   - a false refusal: a script of the project named baseline.sh, brief.sh,
#     hooks.sh, lock.sh or state.sh (or with core or a dot just before that name,
#     as an unquoted Windows path reads), run with one of those subcommands, or
#     one named land.sh, run at all: it reads as the Core script of that name.
factory_shell_targets() {
	factory_shell_resolve "$1" | awk '
		BEGIN {
			SEP = "\036"; MAX = 256; DEEP = 64; SELF = 3; ASSIGN = "^[A-Za-z_][A-Za-z0-9_]*[+]?="
			NEST = 8; CALLS = 4096
			WRITERS = "^(rm|rmdir|unlink|shred|mv|touch|truncate|chmod|chown|tee|mkdir|remove-item|ri|del|erase|rd|set-content|sc|add-content|ac|clear-content|clc|out-file|new-item|ni|move-item|mi|rename-item|ren|rni|move)$"
			COPIERS = "^(cp|install|ln|copy-item|cpi|copy)$"
			EDITORS = "^(sed|perl|gawk|awk|ruby)$"
			IN_PLACE = "^(-[a-zA-Z]*i|--in-place)"
		}
		function base(w,   n, parts) { n = split(w, parts, "/"); w = tolower(parts[n]); sub(/\.exe$/, "", w); return w }
		function out(s) { if (emitting) say(s) }
		# say: print s, counting it in near when it is a path taken from the current
		# folder (relative, or with a variable first), which -execdir moves, or when
		# a shell an -execdir command starts writes it (newdir), whatever its path.
		function say(s) { print s; if (newdir || s !~ /^(\/|~|[A-Za-z]:[\/\\]|::)/) near++ }
		# close_of: where the bracket at s[i] (the ( or { after a $) closes, reading
		# quotes, escapes, backticks and nested $(...) and ${...}; 0 when it never does.
		function close_of(s, i,   n, o, cl, d, c, q, j, k) {
			n = length(s); o = substr(s, i, 1); cl = (o == "(" ? ")" : "}"); d = 1; q = ""
			for (j = i + 1; j <= n; j++) {
				c = substr(s, j, 1)
				if (q == "\x27") { if (c == q) q = ""; continue }
				if (c == "\\") { j++; continue }
				if (q == "`") { if (c == q) q = ""; continue }
				if (c == "$" && substr(s, j + 1, 1) ~ /[({]/) { k = close_of(s, j + 1); if (!k) return 0; j = k; continue }
				if (q == "\"") { if (c == q) q = ""; continue }
				if (c == "\"" || c == "\x27" || c == "`") { q = c; continue }
				if (c == o) d++
				else if (c == cl && --d == 0) return j
			}
			return 0
		}
		# cmdsubs: s with each $(...) and backtick span made $(?), a value the hook cannot know.
		function cmdsubs(s,   r, i, j, n, c) {
			r = ""; n = length(s)
			for (i = 1; i <= n; i++) {
				c = substr(s, i, 1)
				if (c == "$" && substr(s, i + 1, 1) == "(") {
					j = close_of(s, i + 1); if (!j) j = n
					r = r "$(?)"; i = j; continue
				}
				if (c == "`") {
					j = index(substr(s, i + 1), "`")
					r = r "$(?)"; i = j ? i + j : n; continue
				}
				r = r c
			}
			return r
		}
		# note: one more value the command gives a variable.
		function note(name, v) {
			if (name ~ /[+]$/) { name = substr(name, 1, length(name) - 1); v = "$(?)" v }
			if (v ~ /^~(\/|$)/) v = ENVIRON["HOME"] substr(v, 2)
			if (!(name in vals)) vals[name] = v
			else if (index(SEP vals[name] SEP, SEP v SEP) == 0) vals[name] = vals[name] SEP v
		}
		function assign(s,   k) { k = index(s, "="); note(substr(s, 1, k - 1), substr(s, k + 1)) }
		# values: every way the variable reads, joined by SEP.
		function values(name, depth,   a, na, i, r, n, self, re) {
			if (!(name in vals)) {
				if (name == "HOME" || name == "PWD") return ENVIRON[name]
				return "$" name
			}
			self = (active[name] >= SELF)
			re = "[$]([{]?)" name "([^A-Za-z0-9_]|$)"
			active[name]++
			na = split(vals[name], a, SEP); if (na == 0) { na = 1; a[1] = "" }
			r = ""; n = 0
			for (i = 1; i <= na && !exhausted; i++) {
				if (self && a[i] ~ re) continue
				r = r (n++ ? SEP : "") expand(a[i], depth + 1)
				if (n > MAX) exhausted = 1
			}
			active[name]--
			return n ? r : "$" name
		}
		# expand: every way s reads, joined by SEP; past MAX ways or DEEP levels it
		# sets exhausted.
		function expand(s, depth,   head, lit, rest, name, op, a, r, na, nr, i, j, n, alts) {
			s = cmdsubs(s)
			if (!match(s, /\$([{][A-Za-z_][A-Za-z0-9_]*[^{}]*[}]|[A-Za-z_][A-Za-z0-9_]*)/)) return s
			if (depth > DEEP) { exhausted = 1; return s }
			head = substr(s, 1, RSTART - 1); lit = substr(s, RSTART, RLENGTH); rest = substr(s, RSTART + RLENGTH)
			op = ""
			if (substr(lit, 2, 1) == "{") {
				name = substr(lit, 3, length(lit) - 3)
				match(name, /^[A-Za-z_][A-Za-z0-9_]*/)
				op = substr(name, RLENGTH + 1); name = substr(name, 1, RLENGTH)
			} else name = substr(lit, 2)
			if (op ~ /^:?[+]/) { sub(/^:?[+]/, "", op); alts = SEP expand(op, depth + 1) }
			else {
				alts = values(name, depth)
				if (op ~ /^:?[-=]/) { sub(/^:?[-=]/, "", op); if (op != "") alts = alts SEP expand(op, depth + 1) }
				else if (op != "") alts = alts SEP lit
			}
			if (exhausted) return s
			na = split(alts, a, SEP); if (na == 0) { na = 1; a[1] = "" }
			nr = split(expand(rest, depth), r, SEP); if (nr == 0) { nr = 1; r[1] = "" }
			if (exhausted) return s
			alts = ""; n = 0
			for (i = 1; i <= na; i++) for (j = 1; j <= nr; j++) {
				if (++n > MAX) { exhausted = 1; return s }
				alts = alts (n > 1 ? SEP : "") head a[i] r[j]
			}
			return alts
		}
		# ways: every way the word s reads, joined by SEP; sets exhausted when it gave up.
		function ways(s) {
			if (s ~ /^~(\/|$)/) s = ENVIRON["HOME"] substr(s, 2)
			exhausted = 0
			return expand(s, 0)
		}
		# emit: print each way s reads, or that it has too many to check.
		function emit(s,   n, a, i) {
			if (!emitting) return
			n = split(ways(s), a, SEP)
			if (exhausted) { say("::exhausted " s); return }
			for (i = 1; i <= n; i++) say(a[i])
		}
		# anyof: true when some way word i reads matches re (lower-cased with low);
		# a word with too many ways to check prints so.
		function anyof(xv, xe, i, re, low,   a, n, k, v) {
			if (xe[i]) out("::exhausted " w[i])
			n = split(xv[i], a, SEP)
			for (k = 1; k <= n; k++) { v = low ? tolower(a[k]) : a[k]; if (v ~ re) return 1 }
			return 0
		}
		# gitmoves: the git subcommand at word j, when it puts work past the gate:
		# say `::git <what>` for any push (or send-pack), any update-ref, a branch
		# -d/-D/-m/-M/-c/-C/-f (or their long forms) that deletes, moves or
		# overwrites dev or main (refs/heads/ written or not), and a commit
		# with --no-verify or -n, which skips the pre-commit hook.
		function gitmoves(j, xv, xe,   i, k, c, del, mv, cp, force, nn, names, t) {
			if (anyof(xv, xe, j, "^(push|send-pack)$")) say("::git push")
			if (anyof(xv, xe, j, "^update-ref$")) say("::git update-ref")
			if (anyof(xv, xe, j, "^commit$")) {
				for (i = j + 1; i <= nw; i++) {
					if (w[i] == "--") break
					# git takes the unique prefix of an option: --no-veri is --no-verify.
					if (w[i] ~ /^--no-veri(f|fy)?$/) { say("::git commit --no-verify"); break }
					if (w[i] ~ /^--(message|file|reuse-message|reedit-message|template|author|date|cleanup|fixup|squash|trailer|pathspec-from-file)$/) { i++; continue }
					if (w[i] !~ /^-[^-]/) continue
					for (k = 2; k <= length(w[i]); k++) {
						c = substr(w[i], k, 1)
						# -u and -S take the rest of the word as their value (-uno).
						if (index("uS", c)) break
						if (c == "n") { say("::git commit --no-verify"); return }
						if (index("mFCct", c)) { if (k == length(w[i])) i++; break }
					}
				}
			}
			if (!anyof(xv, xe, j, "^branch$")) return
			del = mv = cp = force = nn = 0
			for (i = j + 1; i <= nw; i++) {
				if (w[i] == "--") continue
				if (w[i] ~ /^--/) {
					if (w[i] == "--delete") del = 1
					else if (w[i] == "--move") mv = 1
					else if (w[i] == "--copy") cp = 1
					else if (w[i] == "--force") force = 1
					continue
				}
				if (w[i] ~ /^-./) {
					if (w[i] ~ /^-[^-]*[dD]/) del = 1
					if (w[i] ~ /^-[^-]*[mM]/) mv = 1
					if (w[i] ~ /^-[^-]*[cC]/) cp = 1
					if (w[i] ~ /^-[^-]*[fDMC]/) force = 1
					if (w[i] ~ /^-[^-]*u$/) i++
					continue
				}
				names[++nn] = i
			}
			if (!(del || mv || cp || force) || !nn) return
			# Which names it writes: every one a delete or a move names, the new
			# name of a copy, the branch a forced create resets.
			for (k = 1; k <= nn; k++) {
				if (!(del || mv) && cp && k != nn) continue
				if (!(del || mv || cp) && k != 1) continue
				t = names[k]
				if (anyof(xv, xe, t, "^(refs/heads/)?(dev|main)$")) say("::git branch " w[t])
			}
		}
		# emitw: emit word i, through the ways flush already read.
		function emitw(xv, xe, i,   a, n, k) {
			if (!emitting) return
			if (xe[i]) { say("::exhausted " w[i]); return }
			n = split(xv[i], a, SEP)
			for (k = 1; k <= n; k++) say(a[k])
		}
		# payload: read word i as commands (a bash -c string), as written (so a $(...)
		# in it is read) and then each way it reads, its $0, $1 ... $@ the words
		# after it.
		# A shell an -execdir command starts has the folder of the match as its $PWD,
		# which the hook cannot follow through the stages a string is expanded in: so
		# while indir counts an -execdir, newdir counts each write in such a shell.
		function payload(xv, xe, i,   a, n, k) {
			if (indir) newdir++
			parse(i < nw ? positional(w[i], i + 1) : w[i])
			if (xe[i]) out("::exhausted " w[i])
			n = split(xv[i], a, SEP)
			for (k = 1; k <= n; k++) parse(i < nw ? positional(a[k], i + 1) : a[k])
			if (indir) newdir--
		}
		# positional: s with $N, ${N}, $@ and $* made the words they name, $0 being
		# word first, each value single-quoted so it stays data: outside double
		# quotes a value splits into words at blanks, and $@ and $* give a word per
		# argument; inside them $N and $* give one word, and $@ a word per argument.
		# Inside single quotes they stay as written.
		function positional(s, first,   r, i, n, c, q, t, v, k, m, parts) {
			r = ""; q = ""; n = length(s)
			for (i = 1; i <= n; i++) {
				c = substr(s, i, 1)
				if (q == "\x27") { r = r c; if (c == q) q = ""; continue }
				if (c == "\\") { r = r substr(s, i, 2); i++; continue }
				if (c == "\"") { q = (q == "\"") ? "" : c; r = r c; continue }
				if (c == "\x27" && q == "") { q = c; r = r c; continue }
				if (c != "$" || !match(substr(s, i), /^[$]([{][0-9]+[}]|[{][@*][}]|[0-9@*])/)) { r = r c; continue }
				t = substr(s, i, RLENGTH); i += RLENGTH - 1; gsub(/[${}]/, "", t)
				v = ""
				if (t == "@" || t == "*") {
					if (q == "\"" && t == "*") {
						for (k = first + 1; k <= nw; k++) v = v (k > first + 1 ? " " : "") w[k]
						v = squote(v)
					} else for (k = first + 1; k <= nw; k++) v = v (k > first + 1 ? " " : "") squote(w[k])
				} else if (first + t <= nw) {
					if (q == "\"") v = squote(w[first + t])
					else { m = split(w[first + t], parts, /[ \t\n]+/); for (k = 1; k <= m; k++) if (parts[k] != "") v = v (v != "" ? " " : "") squote(parts[k]) }
				}
				r = r (q == "\"" ? "\"" v "\"" : v)
			}
			return r
		}
		# squote: v as one single-quoted shell word.
		function squote(v,   r, k) {
			r = ""
			while ((k = index(v, "\x27"))) { r = r substr(v, 1, k - 1) "\x27\\\x27\x27"; v = substr(v, k + 1) }
			return "\x27" r v "\x27"
		}
		# dq: s as one double-quoted shell word that parse reads back as s.
		function dq(s) { gsub(/[\\"`]/, "\\\\&", s); return "\"" s "\"" }
		# evals: read the words of eval, joined, as commands: as written (so a $(...)
		# in them is read), then through every way each reads.
		function evals(xv, xe, from,   i, j, k, n, na, nr, a, rr, t, raw) {
			raw = ""
			for (i = from; i <= nw; i++) raw = raw (i > from ? " " : "") w[i]
			parse(raw)
			nr = 1; rr[1] = ""
			for (i = from; i <= nw; i++) {
				if (xe[i]) { out("::exhausted " w[i]); return }
				na = split(xv[i], a, SEP); if (na == 0) { na = 1; a[1] = "" }
				n = 0
				for (j = 1; j <= nr; j++) for (k = 1; k <= na; k++) {
					if (++n > MAX) { out("::exhausted eval"); return }
					t[n] = rr[j] (i > from ? " " : "") a[k]
				}
				nr = n
				for (j = 1; j <= nr; j++) rr[j] = t[j]
			}
			for (j = 1; j <= nr; j++) parse(rr[j])
		}
		# finds: what a find command, words start..nw, writes: its start paths when
		# it deletes; the file of -fprint and the like; and what each -exec command
		# writes, read with each {} (a word or inside one) as each start path. An
		# -execdir command runs in the folders under its start paths, so when it
		# writes a path taken from the current folder, or a shell it starts writes
		# anything, the start paths print too. A match found under a start
		# path (find . -name x -exec rm {} ;) is not followed: Land checks what lands.
		function finds(start, xv, xe,   i, j, k, m, np, p, del, c, dir, before) {
			i = start + 1
			while (i <= nw && (w[i] ~ /^-([HLP]|O[0-9]*)$/ || w[i] == "-D")) i += (w[i] == "-D") ? 2 : 1
			np = 0
			for (; i <= nw && !anyof(xv, xe, i, "^[-(!]"); i++) p[++np] = w[i]
			if (!np) p[++np] = "."
			del = 0
			for (; i <= nw; i++) {
				if (anyof(xv, xe, i, "^-delete$")) del = 1
				else if (anyof(xv, xe, i, "^-(fprint|fprint0|fprintf|fls)$")) { if (i < nw) emitw(xv, xe, i + 1); i++ }
				else if (anyof(xv, xe, i, "^-(exec|execdir|ok|okdir)$")) {
					dir = anyof(xv, xe, i, "^-(execdir|okdir)$")
					for (j = i + 1; j <= nw && w[j] !~ /^[;+]$/; j++) ;
					for (m = 1; m <= np; m++) {
						c = ""
						for (k = i + 1; k < j; k++) c = c " " dq(braces(w[k], p[m]))
						before = near
						if (dir) indir++
						parse(c)
						if (dir) indir--
						if (dir && near > before) emit(p[m])
					}
					i = j
				}
			}
			if (del) for (m = 1; m <= np; m++) emit(p[m])
		}
		# braces: s with each {} in it made p, as find makes it.
		function braces(s, p,   r, k) {
			r = ""
			while ((k = index(s, "{}"))) { r = r substr(s, 1, k - 1) p; s = substr(s, k + 2) }
			return r s
		}
		function flush(   i, start, n, a, k, cmd, seen, xv, xe) {
			start = 1
			while (start <= nw && (w[start] ~ ASSIGN || base(w[start]) ~ /^(sudo|env|command|exec|nohup|time|xargs|&|!|if|then|else|elif|while|until|do)$/)) {
				if (w[start] ~ ASSIGN) assign(w[start])
				start++
			}
			if (start > nw) { nw = 0; return }
			for (i = start; i <= nw; i++) { xv[i] = ways(w[i]); xe[i] = exhausted }
			if (xe[start]) out("::exhausted " w[start])
			n = split(xv[start], a, SEP)
			for (k = 1; k <= n; k++) {
				cmd = base(a[k])
				if (cmd in seen) continue
				seen[cmd] = 1
				classify(cmd, start, xv, xe)
			}
			nw = 0
		}
		# tdir: the folder an option word s gives a -t inside it (-tDIR, -vtDIR, or
		# --target-directory=DIR or a prefix of it from --t), else "".
		function tdir(s,   name) {
			if (match(s, /^-[A-RT-Za-fh-lnp-su-z]*t/) && RLENGTH < length(s)) return substr(s, RLENGTH + 1)
			name = s; sub(/=.*/, "", name)
			if (name != s && length(name) >= 3 && index("--target-directory", name) == 1) return substr(s, length(name) + 2)
			return ""
		}
		# psdest: emit the destination PowerShell names among words start+1..nw
		# (-Destination, or any prefix of it from -Des; its value the next word, or
		# bound with a colon); 1 when one is named.
		function psdest(xv, xe, start,   i, s, key) {
			key = 0
			for (i = start + 1; i <= nw; i++) {
				if (w[i] !~ /^-/) continue
				s = w[i]; sub(/:.*/, "", s)
				if (length(s) >= 4 && index("-destination", tolower(s)) == 1) {
					if (s != w[i]) { emit(substr(w[i], length(s) + 2)); key = 1 }
					else if (i < nw) { i++; emitw(xv, xe, i); key = 1 }
				}
			}
			return key
		}
		# psread: the destination of a PowerShell copy: the one psdest names, else
		# the last operand.
		function psread(xv, xe, start,   i, last) {
			if (psdest(xv, xe, start)) return
			last = 0
			for (i = start + 1; i <= nw; i++) if (w[i] !~ /^-/) last = i
			if (last) emitw(xv, xe, last)
		}
		# psparam: 1 when a word among start+1..nw can only be a PowerShell
		# parameter, being no option GNU cp takes (a letter outside its set before
		# any t or S: -ErrorAction, -Force, -Recurse), or names a Copy-Item
		# parameter, or a prefix of one from four characters (-Path, -Pat,
		# -LiteralPath, -lp).
		function psparam(start,   i, s, k, n, names) {
			n = split("-path -literalpath -pspath -destination -container -credential -exclude -filter -force -fromsession -include -passthru -recurse -tosession -whatif -confirm", names, " ")
			for (i = start + 1; i <= nw; i++) {
				if (w[i] !~ /^-[A-Za-z]/ || w[i] ~ /[$`]/) continue
				s = w[i]; sub(/:.*/, "", s)
				if (substr(s, 2) !~ /^[abdfilnprsuvxHLPRTZ]*([tS].*)?$/) return 1
				s = tolower(s)
				if (s == "-lp") return 1
				if (length(s) < 4 || s !~ /^-[a-z]+$/) continue
				for (k = 1; k <= n; k++) if (index(names[k], s) == 1) return 1
			}
			return 0
		}
		# corename: the Core script the path s names, by its last part (after a / or
		# a \): baseline.sh, brief.sh, hooks.sh, land.sh, lock.sh or state.sh, in any
		# case; else "". An unquoted
		# Windows path reads with its backslashes gone (factory\core\state.sh as
		# factorycorestate.sh, .\state.sh as .state.sh), so the name counts after
		# core or a dot too.
		function corename(s) {
			s = tolower(s); sub(/^.*[\/\\]/, "", s)
			if (!match(s, /(baseline|brief|hooks|land|lock|state)\.sh$/)) return ""
			if (RSTART == 1 || substr(s, RSTART - 1, 1) == "." || substr(s, 1, RSTART - 1) ~ /core$/) return substr(s, RSTART)
			return ""
		}
		# corescript: word i is a script a shell runs (bash <script>, source, .):
		# judge each Core script it may name, its arguments the words after it.
		function corescript(xv, xe, i,   a, n, k, name, done) {
			if (xe[i]) { out("::exhausted " w[i]); return }
			n = split(xv[i], a, SEP)
			for (k = 1; k <= n; k++) {
				name = corename(a[k])
				if (name == "" || (name in done)) continue
				done[name] = 1
				corerun(name, i, xv, xe)
			}
		}
		# corerun: the Core script name, run as word s, rewrites what the Driver owns
		# when its subcommand is baseline.sh shrink, record or add, brief.sh seal,
		# hooks.sh generate, lock.sh record or lift, or state.sh set, unset or incr:
		# print ::core <script> <subcommand>. The subcommand is the first word after
		# the options the script reads before it: --reuse for baseline.sh, --branch
		# and --issue with their values for state.sh. A read-only subcommand (gate,
		# check, files, get, list, stats, and the brief listings) prints nothing.
		# land.sh has no read-only form: any run of it prints ::core land.sh.
		function corerun(name, s, xv, xe,   j, k, n, a, subs, opts, step) {
			if (name == "land.sh") { out("::core land.sh"); return }
			if (name == "baseline.sh") { subs = "^(shrink|record|add)$"; opts = "^--reuse$"; step = 1 }
			else if (name == "brief.sh") { subs = "^seal$"; opts = ""; step = 0 }
			else if (name == "hooks.sh") { subs = "^generate$"; opts = ""; step = 0 }
			else if (name == "lock.sh") { subs = "^(record|lift)$"; opts = ""; step = 0 }
			else { subs = "^(set|unset|incr)$"; opts = "^--(branch|issue)$"; step = 2 }
			for (j = s + 1; j <= nw; j++) {
				if (xe[j]) { out("::exhausted " w[j]); return }
				n = split(xv[j], a, SEP)
				for (k = 1; k <= n; k++) if (a[k] ~ subs) { out("::core " name " " a[k]); return }
				if (!step || !anyof(xv, xe, j, opts)) return
				j += step - 1
			}
		}
		# classify: what command cmd, words start..nw, writes.
		function classify(cmd, start, xv, xe,   i, j, k, n, a, opt, last, key, s, vals, c, hit, unsure, f, dry) {
			if (cmd ~ /^(export|declare|local|readonly|typeset)$/) {
				for (i = start + 1; i <= nw; i++) if (w[i] ~ ASSIGN) assign(w[i])
			} else if (cmd == "for") {
				if (w[start + 2] == "in") for (i = start + 3; i <= nw; i++) note(w[start + 1], w[i])
			} else if (cmd ~ /^(bash|sh|zsh|dash|ksh|ash)$/) {
				# Read two ways, and both count. Any word that may be an option cluster with
				# c in it (-c, -ec, +c; case counts: -C is another option) makes the next
				# word commands, wherever it stands, so an option a variable holds (one
				# field of its value, as the shell splits it), or one that comes to
				# nothing, or an option this reader does not know, cannot hide a -c. The
				# cost, taken over a guess: a -c among the arguments after the commands
				# makes the word after it commands too. And the options read as the shell
				# reads them: up to --, -, or a word that is no option (or holds a
				# variable); each o or O in a cluster (-o, +O, -eco) takes a word, as do
				# --rcfile and --init-file; with a c among them, the first word after them
				# is commands, and with none it is the script the shell runs (a Core
				# script among them is judged by corerun) unless -n or -o noexec, the
				# last of them with + or - counting, has the shell only read it.
				for (i = start + 1; i < nw; i++)
					if (anyof(xv, xe, i, w[i] ~ /[$`]/ ? "(^|[ \t\n])[-+][A-Za-z]*c[A-Za-z]*([ \t\n]|$)" : "^[-+][A-Za-z]*c[A-Za-z]*$")) { payload(xv, xe, i + 1); hit[i + 1] = 1 }
				key = 0
				for (i = start + 1; i <= nw; i++) {
					if (w[i] == "--" || w[i] == "-") { i++; break }
					if (w[i] ~ /[$`]/) break
					if (w[i] ~ /^--./) { if (w[i] ~ /^--(rcfile|init-file)$/) i++; continue }
					if (w[i] !~ /^[-+][A-Za-z]+$/) break
					if (w[i] ~ /^-[A-Za-z]*c/) key = 1
					if (w[i] ~ /^[-+][A-Za-z]*n/) dry = (substr(w[i], 1, 1) == "-")
					if (w[i] ~ /o/ && i < nw && w[i + 1] == "noexec") dry = (substr(w[i], 1, 1) == "-")
					s = w[i]; i += gsub(/[oO]/, "", s)
				}
				if (key && i <= nw && !(i in hit)) payload(xv, xe, i)
				else if (!key && i <= nw && !dry) corescript(xv, xe, i)
			} else if (cmd == "." || cmd == "source") {
				i = start + 1
				if (i <= nw && w[i] == "--") i++
				if (i <= nw) corescript(xv, xe, i)
			} else if (corename(cmd) != "") {
				corerun(corename(cmd), start, xv, xe)
			} else if (cmd ~ /^(powershell|pwsh|cmd)$/) {
				for (i = start + 1; i < nw; i++)
					if (anyof(xv, xe, i, "^(-c|-command|/c)$", 1)) { payload(xv, xe, i + 1); break }
			} else if (cmd == "eval") {
				evals(xv, xe, start + 1)
			} else if (cmd ~ WRITERS) {
				for (i = start + 1; i <= nw; i++) if (w[i] !~ /^-/) emitw(xv, xe, i)
			} else if (cmd ~ /^(cp|install|ln)$/) {
				# Read as GNU getopt reads them: options up to --; a letter that takes a
				# value (S and t, and g, m and o for install) takes the rest of its word
				# or the next word, as do --suffix, --target-directory (or a prefix of it
				# from --t), --mode, --owner, --group, --strip-program, --sparse and
				# --no-preserve. The destination is the folder of a -t when there is one,
				# else the last operand. But when a word with a variable in it may be an
				# option, which cannot be read that way, every operand and every such word
				# is a destination, with each -t folder its values may give. Such a word
				# counts wherever it stands (a -- may be a value of -S), and a value
				# counts field by field, as the shell splits it. In PowerShell cp is
				# Copy-Item, so a cp that names one of its parameters reads as PowerShell
				# too (psread).
				if (cmd == "cp" && psparam(start)) psread(xv, xe, start)
				unsure = 0
				for (i = start + 1; i <= nw; i++) if (w[i] ~ /[$`]/ && anyof(xv, xe, i, "(^|[ \t\n])-")) unsure = 1
				if (unsure) {
					for (i = start + 1; i <= nw; i++) {
						if (w[i] == "--") continue
						if (w[i] ~ /^-/ && w[i] !~ /[$`]/) {
							s = tdir(w[i]); if (s != "") emit(s)
							if (w[i] ~ /^(-[A-RT-Za-fh-lnp-su-z]*t|--t[a-z-]*)$/ && i < nw) emitw(xv, xe, i + 1)
							continue
						}
						emitw(xv, xe, i)
						if (w[i] !~ /[$`]/) continue
						key = 0
						n = split(xv[i], a, SEP)
						for (k = 1; k <= n; k++) {
							c = split(a[k], f, /[ \t\n]+/); last = ""
							for (j = 1; j <= c; j++) {
								if (f[j] == "") continue
								if (c > 1) out(f[j])
								s = tdir(f[j]); if (s != "") out(s)
								last = f[j]
							}
							if (last ~ /^(-[A-Za-z]*t|--t[a-z-]*)$/) key = 1
						}
						if (key && i < nw) emitw(xv, xe, i + 1)
					}
					return
				}
				vals = (cmd == "install") ? "gmoSt" : "St"
				opt = 1; last = 0; key = 0
				for (i = start + 1; i <= nw; i++) {
					if (opt && w[i] == "--") { opt = 0; continue }
					if (opt && w[i] ~ /^--./) {
						s = w[i]; sub(/=.*/, "", s)
						if (length(s) >= 3 && index("--target-directory", s) == 1) {
							if (s != w[i]) emit(substr(w[i], length(s) + 2))
							else if (i < nw) { i++; emitw(xv, xe, i) }
							key = 1
						} else if (s == w[i] && w[i] ~ /^--(suffix|mode|owner|group|strip-program|sparse|no-preserve)$/) i++
						continue
					}
					if (opt && w[i] ~ /^-./) {
						for (k = 2; k <= length(w[i]); k++) {
							c = substr(w[i], k, 1)
							if (!index(vals, c)) continue
							if (k < length(w[i])) { if (c == "t") { emit(substr(w[i], k + 1)); key = 1 } }
							else if (i < nw) { i++; if (c == "t") { emitw(xv, xe, i); key = 1 } }
							break
						}
						continue
					}
					last = i
				}
				if (last && !key) emitw(xv, xe, last)
			} else if (cmd ~ COPIERS) {
				psread(xv, xe, start)
			} else if (cmd ~ EDITORS) {
				opt = 0
				for (i = start + 1; i <= nw; i++) if (anyof(xv, xe, i, IN_PLACE)) opt = 1
				if (opt) for (i = start + 1; i <= nw; i++) if (w[i] !~ /^-/) emitw(xv, xe, i)
			} else if (cmd == "dd") {
				for (i = start + 1; i <= nw; i++) if (anyof(xv, xe, i, "^of=")) {
					n = split(xv[i], a, SEP)
					for (k = 1; k <= n; k++) if (a[k] ~ /^of=/) out(substr(a[k], 4))
				}
			} else if (cmd == "find") {
				finds(start, xv, xe)
			} else if (cmd == "git") {
				# the options of git itself, before the subcommand: those that take the next
				# word as their value skip it, and a config that turns the hooks off
				# (-c core.hooksPath=..., --config-env) skips the pre-commit hook.
				for (j = start + 1; j <= nw && w[j] ~ /^-/; j++) {
					if (w[j] ~ /^--config-env=/ && emitting && anyof(xv, xe, j, "^--config-env=core\\.hookspath=", 1)) say("::git -c core.hooksPath")
					if (w[j] !~ /^(-[Cc]|--(git-dir|work-tree|namespace|super-prefix|config-env|attr-source))$/) continue
					j++
					if (w[j - 1] ~ /^(-c|--config-env)$/ && emitting && anyof(xv, xe, j, "^core\\.hookspath(=|$)", 1)) say("::git -c core.hooksPath")
				}
				if (j > nw) return
				if (anyof(xv, xe, j, "^(checkout|restore|rm|mv)$")) {
					for (i = j + 1; i <= nw; i++) if (w[i] !~ /^-/ && w[i] != "--") emitw(xv, xe, i)
				}
				if (anyof(xv, xe, j, "^config$") && emitting) {
					# A write sets a key to a value, or unsets it; a read names the key alone.
					opt = 0; last = 0; key = 0
					for (i = j + 1; i <= nw; i++) {
						if (w[i] ~ /^--(get|list|show|name-only|null|type)/ || w[i] == "-l") opt = -1
						else if (anyof(xv, xe, i, "^--(unset|add|replace|rename-section|remove-section)") && opt == 0) opt = 1
						else if (w[i] !~ /^-/) { last++; if (xv[i] ~ /factory-/) key = 1 }
					}
					if (key && opt >= 0 && (opt == 1 || last >= 2)) say("::run-state")
				}
				if (emitting) gitmoves(j, xv, xe)
			}
		}
		function word() {
			if (have) {
				if (redir) emit(cur)
				else if (!skip) w[++nw] = cur
				redir = 0; skip = 0
			}
			cur = ""; have = 0
		}
		# subs: parse the commands inside each $(...) and backtick of s, and those
		# inside each ${...}, nothing else.
		function subs(s,   i, j, n, c) {
			n = length(s)
			for (i = 1; i <= n; i++) {
				c = substr(s, i, 1)
				if (c == "$" && substr(s, i + 1, 1) ~ /[({]/) {
					j = close_of(s, i + 1)
					if (!j) { out("::doubt a $" substr(s, i + 1, 1) " that never closes"); j = n + 1 }
					if (substr(s, i + 1, 1) == "(") parse(substr(s, i + 2, j - i - 2))
					else subs(substr(s, i + 2, j - i - 2))
					i = j
				} else if (c == "`") {
					j = index(substr(s, i + 1), "`"); j = j ? i + j : n
					parse(substr(s, i + 1, j - i - 1)); i = j
				}
			}
		}
		# bodies: read the here-documents whose delimiters this line named, from
		# s after position i (a newline); return the position their last one ends at.
		function bodies(s, i, n,   h, j, line, body, cmp) {
			for (h = 1; h <= nh; h++) {
				body = ""
				while (i < n) {
					j = index(substr(s, i + 1), "\n")
					line = j ? substr(s, i + 1, j - 1) : substr(s, i + 1)
					i = j ? i + j : n
					cmp = line
					if (hstrip[h]) sub(/^\t+/, "", cmp)
					if (cmp == hdelim[h]) break
					body = body line "\n"
				}
				if (hscript[h]) parse(body)
				else if (!hquoted[h]) subs(body)
			}
			nh = 0
			return i
		}
		# parse: read s as commands. A nested command ($(...), a backtick, a -c
		# string, a here-document fed to a shell) keeps the outer words, the word
		# being read and the outer here-documents still to come aside.
		function parse(s,   i, j, c, q, n, o, k, saved, saved_nw, saved_cur, saved_have, saved_redir, saved_skip, saved_nh, sd, sq, ss, sc, delim, quoted, strip, shell_in) {
			if (nest >= NEST || ++calls > CALLS) { if (!deep) out("::exhausted the command nests too deep to read"); deep = 1; return }
			nest++
			saved_nw = nw; saved_cur = cur; saved_have = have; saved_redir = redir; saved_skip = skip; saved_nh = nh
			for (k = 1; k <= nw; k++) saved[k] = w[k]
			for (k = 1; k <= nh; k++) { sd[k] = hdelim[k]; sq[k] = hquoted[k]; ss[k] = hstrip[k]; sc[k] = hscript[k] }
			nw = 0; cur = ""; have = 0; redir = 0; skip = 0; nh = 0
			n = length(s)
			for (i = 1; i <= n; i++) {
				c = substr(s, i, 1)
				if (q == "\x27") { if (c == q) q = ""; else cur = cur c; continue }
				if (c == "\\") { if (i < n && substr(s, i + 1, 1) != "\n") { cur = cur substr(s, i + 1, 1); have = 1 } i++; continue }
				# A comment: from a # that starts a word to the end of the line.
				if (c == "#" && q == "" && !have) { j = index(substr(s, i + 1), "\n"); i = j ? i + j - 1 : n; continue }
				if (c == "$" && substr(s, i + 1, 1) ~ /[({]/) {
					o = substr(s, i + 1, 1)
					j = close_of(s, i + 1)
					if (!j) { out("::doubt a $" o " that never closes"); j = n }
					if (o == "(") parse(substr(s, i + 2, j - i - 2))
					else subs(substr(s, i + 2, j - i - 2))
					cur = cur substr(s, i, j - i + 1); have = 1; i = j; continue
				}
				if (c == "`") {
					j = index(substr(s, i + 1), "`"); j = j ? i + j : n
					parse(substr(s, i + 1, j - i - 1))
					cur = cur substr(s, i, j - i + 1); have = 1; i = j; continue
				}
				if (q == "\"") { if (c == q) q = ""; else cur = cur c; continue }
				if (c == "\"" || c == "\x27") { q = c; have = 1; continue }
				if (c ~ /[ \t]/) { word(); continue }
				if (c == "<" && substr(s, i + 1, 2) == "<<") { word(); skip = 1; i += 2; continue }
				if (c == "<" && substr(s, i + 1, 1) == "<") {
					# A here-document: note its delimiter; its body follows the line.
					word()
					shell_in = 0
					for (k = 1; k <= nw; k++) if (base(w[k]) ~ /^(bash|sh|zsh|dash|ksh|ash)$/) shell_in = 1
					j = i + 2; strip = 0; quoted = 0; delim = ""
					if (substr(s, j, 1) == "-") { strip = 1; j++ }
					while (substr(s, j, 1) ~ /[ \t]/) j++
					while (j <= n && substr(s, j, 1) !~ /[ \t\n;|&<>()]/) {
						c = substr(s, j, 1)
						if (c == "\"" || c == "\x27") {
							quoted = 1
							k = index(substr(s, j + 1), c)
							if (!k) { delim = delim substr(s, j + 1); j = n + 1; break }
							delim = delim substr(s, j + 1, k - 1); j += k + 1; continue
						}
						if (c == "\\") { quoted = 1; j++; c = substr(s, j, 1) }
						delim = delim c; j++
					}
					if (delim != "") { nh++; hdelim[nh] = delim; hquoted[nh] = quoted; hstrip[nh] = strip; hscript[nh] = shell_in }
					i = j - 1
					continue
				}
				# { and } are reserved words only as whole words; {} and {a,b} are words.
				if ((c == "{" || c == "}") && (have || substr(s, i + 1, 1) !~ /^([ \t\n;|&()<>]|)$/)) { cur = cur c; have = 1; continue }
				if (c ~ /[;|&\n(){}]/) {
					if (c == "&" && substr(s, i + 1, 1) == ">") { word(); redir = 1; i++; if (substr(s, i + 1, 1) == ">") i++; continue }
					word(); flush()
					if (c == "\n" && nh > 0) i = bodies(s, i, n)
					continue
				}
				if (c == ">") {
					if (have && cur ~ /^[0-9]$/) { cur = ""; have = 0 } else word()
					while (substr(s, i + 1, 1) ~ /[>|]/) i++
					if (substr(s, i + 1, 1) == "&") { i++; while (substr(s, i + 1, 1) ~ /[0-9-]/) i++; continue }
					redir = 1
					continue
				}
				if (c == "<") { word(); skip = 1; continue }
				cur = cur c
				have = 1
			}
			word(); flush()
			nw = saved_nw; cur = saved_cur; have = saved_have; redir = saved_redir; skip = saved_skip; nh = saved_nh
			for (k = 1; k <= nw; k++) w[k] = saved[k]
			for (k = 1; k <= nh; k++) { hdelim[k] = sd[k]; hquoted[k] = sq[k]; hstrip[k] = ss[k]; hscript[k] = sc[k] }
			nest--
		}
		{ text = text (NR > 1 ? "\n" : "") $0 }
		# Three passes: the first two gather every value each variable is given
		# (the second sees the -c strings the first filled in), the third prints
		# the targets with them.
		END { emitting = 0; parse(text); calls = deep = 0; parse(text); emitting = 1; calls = deep = 0; parse(text) }
	' | tr '\034' ' '
	# An awk that stops early (a limit of its own) has read part of the command at most.
	[ "${PIPESTATUS[1]}" -eq 0 ] || echo "::exhausted the hook could not finish reading the command"
}
