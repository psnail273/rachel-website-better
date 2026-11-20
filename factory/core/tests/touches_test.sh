# A Run's Pick by area (touches.sh): the ready issues it dispatches together are
# those whose `Touches:` areas share none, with each other or with an issue in
# flight.

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh

# issue <n> [touches line]: issue n's body at ./<n>.md, as the tracker gives one,
# with that Touches: line among its header lines; none without one.
issue() {
	{
		echo "Part of #1"
		[ "$#" -lt 2 ] || echo "Touches: $2"
		echo "Kind: build"
		echo
		echo "## Synopsis"
		echo
		echo "Slice $1. It touches the header in passing, but only its Touches: line counts."
	} > "$1.md"
}

pick() {
	run_cmd bash "$FACTORY_CORE/touches.sh" pick "$@"
}

# in_flight <n> <touches line>: a repo at ./repo with issue n checked out in a
# worktree, its issue.md saved where start.sh saves it; the test runs in the repo.
in_flight() {
	isolate_git
	[ -d repo ] || {
		git init -q -b dev repo && git -C repo commit -q --allow-empty -m one
	} || fail "no fixture repo"
	git -C repo worktree add -q -b "issue/$1" "$TEST_TMP/wt-$1" || fail "no worktree for #$1"
	issue "$1" "$2"
	mkdir -p "$TEST_TMP/repo/.git/worktrees/wt-$1/factory"
	{ printf '#%s: Slice %s\n\n' "$1" "$1" && cat "$1.md"; } > "$TEST_TMP/repo/.git/worktrees/wt-$1/factory/issue.md"
	cd repo || fail "no repo"
}

test_two_issues_naming_the_same_area_pick_only_the_first() {
	issue 11 "the header, globals.css/tokens"
	issue 12 "The Header."
	pick 11:11.md 12:12.md
	assert_status 0
	assert_eq "#11" "$out"
	stderr_has "touches: #12 waits on #11: header"
}

test_three_issues_with_disjoint_areas_are_all_picked() {
	issue 11 "the header"
	issue 12 "the footer; \`globals.css\`/tokens"
	issue 13 "the about page"
	pick 11:11.md 12:12.md 13:13.md
	assert_status 0
	assert_eq "#11
#12
#13" "$out"
}

test_an_issue_with_no_touches_line_overlaps_nothing() {
	issue 11 "the header, the footer"
	issue 12
	issue 13 "none"
	pick 11:11.md 12:12.md 13:13.md
	assert_status 0
	assert_eq "#11
#12
#13" "$out"
}

test_a_skipped_issue_lets_the_next_one_go() {
	issue 11 "the header"
	issue 12 "the header, the footer"
	issue 13 "the footer"
	pick 11:11.md 12:12.md 13:13.md
	assert_status 0
	assert_eq "#11
#13" "$out"
}

test_an_issue_in_a_worktree_holds_its_areas() {
	in_flight 7 "the layout components"
	issue 11 "the home page, the layout components"
	issue 12 "the footer"
	issue 7 "the layout components"
	pick 11:11.md 12:12.md 7:7.md
	assert_status 0
	assert_eq "#12" "$out"
	stderr_has "touches: #11 waits on #7: layout components"
	stderr_has "touches: #7 is in flight"
}

test_a_busy_issue_holds_its_areas() {
	issue 9 "the footer"
	issue 11 "the footer"
	issue 12 "the header"
	pick --busy 9:9.md 11:11.md 12:12.md
	assert_status 0
	assert_eq "#12" "$out"
	stderr_has "touches: #11 waits on #9: footer"
}

# An issue in flight whose start.sh hasn't saved its issue.md yet holds no area
# unless the Pick passes its body as --busy, and pick says so.
test_an_issue_in_flight_with_no_issue_md_holds_its_areas_only_when_busy() {
	in_flight 5 "the header"
	rm -f "$TEST_TMP/repo/.git/worktrees/wt-5/factory/issue.md"
	issue 6 "the header"
	pick 6:6.md
	assert_status 0
	assert_eq "#6" "$out"
	stderr_has "touches: #5 is in flight with no issue.md to read its areas from; pass its body as --busy 5:<file>"
	issue 5 "the header"
	pick --busy 5:5.md 6:6.md
	assert_status 0
	assert_eq "" "$out"
	stderr_has "touches: #6 waits on #5: header"
	! grep -qF "no issue.md" "$TEST_TMP/stderr" || fail "pick asked for a --busy body it had"
}

test_areas_prints_each_area_as_compared() {
	printf 'Part of #1\r\nTouches:  The Header , `globals.css`/tokens;the  home page. ,header\r\nTouches: the footer\r\n' > 11.md
	run_cmd bash "$FACTORY_CORE/touches.sh" areas 11.md
	assert_status 0
	assert_eq "header
globals.css/tokens
home page" "$out"
}

test_a_body_file_that_cant_be_read_is_a_usage_error() {
	issue 11 "the header"
	pick 11:11.md 12:missing.md
	assert_status 2
	stderr_has "touches: no body file for #12: missing.md"
	pick 11.md
	assert_status 2
	pick
	assert_status 2
}
