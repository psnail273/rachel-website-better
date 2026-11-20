# The factory's hooks: where their sources live, the config generated from them,
# and the hook mode. Sourced by hooks.sh, amend.sh and hooks/pre-commit.sh (needs
# steps.sh and findings.sh); defines no side effects.
#
# Sources, all in factory/core/hooks/:
#   githooks/            core.hooksPath points here (git hooks; nothing is copied)
#   claude-hooks.json    the value of the "hooks" key of .claude/settings.json: the
#                        Sonnet Editor's PreToolUse deny (claude-deny.sh),
#                        every agent's PreToolUse wait guard on Bash
#                        (claude-wait-guard.sh: no pgrep -f that matches its
#                        own shell; advice to background verify, lock.sh
#                        record and land), the Editor's SubagentStart hook
#                        (claude-subagent-start.sh, the round's snapshot,
#                        lib/round.sh), its SubagentStop hook
#                        (claude-subagent-stop.sh, also the PreToolUse of every
#                        SubagentHandback call, which it takes only from the
#                        Editor) and the session-start update check
#                        (claude-update-check.sh)
#   claude-workspace-hooks.json  the same for the factory repo's own workspace,
#                        which amend.sh record writes: the wait guard alone, its
#                        entry as claude-hooks.json has it
#   editor-gate.sh       the gate the Editor's stop hook runs
# A hook is added by editing a source, then regenerating. The generator rewrites
# only the "hooks", "model", "effortLevel" and "maxEffortLevel" keys of
# .claude/settings.json (the last three: the main session runs FACTORY_MAIN_MODEL
# at FACTORY_MAIN_EFFORT, and no session or subagent above FACTORY_MAX_EFFORT,
# the factory's effort policy, CONTEXT.md's Models and effort), adds
# FACTORY_LIFT_RULE to its "permissions" "allow" list when that lacks it, and
# leaves the rest, byte for byte, as it was: the human's own allow rules and
# other keys. A human who wants another model for their own sessions sets it in
# the untracked .claude/settings.local.json, which wins.
#
# Retired: the Cursor Editor's generated .cursor/hooks.json and .cursor/cli.json.
# generate removes each when it is still the factory's (factory_retired_hook_files)
# and check reports it, so a project that synced past them loses them.
#
# The hook mode is the tracked tools/verify/hook-mode, one word: `report` while the
# project is Adopted (pre-commit prints findings, never blocks) or `enforce` once it
# is Armed (pre-commit blocks). adopt.sh writes it and arm.sh flips it. Only
# pre-commit reads it: the write deny refuses and the Editor's stop hook loops in
# both modes. A project without it has not adopted the factory's hooks, so there is
# nothing to drift.

FACTORY_HOOKS_SRC="factory/core/hooks"
# shellcheck disable=SC2034 # read by the scripts that source this lib
FACTORY_GITHOOKS_DIR="$FACTORY_HOOKS_SRC/githooks"
FACTORY_HOOK_MODE_FILE="$FACTORY_STEPS_DIR/hook-mode"
# shellcheck disable=SC2034 # read by the scripts that source this lib
FACTORY_CLAUDE_SETTINGS=".claude/settings.json"
# shellcheck disable=SC2034 # read by amend.sh
FACTORY_WORKSPACE_HOOKS="$FACTORY_HOOKS_SRC/claude-workspace-hooks.json"
# The main session's model and effort, written into .claude/settings.json.
FACTORY_MAIN_MODEL="claude-opus-5-5"
FACTORY_MAIN_EFFORT="medium"
# The highest effort any session or subagent may run at, as "maxEffortLevel".
FACTORY_MAX_EFFORT="xhigh"
# The Bash permission rule for a Driver's one Lock lift (the build skill's Driver's
# calls), in "permissions" "allow": a narrow allow rule is settled before a
# permission prompt or the auto-mode classifier is asked, so a driver subagent's
# `bash factory/core/lock.sh lift` runs. lock.sh still allows one lift per issue.
FACTORY_LIFT_RULE="Bash(bash factory/core/lock.sh lift:*)"

# factory_hook_mode: print the mode (report or enforce); false when the file is
# missing or holds anything else.
factory_hook_mode() {
	local mode
	[ -f "$FACTORY_HOOK_MODE_FILE" ] || return 1
	mode="$(tr -d '\r' < "$FACTORY_HOOK_MODE_FILE" | awk 'NF && $1 !~ /^#/ { print $1; exit }')"
	case "$mode" in
		report | enforce) printf '%s\n' "$mode" ;;
		*) return 1 ;;
	esac
}

# factory_hook_mode_write <report|enforce>: write the hook mode file.
factory_hook_mode_write() {
	printf '%s\n' "# The hook mode: report (Adopted) or enforce (Armed, set by factory/core/arm.sh)." "$1" > "$FACTORY_HOOK_MODE_FILE"
}

