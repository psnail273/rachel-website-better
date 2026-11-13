# install.sh: a clone of the factory's repo (this factory at its root, with a stub
# adapter `fake` made from the fixture project's step scripts) installs itself
# into a project's factory/ and adopts it, in one step.

# factory_clone: $TEST_TMP/factory.git, a bare repo holding this factory at its
# root on main, tagged v0.1.0; $TEST_TMP/clone, a clone of it checked out at the
# tag. The fake adapter has a --new skeleton (a .gitignore and project.cfg).
factory_clone() {
	isolate_git
	export FAKETOOL_VERSION=1.2.3
	unset FACTORY_PROJECT FACTORY_LABEL_CMD FACTORY_BASE FACTORY_UPSTREAM FACTORY_INSTALL FACTORY_INSTALL_TAG FACTORY_INSTALL_UPSTREAM
	local src="$TEST_TMP/src"
	mkdir -p "$src/adapters/fake/new" || fail "could not make the factory"
	copy_factory "$src" || fail "could not copy the factory"
	cp -R "$FIXTURE_SRC/tools" "$src/adapters/fake/" || fail "could not make the fake adapter"
	printf '/.fixture/\n' > "$src/adapters/fake/new/.gitignore.txt"
	printf 'name=<project>\n' > "$src/adapters/fake/new/project.cfg.txt"
	git -C "$src" init -q -b main && git -C "$src" add -A && git -C "$src" commit -q -m "factory 0.1.0" &&
		git -C "$src" tag -a v0.1.0 -m "factory 0.1.0" || fail "could not commit the factory"
	git init -q --bare -b main "$TEST_TMP/factory.git" &&
		git -C "$src" push -q "$TEST_TMP/factory.git" main v0.1.0 2> /dev/null || fail "could not push the factory"
	git clone -q -b v0.1.0 "$TEST_TMP/factory.git" "$TEST_TMP/clone" 2> /dev/null || fail "could not clone the factory"
}

# a_project [name]: $TEST_TMP/<name, default game>, a git repo on dev with one
# commit (a source file and a .gitignore for the fixture's own files); cd there.
a_project() {
	local dir="$TEST_TMP/${1:-game}"
	mkdir -p "$dir/src" && cd "$dir" || fail "could not make the project"
	echo one > src/a.txt
	printf '/.fixture/\n' > .gitignore
	git init -q -b dev . && git add -A && git commit -q -m project || fail "could not commit the project"
}

install() {
	run_cmd bash "$TEST_TMP/clone/core/install.sh" "$@"
}

# The clone's tracked files, and the project's factory/ files, one path a line.
clone_files() {
	git -C "$TEST_TMP/clone" ls-files | LC_ALL=C sort
}
factory_files() {
	(cd factory && find . -type f | sed 's#^\./##' | LC_ALL=C sort)
}

test_install_copies_the_clone_and_adopts_an_existing_project() {
	factory_clone
	a_project
	install "$PWD" fake
	assert_status 0
	assert_eq "$(clone_files)" "$(factory_files)" "factory/ doesn't hold the clone's tracked files"
	[ ! -e factory/.git ] || fail "factory/ holds the clone's .git"
	cmp -s "$TEST_TMP/clone/core/adopt.sh" factory/core/adopt.sh || fail "factory/core/adopt.sh differs from the clone's"
	assert_eq "version $(cat factory/VERSION)
adapter fake
tag v0.1.0
upstream $TEST_TMP/factory.git" "$(head -n 4 tools/verify/factory-version)" "factory-version"
	[ -f tools/verify/ratchet/baseline.txt ] || fail "no Baseline: not adopted"
	assert_eq "" "$(git status --porcelain | grep -v '^[AM] ')" "the install left files unstaged"
	assert_eq 1 "$(git rev-list --count HEAD)" "the install committed"
	stderr_has "installed; review and commit the result"
}

