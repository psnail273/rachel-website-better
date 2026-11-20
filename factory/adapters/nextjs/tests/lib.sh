# Helpers for the Next.js adapter's tests, sourced by each Next.js *_test.sh after
# the Core's tests/lib.sh.
#
# No test reaches the network. A test that needs Node and pnpm calls needs_node
# and skips without them (NODE_BIN and PNPM_BIN, else on PATH), and fails, naming
# both versions, when that Node isn't the one tools/verify/pins names: a skip would
# let a land pass with those tests unrun. (pnpm needs no such check: it switches
# itself to package.json's packageManager.) One that needs the
# skeleton's packages calls needs_store, which skips without FACTORY_PNPM_STORE, a
# pnpm store primed with them (tests/prime-store.sh), and from then on points
# every pnpm the test runs at that store, offline, with no registry to fall back
# on: bootstrap's plain install too. Playwright gets no download host either, and
# a browsers folder of the test's own (empty) unless the test calls
# needs_browser, which skips without FACTORY_PLAYWRIGHT_BROWSERS, a folder
# holding the pinned Playwright's Chromium, Firefox and WebKit (prime-store.sh
# primes it too), and points Playwright there.
#
# A test that calls needs_node, needs_store or needs_browser, itself or through a
# helper, runs a real tool: its name ends in _with_node, so test.sh starts it
# first, and no other test's does (names_test.sh holds both).

NEXTJS_ADAPTER="$FACTORY_CORE/../adapters/nextjs"
NEXTJS_FIXTURES="$NEXTJS_ADAPTER/tests/fixture"
[ -z "${TEST_TMP:-}" ] || export TEST_TMP

# Each test's next builds take a build lock of the test's own (_nextjs.sh), never
# the machine's: a stand-in build blocking in one test holds up no real gate.
[ -z "${TEST_TMP:-}" ] || export FACTORY_BUILD_LOCK="$TEST_TMP/next-build.lock"
# So do their gate slots (_nextjs.sh's pool): a test's smoke or mutate never
# waits on a real gate's, nor holds one up.
[ -z "${TEST_TMP:-}" ] || export FACTORY_GATE_POOL="$TEST_TMP/gate-slots"

# needs_node: skip unless Node and pnpm run here; fail unless that Node is the
# one the adapter's tools/verify/pins names (node_is_pinned). From then on the
# test runs on the PATH tools/verify/_nextjs.sh gives the steps (node_bins_first),
# so a bare node, or a script that starts #!/usr/bin/env node, runs that Node.
needs_node() {
	command -v "${NODE_BIN:-node}" > /dev/null 2>&1 || skip "no Node (NODE_BIN, or node on PATH)"
	command -v "${PNPM_BIN:-pnpm}" > /dev/null 2>&1 || skip "no pnpm (PNPM_BIN, or pnpm on PATH)"
	node_is_pinned "$NEXTJS_ADAPTER/tools/verify/pins"
	node_bins_first
}

# node_bins_first: PNPM_BIN's folder, then NODE_BIN's, first on PATH when they
# name a path, as tools/verify/_nextjs.sh puts them. Each test runs in its own
# subshell, so the PATH ends with the test.
node_bins_first() {
	local bin
	for bin in "${PNPM_BIN:-}" "${NODE_BIN:-}"; do
		case "$bin" in */*) PATH="$(dirname "$bin"):$PATH" ;; esac
	done
	export PATH
}

# node_is_pinned <pins>: fail unless the Node the steps run is the version the
# pins file <pins> names (its node line, read as factory/core/pins.sh reads it),
# naming both and the fix. That Node is "${NODE_BIN:-node}" --version, less the
# v, on the PATH tools/verify/_nextjs.sh gives the steps: PNPM_BIN's folder, then
# NODE_BIN's, first when they name a path. A test may call it with a stand-in
# Node: it starts no other.
node_is_pinned() {
	local pins="$1" pin found which="the node on PATH"
	pin="$(tr -d '\r' < "$pins" | awk '$1 == "node" { print $2; exit }')"
	[ -n "$pin" ] || fail "no node line in $pins"
	found="$(
		node_bins_first
		"${NODE_BIN:-node}" --version 2> /dev/null | tr -d '\r' | head -n 1
	)"
	found="${found#v}"
	case "${PNPM_BIN:-}" in */*) which="the node on PATH, PNPM_BIN's folder first" ;; esac
	[ -z "${NODE_BIN:-}" ] || which="NODE_BIN=$NODE_BIN"
	[ "$found" = "$pin" ] ||
		fail "Node ${found:-(no version printed)} runs here ($which), but the Next.js adapter's tools/verify/pins names $pin: put Node $pin first on PATH, or name it in NODE_BIN"
}

