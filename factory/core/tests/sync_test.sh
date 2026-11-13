# sync.sh: an Adopted project (adopt_project, then adopt.sh, committed) updated to
# a release v2 of its factory, from an upstream repo whose v1 is the vendored copy.

# v2_release: the release's changes, made inside a factory folder.
v2_release() {
	echo 9.9.9 > VERSION
	echo "- **New:** from v2." >> core/templates/agents-section.md
	sed -i 's/NotebookRead|LS)/NotebookRead|LS|Task)/' core/hooks/claude-hooks.json
	echo "# v2 lint" >> adapters/fake/tools/verify/lint
	echo "v2 line" >> skills/factory-run/SKILL.md
	echo "v2 line" >> skills/factory-run/editor.md
	mkdir -p skills/v2-skill && echo "a v2 skill" > skills/v2-skill/SKILL.md
	echo "echo v2 entry point" >> core/templates/verify.sh
	rm core/rubric.sh
	! declare -F v2_extra > /dev/null || v2_extra
}

# make_upstream [root|workspace]: $TEST_TMP/upstream, a git repo holding the
# project's factory/ tagged v1, then v2_release tagged v2; FACTORY_UPSTREAM
# points at it. With `root` the factory sits at the repo's root (the factory
# repo's root layout); with `workspace` it holds the factory repo's workspace
# files at its root too (.factory-repo, CLAUDE.md, README.md, a skill copy
# that differs from the factory's).
make_upstream() {
	local up="$TEST_TMP/upstream" dir="$TEST_TMP/upstream/factory"
	[ "${1:-}" = root ] && dir="$up"
	mkdir -p "$dir" && cp -R factory/. "$dir/" || fail "could not copy the factory upstream"
	if [ "${1:-}" = workspace ]; then
		echo "the workspace" > "$up/.factory-repo" && echo "# CLAUDE.md for the factory repo" > "$up/CLAUDE.md" &&
			echo "# the workspace" > "$up/README.md" && mkdir -p "$up/.claude/skills/factory-amend" &&
			echo "the workspace's copy" > "$up/.claude/skills/factory-amend/SKILL.md" || fail "could not write the workspace"
	fi
	git -C "$up" init -q -b main && git -C "$up" add -A && git -C "$up" commit -q -m v1 && git -C "$up" tag v1 ||
		fail "could not make v1 upstream"
	(cd "$dir" && v2_release) || fail "could not make the v2 release"
	git -C "$up" add -A && git -C "$up" commit -q -m v2 && git -C "$up" tag v2 || fail "could not tag v2 upstream"
	export FACTORY_UPSTREAM="$up"
}

sync() {
	run_cmd bash factory/core/sync.sh "$@"
}

# tree_sums [dir...]: every file under the dirs with its blob id, sorted.
tree_sums() {
	find "$@" -type f | LC_ALL=C sort | while IFS= read -r f; do
		printf '%s %s\n' "$(git hash-object "$f")" "$f"
	done
}

# assert_factory_is <dir>: factory/ holds exactly the files of <dir>, byte for byte.
assert_factory_is() {
	assert_eq "$(cd "$1" && find . -path ./.git -prune -o -type f -print | sed 's#^\./##' | LC_ALL=C sort)" \
		"$(cd factory && find . -type f | sed 's#^\./##' | LC_ALL=C sort)" "factory/ doesn't hold the tag's files"
	local f
	for f in $(cd factory && find . -type f | sed 's#^\./##'); do
		cmp -s "$1/$f" "factory/$f" || fail "factory/$f differs from the tag's"
	done
}

test_sync_copies_the_tags_factory_and_records_it() {
	adopted
	make_upstream
	sync v2
	assert_status 0
	assert_factory_is "$TEST_TMP/upstream/factory"
	[ ! -e factory/core/rubric.sh ] || fail "a file the tag dropped is still vendored"
	assert_eq "version 9.9.9"$'\n'"adapter fake"$'\n'"tag v2" "$(head -n 3 tools/verify/factory-version)" "factory-version"
	assert_eq "file $(git hash-object factory/VERSION) factory/VERSION" \
		"$(grep ' factory/VERSION$' tools/verify/factory-version)" "the record of factory/VERSION"
	assert_eq "" "$(git status --porcelain | grep -v '^[AMDR] ')" "the sync left files unstaged"
	stderr_has "factory/ is now version 9.9.9 (tag v2; was 0.1.0)"
}

