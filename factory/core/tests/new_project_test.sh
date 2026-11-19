# new-project.sh: a new project from the factory's own repo, in one step. The
# factory's repo is a bare repo in the workspace layout (.factory-repo beside
# factory/) with the fake adapter, its --new skeleton and an adapter with none,
# released at several tags; the workspace is a checkout of it. gt is a stand-in
# on PATH that logs its arguments (never the real Gitea): its Gitea repos are
# bare repos in $GT_STAND_IN/repos.

# shellcheck disable=SC2154 # out, status: set by run_cmd, in factory/core/tests/lib.sh

# a_factory_repo: $TEST_TMP/factory.git, the factory's repo, released at v0.2.0,
# v0.10.0 and v0.9.0 in that order (each its factory/VERSION) and a v1.0.0-rc1
# after them, no release; $WS, a checkout of it on main.
a_factory_repo() {
	export FAKETOOL_VERSION=1.2.3
	unset FACTORY_PROJECT FACTORY_LABEL_CMD FACTORY_BASE FACTORY_UPSTREAM FACTORY_INSTALL FACTORY_INSTALL_TAG FACTORY_INSTALL_UPSTREAM
	local src="$TEST_TMP/src" v
	mkdir -p "$src/factory/adapters/fake/new" || fail "could not make the factory"
	copy_factory "$src/factory" || fail "could not copy the factory"
	cp -R "$FIXTURE_SRC/tools" "$src/factory/adapters/fake/" &&
		mkdir -p "$src/factory/adapters/plain" && cp -R "$FIXTURE_SRC/tools" "$src/factory/adapters/plain/" ||
		fail "could not make the adapters"
	printf '/.fixture/\n' > "$src/factory/adapters/fake/new/.gitignore.txt"
	printf 'name=<project>\n' > "$src/factory/adapters/fake/new/project.cfg.txt"
	echo "the workspace" > "$src/.factory-repo"
	git -C "$src" init -q -b main || fail "could not make the factory's repo"
	for v in 0.2.0 0.10.0 0.9.0 1.0.0-rc1; do
		echo "$v" > "$src/factory/VERSION"
		git -C "$src" add -A && git -C "$src" commit -q -m "factory $v" && git -C "$src" tag -a "v$v" -m "factory $v" ||
			fail "could not release $v"
	done
	git init -q --bare -b main "$TEST_TMP/factory.git" &&
		git -C "$src" push -q --tags "$TEST_TMP/factory.git" main 2> /dev/null || fail "could not push the factory"
	WS="$TEST_TMP/ws"
	git clone -q "$TEST_TMP/factory.git" "$WS" 2> /dev/null || fail "could not check the factory out"
}

# gt_stand_in: gt on PATH, logging each call's arguments to $GT_STAND_IN/log.
# Logged in as alice, unless $GT_STAND_IN/unauth exists (exit 4, as gt); a repo
# exists when $GT_STAND_IN/exists does, else gt api answers 404. repo create
# makes the repo a bare one in $GT_STAND_IN/repos and prints its path; it fails
# when $GT_STAND_IN/create-fails exists, and prints a path with no repo when
# $GT_STAND_IN/bad-url does. label create fails when $GT_STAND_IN/label-fails
# exists.
gt_stand_in() {
	export GT_STAND_IN="$TEST_TMP/gt"
	mkdir -p "$GT_STAND_IN/bin" "$GT_STAND_IN/repos" || fail "could not make the gt stand-in"
	: > "$GT_STAND_IN/log"
	cat > "$GT_STAND_IN/bin/gt" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GT_STAND_IN/log"
if [ -e "$GT_STAND_IN/unauth" ]; then
	echo "not logged in" >&2
	exit 4
fi
case "$1 $2" in
	"api user") echo alice ;;
	api\ repos/*)
		[ -e "$GT_STAND_IN/exists" ] && exit 0
		echo "HTTP/1.1 404 Not Found" >&2
		exit 1
		;;
	"repo create")
		[ -e "$GT_STAND_IN/create-fails" ] && { echo "500 boom" >&2; exit 1; }
		[ -e "$GT_STAND_IN/bad-url" ] && { echo "$GT_STAND_IN/repos/missing.git"; exit 0; }
		repo="$GT_STAND_IN/repos/${3##*/}.git"
		git init -q --bare -b dev "$repo" || exit 1
		echo "$repo"
		;;
	"label create") [ ! -e "$GT_STAND_IN/label-fails" ] || { echo "500 label boom" >&2; exit 1; } ;;
	*) echo "the stand-in knows no gt $*" >&2; exit 1 ;;
