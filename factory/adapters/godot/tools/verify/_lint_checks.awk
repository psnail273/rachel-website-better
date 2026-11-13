# The Godot adapter's own lint checks, run by tools/verify/lint over every test
# file in scope (by tools/verify/test-paths; file paths as arguments,
# project-relative). Prints findings:
#   <file>:<line> assertion-free      a test with no assertion
#   <file>:<line> unseeded-fuzzer     a fuzzer test without fuzzer_seed
#   <file>:<line> float-exact         an array or dictionary assertion that
#                                     compares a float literal exactly
#   <file>:<line> vector-tolerance    assert_vector's is_equal_approx given a
#                                     float tolerance, which it can't take
#   <file>:<line> unnamed-tolerance   an is_equal_approx tolerance written as a
#                                     number rather than a named constant
#   <file>:<line> fixed-wait          a wait for a fixed time on a line the branch
#                                     adds: await_millis(), an awaited
#                                     create_timer(), OS.delay_msec() or
#                                     OS.delay_usec(), with no reason given
#   <file>:<line> branched-assert     an assertion on a line the branch adds
#                                     that sits under an if, elif, else, for,
#                                     while or match, or after a guard return
#   <file>:<line> unguarded-poll      a while loop on a line the branch adds
#                                     that awaits, with nothing in its
#                                     condition to bound it
#
# fixed-wait reads the lines the lint step lists in the file added_file, one
# `<file>:<line>` per line (`<file>:*` for every line of a file); with
# all_added=1 it reads every line. A fixed wait passes on a correct machine and
# fails on a busy one, so a test waits for the state it needs, polled each frame
# behind a guard timer. A wait that has to be fixed (a check that something does
# not happen within a time) gives its reason in a comment on its line, or alone
# on the line above: `# fixed-wait: <why>`. A timer kept in a variable is a guard
# and passes; awaiting its timeout on a later line isn't seen.
#
# branched-assert reads the same added lines, in every func of a test file,
# helpers too. An assertion (assert_*(), verify(), verify_no_interactions(),
# verify_no_more_interactions() or fail()) is a finding when it sits in the
# body of an if, elif, else, for, while or match, in the statement that opens
# one, or after a return inside one, until the code goes back out past that
# block: then what the test asserts depends on the run. A loop that waits for a
# state and the assertion after it, at the loop's own indent, pass. Blocks are
# read by indent, a tab counting four, and a lambda's body is a scope of its
# own: a return there guards only the rest of the lambda. A header split over
# lines counts once; a lambda's body inside a call's brackets is read line by
# line, and ends at the comma after its last line. A lambda's return in a
# condition guards nothing.
#
# unguarded-poll reads the same added lines: the line a while loop starts on. The
# loop is a finding when it awaits, in its condition or its body (not in a lambda
# written there), and nothing in its condition bounds it: a broken build then
# hangs the test instead of failing it. These bound a loop:
#   - a guard timer: its time_left, or an is_stopped() call;
#   - the clock: get_ticks_msec(), get_ticks_usec(), get_unix_time*(),
#     get_process_frames(), get_physics_frames() or get_frames_drawn();
#   - a name that says it guards: one holding guard, deadline, timeout,
#     timed_out or expired (frame_guard < 600, not timed_out[0], _in_deadline());
#   - a counter compared with a bound: a variable, indexed, bracketed or not, on
#     the left of <, <=, > or >= (guard < 1000, tries <= 3, remaining > 0,
#     i < list.size()), on the right of one with a number or a constant on its
#     left (0 < left), or compared with a number or a constant by != (frames !=
#     600). A member (box.frames, states[0].frames) counts when the body steps
#     its root, and so does any other name the condition holds (`while left:`).
#     A step is an assignment by +=, -= and the like, or by = from the root
#     itself, on one line or over lines, through an index, a key or a cast or
#     not, with self. or without (box["frames"] += 1, self.box.frames += 1,
#     (node as Node2D).position.x += 1.0, left = maxi(0, left - 1)). A
#     constant, a call and a member the body leaves alone are no counter, so
#     state compared with a bound bounds nothing (level_index() < last,
#     list.size() < 3, ball.position.y < floor_y). A counter that counts up
#     and is set back to 0 in the body, outside a lambda, is no bound either
#     (stable_frames = 0: it counts stable frames, not frames);
#   - a list the body drains: the condition names it and the body calls
#     pop_front(), pop_back(), pop_at(), remove_at(), erase() or clear() on it,
#     an item of it, a cast of it or a call that returns it.
# A guard that breaks out of the body is not read: the bound goes in the
# condition. A loop that has to poll unbounded gives its reason on its while
# line, or alone on the line above: `# unguarded-poll: <why>`.
#
# The last three read whole statements (a line, joined with the lines after it
# while a bracket stays open or the line ends in a backslash), anywhere in the
# file. A float tolerance is a number, or a name declared as a float (`const X:
# float`, `const X := 0.5`, `var X = 1e-3`) in the same func, else at the top of
# the file. float-exact reads the assertion's subject when it is a literal array
# or dictionary, and every exact comparison in its chain.
#
# A test is a `func test_*`; its body runs to the next func or the next line at
# column 0. It asserts when the body calls assert_*(), verify(),
# verify_no_interactions or verify_no_more_interactions. It is a fuzzer test when
# its signature names a Fuzzer or fuzzer_iterations; then it needs fuzzer_seed, so
# that every run draws the same inputs. Comments and strings never count, a
# triple-quoted string over many lines too.
#
# With counts=1 it prints no finding: it counts assertions for
# tools/verify/assert-counts, one file read on stdin. For each func, in file
# order, it prints `<line> <func> <count>`: the line its `func` starts on, its
# name, and the assertion calls in its body, by branched-assert's pattern, every
# call on a line counted. A func is a `func <name>` statement at column 0, or at
# the indent of an inner class's body, named `<Class>.<name>` then (nested:
# `<Outer>.<Inner>.<name>`). Its body runs to the next statement at that indent
# or left of it, so a lambda or a func written deeper inside it counts as its.