# needs_store: needs_node, and a primed pnpm store in FACTORY_PNPM_STORE; pnpm
# installs from it alone from here on.
needs_store() {
	needs_node
	[ -n "${FACTORY_PNPM_STORE:-}" ] || skip "FACTORY_PNPM_STORE is not set (prime one: bash factory/adapters/nextjs/tests/prime-store.sh <dir>)"
	[ -d "$FACTORY_PNPM_STORE" ] || skip "FACTORY_PNPM_STORE '$FACTORY_PNPM_STORE' is not a folder"
	export pnpm_config_store_dir="$FACTORY_PNPM_STORE" pnpm_config_offline=true
	export pnpm_config_registry=http://127.0.0.1:9/ pnpm_config_update_notifier=false
	export NEXT_TELEMETRY_DISABLED=1
	export PLAYWRIGHT_DOWNLOAD_HOST=http://127.0.0.1:9 PLAYWRIGHT_BROWSERS_PATH="$TEST_TMP/no-browsers"
}

# needs_browser: needs_store, and the browsers for the pinned Playwright in
# FACTORY_PLAYWRIGHT_BROWSERS, which Playwright uses from here on.
needs_browser() {
	needs_store
	[ -n "${FACTORY_PLAYWRIGHT_BROWSERS:-}" ] || skip "FACTORY_PLAYWRIGHT_BROWSERS is not set (prime one: bash factory/adapters/nextjs/tests/prime-store.sh <store> <browsers>)"
	[ -d "$FACTORY_PLAYWRIGHT_BROWSERS" ] || skip "FACTORY_PLAYWRIGHT_BROWSERS '$FACTORY_PLAYWRIGHT_BROWSERS' is not a folder"
	export PLAYWRIGHT_BROWSERS_PATH="$FACTORY_PLAYWRIGHT_BROWSERS"
}

# lay_skeleton <dir> [name]: the adapter's skeleton (new/) in <dir>, as adoption
# lays it: each file without its .txt, with <project> as <name> (default skel).
lay_skeleton() {
	local f
	mkdir -p "$1" || fail "could not make $1"
	while IFS= read -r f; do
		mkdir -p "$1/$(dirname "$f")"
		sed "s/<project>/${2:-skel}/g" "$NEXTJS_ADAPTER/new/$f" > "$1/${f%.txt}" || fail "could not copy $f"
	done < <(cd "$NEXTJS_ADAPTER/new" && find . -type f | sed 's#^\./##')
}

# skeleton_project: $TEST_TMP/project, a git repo holding the skeleton, the
# adapter's ARCHITECTURE.md and tools/verify (with an empty local.env), and the
# Core where the steps look for it; cd there. It installs nothing: prepare does.
skeleton_project() {
	isolate_git
	lay_skeleton "$TEST_TMP/project"
	cd "$TEST_TMP/project" || fail "could not enter the project"
	cp "$NEXTJS_ADAPTER/ARCHITECTURE.md" ARCHITECTURE.md || fail "could not copy ARCHITECTURE.md"
	mkdir -p tools && cp -R "$NEXTJS_ADAPTER/tools/verify" tools/verify || fail "could not copy the adapter"
	: > tools/verify/local.env
	echo /tools/verify/local.env >> .gitignore
	git init -q -b dev . || fail "git init failed"
}

