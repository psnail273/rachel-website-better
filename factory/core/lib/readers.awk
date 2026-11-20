# The source-reader scan behind `brief.sh readers` (lib/readers.sh runs it over
# every test file at once). A text heuristic for JavaScript and TypeScript tests;
# lib/readers.sh's header names the shapes it reads.
#
# Variables: q, a single quote. The environment's FACTORY_RAW_ALIASES holds
# "<prefix>\t<target>" lines from tsconfig.json's paths (`@/*` -> `./src/*`
# gives "@/\t./src/"): not a -v, since gawk reads a -v value @/.../ as a regex.
# Prints one line per path a test reads: "<file>\t<0|1>\t<path>", the path from
# the project root, not yet normalized (it may hold . and ..); 1 when a part the
# scan can't read follows it, so the test reads somewhere below that folder.

BEGIN {
	UNK = "\001"
	WS = "[ \t\r\n]*"
	IDENT = "[A-Za-z_$][A-Za-z0-9_$]*"
	READFN = "(readFileSync|readFile|readdirSync|readdir|opendirSync|opendir|existsSync|statSync|lstatSync|createReadStream|globSync)"
	CALLRE = "(const|let|var)[ \t\r\n]+" IDENT WS "=" WS "(import\\.meta\\.dirname|__dirname|process\\.cwd\\(\\))" \
		"|(join|resolve)" WS "\\(" \
		"|new[ \t\r\n]+URL" WS "\\(" \
		"|" READFN WS "\\("
	RAWRE = "[\"" q "][^\"" q "\n]+\\?raw[\"" q "]"
	SQRE = "^" q "[^" q "]*" q "$"
	nalias = split(ENVIRON["FACTORY_RAW_ALIASES"], ALINES, "\n")
}

FNR == 1 && NR > 1 { scan(prev, s); s = "" }
{ s = s $0 "\n"; prev = FILENAME }
END { if (NR > 0) scan(prev, s) }

function trim(x) {
	sub(/^[ \t\r\n]+/, "", x)
	sub(/[ \t\r\n]+$/, "", x)
	return x
}

function islit(e) {
	if (e ~ /^"[^"]*"$/ || e ~ SQRE) return 1
	return e ~ /^`[^`]*`$/ && index(e, "${") == 0
}

function litval(e) {
	return substr(e, 2, length(e) - 2)
}

# parseargs(str, at, out): split the call whose ( is at str[at] into its
# arguments, out[1..n], at the commas outside brackets and strings; sets PEND to
# the index of its ). Returns n, or -1 when the ) never comes.
function parseargs(str, at, out,    i, c, depth, inq, n, cur, len) {
	len = length(str)
	depth = 1
	inq = ""
	n = 0
	cur = ""
	for (i = at + 1; i <= len; i++) {
		c = substr(str, i, 1)
		if (inq != "") {
			cur = cur c
			if (c == "\\") {
				i++
				cur = cur substr(str, i, 1)
			} else if (c == inq) {
				inq = ""
			}
			continue
		}
		if (c == "\"" || c == q || c == "`") {
			inq = c
			cur = cur c
			continue
		}
		if (c == "(" || c == "[" || c == "{") depth++
		if (c == ")" || c == "]" || c == "}") {
			depth--
			if (depth == 0) {
				cur = trim(cur)
				if (cur != "" || n > 0) out[++n] = cur
				PEND = i
				return n
			}
		}
		if (c == "," && depth == 1) {
			out[++n] = trim(cur)
			cur = ""
			continue
		}
		cur = cur c
	}
	return -1
}

# ev(e): the path expression e names, or UNK. Sets DYN when a part it can't
# read follows the path it returns.
function ev(e,    a, n, p) {
	e = trim(e)
	if (e == "import.meta.dirname" || e == "__dirname" || e == "import.meta.dir") return DIR
	if (e ~ /^process\.cwd\(\)$/) return "."
	if (e ~ ("^" IDENT "$") && (e in VAR)) {
		if (VDYN[e]) DYN = 1
		return VAR[e]
	}
	if (match(e, "^((path|posix)\\.)?(join|resolve)" WS "\\(")) {
		n = parseargs(e, RLENGTH, a)
		if (n < 1) return UNK
		return evjoin(a, n)
	}
	if (match(e, "^new[ \t\r\n]+URL" WS "\\(")) {
		n = parseargs(e, RLENGTH, a)
		return evurl(a, n)
	}
	return UNK
}

