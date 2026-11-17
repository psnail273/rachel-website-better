# Helpers for the Core's tests, sourced by test.sh before each *_test.sh file.
#
# A test file defines test_* functions. test.sh runs each one in its own subshell,
# inside its own empty temp folder ($TEST_TMP), and cleans it up afterwards. A test
# fails by calling fail (or a failing assert_*), and skips by calling skip.

# The Core under test (exported, as the runner does, for step scripts run by
# hand), and the fixture project's tracked source.
FACTORY_CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export FACTORY_CORE
FIXTURE_SRC="$FACTORY_CORE/tests/fixture/project"

fail() {
	echo "    $*" >&2
	exit 1
}

skip() {
	echo "    $*" >&2
	exit 77
}

# The fixtures' factory version: every land bumps the real factory/VERSION, so
# no test reads it.
FIXTURE_FACTORY_VERSION=0.1.0

# copy_factory <dest>: this factory's files into <dest>, without the .git a
# clone of the factory's repo has at its root, at FIXTURE_FACTORY_VERSION.
copy_factory() {
	mkdir -p "$1" && cp -R "$FACTORY_CORE/../." "$1/" && rm -rf "$1/.git" &&
		echo "$FIXTURE_FACTORY_VERSION" > "$1/VERSION"
}

# isolate_git: from here on, git runs with no global or system config, under a
# fixed identity. test.sh calls it before every test, so a test body never reads
# the runner's git config; a test that wants a global config writes its own, to
# $GIT_CONFIG_GLOBAL. Calling it again empties that file. Nor does git read the
# runner's global ignore and attributes, the defaults of core.excludesFile and
# core.attributesFile ($XDG_CONFIG_HOME/git/, else ~/.config/git/): XDG_CONFIG_HOME
# is the test's own empty $TEST_TMP/xdg-config, so any other tool the test runs
# (pnpm, Godot) finds no config of the runner's there either. Nor the config the
# runner gives git in its environment (GIT_CONFIG_COUNT, or GIT_CONFIG_PARAMETERS,
# which `git -c` passes on), which could name the runner's files again.
isolate_git() {
	: > "$TEST_TMP/gitconfig"
	mkdir -p "$TEST_TMP/xdg-config"
	export XDG_CONFIG_HOME="$TEST_TMP/xdg-config"
	unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
	export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
	export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.com
	export GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.com
}

# --- waiting ------------------------------------------------------------------------
# A test never sleeps for a fixed time nor reads the clock (test.sh's raw-waits step
# refuses sleep, timeout and $SECONDS in a *_test.sh file): it waits for a condition
# through wait_until, and a stand-in that must still be running blocks until the
# test releases or kills it (blocking_stand_in). This file is the one exempt.

# The hang guard: the most seconds wait_until waits; a blocking stand-in blocks
# three times as long, so a test waiting for one to be killed never sees it end by
# its guard instead. It only ends a broken run; it never decides which way a
# healthy test goes.
TEST_HANG_GUARD="${FACTORY_TEST_HANG_GUARD:-120}"

# wait_until <what> <command...>: run the command until it succeeds; fail, naming
# <what>, once the hang guard runs out.
wait_until() {
	local what="$1" end=$((SECONDS + TEST_HANG_GUARD))
	shift
	until "$@"; do
		[ "$SECONDS" -lt "$end" ] || fail "gave up waiting for $what: the hang guard ran out (${TEST_HANG_GUARD}s)"
		sleep 0.1
	done
}

# refusing_stand_in <command> <glob>: put a stand-in for <command> first on PATH
# that refuses, as the system refuses a read or write it may not make, any call
# with an argument matching <glob>, and runs the real <command> otherwise. A test
# that needs a read or write to fail uses it (or a path that can't be a file,
# such as one inside a regular file), never chmod: root reads and writes through
# a mode. A later call for the same command replaces its glob.
refusing_stand_in() {
	local real
	# The real command, never an earlier stand-in, which would run itself.
	real="$(PATH="${PATH//"$TEST_TMP/stand-ins:"/}" command -v "$1")" || fail "no $1 to stand in for"
	mkdir -p "$TEST_TMP/stand-ins" || fail "could not make the stand-ins folder"
	{
		printf '#!/usr/bin/env bash\n'
		printf 'for a in "$@"; do\n'
		printf '\tcase "$a" in %s) echo "%s: $a: Permission denied" >&2 && exit 1 ;; esac\n' "$2" "$1"
		printf 'done\n'
		printf 'exec %q "$@"\n' "$real"
	} > "$TEST_TMP/stand-ins/$1" && chmod +x "$TEST_TMP/stand-ins/$1" || fail "could not write the $1 stand-in"
	case ":$PATH:" in *":$TEST_TMP/stand-ins:"*) ;; *) export PATH="$TEST_TMP/stand-ins:$PATH" ;; esac
}