# The recorded upstream is what a later sync reads: here, nothing to sync to v0.1.0.
test_an_installed_project_syncs_from_the_recorded_upstream() {
	factory_clone
	a_project
	install "$PWD" fake
	assert_status 0
	git commit -q -m adopt || fail "could not commit the adoption"
	run_cmd bash factory/core/sync.sh v0.1.0
	assert_status 0
	assert_eq "" "$(git status --porcelain)" "a sync to the installed tag changed the tree"
}

test_install_new_lays_the_skeleton_in_an_empty_project() {
	factory_clone
	mkdir -p "$TEST_TMP/fresh" && cd "$TEST_TMP/fresh" || fail "no project folder"
	git init -q -b dev . && git commit -q --allow-empty -m "empty" || fail "could not make the project"
	install "$PWD" fake --new
	assert_status 0
	assert_eq "name=fresh" "$(cat project.cfg)" "the skeleton wasn't laid"
	assert_eq "tag v0.1.0" "$(grep '^tag ' tools/verify/factory-version)" "the tag line"
	[ -f tools/verify/ratchet/baseline.txt ] || fail "no Baseline: not adopted"
}

test_a_clone_off_a_tag_or_without_origin_records_neither_line() {
	factory_clone
	git -C "$TEST_TMP/clone" checkout -q --detach && git -C "$TEST_TMP/clone" commit -q --allow-empty -m "past the tag" ||
		fail "could not move the clone"
	git -C "$TEST_TMP/clone" remote remove origin || fail "could not drop origin"
	a_project
	install "$PWD" fake
	assert_status 0
	! grep -q '^\(tag\|upstream\) ' tools/verify/factory-version || fail "a tag or upstream line was recorded"
	stderr_has "the clone's HEAD is no tag"
	stderr_has "the clone has no origin remote"
}

test_install_refuses_a_dirty_clone() {
	factory_clone
	echo stray > "$TEST_TMP/clone/stray.txt"
	a_project
	install "$PWD" fake
	assert_status 1
	stderr_has "the clone $TEST_TMP/clone has uncommitted or untracked files"
	[ ! -e factory ] || fail "the refused install copied the factory"
}

test_install_refuses_a_project_with_a_factory_or_a_record() {
	factory_clone
	a_project
	mkdir factory && echo x > factory/VERSION && git add -A && git commit -q -m "a factory" || fail "could not commit"
	install "$PWD" fake
	assert_status 1
	stderr_has "has a factory/ already"
	a_project other
	mkdir -p tools/verify && echo "version 0.0.1" > tools/verify/factory-version && git add -A && git commit -q -m record ||
		fail "could not commit"
	install "$PWD" fake
	assert_status 1
	stderr_has "has adopted already (tools/verify/factory-version)"
	[ ! -e factory ] || fail "the refused install copied the factory"
}

test_install_refuses_what_is_no_git_checkout_or_not_its_top() {
	factory_clone
	mkdir -p "$TEST_TMP/plain"
	install "$TEST_TMP/plain" fake
	assert_status 1
	stderr_has "$TEST_TMP/plain is not a git checkout"
	[ ! -e "$TEST_TMP/plain/factory" ] || fail "the refused install copied the factory"
	a_project
	install "$PWD/src" fake
	assert_status 1
	stderr_has "is not the top of its git checkout; install into $PWD"
	install "$TEST_TMP/missing" fake
	assert_status 1
	stderr_has "no folder $TEST_TMP/missing"
}

test_install_refuses_a_dirty_project() {
	factory_clone
	a_project
	echo two > src/a.txt
	install "$PWD" fake
	assert_status 1
	stderr_has "the project's tree is dirty"
	[ ! -e factory ] || fail "the refused install copied the factory"
}

# install.sh run from a project's vendored factory/ is no clone of the factory repo.
test_install_refuses_to_run_from_a_vendored_factory() {
	factory_clone
	a_project
	install "$PWD" fake
	assert_status 0
	git commit -q -m adopt || fail "could not commit"
	a_project other
	run_cmd bash "$TEST_TMP/game/factory/core/install.sh" "$PWD" fake
	assert_status 1
	stderr_has "is no clone of the factory repo"
}