# evjoin(a, n): a join or resolve of the arguments a[1..n].
function evjoin(a, n,    p, k, v) {
	if (islit(a[1])) {
		v = litval(a[1])
		if (v ~ /^\//) return UNK
		p = "./" v
	} else {
		p = ev(a[1])
		if (p == UNK) return UNK
		if (DYN) return p
	}
	for (k = 2; k <= n; k++) {
		if (!islit(a[k])) {
			DYN = 1
			return p
		}
		v = litval(a[k])
		if (v ~ /^\//) return UNK
		p = p "/" v
	}
	return p
}

# evurl(a, n): new URL("<relative>", import.meta.url).
function evurl(a, n,    v) {
	if (n < 2 || trim(a[2]) != "import.meta.url" || !islit(a[1])) return UNK
	v = litval(a[1])
	if (v ~ /^\// || v ~ /^[a-z]+:/) return UNK
	return DIR "/" v
}

function emit(file, dyn, p) {
	if (p == UNK || p == "") return
	print file "\t" (dyn ? 1 : 0) "\t" p
}

# imported(name): true when the file imports name from node's path module.
function imported(name, str,    rest, clause) {
	rest = str
	while (match(rest, "import[^;]*from" WS "[\"" q "](node:)?path[\"" q "]")) {
		clause = substr(rest, RSTART, RLENGTH)
		rest = substr(rest, RSTART + RLENGTH)
		if (match(clause, "\\{[^}]*\\}") && substr(clause, RSTART, RLENGTH) ~ ("[{, \t\r\n]" name "[}, \t\r\n]")) return 1
	}
	return 0
}

# used(name, str): true when name is read anywhere but where it is defined or
# as the folder a join or resolve starts from.
function used(name, str,    rest, at, before, after, re) {
	re = name
	gsub(/\$/, "\\$", re)
	rest = str
	at = 0
	while (match(rest, re)) {
		before = at + RSTART - 1 > 0 ? substr(str, at + RSTART - 1, 1) : ""
		after = substr(rest, RSTART + RLENGTH, 1)
		if (before !~ /[A-Za-z0-9_$.]/ && after !~ /[A-Za-z0-9_$]/) {
			if (substr(str, 1, at + RSTART - 1) ~ ("(const|let|var)[ \t\r\n]+$")) {
			} else if (substr(str, 1, at + RSTART - 1) ~ ("(join|resolve)" WS "\\(" WS "$") && substr(rest, RSTART + RLENGTH) ~ ("^" WS ",")) {
			} else {
				return 1
			}
		}
		at += RSTART + RLENGTH - 1
		rest = substr(rest, RSTART + RLENGTH)
	}
	return 0
}

function bound(str, m,    from, pre, name) {
	from = m > 160 ? m - 160 : 1
	pre = substr(str, from, m - from)
	if (!match(pre, "(const|let|var)[ \t\r\n]+" IDENT WS "(:[^=;]*)?=" WS "$")) return ""
	name = substr(pre, RSTART, RLENGTH)
	sub(/^(const|let|var)[ \t\r\n]+/, "", name)
	match(name, "^" IDENT)
	return substr(name, 1, RLENGTH)
}

function scan(file, str,    dir, pos, m, len, tok, c, k, objend, obj, start, a, n, v, name, rest, spec, p, i, pair) {
	delete VAR
	delete VDYN
	dir = file
	if (sub(/\/[^\/]*$/, "", dir) == 0) dir = "."
	DIR = dir

	# ?raw imports read the file as text, whatever else the test does.
	rest = str
	while (match(rest, RAWRE)) {
		spec = substr(rest, RSTART + 1, RLENGTH - 6)
		rest = substr(rest, RSTART + RLENGTH)
		p = UNK
		if (spec ~ /^\.\.?\//) {
			p = DIR "/" spec
		} else if (spec ~ /^\//) {
			p = "." spec
		} else {
			for (i = 1; i <= nalias; i++) {
				split(ALINES[i], pair, "\t")
				if (pair[1] != "" && index(spec, pair[1]) == 1) {
					p = pair[2] substr(spec, length(pair[1]) + 1)
					break
				}
			}
		}
		emit(file, 0, p)
	}

	if (str !~ (READFN WS "\\(")) return
	FREEJOIN = imported("join", str)
	FREERESOLVE = imported("resolve", str)
	pos = 1
	while (match(substr(str, pos), CALLRE)) {
		m = pos + RSTART - 1
		len = RLENGTH
		tok = substr(str, m, len)
		pos = m + len
		if (tok ~ /^(const|let|var)/) {
			name = tok
			sub(/^(const|let|var)[ \t\r\n]+/, "", name)
			match(name, "^" IDENT)
			name = substr(name, 1, RLENGTH)
			VAR[name] = tok ~ /process\.cwd/ ? "." : DIR
			VDYN[name] = 0
			continue
		}
		c = m > 1 ? substr(str, m - 1, 1) : ""
		if (c ~ /[A-Za-z0-9_$]/) continue
		start = m
		if (tok ~ /^(join|resolve)/) {
			if (c == ".") {
				objend = m - 1
				for (k = objend - 1; k >= 1 && substr(str, k, 1) ~ /[A-Za-z0-9_$]/; k--);
				obj = substr(str, k + 1, objend - k - 1)
				if (obj != "path" && obj != "posix") continue
				if (k >= 1 && substr(str, k, 1) == ".") continue
				start = k + 1
			} else if (tok ~ /^join/ && !FREEJOIN || tok ~ /^resolve/ && !FREERESOLVE) {
				continue
			}
			n = parseargs(str, m + len - 1, a)
			if (n < 1) continue
			DYN = 0
			v = evjoin(a, n)
		} else if (tok ~ /^new/) {
			n = parseargs(str, m + len - 1, a)
			DYN = 0
			v = evurl(a, n)
		} else {
			# A read call: only a literal path is read here; a path built in its
			# arguments is a join or a name the scan meets on its own.
			n = parseargs(str, m + len - 1, a)
			if (n >= 1 && islit(a[1]) && litval(a[1]) !~ /^\//) emit(file, 0, "./" litval(a[1]))
			continue
		}
		if (v == UNK) continue
		name = bound(str, start)
		if (name != "") {
			VAR[name] = v
			VDYN[name] = DYN
		} else {
			emit(file, DYN, v)
		}
	}
	for (name in VAR) {
		if (used(name, str)) emit(file, VDYN[name], VAR[name])
	}
}