esac
EOF
	chmod +x "$GT_STAND_IN/bin/gt"
	export PATH="$GT_STAND_IN/bin:$PATH"
}

new_project() {
	run_cmd bash "$WS/factory/core/new-project.sh" "$@"
}

# made_nothing <dir>: no <dir>, and gt neither created a repo nor a label.
made_nothing() {
	[ ! -e "$1" ] || fail "the refusal left $1"
	! grep -q '^repo create\|^label create' "$GT_STAND_IN/log" || fail "the refusal ran gt: $(cat "$GT_STAND_IN/log")"
	assert_eq "" "$(ls "$GT_STAND_IN/repos")" "the refusal made a Gitea repo"
}

# The happy path: the folder on dev, pushed to its new Gitea repo, the latest
# release installed with the skeleton, adopted and staged, the labels created
# in the new repo; the workspace's own skill is vendored, never installed.
test_new_project_makes_installs_and_pushes_a_new_project() {
	a_factory_repo
	gt_stand_in
	new_project "$TEST_TMP/shop" fake
	assert_status 0
	local p="$TEST_TMP/shop" origin="$GT_STAND_IN/repos/shop.git"
	assert_eq dev "$(git -C "$p" symbolic-ref --short HEAD)" "the branch"
	assert_eq "Start shop" "$(git -C "$p" log -1 --format=%s)" "the first commit"
	assert_eq 1 "$(git -C "$p" rev-list --count HEAD)" "the install committed"
	assert_eq "$origin" "$(git -C "$p" remote get-url origin)" "the origin"
	assert_eq "$(git -C "$p" rev-parse HEAD)" "$(git -C "$origin" rev-parse dev)" "dev isn't pushed"
	assert_eq origin/dev "$(git -C "$p" rev-parse --abbrev-ref 'dev@{upstream}')" "dev's upstream"
	assert_eq "repo create shop --private --default-branch dev --jq .clone_url" "$(grep '^repo create' "$GT_STAND_IN/log")" "gt repo create"
	assert_eq "version 0.10.0
adapter fake
tag v0.10.0
upstream $TEST_TMP/factory.git" "$(head -n 4 "$p/tools/verify/factory-version")" "factory-version"
	assert_eq "name=shop" "$(cat "$p/project.cfg")" "the skeleton"
	[ -f "$p/tools/verify/ratchet/baseline.txt" ] || fail "not adopted"
	assert_eq "" "$(git -C "$p" status --porcelain | grep -v '^A ')" "the adoption isn't staged"
	assert_eq 3 "$(grep -c '^label create .* --repo alice/shop --color .* --description .* --force$' "$GT_STAND_IN/log")" "the labels"
	for l in spec approved playtest; do
		grep -q "^label create $l " "$GT_STAND_IN/log" || fail "no label $l"
	done
	[ -f "$p/factory/workspace-skills/new-project/SKILL.md" ] || fail "the factory isn't vendored whole"
	[ -f "$p/.claude/skills/adopt/SKILL.md" ] || fail "the project's skills aren't installed"
	[ ! -e "$p/.claude/skills/new-project" ] || fail "the project installed the workspace's new-project skill"
	stderr_has "the latest release is v0.10.0"
	stderr_has "take it through the adopt skill's steps"
}

# --repo names another owner and name, --public its visibility, --tag the release.
test_new_project_takes_the_owner_name_visibility_and_tag() {
	a_factory_repo
	gt_stand_in
	new_project "$TEST_TMP/shop" fake --repo acme/store --public --tag v0.9.0
	assert_status 0
	grep -qx 'api repos/acme/store --silent --include' "$GT_STAND_IN/log" || fail "didn't ask for acme/store: $(cat "$GT_STAND_IN/log")"
	assert_eq "repo create acme/store --public --default-branch dev --jq .clone_url" "$(grep '^repo create' "$GT_STAND_IN/log")" "gt repo create"
	assert_eq 3 "$(grep -c '^label create .* --repo acme/store ' "$GT_STAND_IN/log")" "the labels"
	assert_eq "tag v0.9.0" "$(grep '^tag ' "$TEST_TMP/shop/tools/verify/factory-version")" "the tag"
	assert_eq "0.9.0" "$(cat "$TEST_TMP/shop/factory/VERSION")" "the release"
	assert_eq "$GT_STAND_IN/repos/store.git" "$(git -C "$TEST_TMP/shop" remote get-url origin)" "the origin"
}