# blocking_stand_in <path> <release>: an executable stand-in at <path> that, run,
# writes its pid to <path>.pid, then blocks until the file <release> exists (exit
# 0) or it is killed. Once its hang guard runs out it gives up: a note on stderr,
# exit 124. Its arguments are ignored, so a test can give it a command line to be
# known by.
blocking_stand_in() {
	local guard=$((TEST_HANG_GUARD * 3))
	cat > "$1" << SH
#!/usr/bin/env bash
echo "\$\$" > $(printf '%q' "$1.pid")
until [ -e $(printf '%q' "$2") ]; do
	if [ "\$SECONDS" -ge $guard ]; then
		echo "blocking stand-in \$0: never released; its hang guard ran out (${guard}s)" >&2
		exit 124
	fi
	sleep 0.1
done
SH
	chmod 755 "$1"
}

# path_without <command>: PATH becomes one folder, $TEST_TMP/path-without-<command>,
# of links to every command PATH finds now but <command> (the first of each name),
# so the code under test runs as on a machine that lacks <command>.
path_without() {
	local bin="$TEST_TMP/path-without-$1" dir f name
	local -a dirs links=()
	local -A seen=()
	mkdir -p "$bin" || fail "could not make $bin"
	IFS=: read -ra dirs <<< "$PATH"
	for dir in "${dirs[@]}"; do
		[ -n "$dir" ] && [ -d "$dir" ] || continue
		for f in "$dir"/*; do
			name="${f##*/}"
			[ "$name" != "$1" ] && [ -z "${seen[$name]:-}" ] && [ -f "$f" ] && [ -x "$f" ] || continue
			seen[$name]=1
			links+=("$f")
		done
	done
	ln -s "${links[@]}" "$bin/" || fail "could not link the commands into $bin"
	export PATH="$bin"
	! command -v "$1" > /dev/null 2>&1 || fail "$1 is still on PATH: $(command -v "$1")"
}

# The Build Brief's fence, and where a work branch's brief lives in the fixtures.
FENCE='```'
BRIEF=.git/factory/brief.md

# brief <line...>: the work branch's brief, its block holding the given lines.
brief() {
	mkdir -p .git/factory
	{
		echo "# Brief"
		echo "${FENCE}factory-brief"
		printf '%s\n' "$@"
		echo "$FENCE"
	} > "$BRIEF"
}

# seal_stub [state.sh option...]: a stand-in seal in the run state, since
# state.sh refuses a phase until the Build Brief is sealed. Nothing checks it
# against a brief unless a test writes one where the gates read it.
seal_stub() {
	bash "$FACTORY_CORE/state.sh" "$@" set brief-sha 0123abcd > /dev/null || fail "could not set the seal"
}

# fixture_project: copy the fixture into $TEST_TMP/project, give it a local.env
# from its example, and cd there.
fixture_project() {
	cp -R "$FIXTURE_SRC" "$TEST_TMP/project" || fail "could not copy the fixture"
	cp "$TEST_TMP/project/tools/verify/local.env.example" "$TEST_TMP/project/tools/verify/local.env"
	mkdir -p "$TEST_TMP/project/.fixture"
	cd "$TEST_TMP/project" || fail "could not enter the fixture"
}

# fixture_git_project: fixture_project, made a git repo: the fixture plus a
# product file src/a.txt and a test file tests/a_test.txt committed on dev, and a
# work branch checked out from there. git runs with no global or system config.
fixture_git_project() {
	fixture_project
	isolate_git
	mkdir -p src tests
	echo one > src/a.txt
	printf 'test_old_one\ntest_old_two\n' > tests/a_test.txt
	printf '/.fixture/\n/tools/verify/local.env\n' > .gitignore
	git init -q -b dev . || fail "git init failed"
	git add -A && git commit -q -m "fixture" || fail "could not commit the fixture"
	git checkout -q -b work || fail "no work branch"
}

# run_cmd <cmd...>: run it, capturing stdout in $out and the exit code in $status.
# stderr goes to $TEST_TMP/stderr.
run_cmd() {
	out="$("$@" 2> "$TEST_TMP/stderr")"
	status=$?
}

