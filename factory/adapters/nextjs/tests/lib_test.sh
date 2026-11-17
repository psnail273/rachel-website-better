# The Next.js tests' own helpers (tests/lib.sh) that start no real tool: the primed
# project's copy and its one build per run, and tether, which stops what a test
# started however the test ends.

NEXTJS_ADAPTER="$FACTORY_CORE/../adapters/nextjs"
. "$NEXTJS_ADAPTER/tests/lib.sh"

# --- link_tree ------------------------------------------------------------------------

# installed_tree <dir>: a project in <dir> as pnpm leaves one: a package file
# linked from a store ($TEST_TMP/store), a package file of the project's own (pnpm
# copies some), node_modules' metadata, a bin, a package's symlink, a source.
installed_tree() {
	local pkg="$1/node_modules/.pnpm/pkg@1.0.0/node_modules/pkg"
	mkdir -p "$TEST_TMP/store" "$pkg" "$1/node_modules/.bin" "$1/src" || fail "could not make $1"
	echo stored > "$TEST_TMP/store/index.js"
	ln "$TEST_TMP/store/index.js" "$pkg/index.js" || fail "could not link from the store"
	echo own > "$pkg/cli.js"
	echo lock > "$1/node_modules/.pnpm/lock.yaml"
	echo modules > "$1/node_modules/.modules.yaml"
	echo bin > "$1/node_modules/.bin/pkg"
	ln -s .pnpm/pkg@1.0.0/node_modules/pkg "$1/node_modules/pkg"
	echo source > "$1/src/a.ts"
	printf '{\n  "projects": {\n    "%s": {}\n  },\n  "lockfiles": {\n    "%s/pnpm-lock.yaml": {},\n    "%s2/pnpm-lock.yaml": {}\n  }\n}\n' \
		"$1" "$1" "$1" > "$1/node_modules/.pnpm-workspace-state-v1.json"
}

# own_copies <from> <to>: every file of the project's own is a copy of its own in
# <to>, which a write in place changes in <to> alone.
own_copies() {
	local pkg=node_modules/.pnpm/pkg@1.0.0/node_modules/pkg f
	for f in "$pkg/cli.js" node_modules/.pnpm/lock.yaml node_modules/.modules.yaml node_modules/.bin/pkg src/a.ts; do
		[ -f "$2/$f" ] && [ ! "$2/$f" -ef "$1/$f" ] || fail "$f is not a copy of its own in $2"
		assert_eq "$(cat "$1/$f")" "$(cat "$2/$f")" "the copy of $f"
		echo changed >> "$2/$f"
		[ "$(wc -l < "$1/$f")" -eq 1 ] || fail "a write to $2's $f reached $1"
	done
}

# The files pnpm linked from its store are links to the original's in the copy;
# every other file is a copy of its own, so a write to one in place reaches no
# other tree; symlinks stay symlinks. So with a copy of the copy, while another
# copy of it is half done (which adds a link to each of its files).
test_link_tree_links_only_what_pnpm_linked_from_its_store() {
	local tmp pkg=node_modules/.pnpm/pkg@1.0.0/node_modules/pkg
	tmp="$(cd "$TEST_TMP" && pwd -P)" # the path pnpm records, which link_tree matches
	installed_tree "$tmp/from"
	mkdir "$tmp/to" "$tmp/busy" "$tmp/again"
	link_tree "$tmp/from" "$tmp/to" || fail "link_tree failed"
	[ "$tmp/to/$pkg/index.js" -ef "$tmp/from/$pkg/index.js" ] || fail "the store's file was copied, not linked"
	cp -al "$tmp/to/." "$tmp/busy/" || fail "could not start another copy"
	link_tree "$tmp/to" "$tmp/again" || fail "link_tree of the copy failed"
	[ "$tmp/again/$pkg/index.js" -ef "$tmp/from/$pkg/index.js" ] || fail "the store's file was copied, not linked, from the copy"
	assert_eq "$(cd "$tmp/from" && find . | sort)" "$(cd "$tmp/again" && find . | sort)" "the copy of the copy's files"
	own_copies "$tmp/from" "$tmp/to"
	own_copies "$tmp/from" "$tmp/again"
	mkdir "$tmp/near" && (cd "$tmp" && link_tree from near) || fail "link_tree of relative paths failed"
	own_copies "$tmp/from" "$tmp/near"
	assert_eq .pnpm/pkg@1.0.0/node_modules/pkg "$(readlink "$tmp/to/node_modules/pkg")" "the package's symlink"
	# pnpm's record of the project's path names the copy's, and nothing else changes.
	assert_eq "{
  \"projects\": {
    \"$tmp/again\": {}
  },
  \"lockfiles\": {
    \"$tmp/again/pnpm-lock.yaml\": {},
    \"$tmp/from2/pnpm-lock.yaml\": {}
  }
}" "$(cat "$tmp/again/node_modules/.pnpm-workspace-state-v1.json")" "the copy's workspace state"
	grep -qF "\"$tmp/to\": {}" "$tmp/to/node_modules/.pnpm-workspace-state-v1.json" || fail "the first copy's workspace state is not its own"
	grep -qF "\"$tmp/from\": {}" "$tmp/from/node_modules/.pnpm-workspace-state-v1.json" || fail "the original's workspace state changed"
}