test_step_scripts_are_byte_identical_after_a_sync() {
	adopted
	echo "# the project's own lint" >> tools/verify/lint
	git commit -q -am "own lint" || fail "could not commit"
	before="$(tree_sums tools/verify | grep -v ' tools/verify/factory-version$')"
	make_upstream
	sync v2
	assert_status 0
	assert_eq "$before" "$(tree_sums tools/verify | grep -v ' tools/verify/factory-version$')" "sync touched tools/verify/"
	assert_line "diff --git was/tools/verify/lint now/tools/verify/lint"
	assert_line "+# v2 lint"
	stderr_has "the fake adapter's templates changed; port what fits into tools/verify/ by hand"
}

test_sync_rewrites_the_hook_config_and_the_agents_section() {
	adopted
	make_upstream
	sync v2
	assert_status 0
	grep -qF 'NotebookRead|LS|Task)' .claude/settings.json || fail "the hook config wasn't rewritten"
	grep -qF '"model": "claude-opus-5-5"' .claude/settings.json || fail "the settings lack the main model"
	grep -qxF -- "- **New:** from v2." AGENTS.md || fail "the AGENTS.md section wasn't rewritten"
	grep -qF "The project's own words." AGENTS.md || fail "the project's AGENTS.md text is gone"
	grep -q '"A": "1"' .claude/settings.json || fail "the settings lost their env"
	run_cmd bash factory/core/hooks.sh check
	assert_status 0
	run_cmd bash factory/core/agents.sh check
	assert_status 0
}

# A project on a release with the Cursor Editor loses its generated files.
test_sync_removes_the_retired_cursor_files() {
	adopted
	mkdir -p .cursor
	printf '{\n  "hooks": {\n    "stop": [{ "command": "bash factory/core/hooks/cursor-stop.sh" }]\n  }\n}\n' > .cursor/hooks.json
	printf '{\n  "permissions": {\n    "allow": ["Shell(bash tools/verify.sh)"],\n    "deny": []\n  }\n}\n' > .cursor/cli.json
	git add .cursor && git commit -q -m "the Cursor files" || fail "could not commit the Cursor files"
	make_upstream
	sync v2
	assert_status 0
	[ ! -e .cursor/hooks.json ] && [ ! -e .cursor/cli.json ] || fail "the retired Cursor files are still there"
	run_cmd bash factory/core/hooks.sh check
	assert_status 0
}

test_sync_refreshes_the_installed_copies_the_project_left_alone() {
	adopted
	echo "the project's edit" >> .claude/skills/factory-run/editor.md
	echo "echo the project's entry point" >> tools/verify.sh
	git commit -q -am "own edits" || fail "could not commit"
	make_upstream
	sync v2
	assert_status 0
	cmp -s factory/skills/factory-run/SKILL.md .claude/skills/factory-run/SKILL.md || fail "an untouched skill copy wasn't refreshed"
	cmp -s factory/skills/v2-skill/SKILL.md .claude/skills/v2-skill/SKILL.md || fail "a new skill wasn't installed"
	assert_eq "the project's edit" "$(tail -n 1 .claude/skills/factory-run/editor.md)" "an edited skill copy was overwritten"
	assert_eq "echo the project's entry point" "$(tail -n 1 tools/verify.sh)" "an edited tools/verify.sh was overwritten"
	stderr_has "kept .claude/skills/factory-run/editor.md, which the project changed"
	assert_line "+++ now/.claude/skills/factory-run/editor.md"
	assert_line "+++ now/tools/verify.sh"
}