# add_fixture <fixture> <path>: tests/fixture/<fixture> (stored with .txt, so no
# tool reads it where it's stored) at <path> in the project.
add_fixture() {
	mkdir -p "$(dirname "$2")" && cp "$NEXTJS_FIXTURES/$1" "$2" || fail "could not copy the fixture $1"
}

# step <name> [args...]: run the step script on the current project, as the
# runner would, with run_cmd.
step() {
	local name="$1"
	shift
	run_cmd bash "tools/verify/$name" "$@"
}

# --- the primed project ---------------------------------------------------------------
# The skeleton, installed and prepared, is what most of the adapter's real tests
# start from; installing it is most of what they take. primed_project builds it
# once per test.sh run and copies it into each test that asks.

# primed_project: skeleton_project, prepared (packages installed, route types
# generated) with no finding, or fail; cd there. The test calls needs_store (or
# needs_browser) first. It is built once per test.sh run (cached_once) and
# copied (link_tree), so each test has a tree of its own; a test that needs one
# with nothing installed starts from skeleton_project instead.
primed_project() {
	isolate_git
	cached_once nextjs-primed build_primed
}

# build_primed: primed_project's project, built in $TEST_TMP/project.
build_primed() {
	skeleton_project
	step prepare
	# shellcheck disable=SC2154 # out and status: set by run_cmd, in factory/core/tests/lib.sh
	[ "$status" -eq 0 ] && [ -z "$out" ] || fail "prepare on the skeleton: status $status: $out"$'\n'"$(tail -n 20 "$TEST_TMP/stderr")"
}

# cached_once <key> <builder> [args...]: cached_project, copying by link_tree, but
# the run's tests wait while one of them builds <key> instead of each building its
# own at once: the first to claim the key (a symlink to its shell's pid, which ln
# makes atomically) builds, and the others wait until it has published the
# project, or its shell is gone (its build failed, or it was killed), then copy
# it, or build their own as cached_project does. They wait three hang guards at
# most, then build their own too: a slow build never fails another test.
cached_once() {
	# shellcheck disable=SC2034 # CACHED_COPY: read by cached_project
	local key="$1" dir="${FACTORY_TEST_RUN:-}/fixtures" end CACHED_COPY=link_tree
	if [ -n "${FACTORY_TEST_RUN:-}" ] && [ -d "$FACTORY_TEST_RUN" ] && [ ! -e "$dir/$key" ]; then
		mkdir -p "$dir" || fail "could not make $dir"
		if ! ln -s "$BASHPID" "$dir/.$key.builder" 2> /dev/null; then
			end=$((SECONDS + TEST_HANG_GUARD * 3))
			until [ -e "$dir/$key" ] || ! kill -0 "$(readlink "$dir/.$key.builder")" 2> /dev/null || [ "$SECONDS" -ge "$end" ]; do
				sleep 0.1
			done
		fi
	fi
	cached_project "$@"
}

