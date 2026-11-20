#!/usr/bin/env bash
# The wait guard, a Claude Code PreToolUse hook (claude-hooks.json) for every
# agent: the main session and every subagent, in a project and in the factory
# repo's own workspace (amend.sh record writes it there). It refuses a Bash call
# that runs pgrep, pkill or pidwait with -f (also -af, -fl, --full, ...) on a
# pattern that, as pgrep reads it (an extended regex, unanchored; -i and -x as
# pgrep applies them), matches the call's own command text. Claude Code runs the
# call as `bash -c "... eval '<the command>' ..."`, so such a pgrep matches the
# shell running it: a wait loop like `until ! pgrep -f "<script>"; do sleep 2;
# done` never ends, and pkill kills its own shell.
# Claude Code runs it before each Bash call, with the call as JSON on stdin:
#   {"tool_name": "Bash", "tool_input": {"command": "..."}, ...}
# By hand: bash factory/core/hooks/claude-wait-guard.sh < call.json
#
# It reads the command as the shell would: quotes, escapes, comments, here-docs,
# redirections, $(...), backquotes and subshells, the words before a command
# (assignments, `!`, `until`, `do`, ...) and wrappers (`timeout 60`, `nice`,
# `sudo`, ...), and the string a `bash -c` or `sh -c` runs. A pgrep in a string
# or a comment runs nothing and passes. It lets a call by whenever it can't be
# sure: a pattern or an option from a variable, `$(...)` or a glob; an option it
# doesn't know; a command that doesn't parse; one that also selects by -P, -F,
# -g, -s, -t, -r or --cgroup, or excludes the shell with -v or -A
# (--ignore-ancestors), -u, -U or -G naming none of its user and group, or -O.
# `exec pgrep` and the one simple command a `bash -c` runs replace their shell,
# so only the command line above them counts. An array's value runs nothing. A pattern is judged against the command as it stands in
# the shell's command line: between other text, so `^` and `$` don't match at
# its ends, and both as written and with each ' as Claude Code's eval quotes it
# ('"'"'): it refuses only when the pattern matches both.
#
# The refusal gives the bracketed form of the caller's own pattern, `pgrep -f
# 'tools/verify.sh'` -> `pgrep -f '[t]ools/verify.sh'`, when that form no
# longer matches the command.
#
# It also advises, without refusing: a call that runs verify.sh, `lock.sh
# record` or land.sh in the foreground (the command word, or the script a shell
# runs; not in a call that holds a lone `&`, nor with its run_in_background) runs past the
# 180 s after which the Bash tool backgrounds it anyway, so it is told to use
# run_in_background and wait with `tail --pid=<pid> -f /dev/null`. The advice is
# PreToolUse JSON on stdout, an additionalContext with no permissionDecision:
# the call goes on to the normal permission flow.
#
# It loads no lib and needs only bash and awk. A call whose JSON holds none of
# pgrep, pkill, pidwait, verify.sh, lock.sh and land.sh exits at once. A refusal
# exits 2 with the rule and its fixes on stderr, which Claude Code hands the
# agent; otherwise it exits 0, with the advice or no output, and the call goes
# on to the normal permission flow.
set -u

input="$(cat)"
case "$input" in *pgrep* | *pkill* | *pidwait* | *verify.sh* | *lock.sh* | *land.sh*) ;; *) exit 0 ;; esac