# The Sonnet Editor and the verify-<project> skill are installed copies too: the
# filled-in template, and what the adapter's generator writes for the project.
test_sync_refreshes_the_sonnet_editor_and_the_generated_verify_skill() {
	adopt_project
	fake_generator
	run_cmd bash factory/core/adopt.sh fake
	assert_status 0
	git commit -q -m adopt || fail "could not commit the adoption"
	# shellcheck disable=SC2317 # v2_release calls it
	v2_extra() {
		sed -i 's/Drive the fake build\./Drive the fake build, v2./' adapters/fake/verify-skill.sh
		echo "A v2 rule for <stack> in <project>." >> agents/editor-sonnet.md
	}
	make_upstream
	sync v2
	assert_status 0
	grep -qxF "description: Drive the fake build, v2." .claude/skills/verify-my-game/SKILL.md ||
		fail "the generated skill wasn't refreshed:"$'\n'"$(cat .claude/skills/verify-my-game/SKILL.md)"
	assert_eq "A v2 rule for fake in my-game." "$(tail -n 1 .claude/agents/editor-sonnet.md)" "the Sonnet Editor wasn't refreshed"
	assert_eq "" "$(git status --porcelain | grep -v '^[AMDR] ')" "the sync left files unstaged"
}

# sync.sh runs from the old factory, so the list of installed copies comes from
# the new one: a subagent the release adds is installed, one it drops goes.
test_sync_installs_the_copies_the_new_release_lists() {
	adopted
	[ -f .claude/agents/asset-fetcher.md ] || fail "the adoption installed no asset fetcher"
	# shellcheck disable=SC2317 # v2_release calls it
	v2_extra() {
		printf -- '---\nname: v2-agent\n---\nFor <project>.\n' > agents/v2-agent.md
		sed -i 's#^\(\t*\)"agent agents/asset-fetcher.md .claude/agents/asset-fetcher.md" \\$#\1"agent agents/v2-agent.md .claude/agents/v2-agent.md" \\#' core/lib/vendor.sh
		rm agents/asset-fetcher.md
		grep -q 'v2-agent' core/lib/vendor.sh || fail "the v2 release lists no new agent"
	}
	make_upstream
	sync v2
	assert_status 0
	assert_eq "For my-game." "$(tail -n 1 .claude/agents/v2-agent.md 2> /dev/null)" "the new release's agent wasn't installed"
	[ ! -e .claude/agents/asset-fetcher.md ] || fail "the agent the release dropped is still installed"
}

# A release that renames a template but keeps its copy's path refreshes the copy.
test_sync_keeps_a_copy_whose_template_the_release_renamed() {
	adopted
	# shellcheck disable=SC2317 # v2_release calls it
	v2_extra() {
		git mv -q agents/asset-fetcher.md agents/renamed-fetcher.md 2> /dev/null || mv agents/asset-fetcher.md agents/renamed-fetcher.md
		echo "A v2 line for <project>." >> agents/renamed-fetcher.md
		sed -i 's#"agent agents/asset-fetcher.md #"agent agents/renamed-fetcher.md #' core/lib/vendor.sh
		grep -q 'renamed-fetcher' core/lib/vendor.sh || fail "the v2 release didn't rename the template"
	}
	make_upstream
	sync v2
	assert_status 0
	assert_eq "A v2 line for my-game." "$(tail -n 1 .claude/agents/asset-fetcher.md 2> /dev/null)" "the renamed template's copy wasn't refreshed"
}

# A release that moves a folder of skills keeps their copies, refreshed, and a
# skill the project removed stays removed.
test_sync_keeps_the_copies_of_a_skills_folder_the_release_moved() {
	adopted
	[ -f .claude/skills/factory-spec/SKILL.md ] || fail "the adoption installed no factory-spec skill"
	git rm -q -r .claude/skills/factory-spec && git commit -q -m "drop a skill" || fail "could not drop a skill"
	# shellcheck disable=SC2317 # v2_release calls it
	v2_extra() {
		mv skills core-skills
		sed -i 's#"tree skills .claude/skills"#"tree core-skills .claude/skills"#' core/lib/vendor.sh
		grep -q 'tree core-skills' core/lib/vendor.sh || fail "the v2 release didn't move the skills"
	}
	make_upstream
	sync v2
	assert_status 0
	assert_eq "v2 line" "$(tail -n 1 .claude/skills/factory-run/SKILL.md 2> /dev/null)" "the moved skill's copy wasn't refreshed"
	[ -f .claude/skills/v2-skill/SKILL.md ] || fail "the moved folder's new skill wasn't installed"
	[ ! -e .claude/skills/factory-spec ] || fail "the skill the project removed came back"
}