# An empty folder there already is the project's.
test_new_project_takes_an_empty_folder() {
	a_factory_repo
	gt_stand_in
	mkdir "$TEST_TMP/shop"
	new_project "$TEST_TMP/shop" fake
	assert_status 0
	assert_eq dev "$(git -C "$TEST_TMP/shop" symbolic-ref --short HEAD)" "the branch"
}

# --- refusals: each before anything is made ---

test_new_project_refuses_a_folder_with_anything_in_it() {
	a_factory_repo
	gt_stand_in
	mkdir "$TEST_TMP/shop" && echo mine > "$TEST_TMP/shop/notes.txt"
	new_project "$TEST_TMP/shop" fake
	assert_status 1
	stderr_has "is not empty"
	assert_eq "notes.txt" "$(ls -A "$TEST_TMP/shop")" "the refusal changed the folder"
	assert_eq "" "$(cat "$GT_STAND_IN/log")" "the refusal ran gt"
	rm -rf "$TEST_TMP/shop"
	made_nothing "$TEST_TMP/shop"
}

test_new_project_refuses_an_unknown_adapter() {
	a_factory_repo
	gt_stand_in
	new_project "$TEST_TMP/shop" nosuch
	assert_status 2
	stderr_has "has no adapter 'nosuch' (it has: fake "
	made_nothing "$TEST_TMP/shop"
}

test_new_project_refuses_an_adapter_with_no_skeleton() {
	a_factory_repo
	gt_stand_in
	new_project "$TEST_TMP/shop" plain
	assert_status 2
	stderr_has "the plain adapter at v0.10.0 has no --new skeleton"
	made_nothing "$TEST_TMP/shop"
}

test_new_project_refuses_when_gt_is_not_logged_in() {
	a_factory_repo
	gt_stand_in
	touch "$GT_STAND_IN/unauth"
	new_project "$TEST_TMP/shop" fake
	assert_status 1
	stderr_has "run \`gt auth login\`"
	made_nothing "$TEST_TMP/shop"
}

test_new_project_refuses_without_gt() {
	a_factory_repo
	path_without gt
	export GT_STAND_IN="$TEST_TMP/gt"
	mkdir -p "$GT_STAND_IN/repos" && : > "$GT_STAND_IN/log"
	new_project "$TEST_TMP/shop" fake
	assert_status 1
	stderr_has "gt is not on PATH"
	made_nothing "$TEST_TMP/shop"
}

test_new_project_refuses_a_gitea_repo_that_exists() {
	a_factory_repo
	gt_stand_in
	touch "$GT_STAND_IN/exists"
	new_project "$TEST_TMP/shop" fake
	assert_status 1
	stderr_has "the Gitea repo alice/shop exists already"
	made_nothing "$TEST_TMP/shop"
}

test_new_project_refuses_a_tag_the_factory_lacks() {
	a_factory_repo
	gt_stand_in
	new_project "$TEST_TMP/shop" fake --tag v0.3.0
	assert_status 1
	stderr_has "could not clone the factory at v0.3.0"
	made_nothing "$TEST_TMP/shop"
}

test_new_project_refuses_a_folder_inside_the_checkout() {
	a_factory_repo
	gt_stand_in
	new_project "$WS/shop" fake
	assert_status 1
	stderr_has "inside the factory's checkout"
	made_nothing "$WS/shop"
}

test_new_project_refuses_bad_usage() {
	a_factory_repo
	gt_stand_in
	new_project "$TEST_TMP/shop"
	assert_status 2
	new_project "$TEST_TMP/shop" fake --tag 0.9.0
	assert_status 2
	new_project "$TEST_TMP/shop" fake --private
	assert_status 2
	new_project "$TEST_TMP/shop" fake --repo 'bad name'
	assert_status 1
	stderr_has "is no Gitea repo name"
	made_nothing "$TEST_TMP/shop"
}