BEGIN {
	EXACT = "is_equal|is_not_equal|contains|contains_exactly|contains_exactly_in_any_order|contains_same|contains_same_exactly"
	if (added_file != "")
		while ((getline entry < added_file) > 0) added[entry] = 1
	REASON = "#[ \t]*fixed-wait:[ \t]*[^ \t]"
	ASSERT_CALL = "(^|[^A-Za-z0-9_])(assert_[a-z_]+|verify|verify_no_interactions|verify_no_more_interactions|fail)[ \t]*\\("
	COUNT_ANNOTATIONS = "^[ \t]*(@[^ \t(]+(\\([^)]*\\)[ \t]*|[ \t]+))*"
	CONTROL = "^[ \t]*(if|elif|else|for|while|match)([^A-Za-z0-9_]|$)"
	RETURN_AFTER_COLON = ":[ \t]*return([^A-Za-z0-9_]|$)"
	RETURN_FIRST = "^[ \t]*return([^A-Za-z0-9_]|$)"
	FUNC_WORD = "(^|[^A-Za-z0-9_])func([^A-Za-z0-9_]|$)"
	ENDS_COLON = ":[ \t]*$"
	ELSE = "^[ \t]*else([^A-Za-z0-9_]|$)"
	POLL_REASON = "#[ \t]*unguarded-poll:[ \t]*[^ \t]"
	AWAIT = "(^|[^A-Za-z0-9_.$%/])await([^A-Za-z0-9_]|$)"
	WHILE = "^[ \t]*while([^A-Za-z0-9_]|$)"
	DRAIN = "\\.[ \t]*(pop_front|pop_back|pop_at|remove_at|erase|clear)[ \t]*\\("
	WORD_BEFORE = "(^|[^A-Za-z0-9_])(and|or|not|in|is|as|if|else|await|return)[ \t]*$"
}

# indent_of(s): the width of s's leading whitespace, a tab counting four.
function indent_of(s,    i, c, n) {
	n = 0
	for (i = 1; i <= length(s); i++) {
		c = substr(s, i, 1)
		if (c == "\t") n += 4
		else if (c == " ") n++
		else break
	}
	return n
}

# reset_blocks(): no block or lambda is open, and no guard return has been seen.
function reset_blocks() {
	blocks = 0
	controls = 0
	guarded = 0
	guard_indent = 0
	lambda_open = -1
	control_open = -1
}

# open_block(kind, at): a block opens at indent at; kind is "control" for an if,
# elif, else, for, while or match, and "scope" for a lambda's body. Its body sits
# in the brackets the statement leaves open after this line.
function open_block(kind, at) {
	block_indent[++blocks] = at
	block_kind[blocks] = kind
	block_depth[blocks] = statement_depth
	if (kind == "control") controls++
}

# close_blocks(at): a line at indent at is outside every block opened at or
# deeper than it, and past a guard whose block it has left.
function close_blocks(at) {
	while (blocks > 0 && at <= block_indent[blocks]) {
		if (block_kind[blocks] == "control") controls--
		blocks--
	}
	if (guarded && at < guard_indent) guarded = 0
}

# guard(at, inline): a return at indent at. Inside a branch or loop of the
# current func or lambda, what follows runs only on some paths, until the code
# goes back out past the outermost such block. inline: the return sits on its
# block's own line (`if x: return`), so it guards even with no block open.
function guard(at, inline,    k, s, g) {
	s = 0
	for (k = blocks; k >= 1; k--)
		if (block_kind[k] == "scope") { s = k; break }
	g = -1
	for (k = s + 1; k <= blocks; k++)
		if (block_kind[k] == "control") { g = block_indent[k]; break }
	if (g < 0) {
		if (!inline) return
		g = at
	}
	if (!guarded || g < guard_indent) guard_indent = g
	guarded = 1
}

