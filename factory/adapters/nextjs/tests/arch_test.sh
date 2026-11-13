# The Next.js arch step (tools/verify/arch, _arch_imports.mjs): ARCHITECTURE.md's
# sync check and its import checks, on a project made from the skeleton with the
# fixtures in tests/fixture/arch.
#
# They need Node, pnpm and a primed pnpm store (FACTORY_PNPM_STORE), and skip
# without them, but the one naming a missing dependency-cruiser.

# shellcheck disable=SC2154 # out and status: set by run_cmd, in factory/core/tests/lib.sh
NEXTJS_ADAPTER="$FACTORY_CORE/../adapters/nextjs"
. "$NEXTJS_ADAPTER/tests/lib.sh"

# arch_project: skeleton_project with its packages installed (prepare), or fail.
arch_project() {
	needs_store
	skeleton_project
	step prepare
	[ "$status" -eq 0 ] || fail "prepare failed on the skeleton: $out"$'\n'"$(tail -n 20 "$TEST_TMP/stderr")"
}

# rule <id>: the number of the default rule citing arch:<id>, as R<n>.
rule() {
	grep -B1 "arch:$1" ARCHITECTURE.md | sed -n 's/^\*\*\(R[0-9]*\)\.\*\*.*/\1/p'
}

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
	local r6 r9 r10 keep
	r6="$(rule client-server)" r9="$(rule next-in-app)" r10="$(rule fonts-local)"
	keep="keep it on the server and pass the client what it needs as props or through a server action"
	assert_eq "app/_components/cart.tsx:12 $r6 imports @/server/db, which is server-only (server/db.ts: under server/), into client code (app/_components/cart.tsx is \"use client\"); $keep
app/_components/cart.tsx:7 $r6 imports ../../server/db, which is server-only (server/db.ts: under server/), into client code (app/_components/cart.tsx is \"use client\"); $keep
app/_components/cart.tsx:8 $r6 imports ../api/health/route, which is server-only (app/api/health/route.ts: a route handler), into client code (app/_components/cart.tsx is \"use client\"); $keep
lib/format.ts:1 $r6 imports ./secrets, which is server-only (lib/secrets.ts: it imports \"server-only\"), into client code (lib/format.ts is reached from app/_components/cart.tsx, a \"use client\" file); $keep
lib/link.ts:3 $r9 imports next/link outside app/; only app/ (its pages, layouts and route handlers) uses Next's runtime: move this code into app/, or pass it what it needs from there
lib/link.ts:4 $r9 imports next/navigation outside app/; only app/ (its pages, layouts and route handlers) uses Next's runtime: move this code into app/, or pass it what it needs from there
app/fonts.ts:1 $r10 imports next/font/google, which next build downloads, and the gates run offline; use next/font/local with the font files in the repo" "$out" "arch's findings"
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
	printf '\n**R11.** Something new.\nEnforced by: `arch:made-up`\nSource: convention\n' >> ARCHITECTURE.md
	sed -i 's/^Enforced by: `arch:next-in-app`$/Enforced by: `review`/' ARCHITECTURE.md
	step arch
	assert_status 1
	assert_eq "ARCHITECTURE.md:$(grep -n 'arch:made-up' ARCHITECTURE.md | cut -d: -f1) arch-sync arch:made-up (R11) has no check
tools/verify/arch:1 arch-sync check next-in-app is cited by no rule" "$out" "the sync check's findings"
}

test_arch_names_dependency_cruiser_not_installed_with_node() {
	needs_node
	skeleton_project
	step arch
	assert_status 1
	assert_eq "package.json:1 tool-missing node_modules/.bin/depcruise is not installed; run bash tools/verify.sh prepare (on a new machine, bash tools/verify/bootstrap first)" "$out" "arch's finding"
}

test_the_reader_refuses_what_isnt_dependency_cruisers_graph_with_node() {
	needs_node
	echo '{"summary":{}}' > "$TEST_TMP/graph.json"
	: > "$TEST_TMP/list"
	run_cmd "${NODE_BIN:-node}" "$NEXTJS_ADAPTER/tools/verify/_arch_imports.mjs" "$TEST_TMP/graph.json" "$TEST_TMP/list" "$TEST_TMP/list"
	assert_status 2
	stderr_has "isn't dependency-cruiser's JSON"
}