# factory_retired_hook_files: print, one per line, each retired generated file
# (the Cursor Editor's) that is here and still the factory's: .cursor/hooks.json
# running the factory's Cursor hooks, .cursor/cli.json holding its verify allowlist.
# A file the human wrote is left alone.
factory_retired_hook_files() {
	if [ -f .cursor/hooks.json ] && grep -q 'factory/core/hooks/cursor-' .cursor/hooks.json; then
		echo .cursor/hooks.json
	fi
	if [ -f .cursor/cli.json ] && grep -qF 'Shell(bash tools/verify.sh)' .cursor/cli.json; then
		echo .cursor/cli.json
	fi
}

# factory_settings_render <settings-file> [hooks-block-file]: print the settings
# file with the hooks block (when given) as its "hooks" key and the main
# session's model and effort as its "model" and "effortLevel" keys and the
# effort cap as "maxEffortLevel", every other
# key kept as it was (factory_json_set_key), and FACTORY_LIFT_RULE in its
# "permissions" "allow" list (factory_json_allow). Exit 1 when the settings file
# is not a JSON object, or its "permissions" or their "allow" is of another type.
factory_settings_render() {
	local dir status=0
	dir="$(mktemp -d)" || return 1
	if [ -n "${2:-}" ]; then
		factory_json_set_key "$1" hooks "$2" > "$dir/settings" || status=1
	elif [ -f "$1" ]; then
		cp "$1" "$dir/settings" || status=1
	else
		: > "$dir/settings"
	fi
	printf '"%s"\n' "$FACTORY_MAIN_MODEL" > "$dir/model"
	printf '"%s"\n' "$FACTORY_MAIN_EFFORT" > "$dir/effort"
	printf '"%s"\n' "$FACTORY_MAX_EFFORT" > "$dir/max"
	[ "$status" -ne 0 ] || factory_json_set_key "$dir/settings" model "$dir/model" > "$dir/with-model" || status=1
	[ "$status" -ne 0 ] || factory_json_set_key "$dir/with-model" effortLevel "$dir/effort" > "$dir/with-effort" || status=1
	[ "$status" -ne 0 ] || factory_json_set_key "$dir/with-effort" maxEffortLevel "$dir/max" > "$dir/with-max" || status=1
	[ "$status" -ne 0 ] || factory_json_allow "$dir/with-max" "$FACTORY_LIFT_RULE" || status=1
	rm -rf "$dir"
	return "$status"
}

# factory_json_set_key <settings-file> <key> <block-file>: print the settings
# file with its top-level <key> value replaced by the block (added as the last key
# when absent; a missing or empty settings file becomes an object holding only
# it). The block is indented two spaces to sit at the top level. Exit 1 when the
# settings file is not a JSON object.
factory_json_set_key() {
	local settings="$1" key="$2" block="$3"
	[ -f "$settings" ] || settings=/dev/null
	{
		tr -d '\r' < "$block"
		printf '\001\n'
		tr -d '\r' < "$settings"
	} | awk -v want="$key" '
		BEGIN { part = 0 }
		part == 0 && $0 == "\001" { part = 1; next }
		part == 0 { blk = blk (nb++ ? "\n  " : "") $0; next }
		{ s = s (ns++ ? "\n" : "") $0 }
		END {
			sub(/[ \n]+$/, "", blk)
			if (ns == 0 || s ~ /^[ \t\n]*$/) { printf "{\n  \"%s\": %s\n}\n", want, blk; exit 0 }
			n = length(s); depth = 0; instr = 0; expect = ""; open = 0; shut = 0
			hs = 0; he = 0; vstart = 0; last = 0; members = 0; key = ""; str = ""
			for (i = 1; i <= n; i++) {
				c = substr(s, i, 1)
				if (instr) {
					if (c == "\\") { str = str c substr(s, i + 1, 1); i++ }
					else if (c == "\"") {
						instr = 0
						if (depth == 1 && expect == "key") { key = str; expect = "colon" }
					} else str = str c
					last = i
					continue
				}
				if (c ~ /[ \t\n]/) continue
				if (depth == 0) {
					if (open) exit 1
					if (c != "{") exit 1
					open = i; depth = 1; expect = "key"; continue
				}
				if (depth == 1) {
					if (c == ":") { if (expect != "colon") exit 1; expect = "value"; continue }
					if (c == "," || c == "}") {
						if (expect == "in-value" && key == want) { hs = vstart; he = last }
						if (c == "}") { shut = i; depth = 0 }
						expect = "key"; continue
					}
					if (expect == "value") { vstart = i; expect = "in-value"; members++ }
					else if (expect != "in-value" && !(expect == "key" && c == "\"")) exit 1
				}
				last = i
				if (c == "\"") { instr = 1; str = "" }
				else if (c == "{" || c == "[") depth++
				else if (c == "}" || c == "]") depth--
			}
			if (!shut) exit 1
			if (hs) out = substr(s, 1, hs - 1) blk substr(s, he + 1)
			else if (members) out = substr(s, 1, last) ",\n  \"" want "\": " blk "\n" substr(s, shut)
			else out = substr(s, 1, open) "\n  \"" want "\": " blk "\n" substr(s, shut)
			printf "%s\n", out
		}
	'
}