# --- failures ---

# gt repo create failed: no Gitea repo, so the folder goes too; an empty folder
# that was there stays, empty.
test_new_project_removes_its_folder_when_the_gitea_repo_is_not_made() {
	a_factory_repo
	gt_stand_in
	touch "$GT_STAND_IN/create-fails"
	new_project "$TEST_TMP/shop" fake
	assert_status 1
	stderr_has "gt repo create failed"
	[ ! -e "$TEST_TMP/shop" ] || fail "the folder is left"
	mkdir "$TEST_TMP/shop"
	new_project "$TEST_TMP/shop" fake
	assert_status 1
	assert_eq "" "$(ls -A "$TEST_TMP/shop")" "the empty folder isn't empty"
}

# Once the Gitea repo exists, a failure removes nothing and says what it made.
test_new_project_says_what_it_made_when_it_fails_after_the_gitea_repo() {
	a_factory_repo
	gt_stand_in
	touch "$GT_STAND_IN/bad-url"
	new_project "$TEST_TMP/shop" fake
	assert_status 1
	stderr_has "could not push dev to $GT_STAND_IN/repos/missing.git"
	stderr_has "it made, and removes neither: the folder $TEST_TMP/shop (rm -rf $TEST_TMP/shop removes it) and the Gitea repo alice/shop at $GT_STAND_IN/repos/missing.git (gt repo delete alice/shop removes it"
	[ -d "$TEST_TMP/shop/.git" ] || fail "the folder was removed"
	! grep -q '^repo delete' "$GT_STAND_IN/log" || fail "it deleted the Gitea repo"
	! grep -q '^label create' "$GT_STAND_IN/log" || fail "it went on to the install"
}

# An install that stops (here at prepare: the fake tool's version unset) is such
# a failure: the project's folder and Gitea repo stay, and it says how to resume.
test_new_project_says_what_it_made_when_the_install_stops() {
	a_factory_repo
	gt_stand_in
	unset FAKETOOL_VERSION
	new_project "$TEST_TMP/shop" fake
	assert_status 1
	stderr_has "the install stopped"
	stderr_has "it made, and removes neither: the folder $TEST_TMP/shop"
	assert_eq "$(git -C "$TEST_TMP/shop" rev-parse HEAD)" "$(git -C "$GT_STAND_IN/repos/shop.git" rev-parse dev)" "dev isn't pushed"
}

# A label gt could not create is no failure, but the script names it, so the
# skill makes it.
test_new_project_names_the_labels_it_could_not_create() {
	a_factory_repo
	gt_stand_in
	touch "$GT_STAND_IN/label-fails"
	new_project "$TEST_TMP/shop" fake
	assert_status 0
	stderr_has "could not create the labels spec approved playtest in alice/shop"
	[ -f "$TEST_TMP/shop/tools/verify/factory-version" ] || fail "not installed"
}

# --- the workspace's skill ---

# record installs the workspace's skills; adopt.sh, in a project, never does.
test_new_project_skill_is_the_workspace_s_alone() {
	a_factory_repo
	cd "$WS" || fail "no workspace"
	run_cmd bash factory/core/amend.sh record
	[ "$status" -eq 0 ] || fail "record failed: $(cat "$TEST_TMP/stderr")"
	cmp -s factory/workspace-skills/new-project/SKILL.md .claude/skills/new-project/SKILL.md || fail "record didn't install new-project"
	mkdir -p "$TEST_TMP/game" && cd "$TEST_TMP/game" && git init -q -b dev . && git commit -q --allow-empty -m project ||
		fail "could not make the project"
	mkdir factory && cp -R "$WS/factory/." factory/ && git add -A && git commit -q -m "vendor the factory" ||
		fail "could not vendor the factory"
	run_cmd bash factory/core/adopt.sh fake
	[ "$status" -eq 0 ] || fail "adopt failed: $(cat "$TEST_TMP/stderr")"
	[ -f .claude/skills/adopt/SKILL.md ] || fail "adopt installed no skills"
	[ ! -e .claude/skills/new-project ] || fail "adopt installed the workspace's new-project skill"
}
