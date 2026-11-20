# The Build Brief's fenced block and its parser (brief.sh, lib/brief.sh).

# write_brief <line...>: a brief.md in the current folder with prose around one
# factory-brief block holding the given lines.
write_brief() {
	{
		echo "# Brief: issue 1"
		echo
		echo "Some prose, and a block the parser must ignore:"
		echo "${FENCE}bash"
		echo "scope nowhere/**"
		echo "$FENCE"
		echo "${FENCE}factory-brief"
		printf '%s\n' "$@"
		echo "$FENCE"
		echo "More prose."
	} > brief.md
}

run_brief() {
	run_cmd bash "$FACTORY_CORE/brief.sh" "$@"
}

# shellcheck disable=SC2154 # out: set by run_cmd, in factory/core/tests/lib.sh
test_valid_block_lists_scope_tests_and_seams() {
	write_brief "scope src/stock/reorder.txt" "" "# the tests" "scope tests/stock/**" \
		"test test_reorder_waits" "test test_reorder_fires" "seam src/stock/reorder.txt Reorder.due"
	run_brief scope brief.md
	assert_status 0
	assert_eq "src/stock/reorder.txt
tests/stock/**" "$out"
	run_brief tests brief.md
	assert_eq "test_reorder_waits
test_reorder_fires" "$out"
	run_brief seams brief.md
	assert_eq "src/stock/reorder.txt Reorder.due" "$out"
}

test_crlf_brief_parses() {
	write_brief "scope a/b.txt" "test test_one"
	sed -i 's/$/\r/' brief.md
	run_brief tests brief.md
	assert_status 0
	assert_eq "test_one" "$out"
}

test_missing_brief_fails() {
	run_brief check nope.md
	assert_status 1
	assert_eq "nope.md:1 brief-missing no Build Brief at this path" "$out"
}

test_missing_block_fails() {
	printf '# Brief\n\nNo block here.\n' > brief.md
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:1 brief-block-missing no fenced block opened by a line '${FENCE}factory-brief'" "$out"
}

test_unclosed_block_fails_at_its_opening_line() {
	printf '# Brief\n%sfactory-brief\nscope a/**\n' "$FENCE" > brief.md
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:2 brief-block-unclosed the factory-brief block has no closing '$FENCE' line" "$out"
}

test_second_block_fails() {
	write_brief "scope a/**"
	printf '%sfactory-brief\nscope b/**\n%s\n' "$FENCE" "$FENCE" >> brief.md
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:11 brief-block-duplicate a second factory-brief block; the brief has exactly one" "$out"
}

test_block_without_scope_fails() {
	write_brief "test test_one"
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:7 brief-no-scope the factory-brief block has no 'scope <glob>' line" "$out"
}

test_malformed_lines_each_fail_naming_the_line() {
	write_brief "scope a/**" "scope two words" "scope /abs/path" "test" \
		"test test_one" "test test_one" "seam only/a/path.txt" "owner someone"
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:10 brief-format expected 'scope <glob>' with one relative glob, got: scope /abs/path
brief.md:11 brief-format expected 'test <name>', got: test
brief.md:13 brief-format test test_one is named twice
brief.md:14 brief-format expected 'seam <path> <symbol>', got: seam only/a/path.txt
brief.md:15 brief-format unknown key 'owner'; the keys are: scope test seam removes grows asserts invariants lane
brief.md:9 brief-format expected 'scope <glob>' with one relative glob, got: scope two words" "$out"
}

# A test's name is the rest of its line, so a TypeScript name (its describe
# blocks joined by ` > `) fits; outer spaces go, inner ones stay.
test_a_test_name_takes_the_rest_of_the_line() {
	write_brief "scope src/**" "test   cart > adds  an item  " "test test_one" "test cart > adds an item"
	run_brief tests brief.md
	assert_status 0
	assert_eq "cart > adds  an item
test_one
cart > adds an item" "$out"
}

test_removes_lists_the_baseline_entries_the_issue_removes() {
	write_brief "scope src/**" "removes src/a.txt R13 a rule is broken here" \
		"removes src/b.txt:12 format the file isn't formatted"
	run_brief removes brief.md
	assert_status 0
	assert_eq "src/a.txt R13 a rule is broken here
src/b.txt:12 format the file isn't formatted" "$out"
}

test_a_removes_line_needs_a_file_a_rule_and_a_message() {
	write_brief "scope src/**" "removes src/a.txt R13"
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:9 brief-format expected 'removes <file> <rule> <message>', a Baseline entry, got: removes src/a.txt R13" "$out"
}

test_a_brief_without_removes_lists_none() {
	write_brief "scope src/**"
	run_brief removes brief.md
	assert_status 0
	assert_eq "" "$out"
}

test_listing_a_malformed_brief_prints_only_findings() {
	write_brief "scope a/**" "bogus line"
	run_brief scope brief.md
	assert_status 1
	assert_eq "brief.md:9 brief-format unknown key 'bogus'; the keys are: scope test seam removes grows asserts invariants lane" "$out"
}

test_default_brief_is_in_the_git_dir() {
	git init -q repo
	cd repo || fail "no repo"
	mkdir -p .git/factory
	write_brief "scope src/**"
	mv brief.md .git/factory/brief.md
	run_brief scope
	assert_status 0
	assert_eq "src/**" "$out"
}

# FACTORY_BRIEF overrides the default for every listing, removes (Partial mode's)
# included, as it does for verify --red and the deviation step.
test_factory_brief_overrides_the_default() {
	git init -q repo
	cd repo || fail "no repo"
	mkdir -p .git/factory
	write_brief "scope src/**"
	mv brief.md .git/factory/brief.md
	write_brief "scope lib/**" "removes lib/a.txt R2 a finding"
	mv brief.md "$TEST_TMP/elsewhere.md"
	FACTORY_BRIEF="$TEST_TMP/elsewhere.md" run_brief removes
	assert_status 0
	assert_eq "lib/a.txt R2 a finding" "$out"
	FACTORY_BRIEF="$TEST_TMP/elsewhere.md" run_brief scope
	assert_eq "lib/**" "$out"
}

test_bad_usage_exits_2() {
	run_brief list brief.md
	assert_status 2
}

test_glob_star_stays_in_one_folder() {
	. "$FACTORY_CORE/lib/findings.sh"
	. "$FACTORY_CORE/lib/brief.sh"
	factory_glob_match 'src/*.txt' src/a.txt || fail "* missed a file in the folder"
	! factory_glob_match 'src/*.txt' src/b/a.txt || fail "* crossed a folder"
	factory_glob_match 'src/**' src/b/a.txt || fail "** missed a nested file"
	factory_glob_match 'src/**/a.txt' src/a.txt || fail "**/ missed zero folders"
	factory_glob_match 'src/**/a.txt' src/b/c/a.txt || fail "**/ missed two folders"
	factory_glob_match 'src/' src/b/a.txt || fail "a trailing / missed the folder's files"
	factory_glob_match 'src/a?c.txt' src/abc.txt || fail "? missed one character"
	! factory_glob_match 'src/a.txt' src/aXtxt || fail ". matched any character"
	! factory_glob_match 'src/a.txt' xsrc/a.txt || fail "the glob is not anchored"
}

test_grows_lists_the_accepted_ratchet_entries() {
	write_brief "scope src/**" "grows tools/verify/ratchet/tool_scripts.txt tools/new_helper.txt" \
		"grows tools/verify/ratchet/baseline.txt src/a.txt long-line line too long"
	run_brief grows brief.md
	assert_status 0
	assert_eq "tools/verify/ratchet/tool_scripts.txt tools/new_helper.txt
tools/verify/ratchet/baseline.txt src/a.txt long-line line too long" "$out"
}

test_grows_without_an_entry_fails() {
	write_brief "scope src/**" "grows tools/verify/ratchet/tool_scripts.txt"
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:9 brief-format expected 'grows <file> <entry>', got: grows tools/verify/ratchet/tool_scripts.txt" "$out"
}