# Where two trees install one path, the first one's file is the copy, as in
# adopt.sh: a release adding the clash leaves the core skill's copy refreshed.
test_sync_keeps_the_first_tree_where_a_release_adds_a_clash() {
	adopted
	# shellcheck disable=SC2317 # v2_release calls it
	v2_extra() {
		mkdir -p adapters/fake/skills/factory-run && echo "the adapter's own" > adapters/fake/skills/factory-run/SKILL.md
	}
	make_upstream
	sync v2
	assert_status 0
	assert_eq "v2 line" "$(tail -n 1 .claude/skills/factory-run/SKILL.md)" "the adapter's skill replaced the core one's copy"
}

# With the clash in both releases, the untouched copy follows the first tree.
test_sync_keeps_the_first_tree_where_both_releases_clash() {
	adopt_project
	mkdir -p factory/adapters/fake/skills/factory-run && echo "the adapter's own" > factory/adapters/fake/skills/factory-run/SKILL.md
	git add -A && git commit -q -m clash || fail "could not commit the clash"
	run_cmd bash factory/core/adopt.sh fake
	assert_status 0
	git add -A && git commit -q -m adopt || fail "could not commit the adoption"
	[ "$(tail -n 1 .claude/skills/factory-run/SKILL.md)" != "the adapter's own" ] || fail "adopt.sh installed the adapter's skill"
	make_upstream
	sync v2
	assert_status 0
	assert_eq "v2 line" "$(tail -n 1 .claude/skills/factory-run/SKILL.md)" "the core skill's copy wasn't refreshed"
	! grep -qF "kept .claude/skills/factory-run/SKILL.md" "$TEST_TMP/stderr" || fail "the untouched copy was taken for a tuned one"
}

# A copy the project tuned is kept, and the factory's change to it is printed.
test_sync_keeps_a_tuned_sonnet_editor_and_verify_skill() {
	adopt_project
	fake_generator
	run_cmd bash factory/core/adopt.sh fake
	assert_status 0
	echo "the project's note" >> .claude/agents/editor-sonnet.md
	echo "the project's note" >> .claude/skills/verify-my-game/SKILL.md
	git add -A && git commit -q -m "adopt, tuned" || fail "could not commit the adoption"
	# shellcheck disable=SC2317 # v2_release calls it
	v2_extra() {
		sed -i 's/Drive the fake build\./Drive the fake build, v2./' adapters/fake/verify-skill.sh
		echo "A v2 rule." >> agents/editor-sonnet.md
	}
	make_upstream
	sync v2
	assert_status 0
	assert_eq "the project's note" "$(tail -n 1 .claude/agents/editor-sonnet.md)" "the tuned Sonnet Editor was overwritten"
	assert_eq "the project's note" "$(tail -n 1 .claude/skills/verify-my-game/SKILL.md)" "the tuned skill was overwritten"
	assert_line "+++ now/.claude/agents/editor-sonnet.md"
	assert_line "+A v2 rule."
	assert_line "+++ now/.claude/skills/verify-my-game/SKILL.md"
	assert_line "+description: Drive the fake build, v2."
}

test_sync_refuses_a_locally_edited_core_naming_the_files() {
	adopted
	echo "# a local edit" >> factory/core/verify.sh
	echo "a local file" > factory/core/extra.sh
	git rm -q factory/core/pins.sh
	git add -A && git commit -q -m "edit the core" || fail "could not commit"
	echo "# uncommitted" >> factory/core/baseline.sh
	make_upstream
	before="$(tree_sums factory tools .claude)"
	head="$(git rev-parse HEAD)"
	sync v2
	assert_status 1
	stderr_has "factory/core/verify.sh changed"
	stderr_has "factory/core/extra.sh added"
	stderr_has "factory/core/pins.sh missing"
	stderr_has "factory/core/baseline.sh changed"
	assert_eq "$before" "$(tree_sums factory tools .claude)" "the refused sync changed files"
	assert_eq "$head" "$(git rev-parse HEAD)" "the refused sync committed"
}

test_sync_refuses_a_dirty_tree() {
	adopted
	make_upstream
	echo two > src/a.txt
	sync v2
	assert_status 1
	stderr_has "the tree is dirty"
	assert_eq "version 0.1.0" "$(head -n 1 tools/verify/factory-version)" "the refused sync recorded a version"
}

test_sync_refuses_an_unknown_tag() {
	adopted
	make_upstream
	sync v3
	assert_status 1
	stderr_has "no tag v3 at $TEST_TMP/upstream"
	assert_eq "" "$(git status --porcelain)" "the refused sync changed the tree"
}

