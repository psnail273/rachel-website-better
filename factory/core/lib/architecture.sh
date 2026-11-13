# ARCHITECTURE.md rules and the arch step's checks. Sourced by an adapter's arch
# step (with findings.sh and steps.sh); defines no side effects.
#
# The rule format (see the project's ARCHITECTURE.md):
#   **R<n>.** One sentence.
#   Enforced by: `arch:<id>`, `review`        (also typecheck, lint:<rule>, deviation)
#   Source: an ADR link or "convention"
#
# An arch step registers one shell function per check and hands over:
#   factory_arch_check no-autoloads check_no_autoloads
#   factory_arch_check naming       check_naming
#   factory_arch_main ARCHITECTURE.md
# A check function prints `file:line message` lines, one per violation, and exits 0
# (any other exit is an arch-error). factory_arch_main runs the sync check, then
# every check a rule cites, and prints each violation as `file:line R<n> message`,
# R<n> being the rule that cites the check. It exits 1 on any finding.
#
# A check that needs the stack's runtime (reflection, a headless run) registers
# with a third argument, `runtime`. With FACTORY_ARCH_STATIC_ONLY=1 (the pre-commit
# hook sets it) factory_arch_main skips those and runs only the static ones.
#
# The sync check fails on an `arch:<id>` tag with no check, a check no rule cites,
# a rule number used twice, and a check cited by two rules (whose findings would
# have no single rule number).

FACTORY_ARCH_IDS=()
FACTORY_ARCH_FNS=()
FACTORY_ARCH_KINDS=()

# factory_arch_check <id> <function> [runtime]: register the check for `arch:<id>`.
factory_arch_check() {
	FACTORY_ARCH_IDS+=("$1")
	FACTORY_ARCH_FNS+=("$2")
	FACTORY_ARCH_KINDS+=("${3:-static}")
}

# factory_arch_parse <file>: the file's rules and arch tags, one per line, in order:
#   rule <n> <line>         a `**R<n>.**` rule heading
#   tag <n> <line> <id>     an `arch:<id>` on that rule's `Enforced by:` line
# A tag before any rule heading has rule number 0.
factory_arch_parse() {
	tr -d '\r' < "$1" | awk '
		match($0, /^\*\*R[0-9]+\.\*\*/) {
			rule = substr($0, 4, RLENGTH - 6) + 0
			print "rule", rule, NR
			next
		}
		/^Enforced by:/ {
			rest = $0
			while (match(rest, /`arch:[a-z0-9][a-z0-9-]*`/)) {
				print "tag", rule + 0, NR, substr(rest, RSTART + 6, RLENGTH - 7)
				rest = substr(rest, RSTART + RLENGTH)
			}
		}
	'
}

# factory_arch_sync <file>: print the sync check's findings for <file> against the
# registered checks. Exit 1 if there are any.
factory_arch_sync() {
	local file="$1" parsed ids
	parsed="$(factory_arch_parse "$file")"
	ids="$(printf '%s\n' "${FACTORY_ARCH_IDS[@]}")"
	local out
	out="$(
		printf '%s\n' "$parsed" | awk -v file="$file" -v step="$FACTORY_STEPS_DIR/arch" -v ids="$ids" '
			BEGIN {
				n = split(ids, list, "\n")
				for (i = 1; i <= n; i++) if (list[i] != "") have[list[i]] = 1
			}
			$1 == "rule" {
				if ($2 in seen) printf "%s:%s arch-sync R%s is used twice (first at line %s); a rule number is never reused\n", file, $3, $2, seen[$2]
				else seen[$2] = $3
			}
			$1 == "tag" {
				id = $4
				if ($2 == 0) printf "%s:%s arch-sync arch:%s is outside any rule\n", file, $3, id
				if (!(id in have)) printf "%s:%s arch-sync arch:%s (R%s) has no check\n", file, $3, id, $2
				if (id in cited && cited[id] != $2) printf "%s:%s arch-sync arch:%s is cited by R%s and R%s; a check belongs to one rule\n", file, $3, id, cited[id], $2
				else cited[id] = $2
			}
			END {
				for (i = 1; i <= n; i++)
					if (list[i] != "" && !(list[i] in cited)) printf "%s:1 arch-sync check %s is cited by no rule\n", step, list[i]
			}
		'
	)"
	[ -z "$out" ] && return 0
	printf '%s\n' "$out"
	return 1
}

# factory_arch_rule <file> <id>: the number of the first rule citing `arch:<id>`,
# or nothing.
factory_arch_rule() {
	factory_arch_parse "$1" | awk -v id="$2" '$1 == "tag" && $4 == id && $2 > 0 { print $2; exit }'
}

# factory_arch_main <file>: the sync check, then every cited check. Exit 1 on any
# finding.
factory_arch_main() {
	local file="$1" bad=0 i id fn rule out status
	if [ ! -f "$file" ]; then
		factory_finding "$file" 1 arch-sync "no $file; the arch step checks its rules"
		return 1
	fi
	factory_arch_sync "$file" || bad=1
	for i in "${!FACTORY_ARCH_IDS[@]}"; do
		id="${FACTORY_ARCH_IDS[$i]}"
		fn="${FACTORY_ARCH_FNS[$i]}"
		rule="$(factory_arch_rule "$file" "$id")"
		[ -z "$rule" ] && continue # the sync check reported it
		[ "${FACTORY_ARCH_STATIC_ONLY:-0}" = 1 ] && [ "${FACTORY_ARCH_KINDS[$i]}" = runtime ] && continue
		out="$("$fn")"
		status=$?
		if [ "$status" -ne 0 ]; then
			factory_finding "$FACTORY_STEPS_DIR/arch" 1 arch-error "check $id exited $status"
			bad=1
		fi
		[ -z "$out" ] && continue
		bad=1
		printf '%s\n' "$out" | tr -d '\r' | awk -v r="R$rule" '
			{
				sp = index($0, " ")
				if (sp == 0) print $0, r, "(no message)"
				else print substr($0, 1, sp - 1), r, substr($0, sp + 1)
			}
		'
	done
	return "$bad"
}

# factory_arch_review_rules <file>: the rules whose `Enforced by:` line cites
# `review`, in file order, one Markdown bullet each:
#   - **R<n>.** <sentence> (<file>:<line>)
#   - **R<n>.** <sentence> (<file>:<line>; `arch:<id>` checks part of it; judge the rest)
# A rule's sentence runs from its heading to its `Enforced by:` line, joined.
factory_arch_review_rules() {
	tr -d '\r' < "$1" | awk -v file="$1" '
		function flush() {
			if (rule != "" && review) {
				line = "- " text " (" file ":" at
				if (others != "") line = line "; " others " checks part of it; judge the rest"
				print line ")"
			}
			rule = ""
		}
		match($0, /^\*\*R[0-9]+\.\*\*/) {
			flush()
			rule = substr($0, 3, RLENGTH - 4)
			text = $0
			at = NR
			review = 0
			others = ""
			collecting = 1
			next
		}
		rule != "" && /^Enforced by:/ {
			collecting = 0
			rest = substr($0, 13)
			n = split(rest, parts, ",")
			for (i = 1; i <= n; i++) {
				p = parts[i]
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
				bare = p
				gsub(/`/, "", bare)
				if (bare == "review") review = 1
				else if (bare != "") others = others (others == "" ? "" : ", ") "`" bare "`"
			}
			next
		}
		rule != "" && collecting && NF { text = text " " $0 }
		/^#/ { flush() }
		END { flush() }
	'
}