# An asserts line declares a drop the deviation step measures: a relative file, a
# func name as the probe prints it (<Class>.<func> in an inner class, a Unicode
# name whole), and two counts, the second below the first; one line per func.
test_an_asserts_line_needs_a_file_a_func_and_two_falling_counts() {
	write_brief "scope tests/**" \
		"asserts tests/a_test.gd test_a 5 3" \
		"asserts ./tests/a_test.gd Recorder.call_at 2 0" \
		"asserts tests/a_test.gd test_b 5" \
		"asserts tests/a_test.gd test_b five 3" \
		"asserts /tests/a_test.gd test_b 5 3" \
		"asserts tests/a_test.gd test_café 5 3" \
		"asserts tests/a_test.gd test_b 05 3" \
		"asserts tests/a_test.gd test_b 5 3 more" \
		"asserts tests/a_test.gd test_b 3 3" \
		"asserts tests/a_test.gd test_b 3 4" \
		"asserts tests/a_test.gd test_a 5 2"
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:11 brief-format expected 'asserts <file> <func> <from> <to>': a relative path, a func name and two counts, got: asserts tests/a_test.gd test_b 5
brief.md:12 brief-format expected 'asserts <file> <func> <from> <to>': a relative path, a func name and two counts, got: asserts tests/a_test.gd test_b five 3
brief.md:13 brief-format expected 'asserts <file> <func> <from> <to>': a relative path, a func name and two counts, got: asserts /tests/a_test.gd test_b 5 3
brief.md:15 brief-format expected 'asserts <file> <func> <from> <to>': a relative path, a func name and two counts, got: asserts tests/a_test.gd test_b 05 3
brief.md:16 brief-format expected 'asserts <file> <func> <from> <to>': a relative path, a func name and two counts, got: asserts tests/a_test.gd test_b 5 3 more
brief.md:17 brief-format asserts declares a drop, so <to> is below <from>, got: asserts tests/a_test.gd test_b 3 3
brief.md:18 brief-format asserts declares a drop, so <to> is below <from>, got: asserts tests/a_test.gd test_b 3 4
brief.md:19 brief-format asserts names test_a in tests/a_test.gd twice" "$out"
}