test_sync_refuses_a_project_that_has_not_adopted() {
	adopt_project
	make_upstream
	sync v2
	assert_status 1
	stderr_has "not adopted"
}

test_sync_reads_a_factory_at_the_repo_root() {
	adopted
	make_upstream root
	sync v2
	assert_status 0
	assert_factory_is "$TEST_TMP/upstream"
}

# The factory repo's workspace layout: the tag's factory/ alone reaches the
# project, never the workspace's files at its root.
test_sync_reads_a_workspace_and_takes_its_factory_folder_alone() {
	adopted
	make_upstream workspace
	before="$(cat README.md 2> /dev/null)"
	sync v2
	assert_status 0
	assert_factory_is "$TEST_TMP/upstream/factory"
	for f in .factory-repo CLAUDE.md factory/.factory-repo factory/CLAUDE.md factory/factory; do
		[ ! -e "$f" ] || fail "the sync copied $f"
	done
	assert_eq "$before" "$(cat README.md 2> /dev/null)" "the sync wrote the project's README.md"
	cmp -s factory/skills/factory-amend/SKILL.md .claude/skills/factory-amend/SKILL.md || fail "the workspace's skill copy reached the project"
	assert_eq "" "$(git status --porcelain | grep -v '^[ADMR] ')" "the sync left files unstaged"
	assert_eq "version 9.9.9" "$(head -n 1 tools/verify/factory-version)" "factory-version"
}

test_without_an_upstream_the_tag_comes_from_the_project() {
	adopted
	git checkout -q -b release || fail "no release branch"
	(cd factory && v2_release) || fail "could not make the v2 release"
	git add -A && git commit -q -m v2 && git tag v2 || fail "could not tag v2"
	git checkout -q dev || fail "could not go back to dev"
	unset FACTORY_UPSTREAM
	sync v2
	assert_status 0
	assert_eq "9.9.9" "$(cat factory/VERSION)" "the project's own tag wasn't synced"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_a_second_sync_to_the_same_tag_changes_nothing() {
	adopted
	make_upstream
	sync v2
	assert_status 0
	git commit -q -m sync || fail "could not commit the sync"
	sync v2
	assert_status 0
	assert_eq "" "$(git status --porcelain)" "the second sync changed the tree"
	assert_eq "" "$out" "the second sync printed a port"
}

test_a_bad_call_is_a_usage_error() {
	adopted
	sync
	assert_status 2
	sync v1 v2
	assert_status 2
	sync --force
	assert_status 2
}

# record_upstream <url>: factory-version gains an upstream line, committed.
record_upstream() {
	sed -i "2a upstream $1" tools/verify/factory-version
	git commit -q -am "the factory's repo" || fail "could not commit the upstream line"
}

# Without FACTORY_UPSTREAM, the tag comes from factory-version's upstream line,
# which the sync keeps.
test_sync_reads_the_recorded_upstream_and_keeps_it() {
	adopted
	make_upstream root
	unset FACTORY_UPSTREAM
	record_upstream "$TEST_TMP/upstream"
	sync v2
	assert_status 0
	assert_factory_is "$TEST_TMP/upstream"
	assert_eq "version 9.9.9"$'\n'"adapter fake"$'\n'"tag v2"$'\n'"upstream $TEST_TMP/upstream" \
		"$(head -n 4 tools/verify/factory-version)" "factory-version"
}

# FACTORY_UPSTREAM, when set, wins over the recorded line, which stays as it was.
test_factory_upstream_overrides_the_recorded_upstream() {
	adopted
	make_upstream root
	record_upstream "$TEST_TMP/nowhere.git"
	sync v2
	assert_status 0
	assert_eq "9.9.9" "$(cat factory/VERSION)" "the sync didn't read FACTORY_UPSTREAM"
	assert_eq "upstream $TEST_TMP/nowhere.git" "$(grep '^upstream ' tools/verify/factory-version)" "the recorded upstream"
	git reset -q --hard HEAD && unset FACTORY_UPSTREAM
	sync v2
	assert_status 1
	stderr_has "no tag v2 at $TEST_TMP/nowhere.git"
}

# --- check and latest ---------------------------------------------------------

# tagged_upstream <tag...>: $TEST_TMP/tags.git, a bare repo with one commit
# carrying each tag (a tag ending in +a is annotated, the +a dropped from its
# name); FACTORY_UPSTREAM points at it.
tagged_upstream() {
	local up="$TEST_TMP/tags.git" work="$TEST_TMP/tags" t
	git init -q -b main "$work" && commit_in "$work" a.txt one || fail "could not make the tags repo"
	for t in "$@"; do
		case "$t" in
			*+a) git -C "$work" tag -a -m "${t%+a}" "${t%+a}" ;;
			*) git -C "$work" tag "$t" ;;
		esac || fail "could not tag $t"
	done
	git clone -q --bare "$work" "$up" || fail "could not make the bare tags repo"
	export FACTORY_UPSTREAM="$up"
}