# run_verify <args...>: run the Core runner on the current project.
run_verify() {
	run_cmd bash "$FACTORY_CORE/verify.sh" "$@"
}

# ran_steps: the fixture steps that ran, space-separated, in run order.
ran_steps() {
	if [ -f .fixture/ran ]; then
		tr '\n' ' ' < .fixture/ran | sed 's/ $//'
	fi
}

assert_eq() {
	[ "$1" = "$2" ] || fail "${3:-values differ}"$'\n'"      expected: $1"$'\n'"      actual:   $2"
}

assert_status() {
	[ "$status" -eq "$1" ] || fail "expected exit $1, got $status; stdout:"$'\n'"$out"
}

# assert_line <line>: stdout has exactly this line.
assert_line() {
	printf '%s\n' "$out" | grep -qxF -- "$1" || fail "no line '$1' in stdout:"$'\n'"$out"
}

assert_no_line() {
	! printf '%s\n' "$out" | grep -qxF -- "$1" || fail "unexpected line '$1' in stdout:"$'\n'"$out"
}

# stderr_has <text>: run_cmd's stderr holds this text.
stderr_has() {
	grep -qF -- "$1" "$TEST_TMP/stderr" || fail "no '$1' on stderr:"$'\n'"$(cat "$TEST_TMP/stderr")"
}

# assert_last_line <line>: stdout ends with this line.
assert_last_line() {
	assert_eq "$1" "$(printf '%s\n' "$out" | tail -n 1)" "wrong last line of stdout"
}

# fixture_repo: a git repo for the Run scripts, and cd into its main checkout.
#   $TEST_TMP/origin.git  the bare remote, with branch dev
#   $TEST_TMP/main        a clone on dev: a tools/verify.sh that fails while a
#                         file named `red` is tracked, a tools/verify/bootstrap that
#                         appends a line to $BOOTSTRAP_LOG, and a .gitignore for
#                         .claude/worktrees/ and tools/verify/local.env
# git runs with no global or system config, under a fixed identity.
fixture_repo() {
	isolate_git
	export BOOTSTRAP_LOG="$TEST_TMP/bootstrap.log"
	git init -q --bare -b dev "$TEST_TMP/origin.git" || fail "could not make the remote"
	git init -q -b dev "$TEST_TMP/main" || fail "could not make the repo"
	cd "$TEST_TMP/main" || fail "could not enter the repo"
	mkdir -p tools/verify
	printf '/.claude/worktrees/\n/tools/verify/local.env\n' > .gitignore
	cat > tools/verify.sh << 'SH'
if [ -f red ]; then echo "red:1 fixture-red the tree holds red"; echo "verify: FAILED at step test"; exit 1; fi
echo "verify: PASS"
SH
	cat > tools/verify/bootstrap << 'SH'
echo "bootstrap in $(basename "$PWD") core=${FACTORY_CORE:+set} tool=${FIXTURE_TOOL:-none}" >> "$BOOTSTRAP_LOG"
SH
	echo one > a.txt
	git add -A && git commit -q -m "fixture" || fail "could not commit the fixture"
	git remote add origin "$TEST_TMP/origin.git"
	git push -q -u origin dev 2> /dev/null || fail "could not push the fixture"
}

# commit_in <dir> <file> <content>: write the file in <dir> and commit it.
commit_in() {
	printf '%s\n' "$3" > "$1/$2"
	git -C "$1" add "$2" && git -C "$1" commit -q -m "edit $2" || fail "could not commit $2 in $1"
}

# push_from_elsewhere <file> <content>: another clone commits the file and pushes dev.
push_from_elsewhere() {
	git clone -q -b dev "$TEST_TMP/origin.git" "$TEST_TMP/other" 2> /dev/null || fail "could not clone"
	commit_in "$TEST_TMP/other" "$1" "$2"
	git -C "$TEST_TMP/other" push -q origin dev 2> /dev/null || fail "could not push from the other clone"
}

# adopt_project: $TEST_TMP/project, a git repo on dev with the vendored factory/,
# a stub adapter `fake` (the fixture project's step scripts), an AGENTS.md, a
# .claude/settings.json and an origin remote named My_Game, everything committed;
# cd there, ready for adopt.sh. The fixture's tool version comes from the
# environment, so no local.env is needed. Built once per test.sh run and copied
# (cached_project).
adopt_project() {
	adopt_env
	cached_project project build_project
}