# link_tree <from> <to>: cached_project's copy of a project with its packages
# installed. The files pnpm linked from its store (under node_modules/.pnpm, with
# a link of the store's besides <from>'s) are hard links to <from>'s, as they are
# to the store's already, so a test can no more change them than it could the
# store's; every other file is a copy of its own, which a test may change in
# place: the sources, .next, node_modules' metadata and bins, the install record.
# A copy of the packages (cp -a) is half a gigabyte and a minute per test. Where cp
# can't link (cp -l), it copies.
#
# Which files are the project's own is read from <from>'s link counts only where
# no other copy can be running: when <from> is a test's own project, as it is when
# cached_project caches it. That copy keeps the list (LINK_TREE_OWN), and a copy
# of the cache breaks the links of the files it lists, however many other tests
# are copying the cache at once (each adds a link to every file) - and leaves
# the list out.
#
# pnpm's record of the project's own path (node_modules/.pnpm-workspace-state-v1.json)
# then names <to>: naming another folder, it makes the next pnpm install link
# every bin again, over a test's stand-ins.
LINK_TREE_OWN=node_modules/.link-tree-own
link_tree() {
	local own="$1/$LINK_TREE_OWN" list="$2.own"
	if [ ! -f "$own" ]; then
		(cd "$1" && find . -type f \( ! -path "./node_modules/.pnpm/*" -o -links 1 \) -print0) > "$list" || return 1
		own="$list"
	fi
	if cp -al "$1/." "$2/" 2> /dev/null; then
		rm -f "$2/$LINK_TREE_OWN"
		(cd "$2" && xargs -0 sh -c 'for f; do cp -p "$f" "$f.copy" && mv -f "$f.copy" "$f" || exit 1; done' link_tree) < "$own" || return 1
	else
		find "$2" -mindepth 1 -delete && cp -a "$1/." "$2/" && rm -f "$2/$LINK_TREE_OWN" || return 1
	fi
	if [ "$own" = "$list" ]; then
		if [ -d "$2/node_modules" ]; then mv -f "$list" "$2/$LINK_TREE_OWN" || return 1; else rm -f "$list"; fi
	fi
	local state="$2/node_modules/.pnpm-workspace-state-v1.json" from to text
	[ -f "$state" ] || return 0
	from="$(cd "$1" && pwd -P)" && to="$(cd "$2" && pwd -P)" && text="$(cat "$state")" || return 1
	text="${text//"\"$from\""/"\"$to\""}"
	printf '%s\n' "${text//"\"$from/"/"\"$to/"}" > "$state.copy" && touch -r "$state" "$state.copy" && mv -f "$state.copy" "$state"
}

# --- background processes -------------------------------------------------------------

# tether <pid>: the background process <pid> ends with the test however the test
# ends. A test's EXIT trap stops what it started, and test.sh's TERM to the test's
# process group reaches what runs in that group; but a test killed outright (KILL)
# runs no trap, and a process in a group of its own (set -m) misses that TERM. So a
# watcher, in a group of its own that no signal to the test's reaches, TERMs <pid>
# once the shell that called tether is gone, KILLs it 10s later if it is still
# there (as test.sh does), and ends when <pid> does.
tether() {
	local shell="$BASHPID" flags="$-"
	set -m
	bash -c '
		while kill -0 "$1" 2> /dev/null; do
			if ! kill -0 "$2" 2> /dev/null; then
				kill -TERM "$1" 2> /dev/null
				n=0
				while kill -0 "$1" 2> /dev/null && [ "$n" -lt 100 ]; do
					sleep 0.1
					n=$((n + 1))
				done
				kill -KILL "$1" 2> /dev/null
				exit 0
			fi
			sleep 0.1
		done' tether "$1" "$shell" > /dev/null 2>&1 < /dev/null &
	case "$flags" in *m*) ;; *) set +m ;; esac
}

# fixture_server <script> <port> <folder>: the Scenario fixture server <script> (a
# _scenario_fixtures.mjs) on 127.0.0.1:<port>, serving <folder>, in the
# background, its output in <folder>.log; once it listens. Its pid is in $server, a
# global, so the EXIT trap this sets, which runs after the calling test returns,
# still reads it, and it is tethered.
fixture_server() {
	node "$1" "$2" "$3" > "$3.log" 2>&1 < /dev/null &
	server=$!
	trap 'kill "$server" 2> /dev/null; wait "$server"' EXIT
	tether "$server"
	wait_until "the fixture server to listen on $2" grep -qx "listening on http://127.0.0.1:$2" "$3.log"
}
