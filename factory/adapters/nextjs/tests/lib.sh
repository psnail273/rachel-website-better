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
# holding the pinned Playwright's Chromium (prime-store.sh primes it too), and
# points Playwright there.
#
# A test that calls needs_node, needs_store or needs_browser, itself or through a
# helper, runs a real tool: its name ends in _with_node, so test.sh starts it
# first, and no other test's does (names_test.sh holds both).

NEXTJS_ADAPTER="$FACTORY_CORE/../adapters/nextjs"
NEXTJS_FIXTURES="$NEXTJS_ADAPTER/tests/fixture"
[ -z "${TEST_TMP:-}" ] || export TEST_TMP

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

# needs_browser: needs_store, and Chromium for the pinned Playwright in
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