# adopted [finding]: adopt_project, Adopted with the fake adapter and committed,
# and the fixture's step log (.fixture/) gone; with `finding`, the fake lint step
# had a finding then, so the Baseline holds it. Built once per test.sh run and
# copied (cached_project).
adopted() {
	adopt_env
	cached_project "adopted${1:+-$1}" build_adopted "$@"
}

# adopt_env: the test's environment adopt_project's fixture expects: git isolated,
# the fake tool's version set, and no factory variable of the runner's.
adopt_env() {
	isolate_git
	export FAKETOOL_VERSION=1.2.3
	unset FACTORY_PROJECT FACTORY_LABEL_CMD FACTORY_BASE FACTORY_UPSTREAM FACTORY_INSTALL FACTORY_INSTALL_TAG FACTORY_INSTALL_UPSTREAM
}

# cached_project <key> <builder> [args...]: $TEST_TMP/project as <builder> [args...]
# makes it there, and cd there. The first call in a test.sh run with a <key> runs
# the builder, then publishes a copy of its project as $FACTORY_TEST_RUN/fixtures/
# <key>; a later call copies that (cp -a) instead, so each test still has a project
# of its own and none can change the cached one. Calls racing to build each build
# their own, and the first to publish wins: the copy goes to a temp name and is
# published by a symlink to it, which is atomic and never replaces another (ln -n:
# nor lands inside the one already there). The cache is in the run's own folder,
# gone with it. With no run (FACTORY_TEST_RUN unset, or not a folder), the builder
# runs every time. A builder must make the same project in any $TEST_TMP: a path
# of its own baked in would be wrong in a copy. Both copies are copy_tree's, or
# those of the function CACHED_COPY names (<from> <to>, <to> an empty folder), for
# a project too big to copy whole each time.
cached_project() {
	local key="$1" dir="${FACTORY_TEST_RUN:-}/fixtures" tmp
	shift
	if [ -z "${FACTORY_TEST_RUN:-}" ] || [ ! -d "$FACTORY_TEST_RUN" ]; then
		"$@"
		return
	fi
	if [ -d "$dir/$key" ]; then
		mkdir -p "$TEST_TMP/project" && "${CACHED_COPY:-copy_tree}" "$dir/$key" "$TEST_TMP/project" || fail "could not copy the cached $key project"
		cd "$TEST_TMP/project" || fail "could not enter the project"
		return
	fi
	"$@"
	mkdir -p "$dir" && tmp="$(mktemp -d "$dir/.$key.XXXXXX")" &&
		"${CACHED_COPY:-copy_tree}" "$TEST_TMP/project" "$tmp" || fail "could not cache the $key project"
	ln -sn "${tmp##*/}" "$dir/$key" 2> /dev/null || rm -rf "$tmp"
}

# copy_tree <from> <to>: everything in the folder <from>, copied into <to> (cp -a).
copy_tree() {
	cp -a "$1/." "$2/"
}

# build_project: adopt_project's project, built in $TEST_TMP/project.
build_project() {
	mkdir -p "$TEST_TMP/project/factory/adapters/fake" || fail "could not make the project"
	copy_factory "$TEST_TMP/project/factory" || fail "could not vendor the factory"
	cp -R "$FIXTURE_SRC/tools" "$TEST_TMP/project/factory/adapters/fake/" || fail "could not make the fake adapter"
	cd "$TEST_TMP/project" || fail "could not enter the project"
	printf '# AGENTS.md\n\nThe project'"'"'s own words.\n' > AGENTS.md
	mkdir -p .claude src
	printf '{\n  "env": {\n    "A": "1"\n  }\n}\n' > .claude/settings.json
	echo one > src/a.txt
	printf '/.fixture/\n' > .gitignore
	git init -q -b dev . || fail "git init failed"
	git remote add origin "git@example.com:me/My_Game.git"
	git add -A && git commit -q -m "project" || fail "could not commit the project"
}

# build_adopted [finding]: adopted's project, built in $TEST_TMP/project.
build_adopted() {
	cached_project project build_project
	if [ "${1:-}" = finding ]; then
		mkdir -p .fixture && echo "src/a.txt:1 fake-rule a finding" > .fixture/fail-lint
	fi
	run_cmd bash factory/core/adopt.sh fake
	assert_status 0
	git commit -q -m adopt || fail "could not commit the adoption"
	rm -rf .fixture
}