test_a_bad_call_or_an_unknown_adapter_is_a_usage_error() {
	factory_clone
	a_project
	install "$PWD"
	assert_status 2
	install "$PWD" fake --old
	assert_status 2
	install "$PWD" --new
	assert_status 2
	install "$PWD" nope
	assert_status 2
	stderr_has "no adapter 'nope'"
	assert_eq "" "$(git status --porcelain)" "a usage error changed the project"
}

# An adoption that fails before it records anything leaves the project as it
# was, factory/ removed; one that stops at prepare keeps what it seeded.
test_a_failed_adoption_removes_the_factory_and_a_stopped_one_keeps_it() {
	factory_clone
	a_project
	echo "the project's own" > project.cfg && git add -A && git commit -q -m "own project.cfg" || fail "could not commit"
	install "$PWD" fake --new
	assert_status 1
	stderr_has "the project is as it was, without factory/"
	assert_eq "" "$(git status --porcelain)" "the failed install left files behind"
	mkdir -p .fixture && echo "src/a.txt:1 fake-prepare broken" > .fixture/fail-prepare
	install "$PWD" fake
	assert_status 1
	stderr_has "run bash factory/core/adopt.sh fake in $PWD"
	assert_eq "upstream $TEST_TMP/factory.git" "$(grep '^upstream ' tools/verify/factory-version)" "the stopped adoption's upstream line"
	rm .fixture/fail-prepare
	run_cmd bash factory/core/adopt.sh fake
	assert_status 0
	stderr_has "resuming"
}

# A project whose git ignores the executable bit (core.filemode false, as on
# Windows) still stages the factory's scripts with the clone's modes, so its
# factory/ tree is the factory repo's.
test_install_keeps_the_clones_file_modes_where_git_ignores_them() {
	factory_clone
	a_project
	git config core.filemode false
	install "$PWD" fake
	assert_status 0
	assert_eq "$(git -C "$TEST_TMP/clone" ls-tree HEAD core/test.sh | cut -d ' ' -f 1)" "$(git ls-files -s factory/core/test.sh | cut -d ' ' -f 1)" "factory/core/test.sh's mode"
	assert_eq "$(git -C "$TEST_TMP/clone" rev-parse 'HEAD^{tree}')" "$(git write-tree --prefix=factory/)" "factory/'s tree"
}

# A relative origin is recorded as the path it names, so the project can fetch it.
test_install_records_a_relative_origin_as_an_absolute_path() {
	factory_clone
	git -C "$TEST_TMP/clone" remote set-url origin ../factory.git || fail "could not set a relative origin"
	mkdir -p "$TEST_TMP/deep/er" && cd "$TEST_TMP/deep/er" || fail "no folder"
	a_project deep/er/game
	install "$PWD" fake
	assert_status 0
	assert_eq "upstream $TEST_TMP/factory.git" "$(grep '^upstream ' tools/verify/factory-version)" "the upstream line"
	git commit -q -m adopt || fail "could not commit"
	run_cmd bash factory/core/sync.sh v0.1.0
	assert_status 0
}

# A relative origin may name a bundle, a file: its folder is resolved, not it.
test_install_records_a_relative_bundle_origin_as_an_absolute_path() {
	factory_clone
	git -C "$TEST_TMP/factory.git" bundle create -q "$TEST_TMP/factory.bundle" --all 2> /dev/null || fail "could not bundle"
	git -C "$TEST_TMP/clone" remote set-url origin ../factory.bundle || fail "could not set a bundle origin"
	a_project
	install "$PWD" fake
	assert_status 0
	assert_eq "upstream $TEST_TMP/factory.bundle" "$(grep '^upstream ' tools/verify/factory-version)" "the upstream line"
}