# factory_json_allow <settings-file> <rule>: print the settings file with the rule
# in its "permissions" "allow" list: as it was when the list holds the rule; else
# the rule appended to the list, the list added to "permissions", or
# "permissions" added as the first key, each indented as its neighbours are. The
# rest stays byte for byte. The rule is a plain string, no quote or backslash in
# it. Exit 1 when the file is not a JSON object, or "permissions" is not an
# object or its "allow" not a list.
factory_json_allow() {
	{
		[ ! -f "$1" ] || tr -d '\r' < "$1"
	} | awk -v rule="$2" '
		{ s = s (ns++ ? "\n" : "") $0 }
		# The leading blanks of the line that holds position p.
		function indent(p,   b, e) {
			b = p
			while (b > 1 && substr(s, b - 1, 1) != "\n") b--
			e = b
			while (substr(s, e, 1) == " " || substr(s, e, 1) == "\t") e++
			return substr(s, b, e - b)
		}
		END {
			q = "\"" rule "\""
			if (ns == 0 || s ~ /^[ \t\n]*$/) { printf "{\n  \"permissions\": {\n    \"allow\": [\n      %s\n    ]\n  }\n}\n", q; exit 0 }
			n = length(s); depth = 0; instr = 0; open = 0; shut = 0; last = 0; members = 0
			e1 = ""; k1 = ""; pd = 0; popen = 0; pshut = 0; plast = 0; pmembers = 0; e2 = ""; k2 = ""
			ad = 0; aopen = 0; ashut = 0; alast = 0; aelems = 0; have = 0
			for (i = 1; i <= n; i++) {
				c = substr(s, i, 1)
				if (instr) {
					if (c == "\\") { str = str c substr(s, i + 1, 1); i++ }
					else if (c == "\"") {
						instr = 0
						if (depth == 1 && e1 == "key") { k1 = str; e1 = "colon" }
						else if (pd && depth == 2 && e2 == "key") { k2 = str; e2 = "colon" }
						else if (ad && depth == 3 && str == rule) have = 1
					} else str = str c
					last = i
					continue
				}
				if (c ~ /[ \t\n]/) continue
				if (depth == 0) {
					if (open) exit 1
					if (c != "{") exit 1
					open = i; depth = 1; e1 = "key"; continue
				}
				if (depth == 1) {
					if (c == ":") { if (e1 != "colon") exit 1; e1 = "value"; continue }
					if (c == "," || c == "}") {
						if (c == "}") { shut = i; depth = 0 }
						e1 = "key"; continue
					}
					if (e1 == "value") {
						e1 = "in-value"; members++
						if (k1 == "permissions") {
							if (c != "{" || popen) exit 1
							pd = 1; popen = i; e2 = "key"
						}
					} else if (e1 != "in-value" && !(e1 == "key" && c == "\"")) exit 1
				} else if (pd && depth == 2) {
					if (c == ":") { e2 = "value"; continue }
					if (c == ",") { e2 = "key"; continue }
					if (c == "}") { plast = last; pshut = i; pd = 0; depth = 1; last = i; continue }
					if (e2 == "value") {
						e2 = "in-value"; pmembers++
						if (k2 == "allow") {
							if (c != "[" || aopen) exit 1
							ad = 1; aopen = i
						}
					}
				} else if (ad && depth == 3) {
					if (c == ",") continue
					if (c == "]") { alast = last; ashut = i; ad = 0; depth = 2; last = i; continue }
					aelems++
				}
				last = i
				if (c == "\"") { instr = 1; str = "" }
				else if (c == "{" || c == "[") depth++
				else if (c == "}" || c == "]") depth--
			}
			if (!shut) exit 1
			if (have) { printf "%s\n", s; exit 0 }
			if (aopen) {
				if (!aelems) out = substr(s, 1, aopen) "\n" indent(aopen) "  " q "\n" indent(aopen) substr(s, ashut)
				else if (index(substr(s, aopen, alast - aopen), "\n")) out = substr(s, 1, alast) ",\n" indent(alast) q substr(s, alast + 1)
				else out = substr(s, 1, alast) ", " q substr(s, alast + 1)
			} else if (popen) {
				ind = indent(popen)
				blk = "\"allow\": [\n" ind "    " q "\n" ind "  ]"
				if (!pmembers) out = substr(s, 1, popen) "\n" ind "  " blk "\n" ind substr(s, pshut)
				else out = substr(s, 1, plast) ",\n" ind "  " blk substr(s, plast + 1)
			} else {
				blk = "\"permissions\": {\n    \"allow\": [\n      " q "\n    ]\n  }"
				if (members) out = substr(s, 1, open) "\n  " blk (substr(s, open + 1, 1) == "\n" ? "," : ", ") substr(s, open + 1)
				else out = substr(s, 1, open) "\n  " blk "\n" substr(s, shut)
			}
			printf "%s\n", out
		}
	'
}
