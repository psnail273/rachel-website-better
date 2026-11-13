# The Next.js adapter's own lint checks, run by tools/verify/lint over every test
# file in scope (by tools/verify/test-paths; project-relative file paths as
# arguments). Prints findings:
#   <file>:<line> assertion-free   a test that asserts nothing
#   <file>:<line> fixed-wait       a wait for a fixed time
#
# Each file is read as code: comments, and the insides of strings, template
# literals and regular expressions, are left out, so a mention in one never
# counts; in a .tsx or .jsx file, so are JSX's tags and text, but not the code
# in its {...}. A quote or a regular expression left open ends at its line's end.
#
# assertion-free: a test is a call of `it` or `test` (not a method of something
# else: `regex.test(s)` is none), through any of the modifiers skip, only,
# concurrent, sequential, fails, fail, fixme, slow, shuffle, each(...), for(...),
# skipIf(...) and runIf(...), whose arguments hold a function (`=>` or
# `function`); `.todo` declares no test. It is a finding when nothing between its
# brackets calls an assertion: a name starting with expect or assert, called
# itself or through its members (`expect(x)`, `expect.soft(x)`,
# `expect.assertions(1)`, `expectTypeOf(x)`, `assert.equal(a, b)`,
# `assert.strict.equal(a, b)`, a helper `expectValidOrder(order)`). So a helper that asserts carries such a name. The
# finding is at the line of `it` or `test`, and names the test.
#
# fixed-wait: a test that sleeps passes on a quiet machine and fails on a busy
# one; it waits for the state it needs instead (vi.waitFor, expect.poll, an
# awaited event), or drives time itself (vi.useFakeTimers). A finding at each:
#   waitForTimeout(...)                       Playwright's fixed wait
#   Atomics.wait(...)
#   setTimeout(...) inside new Promise(...)   the usual sleep; a delay of 0 or
#                                             none passes (it yields a turn)
#   await setTimeout(...), await <x>.setTimeout(...), await sleep(...),
#   await delay(...), scheduler.wait(...)     node:timers/promises and helpers
# In a file that calls useFakeTimers(...), the setTimeout, sleep, delay and
# scheduler.wait forms pass: under fake timers they wait for no real time. A
# wait that has to be fixed (a check that something does not happen within a
# time) gives its reason in a comment on its line, or alone on the line above:
# `// fixed-wait: <why>`.
#
# With counts=1 it prints no finding: it counts assertions for
# tools/verify/assert-counts, one file read on stdin (path=<its path>, whose
# extension says whether it holds JSX). For each test, as assertion-free finds
# them, in file order: `<line> <func> <count>`. <line> is the line of `it` or
# `test`. <func> is the title of each `describe` or `suite` call whose brackets
# hold the test, outermost first, then the test's own, joined by `.`; a title is
# the call's first argument, a string's text without its quotes (else the code
# as written), each run of ASCII characters other than letters, digits and _
# made one _ (`describe("GET /api/health")` and `it("answers ok")` give
# GET_api_health.answers_ok). <count> is the assertion calls between the test's
# brackets: expect(...), expect.soft, .poll, .assertions, .hasAssertions and
# .unreachable, and any other name starting with expect or assert called as
# assertion-free calls it (expectTypeOf(x), assert.equal(a, b), a helper
# expectValidOrder(order)), each call once. Not counted: expect's asymmetric
# matchers and other members (expect.any(Number), expect.objectContaining({...}),
# expect.extend), which assert nothing themselves, a member of something else
# (ctx.expect(x)), and a function or method being declared (`expect() {...}`).
# With declares=1 as well, a todo (it.todo, a test with no function) is a test
# too, with its count: the test step asks only whether a file declares one.

function add(v, s, e) {
	ntok++
	tk[ntok] = v; tl[ntok] = line; ts[ntok] = s; te[ntok] = e
	return ntok
}