# An exported CDPATH whose folder shadows the origin's does not change it.
test_install_resolves_a_relative_origin_whatever_cdpath_says() {
	factory_clone
	mkdir -p "$TEST_TMP/clone/remotes" "$TEST_TMP/shadow/remotes" || fail "no folders"
	git clone -q --bare "$TEST_TMP/factory.git" "$TEST_TMP/clone/remotes/factory.git" 2> /dev/null || fail "could not clone"
	echo /remotes/ >> "$TEST_TMP/clone/.git/info/exclude"
	git -C "$TEST_TMP/clone" remote set-url origin remotes/factory.git || fail "could not set the origin"
	a_project
	run_cmd env CDPATH="$TEST_TMP/shadow" bash "$TEST_TMP/clone/core/install.sh" "$PWD" fake
	assert_status 0
	assert_eq "upstream $TEST_TMP/clone/remotes/factory.git" "$(grep '^upstream ' tools/verify/factory-version)" "the upstream line"
}

# workspace_clone: factory_clone's repo converted to the workspace layout: the
# factory under factory/, beside the workspace's own files (.factory-repo,
# CLAUDE.md, .gitignore, a skill copy), on main, tagged v0.2.0; $TEST_TMP/clone
# checked out at that tag.
workspace_clone() {
	factory_clone
	local src="$TEST_TMP/src"
	(
		cd "$src" && mkdir factory &&
			git ls-tree -z --name-only HEAD | xargs -0 -I{} git mv {} factory/{} &&
			echo "the workspace" > .factory-repo && echo "# for the factory repo" > CLAUDE.md &&
			printf '/local.env\n' > .gitignore && mkdir -p .claude/skills/s && echo skill > .claude/skills/s/SKILL.md &&
			git add -A && git commit -q -m "workspace layout" && git tag -a v0.2.0 -m "factory 0.2.0" &&
			git push -q "$TEST_TMP/factory.git" main v0.2.0 2> /dev/null
	) || fail "could not convert the factory repo"
	rm -rf "$TEST_TMP/clone"
	git clone -q -b v0.2.0 "$TEST_TMP/factory.git" "$TEST_TMP/clone" 2> /dev/null || fail "could not clone the factory"
	echo "GODOT_BIN=/opt/godot" > "$TEST_TMP/clone/local.env"
}

# From the workspace layout, install.sh copies the clone's factory/ alone: never
# the workspace's files, nor an ignored file of the clone.
test_install_from_a_workspace_clone_copies_its_factory_folder_alone() {
	workspace_clone
	a_project
	run_cmd bash "$TEST_TMP/clone/factory/core/install.sh" "$PWD" fake
	assert_status 0
	assert_eq "$(git -C "$TEST_TMP/clone" ls-tree -r --name-only HEAD:factory | LC_ALL=C sort)" "$(factory_files)" "factory/ doesn't hold the clone's factory/"
	assert_eq "$(git -C "$TEST_TMP/clone" rev-parse HEAD:factory)" "$(git write-tree --prefix=factory/)" "factory/'s tree"
	for f in .factory-repo CLAUDE.md local.env factory/.factory-repo factory/CLAUDE.md factory/factory factory/local.env; do
		[ ! -e "$f" ] || fail "the install copied $f"
	done
	assert_eq "tag v0.2.0
upstream $TEST_TMP/factory.git" "$(grep '^\(tag\|upstream\) ' tools/verify/factory-version)" "factory-version"
	git commit -q -m adopt || fail "could not commit the adoption"
	run_cmd bash factory/core/sync.sh v0.2.0
	assert_status 0
	assert_eq "" "$(git status --porcelain)" "a sync to the installed tag changed the tree"
}

# install.sh at factory/core/ without the marker beside factory/ is a project's
# vendored copy, never a workspace clone.
test_install_refuses_a_workspace_clone_without_its_marker() {
	workspace_clone
	git -C "$TEST_TMP/clone" rm -q .factory-repo && git -C "$TEST_TMP/clone" commit -q -m "no marker" || fail "could not drop the marker"
	a_project
	run_cmd bash "$TEST_TMP/clone/factory/core/install.sh" "$PWD" fake
	assert_status 1
	stderr_has "is no clone of the factory repo"
	[ ! -e factory ] || fail "the refused install copied the factory"
}