# linked_worktree: two real checkouts of one project. adopt_project, Adopted with
# the fake adapter and committed, so core.hooksPath is the relative one adopt.sh
# sets, then a linked worktree made as start.sh makes it: .claude/worktrees/issue-7
# on branch issue/7, with the main checkout's tools/verify/local.env copied in, now
# the only source of the fixture's tool version. cd into the worktree; $MAIN_CORE is
# the main checkout's Core. The main checkout, up to its commit, is built once per
# test.sh run and copied (cached_project).
linked_worktree() {
	adopt_env
	cached_project linked build_linked
	cp tools/verify/local.env.example tools/verify/local.env
	unset FAKETOOL_VERSION
	# shellcheck disable=SC2034 # read by the tests that call linked_worktree
	MAIN_CORE="$PWD/factory/core"
	git worktree add -q -b issue/7 .claude/worktrees/issue-7 || fail "could not add the worktree"
	cp tools/verify/local.env .claude/worktrees/issue-7/tools/verify/local.env || fail "could not copy local.env"
	cd .claude/worktrees/issue-7 || fail "could not enter the worktree"
}

# build_linked: linked_worktree's main checkout, before its local.env and worktree,
# built in $TEST_TMP/project.
build_linked() {
	cached_project project build_project
	run_cmd bash factory/core/adopt.sh fake
	assert_status 0
	echo /.claude/worktrees/ >> .gitignore
	git add -A && git commit -q -m adopt || fail "could not commit the adoption"
}

# fake_generator: the fake adapter gets a verify-<project> generator, committed.
fake_generator() {
	cat > factory/adapters/fake/verify-skill.sh << 'SH'
printf -- '---\nname: verify-%s\ndescription: Drive the fake build.\n---\n\n' "$1" > "$2/SKILL.md"
printf '## %s\n\n' Launch Doctor Drive Evidence Cleanup "Feature map" >> "$2/SKILL.md"
SH
	git add -A && git commit -q -m "generator" || fail "could not commit"
}

# --- the name guards ------------------------------------------------------------------
# An adapter names each test that starts one of its stack's real tools
# *_with_<tool>, one word after the last _with_ (test.sh, its header), and no
# other test: its tests/names_test.sh holds that with misnamed_tests, over what
# read_tool_tests reads. Both need only bash and awk.
#
# Marks say what starts a tool, one a line, `<tools> <awk regex>`: a function
# whose body matches the regex starts each of <tools> (comma-separated words),
# and so does every function that calls it. A guard keeps its marks out of every
# function body of its own, so it doesn't read its own tests as starting a tool.