# --- cached_once ----------------------------------------------------------------------

# blocked_build: a project in $TEST_TMP/project holding a.txt, its build counted by a
# line in $TEST_TMP/../builds, once $TEST_TMP/../go exists; cd there.
blocked_build() {
	echo built >> "$TEST_TMP/../builds"
	wait_until "the build to be let go" test -e "$TEST_TMP/../go"
	mkdir -p "$TEST_TMP/project" && cd "$TEST_TMP/project" && echo built > a.txt || fail "could not build"
}

# counted_build: blocked_build, let go at once.
counted_build() {
	: > "$TEST_TMP/../go"
	blocked_build
}

# While one test builds the project, another that asks for it waits, then copies
# it: one build in the run, and each its own project.
test_cached_once_builds_once_while_the_others_wait() {
	local base="$TEST_TMP/once" one two code1=0 code2=0
	mkdir -p "$base/one" "$base/two" "$base/run"
	export FACTORY_TEST_RUN="$base/run"
	(TEST_TMP="$base/one" cached_once k blocked_build && echo mine > who.txt) &
	one=$!
	wait_until "the first caller to start its build" test -s "$base/builds"
	(TEST_TMP="$base/two" cached_once k blocked_build && echo mine > who.txt) &
	two=$!
	: > "$base/go"
	wait "$one" || code1=$?
	wait "$two" || code2=$?
	assert_eq "0 0" "$code1 $code2" "the callers' exit codes"
	assert_eq 1 "$(wc -l < "$base/builds")" "the builds in one run"
	assert_eq built "$(cat "$base/two/project/a.txt")" "the second caller's copy"
	[ -f "$base/one/project/who.txt" ] && [ -f "$base/two/project/who.txt" ] || fail "a caller had no project of its own"
	[ ! -e "$base/run/fixtures/k/who.txt" ] || fail "a caller's write reached the cached project"
}

# A claim whose test is gone (its build failed, or it was killed) holds no one up:
# the next caller builds its own.
test_cached_once_builds_its_own_when_the_claim_is_dead() {
	local base="$TEST_TMP/dead" gone_pid
	mkdir -p "$base/one" "$base/run/fixtures"
	export FACTORY_TEST_RUN="$base/run"
	bash -c 'exit 0' &
	gone_pid=$!
	wait "$gone_pid"
	ln -s "$gone_pid" "$base/run/fixtures/.k.builder"
	TEST_TMP="$base/one" cached_once k counted_build
	assert_eq 1 "$(wc -l < "$base/builds")" "the builds"
	assert_eq "$base/one/project" "$PWD" "the caller's folder"
	[ -d "$base/run/fixtures/k" ] || fail "the project built was not cached"
}

# --- tether ---------------------------------------------------------------------------

# no_process <pid>: <pid> is no process.
no_process() {
	! kill -0 "$1" 2> /dev/null
}

# A tethered process stops once the shell that tethered it is gone, killed outright
# (KILL) too; and the watcher ends with the process it watches.
test_tether_stops_a_process_once_its_test_is_killed_and_ends_when_it_does() {
	blocking_stand_in "$TEST_TMP/held" "$TEST_TMP/release"
	cat > "$TEST_TMP/a_test.sh" << 'SH'
. "$FACTORY_CORE/tests/lib.sh"
. "$NEXTJS_ADAPTER/tests/lib.sh"
"$TEST_TMP/held" &
tether "$!"
echo "$!" > "$TEST_TMP/watcher.pid"
wait
SH
	local shell held watcher
	NEXTJS_ADAPTER="$NEXTJS_ADAPTER" bash "$TEST_TMP/a_test.sh" > "$TEST_TMP/a_test.out" 2>&1 < /dev/null &
	shell=$!
	wait_until "the held process to start" test -s "$TEST_TMP/held.pid"
	wait_until "the watcher to start" test -s "$TEST_TMP/watcher.pid"
	held="$(cat "$TEST_TMP/held.pid")"
	kill -KILL "$shell"
	wait "$shell" 2> /dev/null
	wait_until "the held process to stop once its test was killed" no_process "$held"
	watcher="$(cat "$TEST_TMP/watcher.pid")"
	wait_until "the watcher to end with it" no_process "$watcher"

	rm -f "$TEST_TMP/held.pid"
	"$TEST_TMP/held" &
	held=$!
	tether "$held"
	watcher=$!
	: > "$TEST_TMP/release"
	wait "$held"
	wait_until "the watcher to end once the process it watches has" no_process "$watcher"
}