# The file whose tests drop checks is one the issue rewrites, so a scope line
# covers it; a leading ./ doesn't count.
test_check_wants_each_asserts_file_in_scope() {
	template_brief
	edit_brief 's|^seam src/stock/supplier.txt Supplier.place$|&\nasserts tests/stock/reorder_test.txt test_reorder_old 4 1\nasserts ./tests/stock/order_test.txt Recorder.call_at 2 0\nasserts tests/other/report_test.txt test_report 3 0|'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:29 brief-asserts asserts names tests/other/report_test.txt, which no scope line covers" "$out"
	edit_brief '/^asserts tests\/other/d'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# Every Kind and phase that scopes test files takes the key: Partial mode, the
# small lane and the test-only route among them.
test_check_takes_asserts_in_partial_mode_the_small_lane_and_a_test_only_brief() {
	cat > brief.md << 'MD'
# Build Brief: #2 Straight-line

Kind: cleanup. Phase: partial.

## Acceptance criteria → tests
- the branched assertions are gone → `removes tests/a_test.gd branched-assert a message`

```factory-brief
scope tests/a_test.gd
removes tests/a_test.gd branched-assert a message
asserts tests/a_test.gd test_each_item 6 1
```
MD
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out" "Partial mode"
	small_brief
	edit_brief 's|^test test_reorder_keeps$|&\nasserts tests/stock/reorder_test.txt test_reorder_old 3 2|'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out" "the small lane"
	test_only_brief
	edit_brief 's|^test test_check_fails_on_an_orphan$|&\nasserts tests/main/leak_test.txt test_leaks_none 2 0|'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out" "a test-only brief"
}

# --- the prose: the template's Kind line and sections, against the block --------

# template_brief: brief.md in the template's shape (the build skill's build-brief.md),
# Phase red, with two tests and one seam that its sections and block agree on.
# Its Existing tests section comes last (lines 29 and 30), so the lines above it
# keep their numbers.
template_brief() {
	cat > brief.md << 'MD'
# Build Brief: #1 Reorder

Kind: build. Phase: red.

## Goal
Reorder stock at the threshold.

## Acceptance criteria → tests
- waits for the threshold → `test_reorder_waits` in `tests/stock/reorder_test.txt`
- keeps the order size → `test_reorder_keeps`

## Seams
- `src/stock/supplier.txt` `Supplier.place`: records the order it is given.

## Probed
None

## Constraints
- R1 holds; untested: the arch step checks it.

```factory-brief
scope src/stock/**
scope tests/stock/**
test test_reorder_waits
test test_reorder_keeps
seam src/stock/supplier.txt Supplier.place
```

## Existing tests
- `test_report_lists_orders` in `tests/stock/report_test.txt`: in scope; it reads the order size.
MD
}

# edit_brief <sed script>: change brief.md in place.
edit_brief() {
	sed -i "$1" brief.md || fail "sed failed"
}

test_check_passes_a_brief_in_the_template_shape() {
	template_brief
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# The listings read only the block: the gates never fail on prose.
test_listings_read_the_block_alone() {
	template_brief
	edit_brief '/^Kind:/d'
	run_brief tests brief.md
	assert_status 0
	assert_eq "test_reorder_waits
test_reorder_keeps" "$out"
}

test_check_wants_one_valid_kind_line() {
	template_brief
	edit_brief '/^Kind:/d'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:1 brief-kind no 'Kind: <kind>. Phase: <phase>.' line" "$out"
	template_brief
	edit_brief 's/^Kind: build/Kind: feature/'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:3 brief-kind expected 'Kind: <build | bug | cleanup | amend | asset>. Phase: <red | partial | green>.', got: Kind: feature. Phase: red." "$out"
	template_brief
	edit_brief '4a Kind: bug. Phase: red.'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:5 brief-kind a second Kind line; the brief has exactly one" "$out"
}

test_check_pairs_kind_cleanup_with_phase_partial() {
	template_brief
	edit_brief 's/^Kind: build/Kind: cleanup/'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:3 brief-kind Kind cleanup goes with Phase partial (Partial mode), and only with it" "$out"
}

# An asset brief: no tests and no seams; the Driver judges the criteria.
asset_brief() {
	cat > brief.md << 'EOF'
# Build Brief: #9 Fetch the level sounds

Kind: asset. Phase: green.

## Goal
The level sounds are in the repo, each with its licence and credit.

## Acceptance criteria → tests
- Each sound is at its path, with its row in docs/assets.md and its credit.

## Seams
None

## Probed
None

```factory-brief
scope audio/sounds/**
scope docs/assets.md
```
EOF
}

test_check_takes_an_asset_brief_in_phase_green_only() {
	asset_brief
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
	sed -i 's/^Kind: asset. Phase: green./Kind: asset. Phase: red./' brief.md
	run_brief check brief.md
	assert_status 1
	assert_line "brief.md:3 brief-kind Kind asset goes with Phase green: the Driver fetches the files, with no tests and no Lock"
}

test_check_maps_every_test_line_to_a_criterion() {
	template_brief
	edit_brief '/^test test_reorder_keeps$/a test test_reorder_extra'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:26 brief-test no criterion maps to test test_reorder_extra: add '- <criterion> → \`test_reorder_extra\`'" "$out"
}

test_check_wants_a_test_line_for_each_red_criterion() {
	template_brief
	edit_brief 's/`test_reorder_keeps`$/`test_reorder_kept`/'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:10 brief-test no 'test test_reorder_kept' line in the block, so the red gate won't check it
brief.md:25 brief-test no criterion maps to test test_reorder_keeps: add '- <criterion> → \`test_reorder_keeps\`'" "$out"
}

test_check_wants_every_red_criterion_to_name_its_test() {
	template_brief
	edit_brief '10a - a criterion with no test'
	edit_brief '11a - another → no backticks'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:11 brief-criterion in Phase red every criterion maps to a test: - <criterion> → \`<test>\`; notes go in Constraints
brief.md:12 brief-criterion after the → go the test names in backticks: - <criterion> → \`<test>\`" "$out"
}

# Outside Phase red a criterion may map to no test (a Verifier judges it), but a
# test line still needs its criterion.
test_check_lets_a_green_criterion_go_to_the_verifier() {
	test_only_brief
	edit_brief '7a - the docs say so'
	edit_brief '8a - the burst looks the same → judged by the Verifier, from the diff'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
	edit_brief 's/Phase: green/Phase: red/'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:8 brief-criterion in Phase red every criterion maps to a test: - <criterion> → \`<test>\`; notes go in Constraints
brief.md:9 brief-criterion in Phase red every criterion maps to a test: - <criterion> → \`<test>\`; notes go in Constraints" "$out"
}

# One criterion may map to several tests, and a file named after `in` is not a test.
# Indented bullets and plain lines under a criterion are its detail.
test_check_takes_several_tests_on_one_criterion() {
	template_brief
	edit_brief '/^- keeps the order size/d'
	edit_brief 's/→ `test_reorder_waits` in/→ `test_reorder_waits`, `test_reorder_keeps` in/'
	edit_brief '9a \  - the expected size is 12\nPlain detail with `test_not_a_criterion`.'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# A Seams bullet may name several symbols of one path.
test_check_takes_several_symbols_on_one_seams_bullet() {
	template_brief
	edit_brief '/^seam /a seam src/stock/supplier.txt Supplier.cancel'
	edit_brief 's/`Supplier.place`:/`Supplier.place`, `Supplier.cancel`:/'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# A seam line names one symbol: two on one line are one seam no bullet names.
test_check_wants_one_symbol_per_seam_line() {
	template_brief
	edit_brief 's/^seam .*$/seam src\/stock\/supplier.txt Supplier.place Supplier.cancel/'
	edit_brief 's/`Supplier.place`:/`Supplier.place`, `Supplier.cancel`:/'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:13 brief-seam no 'seam src/stock/supplier.txt Supplier.cancel' line in the block, so the red phase can't stub it
brief.md:13 brief-seam no 'seam src/stock/supplier.txt Supplier.place' line in the block, so the red phase can't stub it
brief.md:26 brief-seam no Seams bullet describes seam src/stock/supplier.txt Supplier.place Supplier.cancel" "$out"
}

# Seams' None is bare: words after it don't make a None.
test_check_wants_a_bare_none_under_seams() {
	template_brief
	edit_brief '/^seam /d'
	edit_brief 's/^- `src.*$/None: nothing to stub./'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:12 brief-seam Seams is empty: a bullet per seam line, or None" "$out"
	edit_brief 's/^None: nothing to stub\.$/- None, nothing to stub/'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:12 brief-seam Seams is empty: a bullet per seam line, or None
brief.md:13 brief-seam expected '- \`<path>\` \`<symbol>\`: <what the stub does>', or None, got: - None, nothing to stub" "$out"
}

test_check_wants_a_seam_line_for_each_seams_bullet() {
	template_brief
	edit_brief '/^seam /d'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:13 brief-seam no 'seam src/stock/supplier.txt Supplier.place' line in the block, so the red phase can't stub it" "$out"
}

test_check_wants_a_seams_bullet_for_each_seam_line() {
	template_brief
	edit_brief '/^seam /a seam src/stock/clock.txt Clock.now'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:27 brief-seam no Seams bullet describes seam src/stock/clock.txt Clock.now" "$out"
}

test_check_wants_each_seam_path_in_scope() {
	template_brief
	edit_brief 's/^scope src\/stock\/\*\*$/scope src\/stock\/reorder.txt/'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:26 brief-seam seam path src/stock/supplier.txt is outside the scope, and its stub is written there" "$out"
}

test_check_takes_none_for_no_seams_and_refuses_it_with_seam_lines() {
	template_brief
	edit_brief '/^seam /d'
	edit_brief 's/^- `src.*$/None./'
	run_brief check brief.md
	assert_status 0
	template_brief
	edit_brief 's/^- `src.*$/- None/'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:13 brief-seam Seams says None, but the block has seam lines
brief.md:26 brief-seam no Seams bullet describes seam src/stock/supplier.txt Supplier.place" "$out"
}

test_check_refuses_an_empty_seams_section_and_a_loose_bullet() {
	template_brief
	edit_brief '/^seam /d'
	edit_brief '/^- `src/d'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:12 brief-seam Seams is empty: a bullet per seam line, or None" "$out"
	template_brief
	edit_brief '13a - the stub records calls'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:14 brief-seam expected '- \`<path>\` \`<symbol>\`: <what the stub does>', or None, got: - the stub records calls" "$out"
}

test_check_wants_seams_and_probed_sections() {
	template_brief
	edit_brief '/^## Probed$/,/^None$/d'
	edit_brief '/^## Seams$/,/^$/d'
	edit_brief '/^seam /d'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:1 brief-section no '## Probed' section: each engine or library fact the brief relies on and the probe that showed it, or None
brief.md:1 brief-section no '## Seams' section: a bullet per seam line, or None" "$out"
}

test_check_refuses_an_empty_probed_section() {
	template_brief
	edit_brief '/^None$/d'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:15 brief-section Probed is empty: each fact and its probe, or None" "$out"
}

# Existing tests: required as Seams and Probed are, but for an asset brief too.
test_check_wants_an_existing_tests_section_but_in_partial_mode_and_for_an_asset() {
	template_brief
	edit_brief '/^## Existing tests$/,$d'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:1 brief-section no '## Existing tests' section: each existing test the change reaches, its file in scope or unaffected: <reason>, or None and what was searched" "$out"
	test_only_brief
	edit_brief '/^## Existing tests$/,$d'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:1 brief-section no '## Existing tests' section: each existing test the change reaches, its file in scope or unaffected: <reason>, or None and what was searched" "$out"
	asset_brief
	run_brief check brief.md
	assert_status 0
	cat > brief.md << 'MD'
# Build Brief: #2 Tidy

Kind: cleanup. Phase: partial.

## Acceptance criteria → tests
- the long line is gone → `removes src/a.txt long-line line too long`

```factory-brief
scope src/a.txt
removes src/a.txt long-line line too long
```
MD
	run_brief check brief.md
	assert_status 0
}

test_check_refuses_an_empty_existing_tests_section() {
	template_brief
	edit_brief '/^- `test_report/d'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:29 brief-section Existing tests is empty: each existing test the change reaches, or None and what was searched" "$out"
	template_brief
	edit_brief 's/^- `test_report.*$/  - an indented note/'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:29 brief-section Existing tests is empty: each existing test the change reaches, or None and what was searched" "$out"
}

# A bullet names each test's file after `in`; a file no scope line covers needs
# the bullet to say why its test is unaffected. Lines under a bullet are detail.
test_check_wants_each_existing_test_in_scope_or_unaffected() {
	template_brief
	edit_brief '$a \  - it reads `Order.size` and `SUPPLIER_LIMIT`\nPlain detail on `tests/elsewhere/x_test.txt`.'
	edit_brief '$a - `test_a`, `test_b` in `./tests/stock/a_test.txt`, `test_c` in `tests/stock/c_test.txt`: in scope'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
	edit_brief 's|^- `test_report_lists_orders` in `tests/stock/report_test.txt`: in scope|- `test_client_retries` in `tests/supplier/client_test.txt`: in scope|'
	edit_brief '$a - `test_x` in `tests/stock/x_test.txt`, `test_y` in `src/y_test.txt`'
	edit_brief '$a - the report tests read the order size'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:30 brief-existing-test test file tests/supplier/client_test.txt is outside the scope: add a scope line for it, or say why its test is unaffected ('unaffected: <reason>')
brief.md:34 brief-existing-test test file src/y_test.txt is outside the scope: add a scope line for it, or say why its test is unaffected ('unaffected: <reason>')
brief.md:35 brief-existing-test list one test per line, by its name and its file: '- \`<test>\` in \`<file>\`: in scope, or unaffected: <reason>' (tests of one file may share a bullet: '- \`<test>\`, \`<test>\` in \`<file>\`: ...'); a bullet for a group of tests, or for a whole file, names no test, got: - the report tests read the order size" "$out"
	template_brief
	edit_brief 's|in `tests/stock/report_test.txt`: in scope.*$|in `tests/supplier/client_test.txt`: Unaffected: it places no order.|'
	run_brief check brief.md
	assert_status 0
}

# Only the tests and files a bullet opens with are read: a backticked name after
# `in` in its detail is no test file. A leading ./ counts in neither the file nor
# the scope line.
test_check_reads_an_existing_tests_file_only_where_the_bullet_names_it() {
	template_brief
	edit_brief '$a - `test_a` in `tests/stock/a_test.txt`: in scope; checks the limit in `Order.size`'
	edit_brief '$a - `test_b` and `test c` in `tests/stock/b_test.txt` — the size it reads is in `src/x/order.txt`'
	edit_brief '$a - `test_d` in `tests/stock/d_test.txt` and `test_e` in `tests/stock/e_test.txt`, as the limit in `src/x/limit.txt`'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
	edit_brief 's|^scope tests/stock/\*\*$|scope ./tests/stock/**|'
	edit_brief '$a - `test_f` in `./tests/stock/f_test.txt`: in scope'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# None says what was searched, in any case; a None bullet counts as one.
test_check_wants_a_none_line_to_say_what_was_searched() {
	test_only_brief
	run_brief check brief.md
	assert_status 0
	edit_brief 's/^None: searched/- None: Searched/'
	run_brief check brief.md
	assert_status 0
	edit_brief 's/^- None: Searched.*$/None./'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:26 brief-existing-test a None line says what was searched: 'None: searched <where> for <what the issue changes>', got: None." "$out"
	edit_brief 's/^None\.$/- None that the change reaches/'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:26 brief-existing-test a None line says what was searched: 'None: searched <where> for <what the issue changes>', got: - None that the change reaches" "$out"
}

# Partial mode lists removes lines, and has no tests or seams to describe.
test_check_takes_a_partial_brief_without_seams_or_probed() {
	cat > brief.md << 'MD'
# Build Brief: #2 Tidy

Kind: cleanup. Phase: partial.

## Acceptance criteria → tests
- the long line is gone → `removes src/a.txt long-line line too long`

```factory-brief
scope src/a.txt
removes src/a.txt long-line line too long
```
MD
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# Headings and Kind lines inside a fenced block (a quoted example) don't count.
test_check_skips_fenced_text() {
	template_brief
	edit_brief '/^- R1 holds;/a ```text\n## Seams\nKind: bug. Phase: red.\n- `src/x.txt` `X.y`: no\n```'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# Fences as Markdown has them: tildes, longer runs that hold shorter ones, and
# an indent of up to three spaces.
test_check_skips_every_kind_of_fence() {
	template_brief
	edit_brief '/^- R1 holds;/a ~~~text\nKind: bug. Phase: red.\n```\n## Seams\n~~~'
	edit_brief '/^- R1 holds;/a ````markdown\n```text\nKind: bug. Phase: red.\n```\n- `src/x.txt` `X.y`: no\n````'
	edit_brief '/^- R1 holds;/a \   ```\n## Probed\n   ```'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# A brief whose block is malformed gets only the block's findings: the prose is
# checked against the block, so the block comes first.
test_check_reads_the_prose_once_the_block_parses() {
	template_brief
	edit_brief '/^Kind:/d'
	edit_brief 's/^seam src.*$/seam only-a-path/'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:25 brief-format expected 'seam <path> <symbol>', got: seam only-a-path" "$out"
}

# --- Constraints -----------------------------------------------------------------

# Each Constraint names the test that pins it, in backticks as its test line
# names it, anywhere in its bullet or the lines under it; or says why no test
# can, `untested: <reason>` in any case. A Driver's check is the Driver's.
test_check_takes_a_constraint_that_names_its_test_or_says_untested() {
	template_brief
	edit_brief '/^- R1 holds;/a - The order size stays under 10: pinned by `test_reorder_keeps`.\n- Timers are cleared on unmount.\n  - `test_reorder_waits` checks none is left.\n- Names stay as they are; Untested: a name is no behaviour.\n- The Driver'"'"'s check after green: a build runs clean. It is not the Editor'"'"'s to run.'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# #35's Constraint named neither: it cost a brief-review FAIL.
test_check_refuses_a_constraint_with_no_test_and_no_untested_reason() {
	template_brief
	edit_brief '/^- R1 holds;/a - No `metadata` export.\n- The size reads `Order.size`; untested:\n- Uses `test_other` from the report suite.'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:20 brief-constraint a Constraint names the test that pins it, in backticks as its 'test' line names it, or says why no test can: 'untested: <reason>'; got: - No \`metadata\` export.
brief.md:21 brief-constraint a Constraint names the test that pins it, in backticks as its 'test' line names it, or says why no test can: 'untested: <reason>'; got: - The size reads \`Order.size\`; untested:
brief.md:22 brief-constraint a Constraint names the test that pins it, in backticks as its 'test' line names it, or says why no test can: 'untested: <reason>'; got: - Uses \`test_other\` from the report suite." "$out"
}

# An amend's own check, Kind amend with no test lines, has no test to name.
test_check_leaves_constraints_alone_in_a_brief_with_no_test_lines() {
	cat > brief.md << 'MD'
# Build Brief: #4 A colour check

Kind: amend. Phase: green.

## Acceptance criteria → tests
- each hex colour in a .tsx file is reported → judged by the Verifier

## Seams
None

## Probed
None

## Constraints
- The check reads every .tsx file under src/ and reports each hex colour as `raw-colour`.

## Existing tests
None: searched tools/verify/ for a colour check; there is none.

```factory-brief
scope ARCHITECTURE.md
scope tools/verify/lint
scope docs/deviations.md
```
MD
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# A test name holds spaces (TypeScript's describe blocks joined by ` > `).
test_check_takes_a_constraint_naming_a_test_with_spaces() {
	template_brief
	edit_brief 's/^test test_reorder_keeps$/test cart > keeps the size/; s/`test_reorder_keeps`$/`cart > keeps the size`/'
	edit_brief 's/^- R1 holds;.*$/- The size stays under 10 (`cart > keeps the size`)./'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# Partial mode and an asset have no tests, so their Constraints need neither.
test_check_leaves_constraints_alone_in_partial_mode_and_for_an_asset() {
	cat > brief.md << 'MD'
# Build Brief: #2 Tidy

Kind: cleanup. Phase: partial.

## Acceptance criteria → tests
- the long line is gone → `removes src/a.txt long-line line too long`

## Constraints
- Touch nothing but the long line.

```factory-brief
scope src/a.txt
removes src/a.txt long-line line too long
```
MD
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
	asset_brief
	printf '\n## Constraints\n- Keep the sounds under 1 MB each.\n' >> brief.md
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# --- invariants' test file ---------------------------------------------------------

# A property test is written in green, after the red commit locked its test
# files, so it needs a test file of its own in scope: the module with
# .invariants and a test file's ending from a `**/*<ending>` test-paths glob.
test_check_wants_the_invariants_test_file_in_scope() {
	template_brief
	mkdir -p tools/verify && printf '**/*_test.txt\ntests/**\n' > tools/verify/test-paths
	edit_brief 's|^scope src/stock/\*\*$|scope src/stock/supplier.txt|'
	edit_brief 's|^seam src/stock/supplier.txt Supplier.place$|&\
invariants src/stock/ics.txt parseIcs never throws on any string\
invariants src/stock/ics.txt parseIcs events come out sorted by start|'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:27 brief-invariants the property tests of src/stock/ics.txt go in a test file of their own, which the red commit doesn't lock: add 'scope src/stock/ics.invariants_test.txt'" "$out"
	edit_brief 's|^scope src/stock/supplier.txt$|&\
scope ./src/stock/ics.invariants_test.txt|'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# With no `**/*<ending>` glob, as a stack that keeps its tests in a folder of
# their own (Godot's `tests/**`), a scope line whose last part holds
# `invariants` will do, or one that may hold <module>.invariants.*; the module
# of a path with no extension is the path. A tests folder the red commit locks
# is no such line.
test_check_wants_an_invariants_scope_line_without_an_ending_glob() {
	template_brief
	mkdir -p tools/verify && printf 'tests/**\n' > tools/verify/test-paths
	edit_brief 's|^scope src/stock/\*\*$|scope scripts/stock/reorder_rule.gd|'
	edit_brief 's|^seam src/stock/supplier.txt Supplier.place$|&\
invariants scripts/stock/reorder_rule.gd ReorderRule.order_size never below the minimum order|'
	edit_brief 's|^seam src/stock/supplier.txt Supplier.place$||; s|^- `src/stock/supplier.txt` `Supplier.place`.*$|None|'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:27 brief-invariants the property tests of scripts/stock/reorder_rule.gd go in a test file of their own, which the red commit doesn't lock: add a scope line for it, where the project keeps its tests, with 'invariants' in its name" "$out"
	edit_brief 's|^scope scripts/stock/reorder_rule.gd$|&\
scope tests/stock/reorder_rule_invariants_test.gd|'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
	edit_brief 's|^scope tests/stock/reorder_rule_invariants_test.gd$|scope scripts/**|'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# --- source readers ----------------------------------------------------------------

# reader_repo: a git repo on branch issue/1 off dev, whose dev commit holds a
# small TypeScript project: test-paths, tsconfig.json's `@/*` alias, and these
# tests, shaped like this project's own:
#   - src/app/globals.test.ts walks src/ like globals.test.ts's sourceFiles(),
#     and reads globals.css beside it;
#   - src/app/_components/header.test.tsx reads header.tsx with readFileSync;
#   - src/app/_components/hero.css.test.ts imports its stylesheet and
#     globals.css with ?raw, the second through the alias;
#   - src/server/cache.test.ts reads only a temp folder's file, and joins an
#     array: no reader.
reader_repo() {
	isolate_git
	git init -q -b dev repo || fail "git init failed"
	cd repo || fail "no repo"
	mkdir -p tools/verify src/app/_components src/server docs
	printf '**/*.test.ts\n**/*.test.tsx\n' > tools/verify/test-paths
	cat > tsconfig.json << 'JSON'
{
  "compilerOptions": {
    "paths": {
      "@/*": ["./src/*"]
    }
  }
}
JSON
	: > src/app/page.tsx
	: > src/app/globals.css
	: > src/app/_components/header.tsx
	: > src/app/_components/hero.css
	: > src/server/cache.ts
	cat > src/app/globals.test.ts << 'TS'
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

const srcDir = join(import.meta.dirname, "..");
const css = readFileSync(join(import.meta.dirname, "globals.css"), "utf8");

function sourceFiles(dir: string, extensions: string[]): string[] {
  return readdirSync(dir, { recursive: true, encoding: "utf8" }).filter(
    (name) => extensions.some((ext) => name.endsWith(ext)) && !name.includes(".test."),
  );
}

describe("globals", () => {
  it("sets no colour by hand", () => {
    for (const file of sourceFiles(srcDir, [".tsx"])) {
      expect(readFileSync(join(srcDir, file), "utf8")).not.toMatch(/#[0-9a-f]{6}/);
    }
    expect(css).toContain("--ink");
  });
});
TS
	cat > src/app/_components/header.test.tsx << 'TS'
import { readFileSync } from "node:fs";
import path from "node:path";

import { expect, it } from "vitest";

const source = readFileSync(path.join(import.meta.dirname, "header.tsx"), "utf8");

it("names no colour", () => {
  expect(source).not.toContain("#");
});
TS
	cat > src/app/_components/hero.css.test.ts << 'TS'
import { expect, it } from "vitest";

import globals from "@/app/globals.css?raw";
import css from "./hero.css?raw";

it("uses the tokens", () => {
  expect(css).toContain("var(--ink)");
  expect(globals).toContain("--ink");
});
TS
	cat > src/server/cache.test.ts << 'TS'
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { expect, it } from "vitest";

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "cache-"));

it("starts empty", () => {
  const file = path.join(tmp, "nested", "events.sqlite");
  expect(fs.existsSync(file)).toBe(false);
  expect(["a", "b"].join(" > ")).toBe("a > b");
});
TS
	git add -A && git commit -q -m base || fail "no base commit"
	git checkout -q -b issue/1 || fail "no branch"
}

# reader_brief <scope...>: brief.md for a red issue on the page, scoping the
# given paths besides the page's test and docs/deviations.md; its Existing tests
# heading is line 17, its None line 18.
reader_brief() {
	{
		cat << 'MD'
# Build Brief: #3 The page

Kind: build. Phase: red.

## Acceptance criteria → tests
- the page has a heading → `page > has a heading` in `src/app/page.test.tsx`

## Seams
None

## Probed
None

## Constraints
- Rules this touches: R1; untested: the arch step checks it.

## Existing tests
None: searched src/ for the page; no test reads it.

```factory-brief
scope src/app/page.test.tsx
scope docs/deviations.md
test page > has a heading
MD
		printf 'scope %s\n' "$@"
		echo "$FENCE"
	} > brief.md
}

test_readers_lists_each_test_that_reads_source_files_and_its_reach() {
	reader_repo
	run_brief readers
	assert_status 0
	assert_eq "src/app/_components/header.test.tsx src/app/_components/header.tsx
src/app/_components/hero.css.test.ts src/app/_components/hero.css
src/app/_components/hero.css.test.ts src/app/globals.css
src/app/globals.test.ts src/" "$out"
}

# A literal path is read from the project root; a new URL from the test's
# folder. A path that leaves the project, and the root itself, are no reach.
test_readers_reads_literal_paths_urls_and_resolve() {
	reader_repo
	cat > src/server/config.test.ts << 'TS'
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const pkg = readFileSync("package.json", "utf8");
const page = readFileSync(new URL("../app/page.tsx", import.meta.url), "utf8");
const root = resolve(import.meta.dirname, "..", "..");
const up = existsSync(resolve(import.meta.dirname, "..", "..", "..", "elsewhere"));
const files = existsSync(resolve(root, "public"));
TS
	run_brief readers
	assert_status 0
	assert_line "src/server/config.test.ts package.json"
	assert_line "src/server/config.test.ts src/app/page.tsx"
	assert_line "src/server/config.test.ts public"
	[ "$(grep -c '^src/server/config.test.ts ' <<< "$out")" = 3 ] || fail "expected three reaches for config.test.ts, got: $out"
}

test_readers_needs_the_test_paths() {
	reader_repo
	rm tools/verify/test-paths
	run_brief readers
	assert_status 1
	assert_eq "tools/verify/test-paths:1 test-paths-missing no test-paths file; it lists the globs of the project's test files, one per line" "$out"
}

# A brief whose scope a source reader's reach covers lists that reader under
# Existing tests, or check refuses it at that heading, once per reader.
test_check_wants_each_source_reader_whose_reach_a_scope_line_covers() {
	reader_repo
	reader_brief src/app/page.tsx
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:17 brief-reader src/app/globals.test.ts reads src/ as text, and scope src/app/page.tsx may change it: list its tests under Existing tests, one per line, '- \`<test>\` in \`src/app/globals.test.ts\`: in scope, or unaffected: <reason>' (bash factory/core/brief.sh readers lists the source readers)" "$out"
	reader_brief 'src/app/_components/**'
	run_brief check brief.md
	assert_status 1
	assert_line "brief.md:17 brief-reader src/app/_components/header.test.tsx reads src/app/_components/header.tsx as text, and scope src/app/_components/** may change it: list its tests under Existing tests, one per line, '- \`<test>\` in \`src/app/_components/header.test.tsx\`: in scope, or unaffected: <reason>' (bash factory/core/brief.sh readers lists the source readers)"
	assert_line "brief.md:17 brief-reader src/app/_components/hero.css.test.ts reads src/app/_components/hero.css as text, and scope src/app/_components/** may change it: list its tests under Existing tests, one per line, '- \`<test>\` in \`src/app/_components/hero.css.test.ts\`: in scope, or unaffected: <reason>' (bash factory/core/brief.sh readers lists the source readers)"
	[ "$(grep -c brief-reader <<< "$out")" = 3 ] || fail "expected one finding per reader, got: $out"
}

test_check_passes_a_brief_that_lists_the_source_readers_it_reaches() {
	reader_repo
	reader_brief 'src/app/_components/**' src/app/globals.css
	sed -i 's|^None: searched.*$|- `globals > sets no colour by hand` in `src/app/globals.test.ts`: unaffected: the page sets no colour.\
- `names no colour` in `./src/app/_components/header.test.tsx`: in scope\
- `uses the tokens` in `src/app/_components/hero.css.test.ts`: in scope|' brief.md
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# Only readers of product files count: a scope of tests or the Driver's docs, a
# reach no scope line covers, and a test the branch adds pass.
test_check_counts_only_readers_at_the_base_that_reach_a_product_scope_line() {
	reader_repo
	reader_brief src/server/cache.ts src/server/cache.test.ts src/app/_components/header.test.tsx README.md docs/agents/facts.md
	sed -i 's|^None: searched.*$|- `globals > sets no colour by hand` in `src/app/globals.test.ts`: unaffected: the cache sets no colour.|' brief.md
	cp src/app/globals.test.ts src/server/walk.test.ts
	git add -A && git commit -q -m "red: a new walk" || fail "no commit"
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# --- grouped Existing tests ---------------------------------------------------------

# A bullet for a group of tests or a whole file names no test: the refusal says
# to list one test per line. #28 and Spec #3's #9 and #10 each resealed for it.
# A group the change leaves unaffected may share a bullet.
test_check_refuses_grouped_existing_tests_naming_the_fix() {
	template_brief
	edit_brief '$a - `tests/stock/report_test.txt` (all its tests): in scope'
	edit_brief '$a - the report tests in `tests/stock/report_test.txt`: in scope'
	edit_brief '$a - the supplier tests: unaffected: they place no order'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:31 brief-existing-test list one test per line, by its name and its file: '- \`<test>\` in \`<file>\`: in scope, or unaffected: <reason>' (tests of one file may share a bullet: '- \`<test>\`, \`<test>\` in \`<file>\`: ...'); a bullet for a group of tests, or for a whole file, names no test, got: - \`tests/stock/report_test.txt\` (all its tests): in scope
brief.md:32 brief-existing-test list one test per line, by its name and its file: '- \`<test>\` in \`<file>\`: in scope, or unaffected: <reason>' (tests of one file may share a bullet: '- \`<test>\`, \`<test>\` in \`<file>\`: ...'); a bullet for a group of tests, or for a whole file, names no test, got: - the report tests in \`tests/stock/report_test.txt\`: in scope" "$out"
}

# --- the seal --------------------------------------------------------------------

# sealed_repo: a git repo on branch issue/1 with the template brief in its git dir.
sealed_repo() {
	isolate_git
	git init -q -b dev repo || fail "git init failed"
	cd repo || fail "no repo"
	git commit -q --allow-empty -m base || fail "no base commit"
	git checkout -q -b issue/1 || fail "no branch"
	mkdir -p .git/factory
	template_brief
	mv brief.md .git/factory/brief.md
}

test_seal_stores_the_briefs_hash_in_the_run_state() {
	sealed_repo
	run_brief seal
	assert_status 0
	sha="$(git hash-object --no-filters .git/factory/brief.md)"
	assert_eq "brief: sealed .git/factory/brief.md for issue/1 at $sha" "$out"
	assert_eq "$sha" "$(git config branch.issue/1.factory-brief-sha)"
}

test_seal_refuses_a_brief_that_fails_the_check() {
	sealed_repo
	sed -i '/^## Probed$/,/^None$/d' .git/factory/brief.md
	run_brief seal
	assert_status 1
	assert_eq ".git/factory/brief.md:1 brief-section no '## Probed' section: each engine or library fact the brief relies on and the probe that showed it, or None" "$out"
	git config branch.issue/1.factory-brief-sha > /dev/null && fail "a failing brief was sealed"
	return 0
}

test_seal_needs_a_branch() {
	sealed_repo
	git checkout -q --detach
	run_brief seal
	assert_status 1
	stderr_has "brief: HEAD is detached; seal on the issue's branch"
}

test_seal_check_passes_a_sealed_brief_and_fails_a_changed_one() {
	sealed_repo
	. "$FACTORY_CORE/lib/findings.sh"
	. "$FACTORY_CORE/lib/brief.sh"
	. "$FACTORY_CORE/lib/run.sh"
	factory_brief_seal_check .git/factory/brief.md || fail "an unsealed brief failed"
	run_brief seal
	factory_brief_seal_check .git/factory/brief.md || fail "the sealed brief failed"
	echo "seam src/stock/x.txt X.y" >> .git/factory/brief.md
	run_cmd factory_brief_seal_check .git/factory/brief.md
	assert_status 1
	assert_eq ".git/factory/brief.md:1 brief-changed the Build Brief changed after the Driver sealed it; only the Driver edits it, then seals it again with brief.sh seal (Editor: report this and stop)" "$out"
	rm .git/factory/brief.md
	run_cmd factory_brief_seal_check .git/factory/brief.md
	assert_status 1
	assert_eq ".git/factory/brief.md:1 brief-changed the Build Brief is gone since the Driver sealed it; it is the Driver's (Editor: report this and stop)" "$out"
}

# --- the small lane ------------------------------------------------------------------

# small_brief: brief.md in the small lane (Kind build, Phase red): two tests, two
# product files, its test file and docs/deviations.md, no seam; and the test paths
# that tell the test file. The block's lane line is line 16, its scope lines 17
# to 20, its test lines 21 and 22. An existing test outside the scope is unaffected.
small_brief() {
	mkdir -p tools/verify && echo 'tests/**' > tools/verify/test-paths
	cat > brief.md << 'MD'
# Build Brief: #1 Reorder

Kind: build. Phase: red.

## Acceptance criteria → tests
- waits for the threshold → `test_reorder_waits`
- keeps the order size → `test_reorder_keeps`

## Seams
None

## Probed
None

```factory-brief
lane small
scope src/stock/reorder.txt
scope src/stock/order.txt
scope tests/stock/reorder_test.txt
scope docs/deviations.md
test test_reorder_waits
test test_reorder_keeps
```

## Existing tests
- `test_report_lists_orders` in `tests/stock/report_test.txt`: unaffected: it reads no order size.
MD
}

test_check_passes_a_small_lane_brief_within_its_limits() {
	small_brief
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
	edit_brief 's/^Kind: build/Kind: bug/'
	run_brief check brief.md
	assert_status 0
}

test_a_lane_line_says_small_once() {
	write_brief "scope src/a" "lane big" "lane small" "lane small"
	run_brief scope brief.md
	assert_status 1
	assert_eq "brief.md:11 brief-format a second lane line; the brief has at most one
brief.md:9 brief-format expected 'lane small', got: lane big" "$out"
}

test_check_holds_the_small_lane_to_kind_build_or_bug_in_phase_red() {
	small_brief
	edit_brief 's/^Kind: build/Kind: amend/'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:16 brief-lane lane small goes with Kind build or bug in Phase red" "$out"
	small_brief
	edit_brief 's/Phase: red/Phase: green/'
	run_brief check brief.md
	assert_status 1
	assert_line "brief.md:16 brief-lane lane small goes with Kind build or bug in Phase red"
}

test_check_takes_at_most_four_tests_in_the_small_lane() {
	small_brief
	edit_brief '7a - more cases → `t3`, `t4`'
	edit_brief '/^test test_reorder_keeps$/a test t4'
	edit_brief '/^test test_reorder_keeps$/a test t3'
	run_brief check brief.md
	assert_status 0
	edit_brief 's/→ `t3`, `t4`/→ `t3`, `t4`, `t5`/'
	edit_brief '/^test t4$/a test t5'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:26 brief-lane lane small takes at most 4 test lines; this brief has 5" "$out"
}

test_check_wants_no_seam_in_the_small_lane() {
	small_brief
	edit_brief 's/^None$/- `src\/stock\/order.txt` `Order.place`: records the order./;T;:a;n;ba'
	edit_brief '/^test test_reorder_keeps$/a seam src/stock/order.txt Order.place'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:23 brief-lane lane small adds no seam; drop the seam, or the lane" "$out"
}

test_check_wants_one_file_per_scope_line_in_the_small_lane() {
	small_brief
	edit_brief 's|^scope src/stock/order.txt$|scope src/stock/*.txt|'
	edit_brief 's|^scope tests/stock/reorder_test.txt$|scope tests/stock/|'
	edit_brief 's|^scope src/stock/reorder.txt$|scope src/stock/reorder.tx?|'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:17 brief-lane in lane small each scope line names one file, not a glob: src/stock/reorder.tx?
brief.md:18 brief-lane in lane small each scope line names one file, not a glob: src/stock/*.txt
brief.md:19 brief-lane in lane small each scope line names one file, not a glob: tests/stock/" "$out"
}

test_check_keeps_the_small_lane_out_of_the_gate() {
	small_brief
	edit_brief 's|^scope src/stock/order.txt$|scope tools/verify/pins|'
	edit_brief 's|^scope docs/deviations.md$|scope ./Factory/core/verify.sh|'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:18 brief-lane lane small touches no gate file, and tools/verify/pins is the gate's (pins)
brief.md:20 brief-lane lane small touches no gate file, and Factory/core/verify.sh is the gate's (factory)" "$out"
}

# A . or .. part could hide a gate file from the check, so a scope line is a plain path.
test_check_wants_plain_paths_in_the_small_lane() {
	small_brief
	edit_brief 's|^scope src/stock/order.txt$|scope tools/./verify/pins|'
	edit_brief 's|^scope src/stock/reorder.txt$|scope src/../tools/verify/pins|'
	edit_brief 's|^scope tests/stock/reorder_test.txt$|scope tests//stock/reorder_test.txt|'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:17 brief-lane in lane small each scope line names one file by its plain path, with no . or .. part: src/../tools/verify/pins
brief.md:18 brief-lane in lane small each scope line names one file by its plain path, with no . or .. part: tools/./verify/pins
brief.md:19 brief-lane in lane small each scope line names one file by its plain path, with no . or .. part: tests//stock/reorder_test.txt" "$out"
}

# The test files and the Driver's docs don't count toward the product files.
test_check_takes_at_most_three_product_files_in_the_small_lane() {
	small_brief
	edit_brief '/^scope src\/stock\/order.txt$/a scope src/stock/c.txt'
	edit_brief '/^scope docs\/deviations.md$/a scope docs/agents/facts.md'
	run_brief check brief.md
	assert_status 0
	edit_brief '/^scope src\/stock\/c.txt$/a scope src/stock/d.txt'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:20 brief-lane lane small touches at most 3 product files; src/stock/d.txt is one more" "$out"
}

test_check_needs_the_test_paths_for_a_small_lane_brief() {
	small_brief
	rm tools/verify/test-paths
	run_brief check brief.md
	assert_status 1
	assert_eq "tools/verify/test-paths:1 test-paths-missing no test-paths file; it lists the globs of the project's test files, one per line" "$out"
	rm brief.md
	template_brief
	run_brief check brief.md
	assert_status 0
}

test_seal_puts_the_briefs_lane_in_the_run_state() {
	sealed_repo
	small_brief
	mv brief.md .git/factory/brief.md
	run_brief seal
	assert_status 0
	sha="$(git hash-object --no-filters .git/factory/brief.md)"
	assert_eq "brief: sealed .git/factory/brief.md for issue/1 at $sha, in the small lane" "$out"
	assert_eq small "$(git config branch.issue/1.factory-lane)"
	sed -i '/^lane small$/d' .git/factory/brief.md
	run_brief seal
	assert_status 0
	git config branch.issue/1.factory-lane > /dev/null && fail "the lane outlived the brief's lane line"
	return 0
}

# --- invariants ------------------------------------------------------------------

# An invariants line names the seam a property test drives and the property in
# words, the rest of the line; the brief seals with them, and brief.sh
# invariants lists them for the Verifier.
test_a_brief_with_invariants_lines_seals_and_lists_them() {
	sealed_repo
	sed -i 's|^seam src/stock/supplier.txt Supplier.place$|&\
invariants src/stock/ics.txt parseIcs never  throws on any string  \
invariants ./src/stock/ics.txt parseIcs events come out sorted by start|' .git/factory/brief.md
	run_brief seal
	assert_status 0
	sha="$(git hash-object --no-filters .git/factory/brief.md)"
	assert_eq "brief: sealed .git/factory/brief.md for issue/1 at $sha" "$out"
	run_brief invariants
	assert_status 0
	assert_eq "src/stock/ics.txt parseIcs never  throws on any string
src/stock/ics.txt parseIcs events come out sorted by start" "$out"
}

test_a_brief_without_invariants_lists_none() {
	write_brief "scope src/**"
	run_brief invariants brief.md
	assert_status 0
	assert_eq "" "$out"
}

test_a_malformed_invariants_line_is_refused() {
	write_brief "scope src/**" "invariants src/ics.ts parseIcs" "invariants /src/ics.ts parseIcs never throws" \
		"invariants" "invariants src/ics.ts parseIcs never throws" "invariants src/fmt.ts formatIcs never throws" \
		"invariants src/ics.ts  parseIcs  never throws"
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:10 brief-format expected 'invariants <path> <symbol> <property>': a relative path, the exported symbol the property drives and the property in words, got: invariants /src/ics.ts parseIcs never throws
brief.md:11 brief-format expected 'invariants <path> <symbol> <property>': a relative path, the exported symbol the property drives and the property in words, got: invariants
brief.md:14 brief-format invariant 'never throws' of src/ics.ts parseIcs is named twice
brief.md:9 brief-format expected 'invariants <path> <symbol> <property>': a relative path, the exported symbol the property drives and the property in words, got: invariants src/ics.ts parseIcs" "$out"
}

test_seal_refuses_a_malformed_invariants_line() {
	sealed_repo
	sed -i 's|^seam src/stock/supplier.txt Supplier.place$|&\
invariants src/stock/ics.txt parseIcs|' .git/factory/brief.md
	line="$(grep -n '^invariants ' .git/factory/brief.md | cut -d: -f1)"
	run_brief seal
	assert_status 1
	assert_eq ".git/factory/brief.md:$line brief-format expected 'invariants <path> <symbol> <property>': a relative path, the exported symbol the property drives and the property in words, got: invariants src/stock/ics.txt parseIcs" "$out"
	git config branch.issue/1.factory-brief-sha > /dev/null && fail "a brief with a malformed invariants line was sealed"
	return 0
}

# --- test-only issues ------------------------------------------------------------------

# test_only_brief: brief.md for a test-only issue (Kind build, Phase green): two
# tests, scoped to test files and the Driver's docs, no seam; and the test paths
# that tell the test files. The block's scope lines are 17 to 20, its test lines
# 21 and 22; its Existing tests section, lines 25 and 26, is a None line.
test_only_brief() {
	mkdir -p tools/verify && echo 'tests/**' > tools/verify/test-paths
	cat > brief.md << 'MD'
# Build Brief: #7 Leak check

Kind: build. Phase: green.

## Acceptance criteria → tests
- a session leaks nothing → `test_session_leaks_nothing` in `tests/main/leak_test.txt`
- the check fails on an orphan → `test_check_fails_on_an_orphan`

## Seams
None

## Probed
None

```factory-brief
# Tests for behaviour already built.
scope tests/main/leak_test.txt
scope tests/support/**
scope docs/deviations.md
scope docs/agents/facts.md
test test_session_leaks_nothing
test test_check_fails_on_an_orphan
```

## Existing tests
None: searched tests/ for the session's nodes; no test reads them.
MD
}

test_check_passes_a_test_only_brief() {
	test_only_brief
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

# build-brief.md: a test-only brief lists the tests it rewrites and the suites it
# adds to, a suite by a test already in it, each with its file in scope.
test_check_passes_a_test_only_brief_listing_what_it_rewrites_and_adds_to() {
	test_only_brief
	edit_brief '/^None: searched/d'
	edit_brief '$a - `test_session_leaks_nothing` in `tests/main/leak_test.txt`: in scope; the brief rewrites it'
	edit_brief '$a - `test_helper_counts_nodes` in `tests/support/helper_test.txt`: in scope; the suite the brief adds to'
	run_brief check brief.md
	assert_status 0
	assert_eq "" "$out"
}

test_check_keeps_a_test_only_brief_to_test_files_and_the_drivers_docs() {
	test_only_brief
	edit_brief 's|^scope tests/support/\*\*$|scope src/main/main.txt|'
	edit_brief 's|^scope docs/agents/facts.md$|scope docs/notes.md|'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:18 brief-test-only a test-only brief (Kind build, Phase green) scopes only test files (tools/verify/test-paths) and the Driver's docs (docs/deviations.md docs/agents/facts.md), not src/main/main.txt; a product change needs a red phase
brief.md:20 brief-test-only a test-only brief (Kind build, Phase green) scopes only test files (tools/verify/test-paths) and the Driver's docs (docs/deviations.md docs/agents/facts.md), not docs/notes.md; a product change needs a red phase" "$out"
}

# A glob counts as tests only when its fixed part lies inside a test-paths folder,
# and a . or .. part never does.
test_check_reads_a_test_only_scope_glob_by_its_fixed_part() {
	test_only_brief
	edit_brief 's|^scope tests/support/\*\*$|scope tests/*_test.txt|'
	run_brief check brief.md
	assert_status 0
	edit_brief 's|^scope tests/\*_test.txt$|scope tests/|'
	run_brief check brief.md
	assert_status 0
	local glob
	for glob in '**' 'test*/a.txt' '*/tests/a.txt' 'tests/../src/a.txt' 'tests/./a.txt' 'tests//a.txt' 'tests'; do
		test_only_brief
		edit_brief "s|^scope tests/support/\\*\\*\$|scope $glob|"
		run_brief check brief.md
		assert_status 1
		assert_line "brief.md:18 brief-test-only a test-only brief (Kind build, Phase green) scopes only test files (tools/verify/test-paths) and the Driver's docs (docs/deviations.md docs/agents/facts.md), not $glob; a product change needs a red phase"
	done
}

# Only a test-paths glob that is a whole folder covers a scope glob.
test_check_wants_a_test_paths_folder_for_a_test_only_glob() {
	test_only_brief
	echo '**/*_test.txt' > tools/verify/test-paths
	edit_brief 's|^scope tests/main/leak_test.txt$|scope tests/main/a_test.txt|'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:18 brief-test-only a test-only brief (Kind build, Phase green) scopes only test files (tools/verify/test-paths) and the Driver's docs (docs/deviations.md docs/agents/facts.md), not tests/support/**; a product change needs a red phase" "$out"
}

test_check_wants_tests_and_no_seam_in_a_test_only_brief() {
	test_only_brief
	edit_brief 's/^None$/- `tests\/support\/fake.txt` `Fake.make`: a fake./;T;:a;n;ba'
	edit_brief '/^test test_check_fails_on_an_orphan$/a seam tests/support/fake.txt Fake.make'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:23 brief-test-only a test-only brief (Kind build, Phase green) adds no seam: it changes no product file" "$out"
	test_only_brief
	edit_brief '/^- /d'
	edit_brief '/^test /d'
	run_brief check brief.md
	assert_status 1
	assert_eq "brief.md:1 brief-test-only a test-only brief (Kind build, Phase green) names at least one 'test <name>' line" "$out"
}

test_check_needs_the_test_paths_for_a_test_only_brief() {
	test_only_brief
	rm tools/verify/test-paths
	run_brief check brief.md
	assert_status 1
	assert_eq "tools/verify/test-paths:1 test-paths-missing no test-paths file; it lists the globs of the project's test files, one per line" "$out"
}

# Only Kind build in Phase green is test-only: an asset brief and a red brief scope
# what they need.
test_check_holds_only_kind_build_in_phase_green_to_tests() {
	test_only_brief
	edit_brief 's|^scope tests/support/\*\*$|scope src/main/main.txt|'
	edit_brief 's/Phase: green/Phase: red/'
	run_brief check brief.md
	assert_status 0
	asset_brief
	rm -f tools/verify/test-paths
	run_brief check brief.md
	assert_status 0
}

# --- parallel issues: no two in flight on overlapping scopes --------------------------

test_scope_overlap_errs_toward_an_overlap() {
	. "$FACTORY_CORE/lib/brief.sh"
	local pair
	for pair in "src/a.gd src/a.gd" "src/** src/a.gd" "src/a.gd src/*.gd" "src/ src/a/b.gd" \
		"tests/**/*_test.gd tests/foo.txt" "./src/a.gd SRC/A.gd" "src/a src/a/**"; do
		# shellcheck disable=SC2086
		factory_scope_overlap $pair || fail "no overlap found for: $pair"
	done
	for pair in "src/a.gd src/b.gd" "src/a.gd src/a.gd.import" "tests/game/** tests/playfield/a_test.gd" \
		"src/ab.gd src/a/*" "src/a/ src/b/"; do
		# shellcheck disable=SC2086
		factory_scope_overlap $pair && fail "an overlap found for: $pair"
	done
	return 0
}

# other_issue <n> <scope line...>: a worktree ../wt<n> on branch issue/<n>, its
# brief holding those scope lines, sealed.
other_issue() {
	local n="$1" dir
	shift
	git worktree add -q -b "issue/$n" "../wt$n" || fail "no worktree for issue $n"
	dir="$(git -C "../wt$n" rev-parse --path-format=absolute --git-dir)/factory"
	mkdir -p "$dir"
	{
		echo "${FENCE}factory-brief"
		printf '%s\n' "$@"
		echo "$FENCE"
	} > "$dir/brief.md"
	git config "branch.issue/$n.factory-brief-sha" "$(git hash-object --no-filters "$dir/brief.md")"
}

test_seal_refuses_a_scope_an_issue_in_flight_shares() {
	sealed_repo
	other_issue 2 "scope src/stock/supplier.txt" "scope docs/deviations.md"
	run_brief seal
	assert_status 1
	assert_eq ".git/factory/brief.md:22 brief-overlap scope src/stock/** may overlap src/stock/supplier.txt, in the scope of issue/2, which is in flight; seal this brief once it has landed" "$out"
	git config branch.issue/1.factory-brief-sha > /dev/null && fail "an overlapping brief was sealed"
	git worktree remove --force ../wt2 && git branch -q -D issue/2
	run_brief seal
	assert_status 0
}

test_seal_passes_beside_issues_apart_or_unsealed() {
	sealed_repo
	other_issue 2 "scope src/other/x.txt" "scope docs/deviations.md" "scope docs/agents/facts.md"
	other_issue 3 "scope src/stock/supplier.txt"
	git config --unset branch.issue/3.factory-brief-sha
	sed -i 's|^scope tests/stock/\*\*$|scope tests/stock/**\nscope docs/deviations.md\nscope docs/agents/facts.md|' .git/factory/brief.md
	run_brief seal
	assert_status 0
	assert_eq "brief: sealed .git/factory/brief.md for issue/1 at $(git hash-object --no-filters .git/factory/brief.md)" "$out"
}

# An issue in flight whose brief can't be read at the usual path may overlap
# anything, so it holds every other seal until it lands.
test_seal_refuses_beside_an_issue_whose_brief_cant_be_read() {
	sealed_repo
	other_issue 2 "scope src/other/x.txt"
	rm "$(git -C ../wt2 rev-parse --path-format=absolute --git-dir)/factory/brief.md"
	run_brief seal
	assert_status 1
	assert_line ".git/factory/brief.md:1 brief-overlap issue/2 is in flight but its brief can't be read at $(git -C ../wt2 rev-parse --path-format=absolute --git-dir)/factory/brief.md, so its scope may overlap; seal this brief once it has landed"
	git config branch.issue/1.factory-brief-sha > /dev/null && fail "a brief was sealed beside an unreadable one"
	return 0
}

# Seals take turns through a lock folder in the shared git folder, and leave none.
test_seal_waits_for_another_seal_and_leaves_no_lock() {
	sealed_repo
	mkdir .git/factory-seal.lock
	FACTORY_SEAL_WAIT=1 run_brief seal
	assert_status 1
	stderr_has "brief: another seal holds $PWD/.git/factory-seal.lock"
	git config branch.issue/1.factory-brief-sha > /dev/null && fail "sealed while another seal held the lock"
	rmdir .git/factory-seal.lock
	run_brief seal
	assert_status 0
	[ -e .git/factory-seal.lock ] && fail "the seal left its lock behind"
	return 0
}

# Two seals at once on overlapping scopes: one seals, the other sees it.
test_two_seals_at_once_on_one_scope_seal_only_one() {
	sealed_repo
	git worktree add -q -b issue/2 ../wt2 || fail "no worktree"
	mkdir -p .git/worktrees/wt2/factory
	cp .git/factory/brief.md .git/worktrees/wt2/factory/brief.md
	bash "$FACTORY_CORE/brief.sh" seal > /dev/null 2>&1 &
	one=$!
	(cd ../wt2 && bash "$FACTORY_CORE/brief.sh" seal > /dev/null 2>&1) &
	two=$!
	sealed=0
	wait "$one" && sealed=$((sealed + 1))
	wait "$two" && sealed=$((sealed + 1))
	assert_eq 1 "$sealed"
}

# A seal stopped by a signal once it holds the lock still releases it.
test_a_seal_stopped_by_a_signal_releases_its_lock() {
	sealed_repo
	other_issue 2 "scope src/other/x.txt"
	# The overlap check runs brief.sh scope on issue 2's brief; in a stand-in core,
	# brief.sh blocks there until the test releases it, so the test stops the seal
	# while it holds the lock. bash runs the TERM trap once that command ends.
	mkdir -p "$TEST_TMP/core"
	cp -R "$FACTORY_CORE/." "$TEST_TMP/core/"
	blocking_stand_in "$TEST_TMP/block" "$TEST_TMP/release"
	sed -i 's|^what="\$1"$|what="$1"; [ "$what" = scope ] \&\& "$TEST_TMP/block"|' "$TEST_TMP/core/brief.sh"
	bash "$TEST_TMP/core/brief.sh" seal > /dev/null 2>&1 &
	seal=$!
	wait_until "the seal to reach the overlap check" test -s "$TEST_TMP/block.pid"
	[ -d .git/factory-seal.lock ] || fail "the seal reached the overlap check without its lock"
	kill -TERM "$seal"
	: > "$TEST_TMP/release"
	wait "$seal" && fail "the stopped seal exited 0"
	[ -e .git/factory-seal.lock ] && fail "the stopped seal left its lock behind"
	git config branch.issue/1.factory-brief-sha > /dev/null && fail "the stopped seal sealed"
	return 0
}

# A signal that lands as the seal takes its lock, after mkdir and before the seal
# marks it held, still releases it: one to the seal alone, and one to the seal and
# its mkdir both, as a Ctrl-C reaches the process group (pass 1's review). A
# stand-in mkdir sends TERM as soon as it has made the lock folder.
test_a_signal_as_the_seal_takes_its_lock_releases_it() {
	local to
	sealed_repo
	mkdir -p "$TEST_TMP/bin"
	for to in '"$PPID"' '"$PPID" "$$"'; do
		cat > "$TEST_TMP/bin/mkdir" << SH
#!/usr/bin/env bash
$(printf '%q' "$(command -v mkdir)") "\$@" || exit
case "\${!#}" in */factory-seal.lock) kill -TERM $to ;; esac
SH
		chmod 755 "$TEST_TMP/bin/mkdir"
		PATH="$TEST_TMP/bin:$PATH" run_brief seal
		assert_status 1
		[ -e .git/factory-seal.lock ] && fail "a TERM to $to as the seal took its lock left the lock behind"
		git config branch.issue/1.factory-brief-sha > /dev/null && fail "the stopped seal sealed"
	done
	return 0
}