# recorded <version>: a project that records only <version> and an adapter in
# factory-version (all check reads), committed.
recorded() {
	adopt_project
	mkdir -p tools/verify
	printf 'version %s\nadapter fake\n' "$1" > tools/verify/factory-version
	git add -A && git commit -q -m record || fail "could not commit the record"
}

check() {
	run_cmd bash factory/core/sync.sh check
}

test_check_says_newer_when_the_upstream_has_a_greater_release() {
	recorded 0.1.0
	tagged_upstream v0.1.0 v0.2.0
	before="$(git status --porcelain && git rev-parse HEAD)"
	check
	assert_status 0
	assert_eq "newer v0.2.0 (on 0.1.0)" "$out"
	assert_eq "$before" "$(git status --porcelain && git rev-parse HEAD)" "check changed the project"
}

test_check_says_current_when_on_the_highest_release() {
	recorded 0.2.0
	tagged_upstream v0.1.0 v0.2.0
	check
	assert_status 0
	assert_eq "current 0.2.0" "$out"
}

test_check_says_current_when_past_the_highest_release() {
	recorded 0.3.0
	tagged_upstream v0.2.0
	check
	assert_status 0
	assert_eq "current 0.3.0" "$out"
}

test_check_ignores_tags_that_are_not_v_and_three_numbers() {
	recorded 0.1.0
	tagged_upstream v0.5.0+a v1 v2.0 v3.0.0-rc1 release-9.0.0 9.0.0 v01.0.0 v4.0.0.1 v0.4.0
	check
	assert_status 0
	assert_eq "newer v0.5.0 (on 0.1.0)" "$out"
}

test_check_compares_each_part_as_a_number() {
	recorded 0.9.0
	tagged_upstream v0.2.0 v0.10.0 v0.9.0
	check
	assert_status 0
	assert_eq "newer v0.10.0 (on 0.9.0)" "$out"
}

test_check_reads_the_recorded_upstream() {
	recorded 0.1.0
	tagged_upstream v0.3.0
	unset FACTORY_UPSTREAM
	record_upstream "$TEST_TMP/tags.git"
	check
	assert_status 0
	assert_eq "newer v0.3.0 (on 0.1.0)" "$out"
}

test_check_without_an_upstream_cannot_tell() {
	recorded 0.1.0
	git tag v0.2.0
	check
	assert_status 1
	assert_eq "" "$out"
	stderr_has "no upstream"
}

test_check_on_an_unreachable_upstream_cannot_tell() {
	recorded 0.1.0
	export FACTORY_UPSTREAM="$TEST_TMP/nowhere.git"
	check
	assert_status 1
	assert_eq "" "$out"
	stderr_has "could not list the tags at $TEST_TMP/nowhere.git"
}

test_check_on_an_upstream_with_no_release_cannot_tell() {
	recorded 0.1.0
	tagged_upstream v1 latest
	check
	assert_status 1
	stderr_has "no release at $TEST_TMP/tags.git"
}

test_check_on_a_project_that_has_not_adopted_cannot_tell() {
	adopt_project
	tagged_upstream v0.2.0
	check
	assert_status 1
	stderr_has "not adopted"
}

# fake_ssh <body>: $TEST_TMP/ssh, a script git runs as its ssh command, which logs
# its arguments to $TEST_TMP/ssh.log and then runs <body>.
fake_ssh() {
	printf '#!/usr/bin/env bash\necho "$*" >> "%s"\n%s\n' "$TEST_TMP/ssh.log" "$1" > "$TEST_TMP/ssh"
	chmod +x "$TEST_TMP/ssh"
}