# read_line_blocks(s, at): the blocks, lambdas and returns on one line of a
# statement that spans lines, such as a lambda's body inside a call's brackets.
# A block header whose brackets all close on its line opens its block, a lambda
# in its condition or not. A line ending in a colon after `func` with a bracket
# left open opens a lambda, even in an if's condition; a lambda whose signature
# runs on past its line (lambda_open, the line's indent) opens where the
# signature ends in a colon. A block header inside a longer statement whose
# brackets stay open (control_open, its indent; control_depth, the brackets
# still open) opens its block at the line that closes them with a colon.
function read_line_blocks(s, at) {
	if (control_open >= 0) {
		control_depth += depth(s)
		if (control_depth <= 0) {
			if (s ~ ENDS_COLON && s !~ CONTROL) {
				open_block("control", control_open)
				control_open = -1
				return
			}
			control_open = -1
		}
	} else if (!starts_statement && s ~ CONTROL && s !~ ELSE && depth(s) > 0) {
		control_open = at
		control_depth = depth(s)
	}
	if (s ~ CONTROL && s ~ ENDS_COLON && depth(s) <= 0) {
		open_block("control", at)
	} else if (s ~ FUNC_WORD && s ~ ENDS_COLON) {
		open_block("scope", at)
		lambda_open = -1
	} else if (match(s, FUNC_WORD) && depth(substr(s, RSTART)) > 0) {
		lambda_open = at
	} else if (lambda_open >= 0 && s ~ ENDS_COLON && s !~ CONTROL) {
		open_block("scope", lambda_open)
		lambda_open = -1
	} else if (s ~ CONTROL && s ~ ENDS_COLON) {
		open_block("control", at)
	} else if (s ~ CONTROL && top_level(s) ~ RETURN_AFTER_COLON) {
		guard(at, 1)
	} else if (s ~ RETURN_FIRST) {
		guard(at, 0)
	}
}

# end_lambda(s, at): a line of a lambda's body at indent at that ends in a comma,
# in the brackets the body sits in, ends the lambda, and any guard inside it.
function end_lambda(s, at,   k) {
	if (s !~ /,[ \t]*$/) return
	for (k = blocks; k >= 1; k--)
		if (block_kind[k] == "scope") break
	if (k < 1 || at <= block_indent[k] || statement_depth != block_depth[k]) return
	if (guarded && guard_indent > block_indent[k]) guarded = 0
	while (blocks >= k) {
		if (block_kind[blocks] == "control") controls--
		blocks--
	}
}

# top_level(s): s without the text inside its brackets.
function top_level(s,   i, c, d, t) {
	d = 0
	t = ""
	for (i = 1; i <= length(s); i++) {
		c = substr(s, i, 1)
		if (c ~ /[([{]/) d++
		else if (c ~ /[)\]}]/) d--
		else if (d <= 0) t = t c
	}
	return t
}

# read_statement_blocks(st, at): the same for a whole statement starting at
# indent at, read once it ends.
function read_statement_blocks(st, at) {
	if (st ~ CONTROL) {
		if (st ~ ENDS_COLON) open_block("control", at)
		else if (top_level(st) ~ RETURN_AFTER_COLON) guard(at, 1)
	} else if (st ~ FUNC_WORD && st ~ ENDS_COLON) {
		open_block("scope", at)
	} else if (st ~ RETURN_FIRST) {
		guard(at, 0)
	} else if (st ~ RETURN_AFTER_COLON && st !~ FUNC_WORD) {
		guard(at, 0)
	}
}

# is_added(): the current line is one the branch adds.
function is_added() {
	return is_added_at(FNR)
}

# is_added_at(n): line n of the current file is one the branch adds.
function is_added_at(n) {
	return all_added == 1 || ((FILENAME ":" n) in added) || ((FILENAME ":*") in added)
}