# regex_ok: true when a `/` here starts a regular expression, by the token before.
function regex_ok(   p) {
	if (ntok == 0) return 1
	p = tk[ntok]
	if (p ~ /^[A-Za-z_$]/) return (p in KEYWORD)
	if (p ~ /^#[SNRJ]$/ || p == ")" || p == "]" || p == "<") return 0
	return 1
}

# skip_string(i, q): from the opening quote at i, the index after the string.
function skip_string(i, q,   c) {
	i++
	while (i <= n) {
		c = substr(text, i, 1)
		if (c == "\\") { if (substr(text, i + 1, 1) == "\n") line++; i += 2; continue }
		if (c == q) return i + 1
		if (c == "\n") return i
		i++
	}
	return i
}

# skip_regex(i): from the opening / at i, the index after the regex and its flags.
function skip_regex(i,   c, cls) {
	i++
	cls = 0
	while (i <= n) {
		c = substr(text, i, 1)
		if (c == "\\") { i += 2; continue }
		if (c == "\n") return i
		if (c == "[") cls = 1
		else if (c == "]") cls = 0
		else if (c == "/" && !cls) { i++; break }
		i++
	}
	while (i <= n && substr(text, i, 1) ~ /[A-Za-z]/) i++
	return i
}

# embedded(i): read the code of a template's ${...} or a JSX {...} from i, just
# after its {, and return the index after its }. A `#{` token marks where it
# starts, so the token before it can't decide what its first / is.
function embedded(i) {
	add("#{", i - 1, i - 1)
	return scan_code(i, 1)
}

# scan_template(i): from just after the opening backtick, the index after the
# closing one; each ${...} inside is read as code.
function scan_template(i,   c) {
	while (i <= n) {
		c = substr(text, i, 1)
		if (c == "\\") { if (substr(text, i + 1, 1) == "\n") line++; i += 2; continue }
		if (c == "`") return i + 1
		if (c == "$" && substr(text, i + 1, 1) == "{") { i = embedded(i + 2); continue }
		if (c == "\n") line++
		i++
	}
	return i
}

# jsx_start(i): true when the < at i (where an expression may start, in a .tsx
# or .jsx file) opens a JSX element or fragment, not a generic function's type
# parameters. As TypeScript reads a .tsx file: `<T,`, `<T =` and `<T extends U`
# (an optional `const` before T) open type parameters; so does `type F = <T>`.
function jsx_start(i,   j, name) {
	if (tk[ntok] == "=" && ntok > 2 && tk[ntok - 2] == "type") return 0
	j = i + 1
	if (substr(text, j, 1) == ">") return 1
	if (substr(text, j, 1) !~ /[A-Za-z_$]/) return 0
	name = jsx_word(j)
	j += length(name)
	if (name == "const" && match(substr(text, j), /^[ \t\n]+[A-Za-z_$]/)) {
		j += RLENGTH - 1
		j += length(jsx_word(j))
	}
	while (j <= n && substr(text, j, 1) ~ /[ \t\n]/) j++
	if (substr(text, j, 1) == "," || (substr(text, j, 1) == "=" && substr(text, j + 1, 1) != ">")) return 0
	if (substr(text, j, 7) == "extends" && substr(text, j + 7, 1) ~ /[ \t\n]/) {
		j += 7
		while (j <= n && substr(text, j, 1) ~ /[ \t\n]/) j++
		return substr(text, j, 1) ~ /[=>\/]/
	}
	return 1
}

# jsx_word(j): the tag or identifier name that starts at j.
function jsx_word(j,   k) {
	for (k = j; k <= n && substr(text, k, 1) ~ /[A-Za-z0-9_$.:-]/; k++) ;
	return substr(text, j, k - j)
}

# scan_jsx(i): from the < at i that opens a JSX element, the index after it
# closes. Its tags and text are skipped; each {...} in an attribute or among its
# children is read as code; a nested element is read the same way.
function scan_jsx(i,   c, q) {
	i++
	while (i <= n) {
		c = substr(text, i, 1)
		if (c == "\n") { line++; i++; continue }
		if (c == "\"" || c == "\047") {
			q = c
			for (i++; i <= n && substr(text, i, 1) != q; i++) if (substr(text, i, 1) == "\n") line++
			i++
			continue
		}
		if (c == "{") { i = embedded(i + 1); continue }
		if (c == "/" && substr(text, i + 1, 1) == ">") return i + 2
		i++
		if (c == ">") break
	}
	while (i <= n) {
		c = substr(text, i, 1)
		if (c == "\n") { line++; i++; continue }
		if (c == "{") { i = embedded(i + 1); continue }
		if (c == "<" && substr(text, i + 1, 1) == "/") {
			while (i <= n && substr(text, i, 1) != ">") { if (substr(text, i, 1) == "\n") line++; i++ }
			return i + 1
		}
		if (c == "<") { i = scan_jsx(i); continue }
		i++
	}
	return i
}

# scan_code(i, nested): tokenise code from i; nested, it stops after the } that
# closes a template's ${ and returns the index after it.
function scan_code(i, nested,   c, d, depth, start, k) {
	depth = 0
	while (i <= n) {
		c = substr(text, i, 1)
		if (c == "\n") { line++; i++; continue }
		if (c == " " || c == "\t" || c == "\f") { i++; continue }
		d = substr(text, i, 2)
		if (d == "//") { while (i <= n && substr(text, i, 1) != "\n") i++; continue }
		if (d == "/*") {
			i += 2
			while (i <= n && substr(text, i, 2) != "*/") { if (substr(text, i, 1) == "\n") line++; i++ }
			i += 2
			continue
		}
		if (c == "\"" || c == "\047") { start = i; i = skip_string(i, c); add("#S", start, i - 1); continue }
		if (c == "`") { k = add("#S", i, i); i = scan_template(i + 1); te[k] = i - 1; continue }
		if (c == "/" && substr(text, i + 1, 1) != ">" && regex_ok()) { start = i; i = skip_regex(i); add("#R", start, i - 1); continue }
		if (c == "<" && jsx && regex_ok() && jsx_start(i)) {
			# An element that never closes was no element: read the < as code.
			start = line; k = ntok
			d = scan_jsx(i)
			if (d <= n + 1 && substr(text, d - 1, 1) == ">") { k = add("#J", i, d - 1); tl[k] = start; i = d; continue }
			line = start; ntok = k
		}
		if (c ~ /[A-Za-z_$]/) {
			start = i
			while (i <= n && substr(text, i, 1) ~ /[A-Za-z0-9_$]/) i++
			add(substr(text, start, i - start), start, i - 1)
			continue
		}
		if (c ~ /[0-9]/) {
			start = i
			while (i <= n && substr(text, i, 1) ~ /[A-Za-z0-9_.]/) i++
			add("#N", start, i - 1)
			continue
		}
		if (d == "=>") { add("=>", i, i + 1); i += 2; continue }
		if (c == "{") depth++
		if (c == "}") {
			if (nested && depth == 0) return i + 1
			depth--
		}
		add(c, i, i)
		i++
	}
	return i
}

# close_of(k): the token that closes the bracket at token k, else the last token.
function close_of(k,   d, j) {
	d = 0
	for (j = k; j <= ntok; j++) {
		if (tk[j] == "(" || tk[j] == "[" || tk[j] == "{") d++
		else if (tk[j] == ")" || tk[j] == "]" || tk[j] == "}") { d--; if (d == 0) return j }
	}
	return ntok
}

# raw(k): token k's text as written.
function raw(k) { return substr(text, ts[k], te[k] - ts[k] + 1) }

function is_assertion(x,   j) {
	if (tk[x] !~ /^(expect|assert)/) return 0
	if (tk[x + 1] == "(" || tk[x + 1] == "<") return 1
	for (j = x + 1; tk[j] == "." && tk[j + 1] ~ /^[A-Za-z_$]/; j += 2) ;
	return j > x + 1 && tk[j] == "("
}

# call_open(k): for a call of `it`, `test`, `describe` or `suite` at token k (not
# a method of something else), through any of the modifiers, the token of the
# bracket that opens its arguments; 0 when it is no such call, or one that
# declares a todo. `test(...) {` and a member's `test(...): T {` are a method or
# a function named test, no call.
function call_open(k,   j, m, e) {
	if (k > 1 && (tk[k - 1] == "." || tk[k - 1] == "function")) return 0
	j = k + 1
	while (tk[j] == ".") {
		m = tk[j + 1]
		if (!(m in MODIFIER) || (m == "todo" && !declares)) return 0
		j += 2
		if (m in TABLE) {
			if (tk[j] == "(") j = close_of(j) + 1
			else if (tk[j] == "#S") {
				# A tagged template table; its ${...} tokens follow its own.
				e = te[j]
				for (j++; j <= ntok && ts[j] <= e; j++) ;
			}
		}
	}
	if (tk[j] != "(" || declared(k, close_of(j))) return 0
	return j
}

# declared(k, c): true when the name at token k, whose brackets close at token c,
# is a function or method being declared, no call: `name(...) {`, or a member's
# `name(...): T {`, where the first of {, ;, } and ) after the colon is the
# {, as it isn't for a call ending a case label (`case f(), describe(...): break`).
function declared(k, c,   j) {
	if (tk[c + 1] == "{") return 1
	if (tk[c + 1] != ":" || tk[k - 1] !~ /^([{},;]|async|static|get|set|public|private|protected|override)$/) return 0
	for (j = c + 2; j <= ntok && tk[j] != "{" && tk[j] != ";" && tk[j] != "}" && tk[j] != ")"; j++) ;
	return tk[j] == "{"
}

# has_function(j): true when the call's arguments, from the bracket at j, hold a
# function (`=>` or `function`).
function has_function(j,   c, x) {
	c = close_of(j)
	for (x = j + 1; x < c; x++) if (tk[x] == "=>" || tk[x] == "function") return 1
	return 0
}

function check_tests(   k, j, c, x, has_assert, name) {
	for (k = 1; k <= ntok; k++) {
		if (tk[k] != "it" && tk[k] != "test") continue
		j = call_open(k)
		if (!j || !has_function(j)) continue
		c = close_of(j)
		has_assert = 0
		for (x = j + 1; x < c; x++) if (is_assertion(x)) has_assert = 1
		if (has_assert) continue
		name = (tk[j + 1] == "#S") ? raw(j + 1) : tk[k]
		gsub(/[ \t\n]+/, " ", name)
		print file ":" tl[k] " assertion-free " name " has no assertion; call expect or assert, or a helper whose name starts with expect or assert"
	}
}

# awaited(k): true when token k is awaited, itself or as a member (`await x.k`).
function awaited(k) {
	return tk[k - 1] == "await" || (tk[k - 1] == "." && tk[k - 3] == "await")
}

# yields(k): true when the setTimeout call at k has no delay, or a delay of 0.
function yields(k,   c, d, j, comma) {
	c = close_of(k + 1)
	d = 0; comma = 0
	for (j = k + 2; j < c; j++) {
		if (tk[j] == "(" || tk[j] == "[" || tk[j] == "{") d++
		else if (tk[j] == ")" || tk[j] == "]" || tk[j] == "}") d--
		else if (tk[j] == "," && d == 0) { comma = j; break }
	}
	if (!comma || comma + 1 == c) return 1
	return tk[comma + 1] == "#N" && raw(comma + 1) ~ /^0+$/ && (tk[comma + 2] == ")" || tk[comma + 2] == ",")
}

function reasoned(l) {
	return lines[l] ~ /(\/\/|\/\*)[ \t]*fixed-wait:[ \t]*[^ \t*]/ ||
		(l > 1 && lines[l - 1] ~ /^[ \t]*(\/\/|\/\*)[ \t]*fixed-wait:[ \t]*[^ \t*]/)
}

function check_waits(   k, j, c, fake, what) {
	fake = 0
	for (k = 1; k <= ntok; k++) {
		if (tk[k] == "useFakeTimers" && tk[k + 1] == "(") fake = 1
		inpromise[k] = 0
	}
	for (k = 1; k <= ntok; k++) {
		if (tk[k] != "new" || tk[k + 1] != "Promise") continue
		j = k + 2
		if (tk[j] == "<") { while (j <= ntok && tk[j] != ">") j++; j++ }
		if (tk[j] != "(") continue
		c = close_of(j)
		for (; j <= c; j++) inpromise[j] = 1
	}
	for (k = 1; k <= ntok; k++) {
		if (tk[k + 1] != "(") continue
		what = ""
		if (tk[k] == "waitForTimeout") what = "waitForTimeout()"
		else if (tk[k] == "wait" && tk[k - 1] == "." && tk[k - 2] == "Atomics") what = "Atomics.wait()"
		else if (fake) continue
		else if (tk[k] == "setTimeout" && tk[k - 1] != "." && inpromise[k] && !yields(k)) what = "setTimeout() in a new Promise"
		else if (tk[k] == "setTimeout" && awaited(k)) what = "an awaited setTimeout()"
		else if ((tk[k] == "sleep" || tk[k] == "delay") && awaited(k)) what = "an awaited " tk[k] "()"
		else if (tk[k] == "wait" && tk[k - 1] == "." && tk[k - 2] == "scheduler") what = "scheduler.wait()"
		if (what == "" || reasoned(tl[k])) continue
		print file ":" tl[k] " fixed-wait " what " waits a fixed time; wait for the state (vi.waitFor, expect.poll, an event) or use fake timers, or give the reason on this line or the one above: // fixed-wait: <why>"
	}
}

# counted(x): true when token x makes an assertion call, for counts=1 (the
# header's list): expect itself or one of its members that asserts, or another
# name starting with expect or assert, called itself or through its members;
# not a member itself (expect.assertions counts once), nor being declared.
function counted(x) {
	if (tk[x - 1] == "function" || tk[x - 1] == ".") return 0
	if (tk[x + 1] == "(" && declared(x, close_of(x + 1))) return 0
	if (tk[x] == "expect") {
		if (tk[x + 1] == "(" || tk[x + 1] == "<") return 1
		return tk[x + 1] == "." && (tk[x + 2] in EXPECT_ASSERTS) && tk[x + 3] == "("
	}
	return is_assertion(x)
}

# title(j): the name the call whose arguments open at token j gives: its first
# argument, a string's text without its quotes or else the code as written, with
# each run of ASCII characters other than letters, digits and _ made one _.
function title(j,   c, d, x, e, s, q, out, i, ch, run) {
	c = close_of(j)
	d = 0
	for (x = j + 1; x < c; x++) {
		if (tk[x] == "(" || tk[x] == "[" || tk[x] == "{") d++
		else if (tk[x] == ")" || tk[x] == "]" || tk[x] == "}") d--
		else if (tk[x] == "," && d == 0) break
	}
	# A template's ${...} tokens follow its own, so its end is the furthest one.
	e = 0
	for (i = j + 1; i < x; i++) if (te[i] > e) e = te[i]
	s = x > j + 1 ? substr(text, ts[j + 1], e - ts[j + 1] + 1) : ""
	q = substr(s, 1, 1)
	if (length(s) >= 2 && (q == "\"" || q == "\047" || q == "`") && substr(s, length(s)) == q) s = substr(s, 2, length(s) - 2)
	out = ""; run = 0
	for (i = 1; i <= length(s); i++) {
		ch = substr(s, i, 1)
		if (index(NOT_WORD, ch)) { if (!run) out = out "_"; run = 1 }
		else { out = out ch; run = 0 }
	}
	return out == "" ? "_" : out
}

# count_tests: for counts=1, `<line> <func> <count>` for each test, in file order.
function count_tests(   k, j, c, x, d, nd, n, name, dopen, dclose, dname) {
	nd = 0
	for (k = 1; k <= ntok; k++) {
		if (tk[k] != "describe" && tk[k] != "suite") continue
		j = call_open(k)
		if (!j) continue
		nd++; dopen[nd] = j; dclose[nd] = close_of(j); dname[nd] = title(j)
	}
	for (k = 1; k <= ntok; k++) {
		if (tk[k] != "it" && tk[k] != "test") continue
		j = call_open(k)
		if (!j || (!has_function(j) && !declares)) continue
		c = close_of(j)
		n = 0
		for (x = j + 1; x < c; x++) if (counted(x)) n++
		name = ""
		for (d = 1; d <= nd; d++) if (dopen[d] < k && k < dclose[d]) name = name dname[d] "."
		print tl[k], name title(j), n
	}
}

function check_file() {
	if (file == "") return
	n = length(text); line = 1; ntok = 0
	jsx = (file ~ /\.(tsx|jsx)$/)
	scan_code(1, 0)
	tk[ntok + 1] = ""; tk[ntok + 2] = ""; tk[ntok + 3] = ""; tk[0] = ""; tk[-1] = ""; tk[-2] = ""
	if (counts) {
		count_tests()
		return
	}
	check_tests()
	check_waits()
}

BEGIN {
	split("await case delete do else in instanceof new of return throw typeof void yield", w, " ")
	for (i in w) KEYWORD[w[i]] = 1
	split("skip only concurrent sequential fails fail fixme slow shuffle todo each for skipIf runIf", w, " ")
	for (i in w) MODIFIER[w[i]] = 1
	split("each for skipIf runIf", w, " ")
	for (i in w) TABLE[w[i]] = 1
	split("soft poll assertions hasAssertions unreachable", w, " ")
	for (i in w) EXPECT_ASSERTS[w[i]] = 1
	NOT_WORD = ""
	for (i = 1; i < 128; i++) {
		c = sprintf("%c", i)
		if (c !~ /[A-Za-z0-9_]/) NOT_WORD = NOT_WORD c
	}
}

FNR == 1 {
	check_file()
	file = counts ? (path == "" ? "-" : path) : FILENAME; text = ""
	delete lines
}
{
	sub(/\r$/, "")
	lines[FNR] = $0
	text = text $0 "\n"
}
END { check_file() }
