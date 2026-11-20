# The source readers: the project's tests that read source files as text, and
# what each reads (its reach). Sourced by brief.sh (needs diff.sh and brief.sh's
# lib); brief.sh readers prints them, and brief.sh check holds a brief to list
# each one whose reach covers a scope file under Existing tests
# (factory_brief_readers_lint in lib/brief.sh).
#
# A test file is a file git tracks, or would (untracked, not ignored), that the
# test-paths globs match. The scan (lib/readers.awk) is a text heuristic for
# JavaScript and TypeScript tests, kept in the Core for want of an adapter
# probe for it. A file is a
# reader when it calls one of the fs reads (readFileSync, readFile,
# readdirSync, readdir, opendirSync, opendir, existsSync, statSync, lstatSync,
# createReadStream, globSync) or imports a file with `?raw`. Its reach is each
# path it builds from:
#   - join or resolve (path.join, or imported from node:path) starting at
#     import.meta.dirname, __dirname, process.cwd(), a literal path from the
#     project root, or a name bound to one of those, then literal parts: a part
#     that isn't a literal (a variable, a template with ${}) makes the path so
#     far a folder the test reads below, as a directory walk like
#     sourceFiles(srcDir) does;
#   - new URL("<relative path>", import.meta.url);
#   - an fs read of a literal path, from the project root;
#   - a `?raw` import: relative, from the root (/...), or through an alias of
#     tsconfig.json's paths (`"@/*": ["./src/*"]`).
# A name bound to a path counts where the test reads it, not where it is only
# the folder another join starts from; the project root itself, and a path
# outside it, never count. A path that is a folder in the checkout, or that the
# test reads below, is a folder reach (a trailing /), and a reach inside another
# folder reach of the same test is left out.

FACTORY_READERS_AWK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/readers.awk"

# factory_path_normalize <path>: the path from the project root with its . and
# .. parts resolved; false when it is the root itself or leaves it.
factory_path_normalize() {
	local IFS=/ part
	local -a parts=() out=()
	read -r -a parts <<< "$1"
	for part in "${parts[@]}"; do
		case "$part" in
			'' | .) ;;
			..)
				[ "${#out[@]}" -gt 0 ] || return 1
				unset 'out[${#out[@]}-1]'
				;;
			*) out+=("$part") ;;
		esac
	done
	[ "${#out[@]}" -gt 0 ] || return 1
	printf '%s\n' "${out[*]}"
}

# factory_raw_aliases: tsconfig.json's path aliases of the form
# "<prefix>/*": ["<target>/*"], as "<prefix>/\t<target>/" lines.
factory_raw_aliases() {
	[ -f tsconfig.json ] || return 0
	sed -n 's|.*"\([^"*]*\)\*"[[:space:]]*:[[:space:]]*\[[[:space:]]*"\([^"*]*\)\*".*|\1\t\2|p' tsconfig.json
}

# factory_source_readers: print each source reader of the checkout and its
# reach, "<test file> <reach>" one per line, sorted. Run from the project root.
# False, printing nothing, outside a git work tree or without the test-paths
# globs.
factory_source_readers() {
	local file g dyn path reach
	local -a res=() files=()
	git rev-parse --is-inside-work-tree > /dev/null 2>&1 || return 1
	factory_test_paths_load > /dev/null || return 1
	for g in "${TEST_PATHS[@]}"; do
		res+=("$(factory_glob_regex "$g")")
	done
	while IFS= read -r -d '' file; do
		[ -f "$file" ] || continue
		for g in "${res[@]}"; do
			if [[ $file =~ $g ]]; then
				files+=("$file")
				break
			fi
		done
	done < <(git ls-files -z --cached --others --exclude-standard)
	[ "${#files[@]}" -gt 0 ] || return 0
	FACTORY_RAW_ALIASES="$(factory_raw_aliases)" awk -v q="'" -f "$FACTORY_READERS_AWK" "${files[@]}" |
		while IFS=$'\t' read -r file dyn path; do
			reach="$(factory_path_normalize "$path")" || continue
			if [ "$dyn" = 1 ] || [ -d "$reach" ]; then
				reach="$reach/"
			fi
			printf '%s\t%s\n' "$file" "$reach"
		done | LC_ALL=C sort -u | awk -F '\t' '
			{ f[NR] = $1; r[NR] = $2 }
			END {
				for (i = 1; i <= NR; i++) {
					keep = 1
					for (j = 1; j <= NR; j++) {
						if (i == j || f[i] != f[j] || r[j] !~ /\/$/) continue
						if (r[i] != r[j] && index(r[i], r[j]) == 1) { keep = 0; break }
					}
					if (keep) print f[i] " " r[i]
				}
			}'
}
