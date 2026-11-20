# The Next.js arch step (tools/verify/arch, _arch_imports.mjs): ARCHITECTURE.md's
# sync check and its import checks, on a project made from the skeleton with the
# fixtures in tests/fixture/arch.
#
# They need Node, pnpm and a primed pnpm store (FACTORY_PNPM_STORE), and skip
# without them, but the one naming a missing dependency-cruiser.

# shellcheck disable=SC2154 # out and status: set by run_cmd, in factory/core/tests/lib.sh
NEXTJS_ADAPTER="$FACTORY_CORE/../adapters/nextjs"
. "$NEXTJS_ADAPTER/tests/lib.sh"

# arch_project: primed_project, the skeleton with its packages installed (prepare).
arch_project() {
	needs_store
	primed_project
}

# rule <id>: the number of the default rule citing arch:<id>, as R<n>.
rule() {
	grep -B1 "arch:$1" ARCHITECTURE.md | sed -n 's/^\*\*\(R[0-9]*\)\.\*\*.*/\1/p'
}

# The fix an input-zod finding names.
zod="pass its input through a schema's .parse or .safeParse (here, or in a function this one calls) before using it"

test_the_skeleton_passes_and_each_import_rule_finds_its_lines_with_node() {
	arch_project
	step arch
	assert_status 0
	assert_eq "" "$out" "arch on the skeleton"

	add_fixture arch/db.ts.txt server/db.ts
	add_fixture arch/secrets.ts.txt lib/secrets.ts
	add_fixture arch/format.ts.txt lib/format.ts
	add_fixture arch/actions.ts.txt app/actions.ts
	add_fixture arch/cart.tsx.txt app/_components/cart.tsx
	add_fixture arch/nav.tsx.txt app/_components/nav.tsx
	add_fixture arch/nav.tsx.txt pages/nav.tsx
	add_fixture arch/badge.tsx.txt app/_components/badge.tsx
	add_fixture arch/link.ts.txt lib/link.ts
	add_fixture arch/proxy.ts.txt proxy.ts
	add_fixture arch/request.test.ts.txt tests/request.test.ts
	add_fixture arch/fonts.ts.txt app/fonts.ts
	step arch
	assert_status 1
	local r6 r9 r10 r11 keep
	r6="$(rule client-server)" r9="$(rule next-in-app)" r10="$(rule fonts-local)" r11="$(rule input-zod)"
	keep="keep it on the server and pass the client what it needs as props or through a server action"
	assert_eq "app/_components/cart.tsx:12 $r6 imports @/server/db, which is server-only (server/db.ts: under server/), into client code (app/_components/cart.tsx is \"use client\"); $keep
app/_components/cart.tsx:7 $r6 imports ../../server/db, which is server-only (server/db.ts: under server/), into client code (app/_components/cart.tsx is \"use client\"); $keep
app/_components/cart.tsx:8 $r6 imports ../api/health/route, which is server-only (app/api/health/route.ts: a route handler), into client code (app/_components/cart.tsx is \"use client\"); $keep
lib/format.ts:1 $r6 imports ./secrets, which is server-only (lib/secrets.ts: it imports \"server-only\"), into client code (lib/format.ts is reached from app/_components/cart.tsx, a \"use client\" file); $keep
lib/link.ts:3 $r9 imports next/link outside app/; only app/ (its pages, layouts and route handlers) uses Next's runtime: move this code into app/, or pass it what it needs from there
lib/link.ts:4 $r9 imports next/navigation outside app/; only app/ (its pages, layouts and route handlers) uses Next's runtime: move this code into app/, or pass it what it needs from there
app/fonts.ts:1 $r10 imports next/font/google, which next build downloads, and the gates run offline; use next/font/local with the font files in the repo
app/actions.ts:5 $r11 server action rename reads its argument id and parses none of it with zod; $zod" "$out" "arch's findings"
}

# Route handlers and server actions that read their input and parse none of it
# with zod: one finding each. Those that parse it, here or in a function they
# call, and those that read no input (a URL they build, a raw body they
# forward, an action with no argument) are none.
test_input_zod_finds_handlers_and_actions_that_parse_no_input_with_node() {
	arch_project
	add_fixture arch/items-route.ts.txt "app/api/items/[id]/route.ts"
	add_fixture arch/search-route.ts.txt app/api/search/route.ts
	add_fixture arch/parsed-route.ts.txt app/api/parsed/route.ts
	add_fixture arch/validate.ts.txt lib/validate.ts
	add_fixture arch/helper-route.ts.txt app/api/helper/route.ts
	add_fixture arch/defaulted.ts.txt lib/defaulted.ts
	add_fixture arch/barrel.ts.txt lib/checks/index.ts
	add_fixture arch/reexported-route.ts.txt app/api/reexported/route.ts
	add_fixture arch/zod-parse-route.ts.txt app/api/zod-parse/route.ts
	# Four files that each export * from the other three: a lookup ends.
	local f g
	mkdir -p lib/ring
	for f in a b c d; do
		for g in a b c d; do
			[ "$f" = "$g" ] || echo "export * from \"./$g\";"
		done > "lib/ring/$f.ts"
		echo "export const ${f}Value = 1;" >> "lib/ring/$f.ts"
	done
	echo "export const helper = String;" >> lib/ring/d.ts
	printf 'export { readQuery } from "@/lib/validate";\n' >> lib/ring/c.ts
	add_fixture arch/ring-route.ts.txt app/api/ring/route.ts
	add_fixture arch/zod-actions.ts.txt app/form/actions.ts
	add_fixture arch/form.tsx.txt app/form/page.tsx
	add_fixture arch/items-route.ts.txt "tests/route.test.ts"
	step arch
	assert_status 1
	local r11
	r11="$(rule input-zod)"
	assert_eq "app/api/items/[id]/route.ts:1 $r11 route handler GET reads route params and parses none of it with zod; $zod
app/api/items/[id]/route.ts:9 $r11 route handler POST reads its body and parses none of it with zod; $zod
app/api/search/route.ts:1 $r11 route handler GET reads search params and parses none of it with zod; $zod
app/form/actions.ts:7 $r11 server action rename reads its argument formData and parses none of it with zod; $zod
app/form/page.tsx:4 $r11 server action save reads its argument formData and parses none of it with zod; $zod" "$out" "arch's findings"
}

# A client file importing the server-only package itself, and a server-only
# module reached only through types or a "use server" file: one finding.
test_client_code_importing_server_only_itself_is_a_finding_with_node() {
	arch_project
	printf '"use client";\nimport "server-only";\n\nexport const x = 1;\n' > app/widget.tsx
	step arch
	assert_status 1
	assert_eq "app/widget.tsx:2 $(rule client-server) imports server-only, which is server-only (the server-only package), into client code (app/widget.tsx is \"use client\"); keep it on the server and pass the client what it needs as props or through a server action" "$out" "arch's finding"
}

test_the_sync_check_fails_on_a_rule_without_a_check_and_a_check_without_a_rule_with_node() {
	arch_project
	printf '\n**R16.** Something new.\nEnforced by: `arch:made-up`\nSource: convention\n' >> ARCHITECTURE.md
	sed -i 's/^Enforced by: `arch:next-in-app`$/Enforced by: `review`/' ARCHITECTURE.md
	step arch
	assert_status 1
	assert_eq "ARCHITECTURE.md:$(grep -n 'arch:made-up' ARCHITECTURE.md | cut -d: -f1) arch-sync arch:made-up (R16) has no check
tools/verify/arch:1 arch-sync check next-in-app is cited by no rule" "$out" "the sync check's findings"
}

test_arch_names_dependency_cruiser_not_installed_with_node() {
	needs_node
	skeleton_project
	step arch
	assert_status 1
	assert_eq "package.json:1 tool-missing node_modules/.bin/depcruise is not installed; run bash tools/verify.sh prepare (on a new machine, bash tools/verify/bootstrap first)" "$out" "arch's finding"
}

# #19: the pre-commit hook runs arch on a copy of the index, which has no
# node_modules, with FACTORY_ARCH_STATIC_ONLY=1. Every import check reads
# dependency-cruiser's graph, so none runs there, nor does the tool check: a
# staged change gets no tool-missing (and no Node is needed), and the full verify
# still runs them (the tests above).
test_the_pre_commit_hook_on_a_tree_without_node_modules_reports_no_tool_missing() {
	skeleton_project
	add_fixture arch/fonts.ts.txt app/fonts.ts
	git add -A || fail "could not stage the skeleton"
	NODE_BIN=/no/such/node run_cmd bash "$FACTORY_CORE/hooks/pre-commit.sh"
	assert_status 0
	assert_eq "" "$(cat "$TEST_TMP/stderr")" "the hook's report"
}

# Static-only, the sync check still runs: it reads ARCHITECTURE.md alone.
test_static_only_arch_runs_the_sync_check_alone() {
	skeleton_project
	add_fixture arch/fonts.ts.txt app/fonts.ts
	printf '\n**R16.** Something new.\nEnforced by: `arch:made-up`\nSource: convention\n' >> ARCHITECTURE.md
	FACTORY_ARCH_STATIC_ONLY=1 NODE_BIN=/no/such/node step arch
	assert_status 1
	assert_eq "ARCHITECTURE.md:$(grep -n 'arch:made-up' ARCHITECTURE.md | cut -d: -f1) arch-sync arch:made-up (R16) has no check" "$out" "static-only arch's findings"
}

test_the_reader_refuses_what_isnt_dependency_cruisers_graph_with_node() {
	needs_node
	echo '{"summary":{}}' > "$TEST_TMP/graph.json"
	: > "$TEST_TMP/list"
	run_cmd "${NODE_BIN:-node}" "$NEXTJS_ADAPTER/tools/verify/_arch_imports.mjs" "$TEST_TMP/graph.json" "$TEST_TMP/list" "$TEST_TMP/list"
	assert_status 2
	stderr_has "isn't dependency-cruiser's JSON"
}

# The lint-tags check: each `lint:<rule>` tag names a rule the lint step runs.
# stand_in_tools gives the skeleton stand-ins for what the import checks read, so
# they find nothing (dependency-cruiser's graph is empty, and TypeScript's parser
# sees no statement), and a stand-in ESLint package whose
# ESLint#calculateConfigForFile(<file>) appends <file> to node_modules/.asked and
# gives node_modules/.eslint-config.<ext> for a file ending in .<ext> when there
# is one, else node_modules/.eslint-config (`undefined` gives undefined), and
# throws when node_modules/.eslint-exit exists.
stand_in_tools() {
	mkdir -p node_modules/.bin node_modules/typescript node_modules/eslint || fail "could not make node_modules"
	printf '#!/usr/bin/env bash\necho %s\n' "'{\"modules\":[]}'" > node_modules/.bin/depcruise
	echo '{"name":"typescript","type":"module","main":"index.js"}' > node_modules/typescript/package.json
	cat > node_modules/typescript/index.js << 'JS'
const ts = { ScriptKind: {}, ScriptTarget: {}, SyntaxKind: {}, createSourceFile: () => ({ statements: [] }), forEachChild: () => undefined };
export default new Proxy(ts, { get: (t, k) => (k in t ? t[k] : () => false) });
JS
	echo '{"name":"eslint","main":"index.js"}' > node_modules/eslint/package.json
	cat > node_modules/eslint/index.js << 'JS'
const fs = require("node:fs");
class ESLint {
  async calculateConfigForFile(file) {
    fs.appendFileSync("node_modules/.asked", file + "\n");
    if (fs.existsSync("node_modules/.eslint-exit")) throw new Error("stand-in ESLint fails");
    const ext = file.slice(file.lastIndexOf(".") + 1);
    const path = fs.existsSync(`node_modules/.eslint-config.${ext}`) ? `node_modules/.eslint-config.${ext}` : "node_modules/.eslint-config";
    const text = fs.readFileSync(path, "utf8").trim();
    return text === "undefined" ? undefined : JSON.parse(text);
  }
}
module.exports = { ESLint };
JS
	printf '#!/usr/bin/env bash\nexit 9\n' > node_modules/.bin/eslint
	chmod +x node_modules/.bin/depcruise node_modules/.bin/eslint || fail "could not make the stand-ins runnable"
}

# bans: the skeleton's bans' rules (R12-R14), on, for a stand-in config, which
# the tests about the other tags splice in.
bans='"@typescript-eslint/consistent-type-assertions":2,"@typescript-eslint/no-non-null-assertion":2,"@typescript-eslint/switch-exhaustiveness-check":2,"no-restricted-syntax":2,"no-warning-comments":2'

# bans_to_review: the bans' rules (R12-R14) enforced by review alone, so their
# tags ask ESLint nothing.
bans_to_review() {
	sed -i -e '/^Enforced by: `lint:\(@typescript-eslint\/consistent-type-assertions\|no-restricted-syntax\|no-warning-comments\)`/s/^.*$/Enforced by: `review`/' ARCHITECTURE.md
	! grep -q 'lint:\(@typescript-eslint/consistent-type-assertions\|no-restricted-syntax\|no-warning-comments\)`' ARCHITECTURE.md ||
		fail "could not take the bans' lint tags out"
}

# tag_line <rule>: the line of ARCHITECTURE.md holding `lint:<rule>`.
tag_line() {
	grep -nF "\`lint:$1\`" ARCHITECTURE.md | cut -d: -f1
}

# asked: the files the stand-in ESLint was asked about, or (none).
asked() {
	if [ -f node_modules/.asked ]; then cat node_modules/.asked; else echo "(none)"; fi
}

test_lint_tags_whose_rules_are_on_are_no_finding_with_node() {
	needs_node
	skeleton_project
	stand_in_tools
	echo '{"rules":{'"$bans"',"@typescript-eslint/no-floating-promises":[2],"@typescript-eslint/no-unsafe-assignment":"warn","@typescript-eslint/no-unsafe-member-access":["error",{"x":1}],"no-console":[0]}}' > node_modules/.eslint-config
	step arch
	assert_status 0
	assert_eq "" "$out" "arch's findings"
	assert_eq "app/api/health/route.ts" "$(asked)" "the file ESLint was asked about: the first non-test one"
}

test_lint_tags_ask_about_a_file_under_src_when_one_is_there_with_node() {
	needs_node
	skeleton_project
	stand_in_tools
	echo '{"rules":{'"$bans"',"@typescript-eslint/no-floating-promises":1,"@typescript-eslint/no-unsafe-assignment":2,"@typescript-eslint/no-unsafe-member-access":"error"}}' > node_modules/.eslint-config
	mkdir -p src/lib
	printf 'export const a = 1;\n' > src/lib/a.ts
	printf 'export const b = 1;\n' > src/a.test.ts
	step arch
	assert_status 0
	assert_eq "" "$out" "arch's findings"
	assert_eq "src/lib/a.ts" "$(asked)" "the file ESLint was asked about"
}

test_a_lint_tag_whose_eslint_rule_is_off_or_unset_is_a_finding_at_its_line_with_node() {
	needs_node
	skeleton_project
	stand_in_tools
	echo '{"rules":{'"$bans"',"@typescript-eslint/no-floating-promises":[0],"@typescript-eslint/no-unsafe-assignment":"off"}}' > node_modules/.eslint-config
	step arch
	assert_status 1
	local fix="(eslint --print-config); turn it on (warn or error) in the ESLint config, or change this rule's Enforced by: line"
	assert_eq "ARCHITECTURE.md:$(tag_line @typescript-eslint/no-floating-promises) R2 lint:@typescript-eslint/no-floating-promises is not on: ESLint's config turns it off for app/api/health/route.ts $fix
ARCHITECTURE.md:$(tag_line @typescript-eslint/no-unsafe-assignment) R3 lint:@typescript-eslint/no-unsafe-assignment is not on: ESLint's config turns it off for app/api/health/route.ts $fix
ARCHITECTURE.md:$(tag_line @typescript-eslint/no-unsafe-member-access) R3 lint:@typescript-eslint/no-unsafe-member-access is not on: no ESLint config sets it for app/api/health/route.ts $fix" "$out" "arch's findings"
}

test_a_lint_tag_on_a_file_eslints_config_ignores_is_a_finding_with_node() {
	needs_node
	skeleton_project
	stand_in_tools
	sed -i 's/^Enforced by: `lint:@typescript-eslint\/no-unsafe-assignment`.*$/Enforced by: `review`/' ARCHITECTURE.md
	bans_to_review
	echo undefined > node_modules/.eslint-config
	step arch
	assert_status 1
	assert_eq "ARCHITECTURE.md:$(tag_line @typescript-eslint/no-floating-promises) R2 lint:@typescript-eslint/no-floating-promises is not on: the ESLint config ignores app/api/health/route.ts (eslint --print-config); turn it on (warn or error) in the ESLint config, or change this rule's Enforced by: line" "$out" "arch's finding"
}

test_the_lint_steps_own_checks_as_lint_tags_are_no_finding_and_ask_eslint_nothing_with_node() {
	needs_node
	skeleton_project
	stand_in_tools
	bans_to_review
	sed -i 's/^Enforced by: `lint:@typescript-eslint.*$/Enforced by: `review`/' ARCHITECTURE.md
	grep -qF 'Enforced by: `lint:assertion-free`, `lint:fixed-wait`' ARCHITECTURE.md || fail "the skeleton's R5 cites no assertion-free and fixed-wait"
	echo 9 > node_modules/.eslint-exit
	step arch
	assert_status 0
	assert_eq "" "$out" "arch's findings"
	assert_eq "(none)" "$(asked)" "the files ESLint was asked about"
}

test_no_lint_tags_and_no_rules_are_no_lint_tags_finding_with_node() {
	needs_node
	skeleton_project
	stand_in_tools
	echo 9 > node_modules/.eslint-exit
	sed -i 's/^Enforced by: `lint:.*$/Enforced by: `review`/' ARCHITECTURE.md
	step arch
	assert_status 0
	assert_eq "" "$out" "arch's findings with no lint: tags"

	printf '# Architecture\n\nNo rules yet; `lint:no-floating-promises` in prose is no tag.\n' > ARCHITECTURE.md
	step arch
	assert_status 1
	assert_eq "tools/verify/arch:1 arch-sync check client-server is cited by no rule
tools/verify/arch:1 arch-sync check next-in-app is cited by no rule
tools/verify/arch:1 arch-sync check fonts-local is cited by no rule
tools/verify/arch:1 arch-sync check input-zod is cited by no rule" "$out" "arch's findings with no Rules section"
	assert_eq "(none)" "$(asked)" "the files ESLint was asked about"
}

test_eslint_failing_to_print_its_config_is_an_arch_error_with_node() {
	needs_node
	skeleton_project
	stand_in_tools
	: > node_modules/.eslint-config
	echo 2 > node_modules/.eslint-exit
	step arch
	assert_status 1
	assert_eq "tools/verify/arch:1 arch-error check lint-tags: ESLint could not give the config of a file it lints (see stderr)" "$out" "arch's finding"
	stderr_has "could not give the config for app/api/health/route.ts"
}

# A rule a config turns on only for some files (here .tsx: the skeleton's
# app/layout.tsx) holds, though the representative file (the first non-test .ts
# or .tsx, here a .ts) has it off.
test_a_lint_tag_on_only_for_files_after_the_first_is_no_finding_with_node() {
	needs_node
	skeleton_project
	stand_in_tools
	echo '{"rules":{'"$bans"',"@typescript-eslint/no-floating-promises":2,"@typescript-eslint/no-unsafe-assignment":2,"@typescript-eslint/no-unsafe-member-access":"off"}}' > node_modules/.eslint-config
	echo '{"rules":{'"$bans"',"@typescript-eslint/no-floating-promises":2,"@typescript-eslint/no-unsafe-assignment":2,"@typescript-eslint/no-unsafe-member-access":"warn"}}' > node_modules/.eslint-config.tsx
	step arch
	assert_status 0
	assert_eq "" "$out" "arch's findings"
	assert_eq "app/api/health/route.ts" "$(head -n 1 node_modules/.asked)" "the file ESLint was asked about first"
	grep -qxF app/layout.tsx node_modules/.asked || fail "ESLint was not asked about app/layout.tsx: $(asked)"
}

# A rule on for no file the lint step lints is a finding, for the representative file.
test_a_lint_tag_on_for_no_file_is_a_finding_with_node() {
	needs_node
	skeleton_project
	stand_in_tools
	echo '{"rules":{'"$bans"',"@typescript-eslint/no-floating-promises":2,"@typescript-eslint/no-unsafe-assignment":2,"@typescript-eslint/no-unsafe-member-access":"off"}}' > node_modules/.eslint-config
	echo '{"rules":{'"$bans"',"@typescript-eslint/no-floating-promises":2,"@typescript-eslint/no-unsafe-assignment":2}}' > node_modules/.eslint-config.tsx
	step arch
	assert_status 1
	assert_eq "ARCHITECTURE.md:$(tag_line @typescript-eslint/no-unsafe-member-access) R3 lint:@typescript-eslint/no-unsafe-member-access is not on: ESLint's config turns it off for app/api/health/route.ts (eslint --print-config); turn it on (warn or error) in the ESLint config, or change this rule's Enforced by: line" "$out" "arch's finding"
	grep -qxF app/layout.tsx node_modules/.asked || fail "ESLint was not asked about app/layout.tsx: $(asked)"
}

# The real ESLint, on the skeleton's config with R2's rule switched off.
test_the_skeletons_config_with_a_tagged_rule_off_is_a_finding_with_node() {
	arch_project
	sed -i 's/^);$/  { rules: { "@typescript-eslint\/no-floating-promises": "off" } },\n);/' eslint.config.mjs
	grep -q 'no-floating-promises": "off"' eslint.config.mjs || fail "could not switch the rule off"
	step arch
	assert_status 1
	assert_eq "ARCHITECTURE.md:$(tag_line @typescript-eslint/no-floating-promises) R2 lint:@typescript-eslint/no-floating-promises is not on: ESLint's config turns it off for app/api/health/route.ts (eslint --print-config); turn it on (warn or error) in the ESLint config, or change this rule's Enforced by: line" "$out" "arch's finding"
}
