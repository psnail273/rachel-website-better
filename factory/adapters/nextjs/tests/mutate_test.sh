# The Next.js mutate step (tools/verify/mutate): StrykerJS with its Vitest runner
# on a project made from the skeleton, with the fixtures in tests/fixture/mutate,
# and its reader of Stryker's JSON report (_stryker_mutants.mjs).
#
# The step's tests need Node, pnpm and a primed pnpm store (FACTORY_PNPM_STORE)
# and skip without them; the reader's need only Node. Stryker runs with two
# workers and a minute's timeout a mutant, so a loaded machine times none out.

# shellcheck disable=SC2154 # out and status: set by run_cmd, in factory/core/tests/lib.sh
NEXTJS_ADAPTER="$FACTORY_CORE/../adapters/nextjs"
. "$NEXTJS_ADAPTER/tests/lib.sh"

TAB=$'\t'

# mutate_project: the skeleton, prepared, with lib/cart.ts and its test
# committed as the base (MUTATE_BASE); then cart.ts gains discount, which the
# test checks only above 100. The project's Stryker config gains a timeout.
mutate_project() {
	needs_store
	skeleton_project
	step prepare
	[ "$status" -eq 0 ] || fail "prepare failed on the skeleton: $out"$'\n'"$(tail -n 20 "$TEST_TMP/stderr")"
	sed -i 's#^{#{\n  "timeoutMS": 60000,#' stryker.config.json
	add_fixture mutate/cart_base.ts.txt lib/cart.ts
	add_fixture mutate/cart_base.test.ts.txt lib/cart.test.ts
	git add -A && git commit -q -m base || fail "commit failed"
	MUTATE_BASE="$(git rev-parse HEAD)"
	add_fixture mutate/cart.ts.txt lib/cart.ts
	add_fixture mutate/cart.test.ts.txt lib/cart.test.ts
}

# run_mutate: the mutate step, as the runner runs it in the Green phase.
run_mutate() {
	FACTORY_SURVIVORS_FILE="$TEST_TMP/survivors.txt" FACTORY_MUTATE_BASE="$MUTATE_BASE" STRYKER_JOBS=2 step mutate
}

# tree: what git sees of the project, ignored files too, and each file's time.
tree() {
	git status --porcelain --ignored --untracked-files=all | grep -v '^!! node_modules/'
	find . -path ./node_modules -prune -o -path ./.git -prune -o -type f -printf '%T@ %p\n' | LC_ALL=C sort -k 2
}

survivors() { cat "$TEST_TMP/survivors.txt" 2> /dev/null || echo "(no survivors file)"; }

