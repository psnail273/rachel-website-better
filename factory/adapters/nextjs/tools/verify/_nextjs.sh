# Shared by the Next.js adapter's step scripts. Sourced; its only side effects
# are sourcing the Core's glob matcher and Scenario folder reader, reading the
# Scenario folder, putting local.env's Node and pnpm first on PATH and turning
# Next.js's telemetry off. Run from the project root.
#
# NODE_BIN and PNPM_BIN (local.env) name the Node and pnpm binaries; empty means
# the ones on PATH. Their versions are pinned in tools/verify/pins. The steps run
# the project's own tools (tsc, eslint, prettier, next) from node_modules/.bin,
# which bootstrap installs and prepare keeps in step with pnpm-lock.yaml.

# The scope: what the gates check, meaning what ships plus the tests. One glob per
# line (the Build Brief's glob syntax: `*` and `?` stay in one folder, `**` crosses
# folders, a trailing / means the whole folder); a line starting with ! takes the
# paths it matches back out. The last line that matches a path decides; a path no
# line matches is out of scope. Blank lines and # comments are ignored.
# shellcheck disable=SC2034 # these settings are read by the steps that source this
NX_SCOPE="tools/verify/scope"

# Which files are tests, and which the project's tools generate: one glob per
# line, the same syntax (the Core reads both too).
NX_TEST_PATHS="tools/verify/test-paths"
NX_GENERATED="tools/verify/generated"

# The format-exclude list: a ratchet file (it may only shrink). One
# project-relative path per line; blank lines and # comments are ignored.
NX_FORMAT_EXCLUDE="tools/verify/ratchet/format_exclude.txt"

# The files each tool reads, by extension: ESLint the code, Prettier the code and
# its JSON and CSS, and the scope cross-check the TypeScript.
NX_CODE_EXT="ts tsx mts cts js jsx mjs cjs"
NX_FORMAT_EXT="$NX_CODE_EXT json css scss"
NX_TS_EXT="ts tsx mts cts"

# Next.js sends nothing home from a gate.
export NEXT_TELEMETRY_DISABLED=1