# read_tool_tests <marks> <lib> <test file>: each test_* function read in <test
# file>, one a line, as `test<tab><name><tab><the tools it starts>` (space-
# separated, in the marks' order; empty when none), and each other function of
# either file it can't read, as `unread<tab><file><tab><name>`. A body runs from
# the rest of its `name() {` line, at column 0, to the next `}` at column 0 (or
# is the rest of a one-line `name() { ...; }`); comment lines, and a comment
# opening the first line, don't count, and any word of the body is a call. A
# function of <test file> hides one of <lib> of the same name. A function with no
# closing `}` before the next function or the end is unread: a test is left out,
# and a helper printed, since a test calling it might start a tool.
read_tool_tests() {
	FACTORY_TOOL_MARKS="$1" awk '
		BEGIN {
			nm = split(ENVIRON["FACTORY_TOOL_MARKS"], ml, "\n")
			for (i = 1; i <= nm; i++) {
				sp = index(ml[i], " ")
				if (sp < 2) continue
				mark_tools[i] = substr(ml[i], 1, sp - 1); mark_re[i] = substr(ml[i], sp + 1)
				k = split(mark_tools[i], tw, ",")
				for (j = 1; j <= k; j++) if (!(tw[j] in known)) { known[tw[j]] = 1; order[++nt] = tw[j] }
			}
		}
		FNR == 1 { if (open != "") unread_at(open); open = "" }
		/^[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{/ {
			name = $0; sub(/\(.*/, "", name)
			if (open != "") unread_at(open)
			open = name; at[name] = FILENAME; tests[name] = (FILENAME == ARGV[2] && name ~ /^test_/); delete unread[name]
			rest = $0; sub(/^[^{]*\{/, "", rest)
			if (rest ~ /^[ \t]*#/) rest = ""
			body[name] = rest
			if (rest ~ /;[ \t]*\}[ \t]*$/) { read[name] = 1; open = "" }
			else read[name] = 0
			next
		}
		open != "" && /^\}/ { read[open] = 1; open = ""; next }
		open != "" && !/^[ \t]*#/ { body[open] = body[open] " " $0 }
		function unread_at(f) {
			delete body[f]
			if (!tests[f]) unread[f] = at[f]
		}
		END {
			if (open != "") unread_at(open)
			for (f in unread) printf "unread\t%s\t%s\n", unread[f], f
			for (f in body) if (read[f]) {
				for (i = 1; i <= nm; i++) if ((i in mark_re) && body[f] ~ mark_re[i]) {
					k = split(mark_tools[i], tw, ",")
					for (j = 1; j <= k; j++) starts[f, tw[j]] = 1
				}
				b = body[f]; gsub(/[^A-Za-z0-9_]+/, " ", b)
				m = split(b, w, " "); callees[f] = " "
				for (i = 1; i <= m; i++) if (w[i] != f && index(callees[f], " " w[i] " ") == 0) callees[f] = callees[f] w[i] " "
			}
			do {
				more = 0
				for (f in callees) {
					m = split(callees[f], w, " ")
					for (i = 1; i <= m; i++) if (w[i] in callees)
						for (j = 1; j <= nt; j++) if (((w[i], order[j]) in starts) && !((f, order[j]) in starts)) { starts[f, order[j]] = 1; more = 1 }
				}
			} while (more)
			for (f in body) if (tests[f] && read[f]) {
				s = ""
				for (j = 1; j <= nt; j++) if ((f, order[j]) in starts) s = s (s == "" ? "" : " ") order[j]
				printf "test\t%s\t%s\n", f, s
			}
		}
	' "$2" "$3"
}

# defined_tests <test file>: the test_* functions bash defines on sourcing it, as
# test.sh lists them.
defined_tests() {
	(
		# shellcheck disable=SC2046 # one name a word
		unset -f $(declare -F | awk '$3 ~ /^test_/ { print $3 }')
		# shellcheck disable=SC1090 # a test file, by path
		. "$1" > /dev/null 2>&1 < /dev/null
		declare -F | awk '$3 ~ /^test_/ { print $3 }'
	)
}

# misnamed_tests <marks> <lib> <test file...>: each test misnamed, and each test or
# helper unread, one a line as `<file>: <function>: <why>` (a helper of <lib>
# once); nothing when all are named right. A test that starts a tool (marks, as
# read_tool_tests reads them) ends in _with_<a tool it starts>; one that starts
# none ends in no _with_<tool>.
misnamed_tests() {
	local marks="$1" lib="$2" file t found tools list ends tool
	local -a each
	shift 2
	for file in "$@"; do
		found="$(read_tool_tests "$marks" "$lib" "$file")"
		printf '%s\n' "$found" | awk -F '\t' '$1 == "unread" { print $2 "\t" $3 }' | LC_ALL=C sort |
			while IFS=$'\t' read -r where t; do
				echo "$(basename "$where"): $t: can't read its body (from \`$t() {\` to a \`}\` at column 0)"
			done
		while IFS= read -r t; do
			tools="$(printf '%s\n' "$found" | awk -F '\t' -v t="$t" '$1 == "test" && $2 == t { print "read " $3 }')"
			if [ -z "$tools" ]; then
				echo "$(basename "$file"): $t: can't read its body (from \`$t() {\` to a \`}\` at column 0)"
				continue
			fi
			read -ra each <<< "${tools#read}"
			if [ "${#each[@]}" -eq 0 ]; then
				[[ ! $t =~ _with_[a-z0-9]+$ ]] ||
					echo "$(basename "$file"): $t: starts no real tool, so doesn't end in _with_<tool>"
				continue
			fi
			[[ $t =~ _with_([a-z0-9]+)$ && " ${each[*]} " == *" ${BASH_REMATCH[1]} "* ]] && continue
			list="" ends=""
			for tool in "${each[@]}"; do
				if [ -z "$list" ]; then
					list="$tool" ends="_with_$tool"
				elif [ "$tool" = "${each[${#each[@]} - 1]}" ]; then
					list+=" and $tool" ends+=" or _with_$tool"
				else
					list+=", $tool" ends+=", _with_$tool"
				fi
			done
			echo "$(basename "$file"): $t: starts the real $list, so ends in $ends"
		done < <(defined_tests "$file" | LC_ALL=C sort)
	done | awk '!seen[$0]++'
}