# The JSON's tool_input.command, decoded, when its tool_name is Bash, after one
# character: 1 when its tool_input.run_in_background is true, else 0; false
# otherwise. Strings and that one true only: the hook needs no other value.
# shellcheck disable=SC2016 # awk's own $
json_command='
	function utf8(c) {
		if (c < 128) return sprintf("%c", c)
		if (c < 2048) return sprintf("%c%c", 192 + int(c / 64), 128 + c % 64)
		if (c < 65536) return sprintf("%c%c%c", 224 + int(c / 4096), 128 + int(c / 64) % 64, 128 + c % 64)
		return sprintf("%c%c%c%c", 240 + int(c / 262144), 128 + int(c / 4096) % 64, 128 + int(c / 64) % 64, 128 + c % 64)
	}
	function hex(h,   k, v) {
		v = 0
		for (k = 1; k <= 4; k++) v = v * 16 + index("0123456789abcdef", tolower(substr(h, k, 1))) - 1
		return v
	}
	# The string opening at i (a quote), decoded; sets i past its closing quote.
	function str(   out, c, e, v, lo) {
		out = ""
		i++
		while (i <= n) {
			c = substr(s, i, 1)
			if (c == "\"") { i++; return out }
			if (c != "\\") { out = out c; i++; continue }
			e = substr(s, i + 1, 1)
			if (e == "u") {
				v = hex(substr(s, i + 2, 4)); i += 6
				if (v >= 55296 && v < 56320 && substr(s, i, 2) == "\\u") {
					lo = hex(substr(s, i + 2, 4))
					if (lo >= 56320 && lo < 57344) { v = 65536 + (v - 55296) * 1024 + (lo - 56320); i += 6 }
				}
				if (v > 0) out = out utf8(v)
				continue
			}
			if (e == "n") out = out "\n"
			else if (e == "t") out = out "\t"
			else if (e == "r") out = out "\r"
			else if (e == "b") out = out "\b"
			else if (e == "f") out = out "\f"
			else out = out e
			i += 2
		}
		return out
	}
	{ s = s (NR > 1 ? "\n" : "") $0 }
	END {
		n = length(s); depth = 0; i = 1
		while (i <= n) {
			c = substr(s, i, 1)
			if (c == "\"") {
				v = str()
				if (type[depth] == "o" && iskey[depth]) { key[depth] = v; iskey[depth] = 0 }
				else if (depth == 1 && key[1] == "tool_name") name = v
				else if (depth == 2 && type[1] == "o" && type[2] == "o" && key[1] == "tool_input" && key[2] == "command") { command = v; have = 1 }
				continue
			}
			if (c == "t" && substr(s, i, 4) == "true" && depth == 2 && type[1] == "o" && type[2] == "o" && key[1] == "tool_input" && key[2] == "run_in_background" && !iskey[2]) { bg = 1; i += 4; continue }
			if (c == "{") { depth++; type[depth] = "o"; iskey[depth] = 1; key[depth] = "" }
			else if (c == "[") { depth++; type[depth] = "a"; key[depth] = "" }
			else if (c == "}" || c == "]") depth--
			else if (c == "," && type[depth] == "o") iskey[depth] = 1
			i++
		}
		if (name != "Bash" || !have) exit 1
		printf "%d%s", bg, command
	}
'