# A tool named by a path puts its folder first on PATH, so pnpm and the tools it
# starts run that Node too.
for nx_bin in "${PNPM_BIN:-}" "${NODE_BIN:-}"; do
	case "$nx_bin" in */*) PATH="$(dirname "$nx_bin"):$PATH" ;; esac
done
unset nx_bin
export PATH

# The glob matcher is the Core's (lib/brief.sh), and so is the Scenario folder's
# reader (lib/scenarios.sh). The runner exports FACTORY_CORE; run by hand, a step
# finds the Core where adoption vendors it.
if ! declare -F factory_glob_regex > /dev/null || ! declare -F factory_scenario_folder > /dev/null; then
	if [ ! -f "${FACTORY_CORE:-factory/core}/lib/brief.sh" ]; then
		echo "no factory Core at '${FACTORY_CORE:-factory/core}'; set FACTORY_CORE" >&2
		exit 2
	fi
	declare -F factory_glob_regex > /dev/null || . "${FACTORY_CORE:-factory/core}/lib/brief.sh"
	[ -n "${FACTORY_STEPS_DIR:-}" ] || . "${FACTORY_CORE:-factory/core}/lib/steps.sh"
	. "${FACTORY_CORE:-factory/core}/lib/scenarios.sh"
fi

# The Scenario folder (tools/verify/scenario-folder), or empty when there is none.
# No gate step reads it: nx_all_files leaves it out, so neither the scope nor any
# step's own list can reach it, and the skeleton's tsconfig.json, vitest.config.ts
# and eslint.config.mjs leave it out of tsc (typecheck, next build), Vitest (test,
# mutate) and ESLint; prepare finds a config that doesn't (scenario-not-ignored).
# The Scenario driver (tools/verify/scenarios) alone runs it.
NX_SCENARIOS="$(factory_scenario_folder)" || NX_SCENARIOS=""

# node_ready: true when Node runs; else prints a finding and is false.
node_ready() {
	local node="${NODE_BIN:-node}"
	if ! command -v "$node" > /dev/null 2>&1; then
		if [ -n "${NODE_BIN:-}" ]; then
			echo "tools/verify/local.env:1 node-missing NODE_BIN '$NODE_BIN' is not a program; fix it in tools/verify/local.env"
		else
			echo "tools/verify/local.env:1 node-missing no node on PATH; install the pinned Node, or name it in NODE_BIN in tools/verify/local.env (see local.env.example)"
		fi
		return 1
	fi
}

# pnpm_ready: true when pnpm runs; else prints a finding and is false.
pnpm_ready() {
	if ! command -v "${PNPM_BIN:-pnpm}" > /dev/null 2>&1; then
		if [ -n "${PNPM_BIN:-}" ]; then
			echo "tools/verify/local.env:1 pnpm-missing PNPM_BIN '$PNPM_BIN' is not a program; fix it in tools/verify/local.env"
		else
			echo "tools/verify/local.env:1 pnpm-missing no pnpm on PATH; install pnpm, or name it in PNPM_BIN in tools/verify/local.env (see local.env.example)"
		fi
		return 1
	fi
}

# pnpm <args...>: the project's pnpm. package.json's packageManager field makes
# it run the pinned version (fetched once, by bootstrap).
pnpm() {
	command "${PNPM_BIN:-pnpm}" "$@"
}

# tool_ready <name>: true when node_modules/.bin/<name> is installed and Node
# runs; else prints a finding and is false.
tool_ready() {
	node_ready || return 1
	if [ ! -x "node_modules/.bin/$1" ]; then
		echo "package.json:1 tool-missing node_modules/.bin/$1 is not installed; run bash tools/verify.sh prepare (on a new machine, bash tools/verify/bootstrap first)"
		return 1
	fi
}

# tool <name> <args...>: run the project's installed tool.
tool() {
	local name="$1"
	shift
	"node_modules/.bin/$name" "$@"
}

# nx_glob_rules <file>: the file's globs as `<+|-> <anchored regex>` lines, one per
# non-blank, non-# line; a leading ! gives `-`.
nx_glob_rules() {
	local line sign
	[ -f "$1" ] || return 0
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line%$'\r'}"
		case "$line" in '' | '#'*) continue ;; esac
		sign=+
		if [ "${line:0:1}" = '!' ]; then
			sign=-
			line="${line:1}"
		fi
		printf '%s %s\n' "$sign" "$(factory_glob_regex "$line")"
	done < "$1"
}

# nx_filter <rules file>: the stdin paths the rules (nx_glob_rules) keep, in order.
nx_filter() {
	awk -v rules="$1" '
		BEGIN { while ((getline line < rules) > 0) { n++; sign[n] = substr(line, 1, 1); re[n] = substr(line, 3) } }
		{ keep = 0; for (i = 1; i <= n; i++) if ($0 ~ re[i]) keep = (sign[i] == "+"); if (keep) print }
	'
}

# nx_all_files <ext...>: every tracked or new (not ignored) file in the project
# with one of these extensions, one per line, sorted byte-wise; never one in the
# Scenario folder.
nx_all_files() {
	local ext
	local -a specs=()
	for ext in "$@"; do specs+=("*.$ext"); done
	git -c core.quotepath=off ls-files --cached --others --exclude-standard -- "${specs[@]}" |
		while IFS= read -r f; do
			[ -z "$NX_SCENARIOS" ] || case "$f" in "$NX_SCENARIOS"/*) continue ;; esac
			[ -f "$f" ] && printf '%s\n' "$f"
		done |
		LC_ALL=C sort -u
}

# nx_files <ext...>: the files with these extensions the gates check, one per
# line, sorted byte-wise: nx_all_files narrowed by the scope. With no scope file,
# everything outside factory/ and tools/ (prepare reports the missing scope).
nx_files() {
	if [ ! -f "$NX_SCOPE" ]; then
		nx_all_files "$@" | grep -Ev '^(factory|tools)/'
		return 0
	fi
	local rules
	rules="$(mktemp)"
	nx_glob_rules "$NX_SCOPE" > "$rules"
	nx_all_files "$@" | nx_filter "$rules"
	rm -f "$rules"
}

# nx_tests: the stdin paths that are tests, by NX_TEST_PATHS's globs (the seeded
# defaults when it holds none), in order.
nx_tests() {
	local rules
	rules="$(mktemp)"
	nx_glob_rules "$NX_TEST_PATHS" > "$rules"
	[ -s "$rules" ] || printf '+ %s\n' "$(factory_glob_regex '**/*.test.ts')" "$(factory_glob_regex '**/*.test.tsx')" "$(factory_glob_regex 'tests/**')" > "$rules"
	nx_filter "$rules"
	rm -f "$rules"
}

# nx_format_excluded: the format-exclude list's paths, one per line, as
# "<line number> <path>".
nx_format_excluded() {
	[ -f "$NX_FORMAT_EXCLUDE" ] || return 0
	awk '{ sub(/\r$/, ""); sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
		$0 != "" && $0 !~ /^#/ { print NR " " $0 }' "$NX_FORMAT_EXCLUDE"
}

# json_line <file> <key>: the line of the file's first "<key>": , else 1.
json_line() {
	[ -f "$1" ] || {
		echo 1
		return
	}
	awk -v k="\"$2\"" '{ i = index($0, k); if (i && substr($0, i + length(k)) ~ /^[ \t]*:/) { print NR; f = 1; exit } } END { if (!f) print 1 }' "$1"
}
