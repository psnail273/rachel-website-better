# Shared by the Godot adapter's steps that run Godot. Sourced; defines no side
# effects. Run from the project root.
#
# GODOT_BIN (local.env) names the Godot binary. There is no default: a machine
# without it set fails the step that needs it. Its version is pinned in
# tools/verify/pins.

GODOT_BIN="${GODOT_BIN:-}"

# Where the steps keep their scratch output: under .godot/, which Godot projects
# never track or export.
# shellcheck disable=SC2034 # read by the steps that source this
GODOT_WORK=".godot/factory"

# godot_ready: true when GODOT_BIN runs; else prints a finding and is false.
godot_ready() {
	if [ -z "$GODOT_BIN" ]; then
		echo "tools/verify/local.env:1 godot-missing GODOT_BIN is not set; set it in tools/verify/local.env (see local.env.example)"
		return 1
	fi
	if ! command -v "$GODOT_BIN" > /dev/null 2>&1; then
		echo "tools/verify/local.env:1 godot-missing GODOT_BIN '$GODOT_BIN' is not a program; fix it in tools/verify/local.env"
		return 1
	fi
}

# godot <args...>: run Godot headless on the project. Its stdout is not the
# step's verdict, so callers redirect it (to a log, or to stderr).
godot() {
	"$GODOT_BIN" --headless --path . "$@"
}

# godot_os_path <path>: the path as Godot sees it: a Windows path under Git Bash,
# the path itself elsewhere.
godot_os_path() {
	if command -v cygpath > /dev/null 2>&1; then
		cygpath -w "$1"
	else
		printf '%s\n' "$1"
	fi
}

# godot_errors <log> <rule> <kinds> <fallback>: a finding per error block in a Godot
# log. A block starts with a line `<kind>: <message>`, <kinds> being an extended
# regex such as 'SCRIPT ERROR|ERROR', and runs over the indented lines after it.
# The finding is at the block's first res:// file:line (line 0 counts as 1), else
# at <fallback> (a file:line). Prints them sorted, without duplicates.
godot_errors() {
	sed 's/\x1b\[[0-9;]*m//g; s/\r$//' "$1" | awk -v rule="$2" -v kinds="$3" -v fallback="$4" '
		function flush() {
			if (msg != "") print (loc != "" ? loc : fallback) " " rule " " msg
			msg = ""; loc = ""
		}
		$0 ~ "^(" kinds "): " { flush(); msg = $0; sub("^(" kinds "): ", "", msg); if (msg == "") msg = "(no message)"; next }
		/^[ \t]/ && msg != "" {
			if (loc == "" && match($0, /\(res:\/\/[^)]*:[0-9]+\)/)) {
				loc = substr($0, RSTART + 7, RLENGTH - 8)
				sub(/:0$/, ":1", loc)
			}
			next
		}
		{ flush() }
		END { flush() }
	' | LC_ALL=C sort -u
}

# gdunit_declared <files>: `<file>\t<name>\t<line>` for each test function (`func
# test_*(`) declared in the files listed in <files>, one path per line.
gdunit_declared() {
	local f
	while IFS= read -r f; do
		tr -d '\r' < "$f" | awk -v file="$f" '
			match($0, /^func test_[A-Za-z0-9_]*[ \t]*\(/) {
				name = substr($0, 6, RLENGTH - 5); sub(/[ \t]*\($/, "", name)
				print file "\t" name "\t" NR
			}
		'
	done < "$1"
}

# gdunit_results <reports> <declared> <dir>: the results seam's lines
# (factory/core/lib/results.sh), `<name>\t<status>\t<file:line>`, for the tests
# in <declared> (gdunit_declared's lines) against gdUnit4's newest report under
# <reports>: each declared test with its worst reported status (ERROR if
# unreported, so every test is ERROR when there is no report), then any reported
# test that isn't declared, at its suite file's line 1; sorted by file and line.
# <dir> is the folder holding _gdunit_results.awk. False when there is no report.
gdunit_results() {
	local report reported found=0
	reported="$(mktemp)" || return 1
	report="$(find "$1" -name results.xml 2> /dev/null | LC_ALL=C sort | tail -n 1)"
	if [ -n "$report" ]; then
		found=1
		awk -f "$3/_gdunit_results.awk" "$report" > "$reported"
	fi
	awk -F '\t' -v OFS='\t' '
		function rank(s) { return s == "ERROR" ? 3 : s == "FAILURE" ? 2 : s == "SKIP" ? 1 : 0 }
		FILENAME == ARGV[1] { key = $1 "\t" $2; if (!(key in st) || rank($3) > rank(st[key])) st[key] = $3; next }
		{
			key = $1 "\t" $2; seen[key] = 1
			print $1, $3, $2, (key in st ? st[key] : "ERROR")
		}
		END { for (key in st) if (!(key in seen)) { split(key, k, "\t"); print k[1], 1, k[2], st[key] } }
	' "$reported" "$2" |
		LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2n -k3,3 |
		awk -F '\t' -v OFS='\t' '{ print $3, $4, $1 ":" $2 }'
	rm -f "$reported"
	[ "$found" -eq 1 ]
}