# fixed_wait(s): the fixed wait the code s makes, or "".
function fixed_wait(s) {
	if (s ~ /(^|[^A-Za-z0-9_])await_millis[ \t]*\(/) return "await_millis()"
	if (s ~ /(^|[^A-Za-z0-9_])await[ \t].*create_timer[ \t]*\(/) return "an awaited create_timer()"
	if (s ~ /OS[ \t]*\.[ \t]*delay_(msec|usec)[ \t]*\(/) return "OS.delay_msec() or OS.delay_usec()"
	return ""
}

# code(s): s without its comment and with each string literal's contents blanked,
# so neither can trip a check. A triple-quoted string left open (tq) carries on
# into the next line.
function code(s,    i, c, q, out, n) {
	q = tq
	out = ""
	n = length(s)
	for (i = 1; i <= n; i++) {
		c = substr(s, i, 1)
		if (q != "") {
			if (c == "\\") { out = out "  "; i++; continue }
			if ((length(q) == 3) ? (substr(s, i, 3) == q) : (c == q)) {
				out = out q
				i += length(q) - 1
				q = ""
				continue
			}
			c = " "
		} else if (c == "\"" || c == "'") {
			q = c
			if (substr(s, i, 3) == c c c) {
				q = c c c
				out = out q
				i += 2
				continue
			}
		} else if (c == "#") {
			break
		}
		out = out c
	}
	tq = (length(q) == 3) ? q : ""
	return out
}

function finish_test() {
	if (in_test && !asserted)
		print test_file ":" test_line " assertion-free " test_name " has no assertion (assert_*, verify)"
	in_test = 0
	in_sig = 0
}

function finish_sig() {
	in_sig = 0
	if (sig ~ /Fuzzer|fuzzer_iterations/ && sig !~ /fuzzer_seed/)
		print test_file ":" test_line " unseeded-fuzzer " test_name " uses a fuzzer without fuzzer_seed"
}

# depth(s): how many brackets s leaves open.
function depth(s,   t) {
	t = s
	return gsub(/[([{]/, "", t) - gsub(/[)\]}]/, "", s)
}

# args_from(s): the text of s up to the bracket that closes one already open.
function args_from(s,   i, c, d) {
	d = 1
	for (i = 1; i <= length(s); i++) {
		c = substr(s, i, 1)
		if (c ~ /[([{]/) d++
		else if (c ~ /[)\]}]/ && --d == 0) break
	}
	return substr(s, 1, i - 1)
}

# call_args(s, name): the text inside the first `.name(` call's parentheses.
function call_args(s, name) {
	if (!match(s, "\\." name "[ \t]*\\(")) return ""
	return args_from(substr(s, RSTART + RLENGTH))
}

# exact_args(s): the text inside every exact comparison's parentheses in s,
# joined by blanks; nothing when it makes none.
function exact_args(s,   all, a) {
	all = ""
	while (match(s, "\\.(" EXACT ")[ \t]*\\(")) {
		s = substr(s, RSTART + RLENGTH)
		a = args_from(s)
		all = all " " a
		s = substr(s, length(a) + 1)
	}
	return all
}

# second_arg(s): the second top-level, comma-separated part of s, trimmed.
function second_arg(s,   i, c, d, start) {
	d = 0
	start = 0
	for (i = 1; i <= length(s); i++) {
		c = substr(s, i, 1)
		if (c ~ /[([{]/) d++
		else if (c ~ /[)\]}]/) d--
		else if (c == "," && d == 0) {
			if (start) break
			start = i + 1
		}
	}
	if (!start) return ""
	s = substr(s, start, i - start)
	gsub(/[ \t]+/, " ", s)
	gsub(/^ | $/, "", s)
	return s
}

function has_number(s) {
	return s ~ /(^|[^A-Za-z0-9_.])[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?([^A-Za-z0-9_.]|$)/
}

function has_float(s) {
	return s ~ /(^|[^A-Za-z0-9_.])[0-9]*\.[0-9]+([eE][-+]?[0-9]+)?([^A-Za-z0-9_.]|$)|(^|[^A-Za-z0-9_.])[0-9]+\.?[eE][-+]?[0-9]+([^A-Za-z0-9_.]|$)|(^|[^A-Za-z0-9_.])[0-9]+\.([^A-Za-z0-9_.]|$)/
}

# is_float(name): the name is declared a float in this func, or else at the top.
function is_float(name) {
	if (name in local_kind) return local_kind[name]
	return (name in top_kind) && top_kind[name]
}

# check_statement(st, at, top): the comparison checks on one whole statement;
# top when it starts at column 0.
function check_statement(st, at, top,   args, subject, tol, name, f) {
	if (match(st, /^[ \t]*(static[ \t]+)?(const|var)[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
		name = substr(st, RSTART, RLENGTH)
		sub(/^.*(const|var)[ \t]+/, "", name)
		f = (st ~ /:[ \t]*float([^A-Za-z0-9_]|$)/ || st ~ /:?=[ \t]*[-+]?(([0-9]+\.[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?|[0-9]+[eE][-+]?[0-9]+)[ \t]*$/)
		if (top) top_kind[name] = f
		else local_kind[name] = f
	}
	if (match(st, /assert_(array|dict|that)[ \t]*\(/)) {
		subject = args_from(substr(st, RSTART + RLENGTH))
		if (subject !~ /^[ \t]*[[{]/) subject = ""
		args = exact_args(st)
		if (args != "" && has_float(subject " " args))
			print FILENAME ":" at " float-exact compares a float exactly inside an array or dictionary; compare each float with is_equal_approx and a named tolerance"
	}
	if (index(st, ".is_equal_approx")) {
		tol = second_arg(call_args(st, "is_equal_approx"))
		if (tol != "" && has_number(tol))
			print FILENAME ":" at " unnamed-tolerance the tolerance " tol " is written with numbers; make it a named constant"
		if (st ~ /assert_vector[ \t]*\(/ && tol != "" && (tol ~ /^[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?$/ || is_float(tol)))
			print FILENAME ":" at " vector-tolerance assert_vector's is_equal_approx takes a vector tolerance, such as Vector2(" tol ", " tol "), not the float " tol
	}
}

# chain_kind(t): the kind of an access chain t (a, a[0], a.b, a[0].b, self.a):
# "number", "constant" (an ALL_CAPS name), "name" (a variable, indexed or not),
# "member" (a chain with a dot past its root) or "other" (a keyword, nothing, a
# member of a call's result). A name or member is kept in operand, blanks
# dropped, its indexes and self. kept.
function chain_kind(t,   base) {
	gsub(/[ \t]/, "", t)
	if (t ~ /^\.?[0-9]/) return "number"
	if (t !~ /^[A-Za-z_]/) return "other"
	base = t
	gsub(/\[[^]]*\]/, "", base)
	sub(/^self\./, "", base)
	operand = t
	if (base == "self" && t ~ /^self\[/) return "name"
	if (base ~ /^(true|false|null|self|not|and|or|in|is|as|await)$/) return "other"
	if (base ~ /^_*[A-Z][A-Z0-9_]*$/) return "constant"
	return (base ~ /\./) ? "member" : "name"
}

# chain_root(t): the name the access chain t starts from, with its self. if it
# has one: box for box.frames and box[0], self.box for self.box.frames.
function chain_root(t) {
	gsub(/[ \t]/, "", t)
	gsub(/\[[^]]*\]/, "", t)
	if (match(t, /^(self\.)?[A-Za-z_][A-Za-z0-9_]*/)) return substr(t, 1, RLENGTH)
	return ""
}

# chain_back(s): the access chain that ends s, the text left of an operator or a
# dot: names, dots and indexes, with a group's brackets opened and a cast in the
# group (as Type) dropped. When a call ends s, called is set and the chain is
# the call's name.
function chain_back(s,   i, c, d, pre) {
	called = 0
	for (;;) {
		sub(/[ \t]+$/, "", s)
		if (s !~ /\)$/) break
		d = 0
		for (i = length(s); i >= 1; i--) {
			c = substr(s, i, 1)
			if (c == ")" || c == "]") d++
			else if ((c == "(" || c == "[") && --d == 0) break
		}
		if (i < 1) return ""
		pre = substr(s, 1, i - 1)
		if (pre ~ /[]A-Za-z0-9_)][ \t]*$/ && pre !~ WORD_BEFORE) {
			called = 1
			s = pre
			sub(/[ \t]+$/, "", s)
			break
		}
		s = substr(s, i + 1, length(s) - i - 1)
		sub(/[ \t]as[ \t].*$/, "", s)
	}
	for (i = length(s); i >= 1; i--) {
		c = substr(s, i, 1)
		if (c == "]") {
			d = 0
			for (; i >= 1; i--) {
				c = substr(s, i, 1)
				if (c == "]" || c == ")") d++
				else if ((c == "[" || c == "(") && --d == 0) break
			}
			if (i < 1) return ""
		} else if (c !~ /[A-Za-z0-9_.]/) {
			break
		}
	}
	return substr(s, i + 1)
}

# chain_fwd(s): the access chain that starts s, the text right of an operator,
# after any sign or opening bracket. called is set when a call follows it.
function chain_fwd(s,   i, c, d, n) {
	sub(/^[-+( \t]*/, "", s)
	n = length(s)
	for (i = 1; i <= n; i++) {
		c = substr(s, i, 1)
		if (c == "[") {
			d = 0
			for (; i <= n; i++) {
				c = substr(s, i, 1)
				if (c == "[" || c == "(") d++
				else if ((c == "]" || c == ")") && --d == 0) break
			}
		} else if (c !~ /[A-Za-z0-9_.]/) {
			break
		}
	}
	called = (substr(s, i) ~ /^[ \t]*\(/)
	return substr(s, 1, i - 1)
}

# left_operand(s), right_operand(s): the kind of the operand left of an operator
# (s ends with it) or right of one (s starts with it); a call is "other".
function left_operand(s,   t) {
	t = chain_back(s)
	return called ? "other" : chain_kind(t)
}

function right_operand(s,   t) {
	t = chain_fwd(s)
	return called ? "other" : chain_kind(t)
}

# poll_counters(cond): what cond compares with a bound, each between blanks: the
# names in counters, the members in members, and those of either that count up
# in ups. A name or member left of <, <=, > or >= counts, or right of one with a
# number or a constant on its left; != counts with a number or a constant on the
# other side. held gets the root of every chain cond holds that is no call.
function poll_counters(cond,   i, j, n, op, lk, ln, rk, rn, name, kind, up, t) {
	counters = " "
	members = " "
	ups = " "
	n = length(cond)
	for (i = 1; i <= n; i++) {
		op = substr(cond, i, 2)
		if (op == "<<" || op == ">>" || op == "->") { i++; continue }
		if (op != "<=" && op != ">=" && op != "!=") op = substr(cond, i, 1)
		if (op != "<" && op != ">" && op != "<=" && op != ">=" && op != "!=") continue
		lk = left_operand(substr(cond, 1, i - 1))
		ln = operand
		rk = right_operand(substr(cond, i + length(op)))
		rn = operand
		i += length(op) - 1
		if (lk ~ /^(name|member)$/ && (op != "!=" || rk ~ /^(number|constant)$/)) {
			name = ln
			kind = lk
			up = op ~ /</
		} else if (rk ~ /^(name|member)$/ && lk ~ /^(number|constant)$/) {
			name = rn
			kind = rk
			up = op ~ />/
		} else {
			continue
		}
		if (kind == "member") members = members name " "
		else counters = counters name " "
		if (up) ups = ups name " "
	}
	held = " "
	for (i = 1; i <= n; i++) {
		if (substr(cond, i, 1) !~ /[A-Za-z_]/ || (i > 1 && substr(cond, i - 1, 1) ~ /[A-Za-z0-9_.$%]/))
			continue
		j = i
		while (j <= n && substr(cond, j, 1) ~ /[A-Za-z0-9_]/) j++
		t = substr(cond, i, j - i)
		if (t == "self" && match(substr(cond, j), /^\.[A-Za-z_][A-Za-z0-9_]*/)) {
			t = t substr(cond, j, RLENGTH)
			j += RLENGTH
		}
		if (substr(cond, j) !~ /^[ \t]*\(/ && t !~ /^(not|and|or|in|is|as|true|false|null|self|await|func|return|if|else)$/)
			held = held t " "
		i = j - 1
	}
}

# poll_guard(cond): cond names a guard timer, the clock or a guard by its name.
function poll_guard(cond) {
	if (cond ~ /(^|[^A-Za-z0-9_])(is_stopped|get_ticks_msec|get_ticks_usec|get_unix_time[A-Za-z0-9_]*|get_process_frames|get_physics_frames|get_frames_drawn)[ \t]*\(/)
		return 1
	return tolower(cond) ~ /(time_left|guard|deadline|timeout|timed_out|expired)/
}

# await_in_lambda(s): the first await on s comes after a func on it, so it sits
# in a lambda written on that line.
function await_in_lambda(s) {
	if (!match(s, AWAIT)) return 0
	return substr(s, 1, RSTART) ~ FUNC_WORD
}

# open_poll(st): the while statement st ends on this line; its condition runs to
# the first colon outside brackets. Its body is the lines below, deeper than its
# while, or the rest of st after that colon, judged at once.
function open_poll(st,   i, c, d, cond, body) {
	sub(/^[ \t]*while/, "", st)
	d = 0
	for (i = 1; i <= length(st); i++) {
		c = substr(st, i, 1)
		if (c ~ /[([{]/) d++
		else if (c ~ /[)\]}]/) d--
		else if (c == ":" && d <= 0) break
	}
	cond = substr(st, 1, i - 1)
	body = substr(st, i + 1)
	polls++
	poll_file[polls] = FILENAME
	poll_line[polls] = statement_line
	poll_indent[polls] = statement_indent
	poll_report[polls] = is_added_at(statement_line) && !poll_reason
	poll_lams[polls] = lams
	poll_cond[polls] = " " cond " "
	poll_awaits[polls] = (cond ~ AWAIT && !await_in_lambda(cond)) || (body ~ AWAIT && !await_in_lambda(body))
	poll_bound[polls] = poll_guard(cond)
	poll_counters(cond)
	poll_names[polls] = counters
	poll_members[polls] = members
	poll_held[polls] = held
	poll_ups[polls] = ups
	poll_resets[polls] = " "
	poll_steps[polls] = " "
	if (body ~ /[^ \t]/) {
		poll_scan(polls, body)
		judge_poll(polls)
		polls--
	}
}

# as_regex(name): a regex that matches name, its dots literal.
function as_regex(name) {
	gsub(/\./, "[.]", name)
	return name
}

# poll_scan(k, s): s is code in loop k's body; its assignments are read outside
# a lambda written on it, and its drain calls anywhere.
function poll_scan(k, s,   t) {
	t = s
	if (match(t, FUNC_WORD)) t = substr(t, 1, RSTART)
	poll_assigns(k, t)
	poll_drains(k, s)
}

# poll_assigns(k, t): each assignment t makes, at its start or after a colon or
# a semicolon, to a chain or to one that starts with a group, cast or not
# ((node as Node2D).position.x += 1.0). `<chain> = 0` sets the chain back to 0.
# Any other `<chain> op=`, or `<chain> = ...` with the chain's root on its right
# (box.frames = box.frames + 1), steps the chain's root, kept with self. and
# without, so that self.box and box are one root here.
function poll_assigns(k, t,   rest, target, step, root) {
	rest = ":" t
	while (match(rest, /[:;][ \t]*(\([^()]*\)|[A-Za-z_])[A-Za-z0-9_.]*([ \t]*\[[^]]*\][A-Za-z0-9_.]*)*[ \t]*[-+*\/%]?=/)) {
		target = substr(rest, RSTART + 1, RLENGTH - 1)
		rest = substr(rest, RSTART + RLENGTH)
		if (rest ~ /^=/) continue
		step = target ~ /[-+*\/%]=$/
		sub(/[ \t]*[-+*\/%]?=$/, "", target)
		if (sub(/^[ \t]*\([ \t]*/, "", target))
			sub(/([ \t]+as[ \t]+[A-Za-z0-9_.]*)?[ \t]*\)/, "", target)
		gsub(/[ \t]/, "", target)
		root = chain_root(target)
		sub(/^self\./, "", root)
		if (!step && rest ~ /^[ \t]*(0+\.?0*|\.0+)[ \t]*(;.*)?$/)
			poll_resets[k] = poll_resets[k] target " "
		else if (root != "" && (step || rest ~ ("(^|[^A-Za-z0-9_.])(self[.])?" as_regex(root) "([^A-Za-z0-9_]|$)")))
			poll_steps[k] = poll_steps[k] root " self." root " "
	}
}

# poll_drains(k, s): a drain call in s on a list the condition names bounds loop
# k: a name of the call's receiver, its indexes, a group, a cast or a call after
# it dropped, is a name the condition holds.
function poll_drains(k, s,   at, list) {
	at = 0
	while (match(substr(s, at + 1), DRAIN)) {
		at += RSTART
		list = chain_back(substr(s, 1, at - 1))
		gsub(/\[[^]]*\]/, "", list)
		while (match(list, /[A-Za-z_][A-Za-z0-9_]*/)) {
			if (substr(list, RSTART, RLENGTH) != "self" && poll_cond[k] ~ ("[^A-Za-z0-9_]" substr(list, RSTART, RLENGTH) "[^A-Za-z0-9_]"))
				poll_bound[k] = 1
			list = substr(list, RSTART + RLENGTH)
		}
	}
}

# poll_body_line(s, at): s, a line of code at indent at, sits in the body of
# every loop still open, and is scanned for those it is not in a lambda opened
# since; an await there makes the loop a poll. A line that ends in a colon after
# a func (a trailing backslash dropped), other than a block header whose brackets
# close on it, opens a lambda, and so does a func whose signature or body leaves
# a bracket open; that one (lam_sig, the line's indent) opens again where its
# signature ends in a colon, in the same statement, if a line has closed it.
function poll_body_line(s, at,   k, t, awaits) {
	while (lams > 0 && at <= lam_indent[lams]) lams--
	awaits = s ~ AWAIT && !await_in_lambda(s)
	for (k = 1; k <= polls; k++) {
		if (poll_lams[k] != lams) continue
		if (awaits) poll_awaits[k] = 1
		poll_scan(k, s)
	}
	t = s
	sub(/\\[ \t]*$/, "", t)
	if (t ~ FUNC_WORD && t ~ ENDS_COLON && !(t ~ CONTROL && depth(t) <= 0)) {
		lam_indent[++lams] = at
		lam_sig = -1
	} else if (match(t, FUNC_WORD) && depth(substr(t, RSTART)) > 0) {
		lam_indent[++lams] = at
		lam_sig = at
	} else if (lam_sig >= 0 && t ~ ENDS_COLON && t !~ CONTROL) {
		if (lams < 1 || lam_indent[lams] != lam_sig) lam_indent[++lams] = lam_sig
		lam_sig = -1
	}
}

# poll_reset(k, c): counter c of loop k counts up and the body sets it back to 0.
function poll_reset(k, c) {
	return index(poll_ups[k], " " c " ") && index(poll_resets[k], " " c " ")
}

# judge_poll(k): loop k has ended. It is a finding when its while line is added
# and gives no reason, it awaits, and nothing in its condition bounds it. A
# counter bounds it unless poll_reset; a member counter only when the body steps
# its root too; and a root the condition holds outside any counter, such as left
# in `while left:`, when the body steps it.
function judge_poll(k,   n, i, names, roots) {
	if (!poll_report[k] || !poll_awaits[k] || poll_bound[k]) return
	roots = " "
	n = split(poll_names[k], names, " ")
	for (i = 1; i <= n; i++) {
		if (!poll_reset(k, names[i])) return
		roots = roots chain_root(names[i]) " "
	}
	n = split(poll_members[k], names, " ")
	for (i = 1; i <= n; i++) {
		if (index(poll_steps[k], " " chain_root(names[i]) " ") && !poll_reset(k, names[i])) return
		roots = roots chain_root(names[i]) " "
	}
	n = split(poll_held[k], names, " ")
	for (i = 1; i <= n; i++)
		if (!index(roots, " " names[i] " ") && index(poll_steps[k], " " names[i] " ")) return
	print poll_file[k] ":" poll_line[k] " unguarded-poll this while loop awaits but nothing in its condition bounds it, so a broken build hangs instead of failing; put a guard timer's time_left (guard.time_left > 0.0) or a frame counter (frames < MAX_FRAMES) in its condition, or give the reason on this line or the one above: # unguarded-poll: <why>"
}

# close_polls(at): a statement at indent at ends every loop open at or right of
# it, the innermost first, and each is judged; at < 0 ends them all.
function close_polls(at) {
	while (polls > 0 && (at < 0 || at <= poll_indent[polls])) {
		judge_poll(polls)
		polls--
	}
}

# count_statement(s, at): in count mode, a statement s starting at indent at. One
# at its scope's member indent (column 0, or the body of the innermost class open)
# ends the func before it, and opens a class or a func when it is one, annotations
# on its line included. A name is any run up to a space, "(", ":" or a line's
# joining backslash, so a Unicode name stays whole. It sets count_head to the
# length of a func's header up to its name, which then counts as no call
# (func assert_valid()).
function count_statement(s, at,   name, member) {
	count_head = 0
	while (count_classes > 0 && at <= count_class_at[count_classes]) count_classes--
	if (count_classes > 0 && count_class_body[count_classes] < 0) count_class_body[count_classes] = at
	member = (count_classes > 0) ? count_class_body[count_classes] : 0
	if (at > member) return
	count_func = ""
	if (match(s, COUNT_ANNOTATIONS "class[ \t]+[^ \t(:\\\\]+")) {
		name = substr(s, RSTART, RLENGTH)
		sub(/^.*class[ \t]+/, "", name)
		if (count_classes > 0) name = count_class_name[count_classes] "." name
		count_class_at[++count_classes] = at
		count_class_name[count_classes] = name
		count_class_body[count_classes] = -1
	} else if (match(s, COUNT_ANNOTATIONS "(static[ \t]+)?func[ \t]+[^ \t(:\\\\]+")) {
		count_head = RLENGTH
		name = substr(s, RSTART, RLENGTH)
		sub(/^.*func[ \t]+/, "", name)
		if (count_classes > 0) name = count_class_name[count_classes] "." name
		count_func = name
		if (!(name in count_calls)) {
			count_order[++count_funcs] = name
			count_line[name] = FNR
			count_calls[name] = 0
		}
	}
}

# Count mode: each line's assertion calls go to the func open; nothing else runs.
counts {
	sub(/\r$/, "")
	in_string = (tq != "")
	line = code($0)
	count_head = 0
	if (!in_string && count_depth <= 0 && !count_joined && line ~ /[^ \t]/)
		count_statement(line, indent_of(line))
	for (rest = substr(line, count_head + 1); match(rest, ASSERT_CALL); rest = substr(rest, RSTART + RLENGTH))
		if (count_func != "") count_calls[count_func]++
	count_depth += depth(line)
	count_joined = (line ~ /\\[ \t]*$/)
	if (count_depth < 0) count_depth = 0
	next
}

FNR == 1 {
	reason_above = 0
	close_polls(-1)
	lams = 0
	lam_sig = -1
	poll_above = 0
	finish_test()
	split("", top_kind)
	split("", local_kind)
	statement = ""
	tq = ""
	reset_blocks()
}

{
	sub(/\r$/, "")
	in_string = (tq != "")
	line = code($0)
	starts_statement = (statement == "")
	if (starts_statement) {
		statement_line = FNR
		statement_top = (line ~ /^[^ \t]/)
		statement_indent = indent_of(line)
	}
	part = line
	joined = sub(/\\[ \t]*$/, "", part)
	statement = statement " " part
	statement_depth = depth(statement)
	finished = ""
	if (depth(statement) <= 0 && !joined) {
		check_statement(statement, statement_line, statement_top)
		finished = statement
		statement = ""
	}
}

# A fixed wait on an added line, with no reason on it or alone on the line above.
{
	wait = fixed_wait(line)
	if (wait != "" && is_added() && !reason_above && $0 !~ REASON)
		print FILENAME ":" FNR " fixed-wait " wait " waits a fixed time; wait for the state each frame behind a guard timer, or give the reason on this line or the one above: # fixed-wait: <why>"
	reason_above = (!in_string && $0 ~ ("^[ \t]*" REASON))
}

# An assertion on an added line under a branch or loop, or after a guard return.
# Each line of code closes the blocks it is not inside. A statement on one line
# is read whole once it ends; the lines of a longer one are read one by one, and
# the whole of it once more when it ends, for a header split over lines.
{
	if (!in_string && line ~ /[^ \t]/) close_blocks(indent_of(line))
	if (starts_statement) statement_is_control = (line ~ CONTROL)
	if (line ~ ASSERT_CALL && is_added() && (controls > 0 || guarded || statement_is_control))
		print FILENAME ":" FNR " branched-assert this assertion sits under an if, elif, else, for, while or match, or after a guard return, so what the test asserts depends on the run; assert straight-line, each recorded value by index"
	if (!in_string && !(starts_statement && finished != "")) {
		read_line_blocks(line, indent_of(line))
		end_lambda(line, indent_of(line))
	}
	if (finished != "") {
		read_statement_blocks(finished, statement_indent)
		lambda_open = -1
		control_open = -1
	}
}

# A while loop on an added line that awaits, with nothing in its condition to
# bound it. A statement at or left of a loop's indent ends the loop, and it is
# judged then; each line of code before that is read as its body, and a
# statement over lines is read whole once more when it ends, for an assignment
# or a drain split over lines. A reason sits on any line of the while statement,
# or alone on the line above it.
{
	if (!in_string && line ~ /[^ \t]/) {
		if (starts_statement) close_polls(indent_of(line))
		poll_body_line(line, indent_of(line))
	}
	if (finished != "" && !starts_statement)
		for (pk = 1; pk <= polls; pk++)
			if (poll_lams[pk] == lams) poll_scan(pk, finished)
	if (finished != "") lam_sig = -1
	if (starts_statement) poll_reason = poll_above
	if (substr($0, length(line) + 1) ~ POLL_REASON) poll_reason = 1
	if (finished ~ WHILE) open_poll(finished)
	poll_above = (!in_string && $0 ~ ("^[ \t]*" POLL_REASON))
}

# A func starts: close the test before it, maybe open a new one; its names are new.
line ~ /^[ \t]*(static[ \t]+)?func[ \t]/ {
	split("", local_kind)
	reset_blocks()
	finish_test()
	if (match(line, /func[ \t]+test_[A-Za-z0-9_]*/)) {
		test_name = substr(line, RSTART, RLENGTH)
		sub(/^func[ \t]+/, "", test_name)
		test_file = FILENAME
		test_line = FNR
		in_test = 1
		asserted = 0
		in_sig = 1
		sig = ""
	}
}

# Any other code at column 0 ends a func body (a signature may close there); the
# rest of a string that started above doesn't.
in_test && !in_sig && !in_string && line ~ /^[^ \t]/ && line !~ /^(static[ \t]+)?func[ \t]/ {
	finish_test()
}

in_test {
	if (in_sig) {
		sig = sig " " line
		opens = gsub(/\(/, "(", sig)
		closes = gsub(/\)/, ")", sig)
		if (opens > 0 && opens == closes) finish_sig()
	}
	if (line ~ /assert_[a-z_]+[ \t]*\(|verify[ \t]*\(|verify_no_interactions|verify_no_more_interactions/)
		asserted = 1
}

END {
	if (counts) {
		for (i = 1; i <= count_funcs; i++)
			print count_line[count_order[i]] " " count_order[i] " " count_calls[count_order[i]]
	} else {
		close_polls(-1)
		finish_test()
	}
}