# Each pgrep, pkill or pidwait call with -f that the command runs, and each
# string a `bash -c` in it runs, one record a line, fields tab-separated, the
# value escaped (\\, \n, \t):
#   P <tool> <flags: i, x, or -> <pattern>
#   C - - <the string bash -c runs>
#   L - - <verify.sh, lock.sh record or land.sh, run in the foreground>
#   S - - -   (first, when the command is one simple command)
#   A - - -   (when it holds a lone &: no advice for the call)
# Nothing when the command doesn't parse.
# shellcheck disable=SC2016 # awk's own $
parse_calls='
	BEGIN {
		split("if then elif else do while until ! { } fi done esac", a, " ")
		for (k in a) KEYWORD[a[k]] = 1
		# Not exec: it replaces the shell, which is then no longer there to match.
		split("sudo nohup command builtin nice env timeout stdbuf setsid ionice time", a, " ")
		for (k in a) WRAP[a[k]] = 1
		split("HUP INT QUIT ILL TRAP ABRT IOT BUS FPE KILL USR1 SEGV USR2 PIPE ALRM TERM STKFLT CHLD CLD CONT STOP TSTP TTIN TTOU URG XCPU XFSZ VTALRM PROF WINCH IO POLL PWR SYS", a, " ")
		for (k in a) SIG[a[k]] = 1
		# The user (-u, -U) and group (-G) of the shell, as IDs and names.
		split(me, a, ","); for (k in a) ME[a[k]] = 1
		split(mygroup, a, ","); for (k in a) MYGROUP[a[k]] = 1
	}
	function esc(v,   out, k, c) {
		out = ""
		for (k = 1; k <= length(v); k++) {
			c = substr(v, k, 1)
			if (c == "\\") out = out "\\\\"
			else if (c == "\n") out = out "\\n"
			else if (c == "\t") out = out "\\t"
			else out = out c
		}
		return out
	}
	# The command frame the current word belongs to: a double quote adds to the
	# word of the frame it opened in.
	function cf() { return T[d] == "dq" ? d - 1 : d }
	function add(ch,   f) { f = cf(); C[f] = C[f] ch; IN[f] = 1 }
	function unknown(   f) { f = cf(); IN[f] = 1; CK[f] = 0 }
	function push(t) { if (t != "dq" && t != "arr") CPLX = 1; d++; T[d] = t; N[d] = 0; C[d] = ""; IN[d] = 0; CK[d] = 1; G[d] = 0; R[d] = 0 }
	# $(...) or `...`: a command of its own, inside a word whose value is unknown.
	function push_sub(t) { unknown(); push(t) }
	function pop() { if (T[d] != "dq") endcmd(d); d-- }
	function endword(f) {
		if (!IN[f]) return
		if (R[f] == 1) R[f] = 0
		else if (R[f] >= 2) { HN++; HD[HN] = C[f]; HS[HN] = (R[f] == 3); R[f] = 0 }
		else { N[f]++; W[f, N[f]] = C[f]; K[f, N[f]] = CK[f] && !G[f] }
		C[f] = ""; IN[f] = 0; CK[f] = 1; G[f] = 0
	}
	function endcmd(f) { endword(f); analyze(f); N[f] = 0; R[f] = 0 }
	# At p, a $: an expansion makes the word unknown; $( opens a command.
	function dollar(p,   nx, q, ch) {
		nx = substr(s, p + 1, 1)
		if (nx == "(") { push_sub("sub"); return p + 2 }
		if (nx == "{") { q = index(substr(s, p + 2), "}"); unknown(); return q ? p + 2 + q : n + 1 }
		if (nx == "\047" && T[d] != "dq") {
			q = p + 2
			while (q <= n) { ch = substr(s, q, 1); if (ch == "\\") { q += 2; continue }; if (ch == "\047") break; q++ }
			unknown(); return q + 1
		}
		if (nx == "\"" && T[d] != "dq") { IN[d] = 1; push("dq"); return p + 2 }
		if (nx ~ /[A-Za-z_]/) { q = p + 1; while (q <= n && substr(s, q, 1) ~ /[A-Za-z0-9_]/) q++; unknown(); return q }
		if (nx != "" && index("0123456789@*#?$!-", nx)) { unknown(); return p + 2 }
		add("$"); return p + 1
	}
	# At p, < or >: the redirection operator; the next word is its target, or a
	# here-doc delimiter (R 2, or 3 for <<-).
	function redir(p,   c, c2, c3) {
		c = substr(s, p, 1); c2 = substr(s, p + 1, 1); c3 = substr(s, p + 2, 1)
		if (c == "<" && c2 == "<" && c3 == "<") { R[d] = 1; return p + 3 }
		if (c == "<" && c2 == "<" && c3 == "-") { R[d] = 3; return p + 3 }
		if (c == "<" && c2 == "<") { R[d] = 2; return p + 2 }
		R[d] = 1
		if (c2 == ">" || c2 == "&" || c2 == "|" || (c == "<" && c2 == ">")) return p + 2
		return p + 1
	}
	# At p, the line after a newline: skip the bodies of the here-docs pending.
	function heredocs(p,   k, e, line) {
		for (k = 1; k <= HN; k++) {
			while (p <= n) {
				e = index(substr(s, p), "\n")
				line = e ? substr(s, p, e - 1) : substr(s, p)
				p = e ? p + e : n + 1
				if (HS[k]) sub(/^\t+/, "", line)
				if (line == HD[k]) break
			}
		}
		HN = 0
		return p
	}
	function issig(w,   name) {
		if (w ~ /^-[0-9]+$/) return 1
		name = toupper(substr(w, 2)); sub(/^SIG/, "", name)
		return (name in SIG) || name ~ /^RTM(IN|AX)([+-][0-9]+)?$/
	}
	function analyze(f,   i, w, base) {
		if (T[f] == "arr") return
		if (N[f]) NC++
		for (i = 1; i <= N[f]; i++) {
			w = W[f, i]
			if (w ~ /^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=/) continue
			if (!K[f, i]) return
			if (w in KEYWORD) { CPLX = 1; continue }
			if (w in WRAP) {
				while (i < N[f] && K[f, i + 1] && (W[f, i + 1] ~ /^-/ || W[f, i + 1] ~ /^[0-9.]+[smhd]?$/ || W[f, i + 1] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) i++
				continue
			}
			break
		}
		if (i > N[f]) return
		base = W[f, i]; sub(/.*\//, "", base)
		# exec: only the script it runs counts; a pgrep or a bash -c string after
		# it is judged as before, not at all (its shell is gone).
		if (base == "exec" && i < N[f] && K[f, i + 1]) { i++; base = W[f, i]; sub(/.*\//, "", base); if (base ~ /^(ba|da|z|k)?sh$/) shells(f, i, 1); else long(f, i, i); return }
		if (base == "pgrep" || base == "pkill" || base == "pidwait") procs(f, i, base)
		else if (base ~ /^(ba|da|z|k)?sh$/) shells(f, i)
		else long(f, i, i)
	}
	# long <frame> <script word> <command word>: an L record when the script is
	# verify.sh, land.sh, or lock.sh with record.
	function long(f, j, i,   base, k) {
		if (!K[f, j]) return
		base = W[f, j]; sub(/.*\//, "", base)
		if (base == "lock.sh") {
			for (k = j + 1; k <= N[f] && W[f, k] ~ /^-/; k++) ;
			if (k > N[f] || W[f, k] != "record") return
			base = "lock.sh record"
		} else if (base != "verify.sh" && base != "land.sh") return
		OUT[++NO] = "L\t-\t-\t" base
	}
	# others <value> <known> <set>: true when the users or groups -u, -U or -G
	# names leave out the shell: unknown, or none of them in <set>.
	function others(v, vk, set,   a, k, m) {
		if (!vk) return 1
		m = split(v, a, ",")
		for (k = 1; k <= m; k++) if (a[k] in set) return 0
		return 1
	}
	# older <value> <known>: true when -O leaves out the shell, started just now.
	function older(v, vk) { return !vk || v !~ /^0*$/ }
	function procs(f, i, tool,   j, k, w, c, v, vk, name, hasv, full, x, ic, safe, havepat, pat, patk, endo, flags) {
		j = i + 1
		if (tool == "pkill" && j <= N[f] && K[f, j] && issig(W[f, j])) j++
		for (; j <= N[f]; j++) {
			w = W[f, j]
			if (endo || w !~ /^-/ || w == "-") {
				if (!havepat) { havepat = 1; pat = w; patk = K[f, j] }
				continue
			}
			if (!K[f, j]) return
			if (w == "--") { endo = 1; continue }
			if (w ~ /^--/) {
				name = substr(w, 3); hasv = index(name, "=")
				if (hasv) { v = substr(name, hasv + 1); vk = 1; name = substr(name, 1, hasv - 1) }
				if (name == "full") full = 1
				else if (name == "exact") x = 1
				else if (name == "ignore-case") ic = 1
				else if (name ~ /^(inverse|ignore-ancestors|parent|pidfile|pgroup|session|terminal|runstates|cgroup|require-handler)$/) safe = 1
				else if (name !~ /^(list-name|list-full|lightweight|count|newest|oldest|echo|logpidfile|delimiter|group|older|signal|euid|uid|ns|nslist|queue)$/) return
				if (!hasv && name ~ /^(delimiter|pgroup|group|older|parent|session|signal|terminal|euid|uid|pidfile|runstates|cgroup|ns|nslist|queue)$/) { j++; v = W[f, j]; vk = K[f, j] }
				if (name == "euid" || name == "uid") safe = safe || others(v, vk, ME)
				else if (name == "group") safe = safe || others(v, vk, MYGROUP)
				else if (name == "older") safe = safe || older(v, vk)
				continue
			}
			for (k = 2; k <= length(w); k++) {
				c = substr(w, k, 1)
				if (index("dgGOPstuUFrq", c)) {
					if (index("PFgstr", c)) safe = 1
					if (k == length(w)) { j++; v = W[f, j]; vk = K[f, j] }
					else { v = substr(w, k + 1); vk = 1 }
					if (c == "u" || c == "U") safe = safe || others(v, vk, ME)
					else if (c == "G") safe = safe || others(v, vk, MYGROUP)
					else if (c == "O") safe = safe || older(v, vk)
					break
				}
				if (c == "f") full = 1
				else if (c == "x") x = 1
				else if (c == "i") ic = 1
				else if (c == "v" || c == "A" || c == "H") safe = 1
				else if (!index("lawcnoeLhV", c)) return
			}
		}
		if (!full || safe || !havepat || !patk || index(pat, "\n")) return
		flags = (ic ? "i" : "") (x ? "x" : "")
		OUT[++NO] = "P\t" tool "\t" (flags == "" ? "-" : flags) "\t" esc(pat)
	}
	# shells <frame> <command word> [no -c]: with a third argument, after exec,
	# a -c string gives no record.
	function shells(f, i, noc,   j, w) {
		for (j = i + 1; j <= N[f]; j++) {
			w = W[f, j]
			if (!K[f, j]) return
			if (w == "-o" || w == "+o" || w == "-O" || w == "+O") { j++; continue }
			if (w ~ /^-[A-Za-z]*c[A-Za-z]*$/) {
				if (!noc && j < N[f] && K[f, j + 1]) OUT[++NO] = "C\t-\t-\t" esc(W[f, j + 1])
				return
			}
			if (w !~ /^[-+]/) { long(f, j, i); return }
		}
	}
	{ s = s (NR > 1 ? "\n" : "") $0 }
	END {
		n = length(s); d = 0; T[0] = "top"; N[0] = 0; C[0] = ""; IN[0] = 0; CK[0] = 1; G[0] = 0; R[0] = 0
		p = 1
		while (p <= n) {
			c = substr(s, p, 1)
			if (T[d] == "dq") {
				if (c == "\"") { d--; p++; continue }
				if (c == "\\") {
					nx = substr(s, p + 1, 1)
					if (nx == "\n") { p += 2; continue }
					if (nx != "" && index("$`\"\\", nx)) { add(nx); p += 2; continue }
					add(c); p++; continue
				}
				if (c == "$") { p = dollar(p); continue }
				if (c == "`") { push_sub("bt"); p++; continue }
				add(c); p++; continue
			}
			if (c == "`" && T[d] == "bt") { pop(); p++; continue }
			if (c == " " || c == "\t") { endword(d); p++; continue }
			if (c == "\n") { endcmd(d); p++; p = heredocs(p); continue }
			if (c == "#" && !IN[d]) { while (p <= n && substr(s, p, 1) != "\n") p++; continue }
			if (c == "\047") {
				e = index(substr(s, p + 1), "\047")
				if (!e) exit 0
				add(substr(s, p + 1, e - 1)); p += e + 1; continue
			}
			if (c == "\"") { IN[d] = 1; push("dq"); p++; continue }
			if (c == "\\") {
				nx = substr(s, p + 1, 1)
				if (nx != "\n") add(nx)
				p += 2; continue
			}
			if (c == "$") { p = dollar(p); continue }
			if (c == "`") { push_sub("bt"); p++; continue }
			if (c == ";" || c == "|") { endcmd(d); p++; continue }
			if (c == "&") {
				if (substr(s, p + 1, 1) == ">") { endword(d); p = redir(p + 1); continue }
				CPLX = 1
				# A lone &, not &&: the command before it runs in the background.
				if (substr(s, p + 1, 1) != "&" && substr(s, p - 1, 1) !~ /[&|]/) AMP = 1
				endcmd(d); p++; continue
			}
			# An array assignment: its value is words, not a command; a $(...) in
			# it still runs.
			if (c == "(" && IN[d] && CK[d] && C[d] ~ /^[A-Za-z_][A-Za-z0-9_]*\+?=$/) { unknown(); push("arr"); p++; continue }
			if (c == "(") { endcmd(d); push("paren"); p++; continue }
			if (c == ")") {
				if (d > 0 && (T[d] == "paren" || T[d] == "sub" || T[d] == "arr")) { pop(); p++; continue }
				endcmd(d); p++; continue
			}
			if (c == "<" || c == ">") {
				if (substr(s, p + 1, 1) == "(") { endword(d); push("paren"); p += 2; continue }
				# A file descriptor number before it is no word.
				if (IN[d] && CK[d] && C[d] ~ /^[0-9]+$/) { C[d] = ""; IN[d] = 0 }
				else endword(d)
				p = redir(p); continue
			}
			if (c == "*" || c == "?" || c == "[" || (c == "~" && !IN[d])) G[d] = 1
			add(c); p++
		}
		if (d != 0) exit 0
		endcmd(0)
		# One simple command: a bash -c running it execs it, and is gone.
		if (NC <= 1 && !CPLX) print "S\t-\t-\t-"
		# A lone &: something runs in the background, maybe the long script
		# inside a ( ) or { }.
		if (AMP) print "A\t-\t-\t-"
		for (k = 1; k <= NO; k++) print OUT[k]
	}
'

# unescape <value>: the record's value as it was.
unescape() {
	printf '%b' "$1"
}

# matches <pattern> <flags> <text>: true when pgrep, with those flags, would
# match a command line holding <text> between other text.
matches() {
	local re="$1" subject=$'\001'"$3"$'\001' status
	case "$2" in *x*) re="^($1)\$" ;; esac
	case "$2" in *i*) shopt -s nocasematch ;; esac
	[[ $subject =~ $re ]]
	status=$?
	shopt -u nocasematch
	return "$status"
}

# self_matches <pattern> <flags> <text>: true when the pattern matches <text>
# both as written and with each ' as Claude Code's eval quotes it.
self_matches() {
	matches "$1" "$2" "$3" && matches "$1" "$2" "${3//\'/\'\"\'\"\'}"
}

# bracketed <pattern>: the pattern with its first plain letter or digit (not
# escaped, not in a [...] or {...}) in brackets, `tools/x` -> `[t]ools/x`;
# empty when it has none.
bracketed() {
	local k c prev="" depth=0
	for ((k = 0; k < ${#1}; k++)); do
		c="${1:k:1}"
		if [ "$prev" = "\\" ]; then
			prev=x
			continue
		fi
		case "$c" in
			'[' | '{') depth=$((depth + 1)) ;;
			']' | '}') [ "$depth" -eq 0 ] || depth=$((depth - 1)) ;;
			[A-Za-z0-9])
				if [ "$depth" -eq 0 ]; then
					printf '%s[%s]%s' "${1:0:k}" "$c" "${1:k+1}"
					return
				fi
				;;
		esac
		prev="$c"
	done
}

# quoted <text>: the text in single quotes, as a shell reads it back.
quoted() {
	printf "'%s'" "${1//\'/\'\\\'\'}"
}

# json_string <text>: the text as a JSON string.
json_string() {
	local v="$1"
	v="${v//\\/\\\\}"
	v="${v//\"/\\\"}"
	v="${v//$'\n'/\\n}"
	v="${v//$'\t'/\\t}"
	printf '"%s"' "$v"
}

# check <text> <level>: refuse (exit 2) when a call in <text> matches the Bash
# call's own command, $command; at level 1 and deeper (the string of a bash -c)
# also when it matches that string, the inner shell's command line, unless the
# string is one simple command, which that shell execs in its own place.
check() {
	local kind tool flags value pattern hit effect single="" fix form rest
	while IFS=$'\t' read -r kind tool flags value; do
		if [ "$kind" = S ]; then
			single=1
			continue
		fi
		if [ "$kind" = A ]; then
			ampersand=1
			continue
		fi
		if [ "$kind" = L ]; then
			case " $long " in *" $value,"*) ;; *) long="${long:+$long }$value," ;; esac
			continue
		fi
		value="$(unescape "$value" && printf x)"
		value="${value%x}"
		if [ "$kind" = C ]; then
			[ "$2" -ge 3 ] || check "$value" $(($2 + 1))
			continue
		fi
		pattern="$value"
		hit=""
		if self_matches "$pattern" "$flags" "$command"; then
			hit=1
		elif [ "$2" -gt 0 ] && [ -z "$single" ] && matches "$pattern" "$flags" "$1"; then
			hit=1
		fi
		[ -n "$hit" ] || continue
		case "$tool" in
			pkill) effect="pkill would kill that shell" ;;
			*) effect="$tool matches that shell too, and a wait on it never ends" ;;
		esac
		# The bracketed form, when the command names the pattern's text once (the
		# pattern itself), and holding the form in its place no longer matches.
		fix="bracket one character of the pattern so it no longer matches itself: \`pgrep -f '[f]actory/core/test.sh'\` (only when the command doesn't also name it plainly)"
		form="$(bracketed "$pattern")"
		rest="${command//"$pattern"/}"
		if [ -n "$form" ] && [ $((${#command} - ${#rest})) -eq ${#pattern} ] &&
			! self_matches "$form" "$flags" "${command//"$pattern"/"$form"}"; then
			fix="bracket one character of the pattern so it no longer matches itself: \`$tool -f $(quoted "$form")\`"
		fi
		cat >&2 << EOF
Refused (wait-guard): \`$tool -f\` with the pattern '$pattern' matches this command's own text. Claude Code runs the command as \`bash -c "<the command>"\`, so $effect. Instead:
- wait on a PID: start the process in this call with \`&\`, then \`while kill -0 "\$pid" 2> /dev/null; do sleep 2; done\` with pid=\$!;
- or run the command with run_in_background and wait for its notification, or in the foreground with a long timeout;
- or, to look for a process another call started, $fix.
EOF
		exit 2
	done < <(printf '%s' "$1" | LC_ALL=C awk -v me="$me" -v mygroup="$mygroup" "$parse_calls")
}

command="$(printf '%s' "$input" | LC_ALL=C awk "$json_command" && printf x)" || exit 0
command="${command%x}"
background="${command:0:1}"
command="${command:1}"
me="$(id -u),$(id -un)"
mygroup="$(id -g),$(id -gn)"
long=""
ampersand=""
check "$command" 0
if [ -n "$long" ] && [ "$background" != 1 ] && [ -z "$ampersand" ]; then
	long="${long%,}"
	long="${long//,/ and}"
	advice="Advice (wait-guard): this call runs $long in the foreground, which takes longer than the 180 s after which the Bash tool moves a command to the background whatever its timeout. Run it with run_in_background instead, recording its PID and its output: \`echo \$\$ > <scratch>/run.pid; exec bash <the script> > <scratch>/run.log 2>&1\`. Then wait for its notification, or for its PID in the foreground: \`tail --pid=\"\$(cat <scratch>/run.pid)\" -f /dev/null\`, and read the log."
	printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}\n' "$(json_string "$advice")"
fi
exit 0
