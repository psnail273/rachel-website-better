# Reading a hook's JSON input and writing its JSON output, with awk alone (no jq,
# no Python). Sourced by the agent hooks; defines no side effects.
#
# A value's key is its path of member names and array indexes joined by dots:
# `tool_input.file_path`, `workspace_roots.0`. Strings come back decoded (\uXXXX
# as UTF-8); numbers, true, false and null come back as written. The reader is for
# input that is already JSON; it doesn't validate it.

# _factory_json_scan <mode> [key]: the shared scanner. Mode `flatten` prints
# `key<TAB>value` for every scalar, with newlines, CRs and tabs in a value turned to
# spaces; mode `get` prints the one value at [key] as it is, and exits 1 when there
# is none.
_factory_json_scan() {
	LC_ALL=C awk -v mode="$1" -v want="${2:-}" '
		function utf8(c) {
			if (c < 128) return sprintf("%c", c)
			if (c < 2048) return sprintf("%c%c", 192 + int(c / 64), 128 + c % 64)
			return sprintf("%c%c%c", 224 + int(c / 4096), 128 + int(c / 64) % 64, 128 + c % 64)
		}
		function hex(h,   i, n) {
			n = 0
			for (i = 1; i <= 4; i++) n = n * 16 + index("0123456789abcdef", tolower(substr(h, i, 1))) - 1
			return n
		}
		# The string opening at pos (a quote); sets pos past its closing quote.
		function str(   out, c, e, n, lo) {
			out = ""
			pos++
			while (pos <= len) {
				c = substr(s, pos, 1)
				if (c == "\"") { pos++; return out }
				if (c == "\\") {
					e = substr(s, pos + 1, 1)
					if (e == "u") {
						n = hex(substr(s, pos + 2, 4))
						pos += 6
						if (n >= 55296 && n < 56320 && substr(s, pos, 2) == "\\u") {
							lo = hex(substr(s, pos + 2, 4))
							n = 65536 + (n - 55296) * 1024 + (lo - 56320)
							pos += 6
							out = out sprintf("%c%c%c%c", 240 + int(n / 262144), 128 + int(n / 4096) % 64, 128 + int(n / 64) % 64, 128 + n % 64)
						} else {
							out = out utf8(n)
						}
						continue
					}
					if (e == "n") out = out "\n"
					else if (e == "t") out = out "\t"
					else if (e == "r") out = out "\r"
					else if (e == "b") out = out "\b"
					else if (e == "f") out = out "\f"
					else out = out e
					pos += 2
					continue
				}
				out = out c
				pos++
			}
			return out
		}
		function ws() { while (pos <= len && index(" \t\n\r", substr(s, pos, 1))) pos++ }
		function emit(key, v) {
			if (mode == "get") {
				if (key == want) { printf "%s", v; found = 1; exit 0 }
				return
			}
			gsub(/[\n\r\t]/, " ", v)
			printf "%s\t%s\n", key, v
		}
		function join(prefix, name) { return prefix == "" ? name : prefix "." name }
		# The value at pos, under key.
		function value(key,   c, start, i, name) {
			ws()
			c = substr(s, pos, 1)
			if (c == "{") {
				pos++
				ws()
				if (substr(s, pos, 1) == "}") { pos++; return }
				while (pos <= len) {
					ws()
					name = str()
					ws()
					pos++ # the colon
					value(join(key, name))
					ws()
					c = substr(s, pos, 1)
					pos++
					if (c != ",") return
				}
				return
			}
			if (c == "[") {
				pos++
				ws()
				if (substr(s, pos, 1) == "]") { pos++; return }
				for (i = 0; pos <= len; i++) {
					value(join(key, i))
					ws()
					c = substr(s, pos, 1)
					pos++
					if (c != ",") return
				}
				return
			}
			if (c == "\"") { emit(key, str()); return }
			start = pos
			while (pos <= len && !index(",}] \t\n\r", substr(s, pos, 1))) pos++
			emit(key, substr(s, start, pos - start))
		}
		{ s = s $0 "\n" }
		END {
			len = length(s)
			pos = 1
			value("")
			if (mode == "get") exit found ? 0 : 1
		}
	'
}

# factory_json_flatten < json: print `key<TAB>value` for every scalar, in order.
factory_json_flatten() {
	_factory_json_scan flatten
}

# factory_json_get <key> < json: print the value at <key>, decoded; false when absent.
factory_json_get() {
	_factory_json_scan get "$1"
}

# factory_json_string <text>: print <text> as a JSON string literal, CRs dropped.
factory_json_string() {
	printf '%s' "$1" | LC_ALL=C awk '
		BEGIN {
			bs = sprintf("%c", 92)
			for (i = 1; i < 32; i++) esc[sprintf("%c", i)] = sprintf("%su%04x", bs, i)
			esc["\t"] = bs "t"
			esc["\""] = bs "\""
			esc[bs] = bs bs
		}
		{
			sub(/\r$/, "")
			out = ""
			for (i = 1; i <= length($0); i++) {
				c = substr($0, i, 1)
				out = out ((c in esc) ? esc[c] : c)
			}
			text = (NR > 1 ? text bs "n" : "") out
		}
		END { printf "\"%s\"", text }
	'
}