# The ssh command gets ConnectTimeout and BatchMode after any options already set.
test_check_bounds_and_silences_ssh() {
	recorded 0.1.0
	fake_ssh "exit 255"
	export FACTORY_UPSTREAM="ssh://example.invalid/factory.git" GIT_SSH_COMMAND="$TEST_TMP/ssh -o User=me"
	check
	assert_status 1
	grep -qF -- "-o User=me -o ConnectTimeout=5 -o BatchMode=yes" "$TEST_TMP/ssh.log" ||
		fail "ssh ran without the bounds:"$'\n'"$(cat "$TEST_TMP/ssh.log" 2> /dev/null)"
}

# An ssh that never answers (a stand-in blocked until killed): check gives up at
# its limit, and says so.
test_check_gives_up_on_an_upstream_that_does_not_answer() {
	recorded 0.1.0
	blocking_stand_in "$TEST_TMP/hang" "$TEST_TMP/never"
	fake_ssh "\"$TEST_TMP/hang\""
	export FACTORY_UPSTREAM="ssh://example.invalid/factory.git" GIT_SSH_COMMAND="$TEST_TMP/ssh" FACTORY_SYNC_TIMEOUT=1
	check
	assert_status 1
	stderr_has "no answer in 1 seconds"
}

# On a machine with no timeout (stock macOS), check still lists the upstream's
# tags (lib/bounded.sh's watchdog bounds the listing) ...
test_check_says_newer_where_timeout_is_missing() {
	recorded 0.1.0
	tagged_upstream v0.1.0 v0.2.0
	path_without timeout
	check
	assert_status 0
	assert_eq "newer v0.2.0 (on 0.1.0)" "$out"
}

# ... and still gives up on an upstream that does not answer, at its limit.
test_check_gives_up_on_an_upstream_that_does_not_answer_where_timeout_is_missing() {
	recorded 0.1.0
	blocking_stand_in "$TEST_TMP/hang" "$TEST_TMP/never"
	fake_ssh "\"$TEST_TMP/hang\""
	export FACTORY_UPSTREAM="ssh://example.invalid/factory.git" GIT_SSH_COMMAND="$TEST_TMP/ssh" FACTORY_SYNC_TIMEOUT=1
	path_without timeout
	check
	assert_status 1
	stderr_has "no answer in 1 seconds"
	wait_until "the ssh stand-in to be gone" stand_in_gone "$TEST_TMP/hang.pid"
}

# stand_in_gone <pid file>: the process the file names is gone (or never started).
stand_in_gone() {
	local pid
	pid="$(cat "$1" 2> /dev/null)" || return 0
	! kill -0 "$pid" 2> /dev/null
}

# latest_upstream: make_upstream, with its v1 and v2 also tagged as releases:
# v0.1.0 (the vendored factory) and v9.9.9 (v2_release).
latest_upstream() {
	make_upstream
	git -C "$TEST_TMP/upstream" tag v0.1.0 v1 && git -C "$TEST_TMP/upstream" tag v9.9.9 v2 ||
		fail "could not tag the releases"
}

test_latest_syncs_to_the_highest_release() {
	adopted
	latest_upstream
	sync latest
	assert_status 0
	assert_factory_is "$TEST_TMP/upstream/factory"
	assert_eq "version 9.9.9"$'\n'"adapter fake"$'\n'"tag v9.9.9" "$(head -n 3 tools/verify/factory-version)" "factory-version"
	stderr_has "the latest release is v9.9.9"
}

test_latest_refuses_when_already_on_it() {
	adopted
	latest_upstream
	sync latest
	assert_status 0
	git commit -q -m sync || fail "could not commit the sync"
	sync latest
	assert_status 1
	stderr_has "already on v9.9.9"
	assert_eq "" "$(git status --porcelain)" "the refused sync changed the tree"
}

test_latest_without_an_upstream_is_refused() {
	adopted
	unset FACTORY_UPSTREAM
	sync latest
	assert_status 1
	stderr_has "no upstream"
}

test_latest_refuses_a_project_past_the_latest_release() {
	recorded 0.3.0
	tagged_upstream v0.2.0
	sync latest
	assert_status 1
	stderr_has "already on 0.3.0, past the latest release v0.2.0"
}