# Only discount's lines are mutated (total's sum - price, which no test would
# catch, is on an unchanged line), and each mutant runs: the two the test misses
# survive, with the test file that covers them.
test_mutate_keeps_what_survives_on_the_changed_lines_with_node() {
	mutate_project
	tree > "$TEST_TMP/before"
	run_mutate
	assert_status 0
	assert_eq "lib/cart.ts:7 mutant-survived ConditionalExpression: \`sum > 100\` -> \`true\`; tests: lib/cart.test.ts
lib/cart.ts:7 mutant-survived EqualityOperator: \`sum > 100\` -> \`sum >= 100\`; tests: lib/cart.test.ts" "$out" "the step's findings"
	assert_eq "# StrykerJS 10.1.1 on the lines changed since $(git rev-parse --short "$MUTATE_BASE"), each mutant against the tests that cover it (tools/verify/mutate)
# killed 4, survived 2, errored 0, timed out 0, ignored 0
lib/cart.ts:7 survived ConditionalExpression: \`sum > 100\` -> \`true\`; tests: lib/cart.test.ts
lib/cart.ts:7 survived EqualityOperator: \`sum > 100\` -> \`sum >= 100\`; tests: lib/cart.test.ts" "$(survivors)" "the survivors file"
	tree > "$TEST_TMP/after"
	assert_eq "$(cat "$TEST_TMP/before")" "$(cat "$TEST_TMP/after")" "the project after the step"
	# A test at 100 kills them both.
	add_fixture mutate/cart_pinned.test.ts.txt lib/cart.test.ts
	run_mutate
	assert_status 0
	assert_eq "" "$out" "the step's findings, pinned"
	assert_eq "# killed 6, survived 0, errored 0, timed out 0, ignored 0" "$(sed -n 2p "$TEST_TMP/survivors.txt")" "the counts, pinned"
}

# A file new since the base is mutated whole, wherever it is: brackets and
# parentheses in its path are only characters. A changed test, a tool's config at
# the root, a generated file and a file out of scope are not mutated. A mutant no
# test reaches survives with tests: none; a // Stryker disable keeps one as ignored.
test_mutate_takes_new_files_whole_and_leaves_tests_and_configs_with_node() {
	mutate_project
	add_fixture mutate/route.ts.txt "app/(shop)/orders/[id]/route.ts"
	add_fixture mutate/route.test.ts.txt "app/(shop)/orders/[id]/route.test.ts"
	add_fixture mutate/cart_pinned.test.ts.txt lib/cart.test.ts
	printf '// Stryker disable next-line all: the floor is a guess\nexport const floor = 1 + 1;\nexport const ceiling = 2 * 3;\n' > lib/limits.ts
	sed -i 's/{}/{ poweredByHeader: false }/' next.config.ts
	printf 'export const STAMP = "a" + "b";\n' > lib/stamp.generated.ts
	echo "lib/*.generated.ts" >> tools/verify/generated
	printf 'export const seed = 1 + 1;\n' > tools/seed.ts
	run_mutate
	assert_status 0
	assert_eq "app/(shop)/orders/[id]/route.ts:2 mutant-survived BooleanLiteral: \`true\` -> \`false\`; tests: app/(shop)/orders/[id]/route.test.ts
lib/limits.ts:2 mutant-ignored ArithmeticOperator: \`1 + 1\` -> \`1 - 1\`; tests: none
lib/limits.ts:3 mutant-survived ArithmeticOperator: \`2 * 3\` -> \`2 / 3\`; tests: none" "$out" "the step's findings"
}

# A module-level constant whose test file loads its module inside a test is
# covered only by the first test that loads it, so the mutant the second test
# would kill survives: the trap write-tests-nextjs steers around. Loaded at the
# file's top, the constant is static code: each of its mutants runs against
# every test, the second test kills the title's, and the untested one survives
# with tests: all (static).
test_mutate_runs_a_constant_loaded_at_the_top_against_every_test_with_node() {
	mutate_project
	add_fixture mutate/cart_pinned.test.ts.txt lib/cart.test.ts
	add_fixture mutate/labels.ts.txt lib/labels.ts
	add_fixture mutate/labels_lazy.test.ts.txt lib/labels.test.ts
	run_mutate
	assert_status 0
	assert_eq "lib/labels.ts:1 mutant-survived ObjectLiteral: \`{ title: \"Cart\", empty: \"Nothing here yet\" }\` -> \`{}\`; tests: lib/labels.test.ts
lib/labels.ts:1 mutant-survived StringLiteral: \`\"Cart\"\` -> \`\"\"\`; tests: lib/labels.test.ts
lib/labels.ts:1 mutant-survived StringLiteral: \`\"Nothing here yet\"\` -> \`\"\"\`; tests: lib/labels.test.ts" "$out" "the step's findings, loaded inside a test"
	add_fixture mutate/labels.test.ts.txt lib/labels.test.ts
	run_mutate
	assert_status 0
	assert_eq "lib/labels.ts:1 mutant-survived StringLiteral: \`\"Nothing here yet\"\` -> \`\"\"\`; tests: all (static)" "$out" "the step's findings, loaded at the top"
	assert_eq "# killed 8, survived 1, errored 0, timed out 0, ignored 0" "$(sed -n 2p "$TEST_TMP/survivors.txt")" "the counts, loaded at the top"
}

# The copy Stryker runs in holds no secret, nothing git ignores but node_modules,
# and no factory folder.
test_mutate_runs_in_a_copy_without_secrets_or_ignored_files_with_node() {
	mutate_project
	add_fixture mutate/sandbox.test.ts.txt lib/sandbox.test.ts
	echo "SECRET=1" > .env.local
	mkdir -p keys factory && echo key > keys/deploy.pem && echo core > factory/VERSION
	echo "keys/" >> tools/verify/secret-paths
	echo "notes.log" >> .gitignore && echo note > notes.log
	SANDBOX_SEEN="$TEST_TMP/seen" run_mutate
	assert_status 0
	assert_eq ".env.local false
keys/deploy.pem false
notes.log false
factory false
lib/cart.ts true" "$(awk '!seen[$0]++' "$TEST_TMP/seen")" "what the copy holds"
}

test_mutate_with_no_changed_source_mutates_nothing_with_node() {
	mutate_project
	git checkout -q -- lib/cart.ts
	run_mutate
	assert_status 0
	assert_eq "" "$out" "the step's findings"
	assert_eq "# StrykerJS 10.1.1 on the lines changed since $(git rev-parse --short "$MUTATE_BASE"), each mutant against the tests that cover it (tools/verify/mutate)
# killed 0, survived 0, errored 0, timed out 0, ignored 0
# no changed source line to mutate" "$(survivors)" "the survivors file"
}

# A test that fails before any mutant runs: Stryker exits non-zero, and the step
# fails with no survivors file.
test_mutate_failing_stryker_is_a_finding_with_node() {
	mutate_project
	sed -i 's/toBe(140)/toBe(141)/' lib/cart.test.ts
	run_mutate
	assert_status 1
	assert_eq "tools/verify/mutate:1 mutate-failed Stryker exited 1 mutating lib/cart.ts (its output is on stderr)" "$out" "the step's finding"
	assert_eq "(no survivors file)" "$(survivors)" "the survivors file"
}

test_mutate_needs_the_runner_and_stryker_with_node() {
	needs_node
	skeleton_project
	run_cmd bash tools/verify/mutate
	assert_status 2
	stderr_has "FACTORY_SURVIVORS_FILE or FACTORY_MUTATE_BASE is not set"
	MUTATE_BASE=HEAD run_mutate
	assert_status 1
	assert_eq "package.json:1 tool-missing node_modules/.bin/stryker is not installed; run bash tools/verify.sh prepare (on a new machine, bash tools/verify/bootstrap first)" "$out" "without Stryker"
}

# --- the reader, on a report of Stryker's JSON shape ---

# Each status, a mutant over two lines, a control character, the covering tests'
# files (once each, sorted), and tests: none.
test_the_reader_prints_each_mutant_with_node() {
	needs_node
	cat > "$TEST_TMP/report.json" << 'JSON'
{"files": {"lib/a.ts": {"source": "const a = 1 + 2;\nif (a) {\n  go();\n}\nconst s = \"x\ty\";\n", "mutants": [
  {"mutatorName": "ArithmeticOperator", "replacement": "1 - 2", "status": "Survived", "coveredBy": ["2", "1", "3"], "location": {"start": {"line": 1, "column": 11}, "end": {"line": 1, "column": 16}}},
  {"mutatorName": "BlockStatement", "replacement": "{}", "status": "NoCoverage", "location": {"start": {"line": 2, "column": 8}, "end": {"line": 4, "column": 2}}},
  {"mutatorName": "StringLiteral", "replacement": "\"\"", "status": "Killed", "coveredBy": ["1"], "location": {"start": {"line": 5, "column": 11}, "end": {"line": 5, "column": 16}}},
  {"mutatorName": "ConditionalExpression", "replacement": "true", "status": "Timeout", "location": {"start": {"line": 2, "column": 5}, "end": {"line": 2, "column": 6}}},
  {"mutatorName": "ConditionalExpression", "replacement": "false", "status": "CompileError", "location": {"start": {"line": 2, "column": 5}, "end": {"line": 2, "column": 6}}},
  {"mutatorName": "ConditionalExpression", "replacement": "false", "status": "Ignored", "location": {"start": {"line": 2, "column": 5}, "end": {"line": 2, "column": 6}}},
  {"mutatorName": "ArithmeticOperator", "replacement": "1 * 2", "status": "Survived", "static": true, "coveredBy": [], "location": {"start": {"line": 1, "column": 11}, "end": {"line": 1, "column": 16}}},
  {"mutatorName": "ArithmeticOperator", "replacement": "1 / 2", "status": "Survived", "static": true, "coveredBy": ["1"], "location": {"start": {"line": 1, "column": 11}, "end": {"line": 1, "column": 16}}},
  {"mutatorName": "ArithmeticOperator", "replacement": "1 % 2", "status": "Survived", "static": false, "coveredBy": ["3"], "location": {"start": {"line": 1, "column": 11}, "end": {"line": 1, "column": 16}}}
]}},
 "testFiles": {"lib/a.test.ts": {"tests": [{"id": "1", "name": "a"}, {"id": "2", "name": "b"}]}, "lib/b.test.ts": {"tests": [{"id": "3", "name": "c"}]}}}
JSON
	run_cmd "${NODE_BIN:-node}" "$NEXTJS_ADAPTER/tools/verify/_stryker_mutants.mjs" "$TEST_TMP/report.json"
	assert_status 0
	assert_eq "lib/a.ts${TAB}1${TAB}11${TAB}survived${TAB}ArithmeticOperator: \`1 + 2\` -> \`1 - 2\`${TAB}lib/a.test.ts, lib/b.test.ts
lib/a.ts${TAB}2${TAB}8${TAB}survived${TAB}BlockStatement: \`{...\` -> \`{}\`${TAB}none
lib/a.ts${TAB}5${TAB}11${TAB}killed${TAB}StringLiteral: \`\"x\\ty\"\` -> \`\"\"\`${TAB}lib/a.test.ts
lib/a.ts${TAB}2${TAB}5${TAB}timed-out${TAB}ConditionalExpression: \`a\` -> \`true\`${TAB}none
lib/a.ts${TAB}2${TAB}5${TAB}errored${TAB}ConditionalExpression: \`a\` -> \`false\`${TAB}none
lib/a.ts${TAB}2${TAB}5${TAB}ignored${TAB}ConditionalExpression: \`a\` -> \`false\`${TAB}none
lib/a.ts${TAB}1${TAB}11${TAB}survived${TAB}ArithmeticOperator: \`1 + 2\` -> \`1 * 2\`${TAB}all (static)
lib/a.ts${TAB}1${TAB}11${TAB}survived${TAB}ArithmeticOperator: \`1 + 2\` -> \`1 / 2\`${TAB}all (static)
lib/a.ts${TAB}1${TAB}11${TAB}survived${TAB}ArithmeticOperator: \`1 + 2\` -> \`1 % 2\`${TAB}lib/b.test.ts" "$out" "the reader's lines"
}

test_the_reader_refuses_what_isnt_strykers_report_with_node() {
	needs_node
	echo '{"not": "a report"}' > "$TEST_TMP/bad.json"
	run_cmd "${NODE_BIN:-node}" "$NEXTJS_ADAPTER/tools/verify/_stryker_mutants.mjs" "$TEST_TMP/bad.json"
	assert_status 2
	stderr_has "no files"
}
