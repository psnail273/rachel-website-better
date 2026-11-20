# The Build Brief's machine-readable block. Sourced by the Core's scripts (needs
# findings.sh); defines no side effects.
#
# The brief lives at <git-dir>/factory/brief.md, so it never lands and each
# worktree has its own. Its prose is for people; the Core reads only the one
# fenced block opened by a line that is exactly ```factory-brief and closed by a
# line that is exactly ```. Inside it, one `<key> <value>` per line; blank lines
# and # comments are allowed:
#
#   ```factory-brief
#   scope src/stock/reorder_rule
#   scope tests/stock/**
#   test test_reorder_waits_for_the_threshold
#   seam src/stock/reorder_rule ReorderRule.is_due
#   ```
#
#   scope <glob>          a path the issue may touch. `*` and `?` stay inside one
#                         folder, `**` crosses folders, a trailing / means the
#                         whole folder. At least one is required.
#   test <name>           an acceptance test the red phase adds: the rest of the
#                         line, so a name may hold spaces (`suite > test`).
#   seam <path> <symbol>  a seam to stub: the stub's file and what it stubs.
#   removes <entry>       a Baseline entry the issue removes (Partial mode):
#                         `<file> <rule> <message>`, as in
#                         tools/verify/ratchet/baseline.txt (baseline.sh).
#   grows <file> <entry>  a ratchet entry the issue may add: Opus accepted that
#                         growth as a Deviation. <file> is the ratchet file,
#                         <entry> the whole line it gains. One line per entry
#                         added, so a repeated entry needs two.
#   asserts <file> <func> <from> <to>
#                         a drop in a test func's assertion calls that the Driver
#                         accepts, as the deviation step measures it: <file> in
#                         scope, <func> as the adapter's probe names it, <from>
#                         its count at the base and <to> at HEAD (0 when the func
#                         is gone), <to> below <from>. One line per func.
#   invariants <path> <symbol> <property>
#                         an invariant of a slice that parses, formats or
#                         transforms data: the seam its property test drives
#                         (the module's path and the exported symbol) and the
#                         property in plain words, the rest of the line, which
#                         is also the property test's title. One line per
#                         property, each named once per seam; brief.sh
#                         invariants lists them for the Verifier.
#   lane small            the small-issue lane: one Editor round, whose stop hook
#                         records the Lock and moves the chat to green itself
#                         (hooks/editor-gate.sh). At most one line.
#                         factory_brief_lane_lint holds the brief to the lane's
#                         limits, and brief.sh seal puts the lane in the run state.
#
# Add a key by adding it to FACTORY_BRIEF_KEYS and a case in factory_brief_parse.
#
# The prose around the block follows the template in the build skill's
# build-brief.md; factory_brief_lint checks the parts of it the gates rely on.
# The Driver seals the brief once it passes (brief.sh seal): its hash goes in the
# run state, and factory_brief_seal_check fails the Editor's gate and the
# deviation step if the brief changes after that.

FACTORY_BRIEF_KEYS="scope test seam removes grows asserts invariants lane"

# The template's `Kind: <kind>. Phase: <phase>.` line.
FACTORY_BRIEF_KINDS="build bug cleanup amend asset"
FACTORY_BRIEF_PHASES="red partial green"

# The Driver's docs: the files the Driver commits on an issue's branch, in any
# phase. docs/deviations.md holds every ruling, docs/agents/facts.md the engine
# and tool facts each brief probes (the build skill's build-brief.md). The red gate
# lets them through as it does tests (lib/red.sh), a test-only brief may scope
# them, and neither the small lane's file count nor the seal's overlap check
# counts them.
FACTORY_DRIVER_DOCS="docs/deviations.md docs/agents/facts.md"

# The small lane's limits: the most `test` lines, and the most product files (a
# scope line that is neither a test file nor one of the Driver's docs).
FACTORY_SMALL_TESTS=4
FACTORY_SMALL_FILES=3

# Filled by factory_brief_parse: the values, and the brief line each came from.
BRIEF_SCOPE=() BRIEF_SCOPE_LINES=()
BRIEF_TESTS=() BRIEF_TEST_LINES=()
BRIEF_SEAMS=() BRIEF_SEAM_LINES=()
BRIEF_REMOVES=() BRIEF_REMOVE_LINES=()
BRIEF_GROWS=() BRIEF_GROW_LINES=()
BRIEF_ASSERTS=() BRIEF_ASSERT_LINES=()
BRIEF_INVARIANTS=() BRIEF_INVARIANT_LINES=()
BRIEF_LANE="" BRIEF_LANE_LINE=0
# Filled by factory_brief_lint: the Kind and Phase its Kind line names, or "";
# the test files its Existing tests bullets name, unaffected ones too, with a
# leading ./ dropped, and the line of that heading (0 when there is none).
BRIEF_KIND="" BRIEF_PHASE=""
BRIEF_EXISTING_FILES=() BRIEF_EXISTING_LINE=0

# factory_is_driver_doc <path>: true when the path is one of the Driver's docs.
factory_is_driver_doc() {
	# shellcheck disable=SC2086 # the list splits into its words
	factory_word_in "$1" $FACTORY_DRIVER_DOCS
}

# factory_brief_path: the brief's path: $FACTORY_BRIEF when set, else
# <git-dir>/factory/brief.md relative to the current folder. False outside git.
factory_brief_path() {
	local dir
	if [ -n "${FACTORY_BRIEF:-}" ]; then
		printf '%s\n' "$FACTORY_BRIEF"
		return 0
	fi
	dir="$(git rev-parse --path-format=relative --git-dir 2> /dev/null)" || return 1
	printf '%s/factory/brief.md\n' "$dir"
}

# factory_brief_parse <brief>: fill the BRIEF_* arrays from the brief's block.
# Prints a finding for each problem, against <brief>, and exits 1 if there were any.
factory_brief_parse() {
	local brief="$1" n=0 line key value rest open=0 opened_at=0 blocks=0 bad=0 func from to more symbol words
	local re_count='^(0|[1-9][0-9]{0,8})$' re_func='^[^[:space:]]+$'
	BRIEF_SCOPE=() BRIEF_SCOPE_LINES=()
	BRIEF_TESTS=() BRIEF_TEST_LINES=()
	BRIEF_SEAMS=() BRIEF_SEAM_LINES=()
	BRIEF_REMOVES=() BRIEF_REMOVE_LINES=()
	BRIEF_GROWS=() BRIEF_GROW_LINES=()
	BRIEF_ASSERTS=() BRIEF_ASSERT_LINES=()
	BRIEF_INVARIANTS=() BRIEF_INVARIANT_LINES=()
	BRIEF_LANE="" BRIEF_LANE_LINE=0

	if [ ! -f "$brief" ]; then
		factory_finding "$brief" 1 brief-missing "no Build Brief at this path"
		return 1
	fi

	# shellcheck disable=SC2094 # the loop reads the brief; factory_finding only names it
	while IFS= read -r line || [ -n "$line" ]; do
		n=$((n + 1))
		line="${line%$'\r'}"
		if [ "$open" -eq 0 ]; then
			if [ "$line" = '```factory-brief' ]; then
				blocks=$((blocks + 1))
				if [ "$blocks" -gt 1 ]; then
					factory_finding "$brief" "$n" brief-block-duplicate "a second factory-brief block; the brief has exactly one"
					bad=1
				fi
				open=1 opened_at=$n
			fi
			continue
		fi
		if [ "$line" = '```' ]; then
			open=0
			continue
		fi
		# Only the first block is read; a duplicate is already a finding.
		[ "$blocks" -gt 1 ] && continue
		case "$line" in '' | '#'*) continue ;; esac

		read -r key value rest <<< "$line"
		case "$key" in
			scope)
				if [ -z "$value" ] || [ -n "$rest" ] || [ "${value#/}" != "$value" ]; then
					factory_finding "$brief" "$n" brief-format "expected 'scope <glob>' with one relative glob, got: $line"
					bad=1
				else
					BRIEF_SCOPE+=("$value") BRIEF_SCOPE_LINES+=("$n")
				fi
				;;
			test)
				# The name is the rest of the line, inner spaces kept as written.
				value="${line#*test}"
				value="${value#"${value%%[![:space:]]*}"}"
				value="${value%"${value##*[![:space:]]}"}"
				if [ -z "$value" ]; then
					factory_finding "$brief" "$n" brief-format "expected 'test <name>', got: $line"
					bad=1
				elif factory_brief_has_test "$value"; then
					factory_finding "$brief" "$n" brief-format "test $value is named twice"
					bad=1
				else
					BRIEF_TESTS+=("$value") BRIEF_TEST_LINES+=("$n")
				fi
				;;
			seam)
				if [ -z "$value" ] || [ -z "$rest" ]; then
					factory_finding "$brief" "$n" brief-format "expected 'seam <path> <symbol>', got: $line"
					bad=1
				else
					BRIEF_SEAMS+=("$value $rest") BRIEF_SEAM_LINES+=("$n")
				fi
				;;
			removes)
				if [ -z "$value" ] || [ "${rest#* }" = "$rest" ]; then
					factory_finding "$brief" "$n" brief-format "expected 'removes <file> <rule> <message>', a Baseline entry, got: $line"
					bad=1
				else
					BRIEF_REMOVES+=("$value $rest") BRIEF_REMOVE_LINES+=("$n")
				fi
				;;
			grows)
				if [ -z "$value" ] || [ -z "$rest" ]; then
					factory_finding "$brief" "$n" brief-format "expected 'grows <file> <entry>', got: $line"
					bad=1
				else
					BRIEF_GROWS+=("$value $rest") BRIEF_GROW_LINES+=("$n")
				fi
				;;
			asserts)
				read -r func from to more <<< "$rest"
				while [ "${value#./}" != "$value" ]; do value="${value#./}"; done
				if [ -z "$value" ] || [ "${value#/}" != "$value" ] || [ -n "$more" ] || ! [[ $func =~ $re_func ]] ||
					! [[ $from =~ $re_count ]] || ! [[ $to =~ $re_count ]]; then
					factory_finding "$brief" "$n" brief-format "expected 'asserts <file> <func> <from> <to>': a relative path, a func name and two counts, got: $line"
					bad=1
				elif [ "$to" -ge "$from" ]; then
					factory_finding "$brief" "$n" brief-format "asserts declares a drop, so <to> is below <from>, got: $line"
					bad=1
				elif factory_brief_has_asserts "$value" "$func"; then
					factory_finding "$brief" "$n" brief-format "asserts names $func in $value twice"
					bad=1
				else
					BRIEF_ASSERTS+=("$value $func $from $to") BRIEF_ASSERT_LINES+=("$n")
				fi
				;;
			invariants)
				# The property is the rest of the line, inner spaces kept as written.
				read -r symbol words <<< "$rest"
				words="${words%"${words##*[![:space:]]}"}"
				while [ "${value#./}" != "$value" ]; do value="${value#./}"; done
				if [ -z "$value" ] || [ "${value#/}" != "$value" ] || [ -z "$symbol" ] || [ -z "$words" ]; then
					factory_finding "$brief" "$n" brief-format "expected 'invariants <path> <symbol> <property>': a relative path, the exported symbol the property drives and the property in words, got: $line"
					bad=1
				elif factory_brief_has_invariant "$value" "$symbol" "$words"; then
					factory_finding "$brief" "$n" brief-format "invariant '$words' of $value $symbol is named twice"
					bad=1
				else
					BRIEF_INVARIANTS+=("$value $symbol $words") BRIEF_INVARIANT_LINES+=("$n")
				fi
				;;
			lane)
				if [ "$value" != small ] || [ -n "$rest" ]; then
					factory_finding "$brief" "$n" brief-format "expected 'lane small', got: $line"
					bad=1
				elif [ "$BRIEF_LANE_LINE" -ne 0 ]; then
					factory_finding "$brief" "$n" brief-format "a second lane line; the brief has at most one"
					bad=1
				else
					BRIEF_LANE="$value" BRIEF_LANE_LINE=$n
				fi
				;;
			*)
				factory_finding "$brief" "$n" brief-format "unknown key '$key'; the keys are: $FACTORY_BRIEF_KEYS"
				bad=1
				;;
		esac
	done < "$brief"

	if [ "$blocks" -eq 0 ]; then
		factory_finding "$brief" 1 brief-block-missing "no fenced block opened by a line '\`\`\`factory-brief'"
		return 1
	fi
	if [ "$open" -eq 1 ]; then
		factory_finding "$brief" "$opened_at" brief-block-unclosed "the factory-brief block has no closing '\`\`\`' line"
		bad=1
	fi
	if [ "${#BRIEF_SCOPE[@]}" -eq 0 ] && [ "$bad" -eq 0 ]; then
		factory_finding "$brief" "$opened_at" brief-no-scope "the factory-brief block has no 'scope <glob>' line"
		bad=1
	fi
	return "$bad"
}

# factory_brief_has_asserts <file> <func>: true when the parsed brief already
# has an `asserts` line for that func.
factory_brief_has_asserts() {
	local a
	for a in "${BRIEF_ASSERTS[@]}"; do
		case "$a" in "$1 $2 "*) return 0 ;; esac
	done
	return 1
}

# factory_brief_has_invariant <path> <symbol> <property>: true when the parsed
# brief already has that `invariants` line: the same property of the same seam.
factory_brief_has_invariant() {
	local i
	for i in "${BRIEF_INVARIANTS[@]}"; do
		[ "$i" = "$1 $2 $3" ] && return 0
	done
	return 1
}

# factory_brief_has_test <name>: true when the parsed brief already names it.
factory_brief_has_test() {
	local t
	for t in "${BRIEF_TESTS[@]}"; do
		[ "$t" = "$1" ] && return 0
	done
	return 1
}

# factory_brief_lint <brief>: check the brief's prose against the template and
# against its block, which factory_brief_parse must have read first. Prints a
# finding per problem, against <brief>, and returns 1 if there were any. Lines
# inside fenced blocks are skipped: a fence opens with three or more backticks
# or tildes, indented at most three spaces, and closes with a run of the same
# character at least as long, as Markdown has it. A section runs to the next #
# or ## heading.
#   - one line `Kind: <kind>. Phase: <phase>.`, with Kind cleanup exactly when
#     Phase is partial (Partial mode), and Kind asset only in Phase green (the
#     Driver fetches the files: no tests, no Lock). Kind build in Phase green is
#     a test-only brief, held to its limits by factory_brief_test_only_lint
#   - `## Acceptance criteria → tests`: each bullet at the start of a line is a
#     criterion, `- <criterion> → `<test>`[, `<test>`...] [in `<file>`]`: the
#     tests are the backticked names after the last →, but for one after `in`.
#     Indented bullets and plain lines under it give detail. Every `test` line
#     is mapped by a criterion. In Phase red every criterion maps only to `test`
#     lines, and there is at least one; in any other phase a criterion may say
#     `→ judged by the Verifier` instead, or have no → at all
#   - `## Seams`: bullets `- `<path>` `<symbol>`[ `<symbol>`...]: <what the
#     stub does>`, which name exactly the block's `seam` lines, or None when
#     there is none; each seam's path is in scope, since its stub is written there
#   - `## Probed`: the engine and library facts the brief relies on, each with
#     the probe that showed it, or None
#   - `## Existing tests`: a bullet per existing test the change reaches,
#     `- `<test>` in `<file>`: <in scope, or unaffected: <reason>>`, whose file
#     a scope line covers unless the bullet says unaffected; or a line starting
#     None that says what was searched. A bullet opens with its tests and their
#     files, `<test>`[, `<test>`...] in `<file>`, groups joined by a comma or
#     "and"; whatever follows is detail, never a file. A bullet that opens with
#     neither is refused with the fix, one test per line, unless it says
#     unaffected
#   - `## Constraints`: each bullet at the start of a line is a Constraint, and
#     the lines under it, up to the next such bullet, are its detail. Each one
#     names a `test` line of the block in backticks, the test that pins it, or
#     says `untested: <reason>`, in any case; a Driver's check (`The Driver's
#     check after green: ...`) is the Driver's, and needs neither. Checked
#     when the block has a `test` line (not in Phase partial, Kind asset or an
#     amend's own check, which have none to name)
#   - each `asserts` line's file is in scope
# Seams and Probed are required in every phase but partial; Existing tests in
# every phase but partial and in every Kind but asset.
factory_brief_lint() {
	local brief="$1" n=0 line fence="" run section="" bad=0 kind="" phase="" heading after i path names
	local kind_line=0 accept_line=0 seams_line=0 probed_line=0 none_line=0 probed_n=0
	local existing_line=0 existing_n=0 pinned
	local -a mapped=() mapped_lines=() untested_lines=() judged_lines=() bullets=() bullet_lines=()
	local -a constraints=() constraint_lines=()
	local re_kind='^Kind: ([a-z]+)\. Phase: ([a-z]+)\.[[:space:]]*$'
	local re_tick='^[[:space:],]*`([^`]+)`(.*)$'
	local re_in='(^|[[:space:]])in[[:space:]]+`[^`]*`'
	local re_existing='^[[:space:],]*(and[[:space:]]+)?((`[^`]+`[[:space:],]*(and[[:space:]]+)?)+)in[[:space:]]+`([^`]+)`(.*)$'
	local re_judged='^[[:space:]]*judged by the Verifier'
	local re_seam='^[-*][[:space:]]+`([^`]+)`(.*)$'
	local re_none='^([-*][[:space:]]+)?None\.?[[:space:]]*$'
	local re_none_start='^([-*][[:space:]]+)?None([^[:alnum:]_]|$)'
	local re_bullet='^[-*][[:space:]]'
	local re_heading='^#{1,2}[[:space:]]+(.*[^[:space:]])[[:space:]]*$'
	local re_fence='^ {0,3}(`{3,}|~{3,})(.*)$'
	local re_untested='untested:[[:space:]]*[^[:space:]]'
	local re_drivers_check='^[-*][[:space:]]+The Driver.s check'
	local re_any_tick='`([^`]+)`(.*)$'

	BRIEF_EXISTING_FILES=() BRIEF_EXISTING_LINE=0
	# shellcheck disable=SC2094 # the loop reads the brief; factory_finding only names it
	while IFS= read -r line || [ -n "$line" ]; do
		n=$((n + 1))
		line="${line%$'\r'}"
		if [[ $line =~ $re_fence ]]; then
			run="${BASH_REMATCH[1]}" after="${BASH_REMATCH[2]}"
			if [ -z "$fence" ]; then
				# A backtick fence's info string holds no backtick.
				if [ "${run:0:1}" = '~' ] || [[ $after != *'`'* ]]; then
					fence="$run"
					continue
				fi
			elif [ "${run:0:1}" = "${fence:0:1}" ] && [ "${#run}" -ge "${#fence}" ] && [[ $after =~ ^[[:space:]]*$ ]]; then
				fence=""
				continue
			fi
		fi
		[ -z "$fence" ] || continue
		if [[ $line =~ $re_heading ]]; then
			heading="${BASH_REMATCH[1]}"
			case "$heading" in
				'Acceptance criteria'*) section=accept accept_line=$n ;;
				Seams) section=seams seams_line=$n ;;
				Probed) section=probed probed_line=$n ;;
				'Existing tests') section=existing existing_line=$n ;;
				Constraints) section=constraints ;;
				*) section="" ;;
			esac
			continue
		fi
		case "$line" in Kind:*)
			# shellcheck disable=SC2086 # the Kind and Phase lists split into their words
			if [ "$kind_line" -ne 0 ]; then
				factory_finding "$brief" "$n" brief-kind "a second Kind line; the brief has exactly one"
				bad=1
			elif [[ $line =~ $re_kind ]] && factory_word_in "${BASH_REMATCH[1]}" $FACTORY_BRIEF_KINDS &&
				factory_word_in "${BASH_REMATCH[2]}" $FACTORY_BRIEF_PHASES; then
				kind="${BASH_REMATCH[1]}" phase="${BASH_REMATCH[2]}" kind_line=$n
			else
				factory_finding "$brief" "$n" brief-kind "expected 'Kind: <$(factory_or_list $FACTORY_BRIEF_KINDS)>. Phase: <$(factory_or_list $FACTORY_BRIEF_PHASES)>.', got: $line"
				bad=1 kind_line=$n
			fi
			continue
			;;
		esac
		case "$section" in
			accept)
				[[ $line =~ $re_bullet ]] || continue
				if [[ $line != *→* ]]; then
					untested_lines+=("$n")
					continue
				fi
				# The names after the last →, dropping the file each `in` names.
				after="${line##*→}"
				while [[ $after =~ $re_in ]]; do
					after="${after/"${BASH_REMATCH[0]}"/ }"
				done
				names=0
				while [[ $after =~ $re_tick ]]; do
					mapped+=("${BASH_REMATCH[1]}") mapped_lines+=("$n")
					after="${BASH_REMATCH[2]}"
					names=$((names + 1))
				done
				if [ "$names" -eq 0 ]; then
					if [[ ${line##*→} =~ $re_judged ]]; then
						judged_lines+=("$n")
					else
						factory_finding "$brief" "$n" brief-criterion "after the → go the test names in backticks: - <criterion> → \`<test>\`"
						bad=1
					fi
				fi
				;;
			seams)
				if [[ $line =~ $re_none ]]; then
					none_line=$n
				elif [[ $line =~ $re_seam ]]; then
					path="${BASH_REMATCH[1]}" after="${BASH_REMATCH[2]}" names=0
					while [[ $after =~ $re_tick ]]; do
						bullets+=("$path ${BASH_REMATCH[1]}") bullet_lines+=("$n")
						after="${BASH_REMATCH[2]}"
						names=$((names + 1))
					done
					if [ "$names" -eq 0 ]; then
						factory_finding "$brief" "$n" brief-seam "expected '- \`<path>\` \`<symbol>\`: <what the stub does>', or None, got: $line"
						bad=1
					fi
				elif [[ $line =~ $re_bullet ]]; then
					factory_finding "$brief" "$n" brief-seam "expected '- \`<path>\` \`<symbol>\`: <what the stub does>', or None, got: $line"
					bad=1
				fi
				;;
			probed)
				[[ $line =~ [^[:space:]] ]] && probed_n=$((probed_n + 1))
				;;
			existing)
				# A None line, or a bullet at the start of a line; the rest is detail.
				if [[ $line =~ $re_none_start ]]; then
					existing_n=$((existing_n + 1))
					if [[ ${line,,} != *searched* ]]; then
						factory_finding "$brief" "$n" brief-existing-test "a None line says what was searched: 'None: searched <where> for <what the issue changes>', got: $line"
						bad=1
					fi
				elif [[ $line =~ $re_bullet ]]; then
					existing_n=$((existing_n + 1))
					after="${line#?}" names=0
					while [[ $after =~ $re_existing ]]; do
						path="${BASH_REMATCH[5]}" after="${BASH_REMATCH[6]}"
						names=$((names + 1))
						while [ "${path#./}" != "$path" ]; do path="${path#./}"; done
						BRIEF_EXISTING_FILES+=("$path")
						# An unaffected test needs no scope line.
						[[ ${line,,} == *unaffected* ]] && continue
						factory_in_scope_plain "$path" && continue
						factory_finding "$brief" "$n" brief-existing-test "test file $path is outside the scope: add a scope line for it, or say why its test is unaffected ('unaffected: <reason>')"
						bad=1
					done
					if [ "$names" -eq 0 ] && [[ ${line,,} != *unaffected* ]]; then
						factory_finding "$brief" "$n" brief-existing-test "list one test per line, by its name and its file: '- \`<test>\` in \`<file>\`: in scope, or unaffected: <reason>' (tests of one file may share a bullet: '- \`<test>\`, \`<test>\` in \`<file>\`: ...'); a bullet for a group of tests, or for a whole file, names no test, got: $line"
						bad=1
					fi
				fi
				;;
			constraints)
				# A bullet at the start of a line opens a Constraint; what follows is its detail.
				if [[ $line =~ $re_bullet ]]; then
					constraints+=("$line") constraint_lines+=("$n")
				elif [ "${#constraints[@]}" -gt 0 ]; then
					constraints[${#constraints[@]} - 1]+=$'\n'"$line"
				fi
				;;
		esac
	done < "$brief"

	if [ "$kind_line" -eq 0 ]; then
		factory_finding "$brief" 1 brief-kind "no 'Kind: <kind>. Phase: <phase>.' line"
		bad=1
	elif [ -n "$kind" ] && { [ "$kind" = cleanup ] || [ "$phase" = partial ]; } && ! { [ "$kind" = cleanup ] && [ "$phase" = partial ]; }; then
		factory_finding "$brief" "$kind_line" brief-kind "Kind cleanup goes with Phase partial (Partial mode), and only with it"
		bad=1
	elif [ "$kind" = asset ] && [ "$phase" != green ]; then
		factory_finding "$brief" "$kind_line" brief-kind "Kind asset goes with Phase green: the Driver fetches the files, with no tests and no Lock"
		bad=1
	fi

	if [ "$accept_line" -eq 0 ]; then
		factory_finding "$brief" 1 brief-section "no '## Acceptance criteria → tests' section"
		bad=1
	fi
	if [ "$phase" != partial ]; then
		if [ "$seams_line" -eq 0 ]; then
			factory_finding "$brief" 1 brief-section "no '## Seams' section: a bullet per seam line, or None"
			bad=1
		fi
		if [ "$probed_line" -eq 0 ]; then
			factory_finding "$brief" 1 brief-section "no '## Probed' section: each engine or library fact the brief relies on and the probe that showed it, or None"
			bad=1
		fi
		if [ "$kind" != asset ] && [ "$existing_line" -eq 0 ]; then
			factory_finding "$brief" 1 brief-section "no '## Existing tests' section: each existing test the change reaches, its file in scope or unaffected: <reason>, or None and what was searched"
			bad=1
		fi
	fi

	# Every test line is mapped; in Phase red every criterion maps to a test line.
	for i in "${!BRIEF_TESTS[@]}"; do
		factory_word_in "${BRIEF_TESTS[i]}" "${mapped[@]}" && continue
		factory_finding "$brief" "${BRIEF_TEST_LINES[i]}" brief-test "no criterion maps to test ${BRIEF_TESTS[i]}: add '- <criterion> → \`${BRIEF_TESTS[i]}\`'"
		bad=1
	done
	if [ "$phase" = red ]; then
		if [ "${#BRIEF_TESTS[@]}" -eq 0 ]; then
			factory_finding "$brief" "$((accept_line > 0 ? accept_line : 1))" brief-test "Phase red needs at least one 'test <name>' line"
			bad=1
		fi
		for i in "${!mapped[@]}"; do
			factory_brief_has_test "${mapped[i]}" && continue
			factory_finding "$brief" "${mapped_lines[i]}" brief-test "no 'test ${mapped[i]}' line in the block, so the red gate won't check it"
			bad=1
		done
		for i in "${untested_lines[@]}" "${judged_lines[@]}"; do
			factory_finding "$brief" "$i" brief-criterion "in Phase red every criterion maps to a test: - <criterion> → \`<test>\`; notes go in Constraints"
			bad=1
		done
	fi

	# Seams: the bullets and the block's seam lines name the same seams.
	if [ "$none_line" -ne 0 ] && [ "${#BRIEF_SEAMS[@]}" -gt 0 ]; then
		factory_finding "$brief" "$none_line" brief-seam "Seams says None, but the block has seam lines"
		bad=1
	fi
	if [ "$seams_line" -ne 0 ] && [ "$none_line" -eq 0 ] && [ "${#bullets[@]}" -eq 0 ]; then
		factory_finding "$brief" "$seams_line" brief-seam "Seams is empty: a bullet per seam line, or None"
		bad=1
	fi
	for i in "${!bullets[@]}"; do
		factory_word_in "${bullets[i]}" "${BRIEF_SEAMS[@]}" && continue
		factory_finding "$brief" "${bullet_lines[i]}" brief-seam "no 'seam ${bullets[i]}' line in the block, so the red phase can't stub it"
		bad=1
	done
	for i in "${!BRIEF_SEAMS[@]}"; do
		if ! factory_word_in "${BRIEF_SEAMS[i]}" "${bullets[@]}"; then
			factory_finding "$brief" "${BRIEF_SEAM_LINES[i]}" brief-seam "no Seams bullet describes seam ${BRIEF_SEAMS[i]}"
			bad=1
		fi
		if ! factory_in_scope "${BRIEF_SEAMS[i]%% *}"; then
			factory_finding "$brief" "${BRIEF_SEAM_LINES[i]}" brief-seam "seam path ${BRIEF_SEAMS[i]%% *} is outside the scope, and its stub is written there"
			bad=1
		fi
	done

	# A declared drop is in a test file the issue rewrites, so in scope.
	for i in "${!BRIEF_ASSERTS[@]}"; do
		factory_in_scope_plain "${BRIEF_ASSERTS[i]%% *}" && continue
		factory_finding "$brief" "${BRIEF_ASSERT_LINES[i]}" brief-asserts "asserts names ${BRIEF_ASSERTS[i]%% *}, which no scope line covers"
		bad=1
	done

	if [ "$probed_line" -ne 0 ] && [ "$probed_n" -eq 0 ]; then
		factory_finding "$brief" "$probed_line" brief-section "Probed is empty: each fact and its probe, or None"
		bad=1
	fi
	if [ "$existing_line" -ne 0 ] && [ "$existing_n" -eq 0 ]; then
		factory_finding "$brief" "$existing_line" brief-section "Existing tests is empty: each existing test the change reaches, or None and what was searched"
		bad=1
	fi

	# Each Constraint names the test that pins it, or why none can; a brief with
	# no test lines (Phase partial, Kind asset, an amend's own check) has none to name.
	if [ "${#BRIEF_TESTS[@]}" -gt 0 ]; then
		for i in "${!constraints[@]}"; do
			line="${constraints[i]}"
			[[ ${line,,} =~ $re_untested ]] && continue
			[[ $line =~ $re_drivers_check ]] && continue
			pinned=0 after="$line"
			while [[ $after =~ $re_any_tick ]]; do
				if factory_brief_has_test "${BASH_REMATCH[1]}"; then
					pinned=1
					break
				fi
				after="${BASH_REMATCH[2]}"
			done
			[ "$pinned" -eq 0 ] || continue
			factory_finding "$brief" "${constraint_lines[i]}" brief-constraint "a Constraint names the test that pins it, in backticks as its 'test' line names it, or says why no test can: 'untested: <reason>'; got: ${line%%$'\n'*}"
			bad=1
		done
	fi
	BRIEF_EXISTING_LINE="$existing_line"
	BRIEF_KIND="$kind" BRIEF_PHASE="$phase"
	return "$bad"
}

# factory_brief_lane_lint <brief>: hold a `lane small` brief to the small lane's
# limits; a brief in no lane passes. Needs factory_brief_parse and
# factory_brief_lint run first, and diff.sh (the test paths) and protect.sh (the
# gate's paths) sourced. Prints a brief-lane finding per problem, against
# <brief>, and returns 1 if there were any.
#   - Kind build or bug, in Phase red: the stop hook records the Lock
#   - at most FACTORY_SMALL_TESTS `test` lines, and no `seam` line
#   - each scope line names one file by its plain path: no `*`, `?` or trailing
#     /, and no . or .. part
#   - no scope line is in the gate (factory_gate_class)
#   - at most FACTORY_SMALL_FILES product files: the scope lines left once the
#     test files and the Driver's docs are set aside
factory_brief_lane_lint() {
	local brief="$1" bad=0 i s product=0 tests_ok=1
	[ "$BRIEF_LANE" = small ] || return 0
	if ! { [ "$BRIEF_KIND" = build ] || [ "$BRIEF_KIND" = bug ]; } || [ "$BRIEF_PHASE" != red ]; then
		factory_finding "$brief" "$BRIEF_LANE_LINE" brief-lane "lane small goes with Kind build or bug in Phase red"
		bad=1
	fi
	if [ "${#BRIEF_TESTS[@]}" -gt "$FACTORY_SMALL_TESTS" ]; then
		factory_finding "$brief" "${BRIEF_TEST_LINES[FACTORY_SMALL_TESTS]}" brief-lane "lane small takes at most $FACTORY_SMALL_TESTS test lines; this brief has ${#BRIEF_TESTS[@]}"
		bad=1
	fi
	for i in "${!BRIEF_SEAMS[@]}"; do
		factory_finding "$brief" "${BRIEF_SEAM_LINES[i]}" brief-lane "lane small adds no seam; drop the seam, or the lane"
		bad=1
	done
	# The test files are told by the test-paths globs; without them the lane can't
	# be checked, and that file's own finding says why.
	factory_test_paths_load || { tests_ok=0 bad=1; }
	for i in "${!BRIEF_SCOPE[@]}"; do
		s="${BRIEF_SCOPE[i]}"
		while [ "${s#./}" != "$s" ]; do s="${s#./}"; done
		# A . or .. part, or an empty one, could name a gate file the check misses.
		case "/${s%/}/" in */./* | */../* | *//*)
			factory_finding "$brief" "${BRIEF_SCOPE_LINES[i]}" brief-lane "in lane small each scope line names one file by its plain path, with no . or .. part: $s"
			bad=1
			continue
			;;
		esac
		case "$s" in *'*'* | *'?'* | */)
			factory_finding "$brief" "${BRIEF_SCOPE_LINES[i]}" brief-lane "in lane small each scope line names one file, not a glob: $s"
			bad=1
			continue
			;;
		esac
		if factory_gate_class "${s,,}"; then
			factory_finding "$brief" "${BRIEF_SCOPE_LINES[i]}" brief-lane "lane small touches no gate file, and $s is the gate's ($PROTECT_CLASS)"
			bad=1
			continue
		fi
		factory_is_driver_doc "$s" && continue
		[ "$tests_ok" -eq 1 ] && factory_is_test_file "$s" && continue
		product=$((product + 1))
		if [ "$product" -gt "$FACTORY_SMALL_FILES" ]; then
			factory_finding "$brief" "${BRIEF_SCOPE_LINES[i]}" brief-lane "lane small touches at most $FACTORY_SMALL_FILES product files; $s is one more"
			bad=1
		fi
	done
	return "$bad"
}

# factory_brief_is_test_only: true when the brief factory_brief_lint read is a
# test-only brief: Kind build in Phase green, tests for behaviour already built,
# with no red phase and no Lock.
factory_brief_is_test_only() {
	[ "$BRIEF_KIND" = build ] && [ "$BRIEF_PHASE" = green ]
}

# factory_brief_test_only_lint <brief>: hold a test-only brief to its limits; any
# other brief passes. Needs factory_brief_parse and factory_brief_lint run first,
# and diff.sh sourced (the test paths). Prints a brief-test-only finding per
# problem, against <brief>, and returns 1 if there were any.
#   - at least one `test` line, and no `seam` line
#   - each scope line names only test files (factory_scope_is_tests) or one of
#     the Driver's docs
# With no red phase, no failing test shows the change is needed, so nothing
# but tests may change: the deviation step fails any other file the branch
# changes, with a trailer or without (deviation.sh).
factory_brief_test_only_lint() {
	local brief="$1" bad=0 i
	factory_brief_is_test_only || return 0
	if [ "${#BRIEF_TESTS[@]}" -eq 0 ]; then
		factory_finding "$brief" 1 brief-test-only "a test-only brief (Kind build, Phase green) names at least one 'test <name>' line"
		bad=1
	fi
	for i in "${!BRIEF_SEAMS[@]}"; do
		factory_finding "$brief" "${BRIEF_SEAM_LINES[i]}" brief-test-only "a test-only brief (Kind build, Phase green) adds no seam: it changes no product file"
		bad=1
	done
	# Without the test-paths globs no scope line can be told a test; that
	# file's own finding says why.
	factory_test_paths_load || return 1
	for i in "${!BRIEF_SCOPE[@]}"; do
		factory_is_driver_doc "${BRIEF_SCOPE[i]}" && continue
		factory_scope_is_tests "${BRIEF_SCOPE[i]}" && continue
		factory_finding "$brief" "${BRIEF_SCOPE_LINES[i]}" brief-test-only "a test-only brief (Kind build, Phase green) scopes only test files ($FACTORY_TEST_PATHS) and the Driver's docs ($FACTORY_DRIVER_DOCS), not ${BRIEF_SCOPE[i]}; a product change needs a red phase"
		bad=1
	done
	return "$bad"
}

# factory_brief_readers_lint <brief>: refuse a brief that leaves a source reader
# out of Existing tests: a test that reads source files as text
# (factory_source_readers, lib/readers.sh) whose reach covers a scope line, so
# the change can break it though it imports nothing the change touches. Needs
# factory_brief_parse and factory_brief_lint run first, and diff.sh and
# readers.sh sourced; run from the project root. Prints a brief-reader finding
# per reader, against <brief>, and returns 1 if there were any.
#   - a reader counts when no Existing tests bullet names its file, in scope or
#     unaffected, and it is in the tree at the diff base (factory_diff_base):
#     a test the issue writes is the brief's own
#   - the scope lines that count are the product's: not the Driver's docs, and
#     not a glob that names only test files (factory_scope_is_tests)
#   - a reach covers a scope line when they may overlap (factory_scope_overlap)
# Phase partial and Kind asset list no Existing tests, and outside a git work
# tree or without the test-paths globs there is nothing to scan: they pass.
factory_brief_readers_lint() {
	local brief="$1" bad=0 base readers file reach i s last=""
	[ "$BRIEF_PHASE" != partial ] && [ "$BRIEF_KIND" != asset ] || return 0
	factory_test_paths_load > /dev/null || return 0
	readers="$(factory_source_readers 2> /dev/null)" || return 0
	base="$(factory_diff_base)" || base=""
	while read -r file reach; do
		[ -n "$file" ] && [ "$file" != "$last" ] || continue
		factory_word_in "$file" "${BRIEF_EXISTING_FILES[@]}" && continue
		[ -z "$base" ] || git cat-file -e "$base:$file" 2> /dev/null || continue
		for i in "${!BRIEF_SCOPE[@]}"; do
			s="${BRIEF_SCOPE[i]}"
			factory_is_driver_doc "$s" && continue
			factory_scope_is_tests "$s" && continue
			factory_scope_overlap "$reach" "$s" || continue
			factory_finding "$brief" "$((BRIEF_EXISTING_LINE > 0 ? BRIEF_EXISTING_LINE : 1))" brief-reader "$file reads $reach as text, and scope $s may change it: list its tests under Existing tests, one per line, '- \`<test>\` in \`$file\`: in scope, or unaffected: <reason>' (bash factory/core/brief.sh readers lists the source readers)"
			bad=1 last="$file"
			break
		done
	done <<< "$readers"
	return "$bad"
}

# factory_brief_invariants_lint <brief>: an `invariants` line's property tests
# need a test file of their own in scope, which no red commit locks: the module
# (its path less its extension) with `.invariants` and a test file's ending,
# from a `**/*<ending>` test-paths glob (`invariants src/server/events.ts ...`
# with `**/*.test.ts` wants `scope src/server/events.invariants.test.ts`). With
# no such glob (a stack that keeps its tests in a folder of their own, as
# `tests/**`), a scope line whose last part holds `invariants`, or one that may
# overlap `<module>.invariants.*`, passes.
# Needs factory_brief_parse run first and diff.sh sourced. Prints a
# brief-invariants finding per module, against <brief>, and returns 1 if there
# were any.
factory_brief_invariants_lint() {
	local brief="$1" bad=0 i g s path name module want ok
	local -a endings=() seen=()
	[ "${#BRIEF_INVARIANTS[@]}" -gt 0 ] || return 0
	if factory_test_paths_load > /dev/null; then
		for g in "${TEST_PATHS[@]}"; do
			case "$g" in '**/*'?*) ;; *) continue ;; esac
			g="${g#'**/*'}"
			case "$g" in *'*'* | *'?'* | */*) continue ;; esac
			endings+=("$g")
		done
	fi
	for i in "${!BRIEF_INVARIANTS[@]}"; do
		path="${BRIEF_INVARIANTS[i]%% *}" module="${BRIEF_INVARIANTS[i]%% *}"
		name="${path##*/}"
		case "$name" in ?*.*) module="${path%.*}" ;; esac
		factory_word_in "$module" "${seen[@]}" && continue
		seen+=("$module")
		ok=0
		if [ "${#endings[@]}" -gt 0 ]; then
			for g in "${endings[@]}"; do
				factory_in_scope_plain "$module.invariants$g" && ok=1 && break
			done
			want="$module.invariants${endings[0]}"
		else
			for s in "${BRIEF_SCOPE[@]}"; do
				[[ ${s##*/} == *invariants* ]] && ok=1 && break
				factory_scope_overlap "$s" "$module.invariants.*" && ok=1 && break
			done
			want=""
		fi
		[ "$ok" -eq 0 ] || continue
		if [ -n "$want" ]; then
			factory_finding "$brief" "${BRIEF_INVARIANT_LINES[i]}" brief-invariants "the property tests of $path go in a test file of their own, which the red commit doesn't lock: add 'scope $want'"
		else
			factory_finding "$brief" "${BRIEF_INVARIANT_LINES[i]}" brief-invariants "the property tests of $path go in a test file of their own, which the red commit doesn't lock: add a scope line for it, where the project keeps its tests, with 'invariants' in its name"
		fi
		bad=1
	done
	return "$bad"
}

# factory_scope_is_tests <glob>: true when every path the scope glob can name is
# a test file (TEST_PATHS loaded). A plain path, with no `*`, `?` or trailing
# /, is one when a test-paths glob matches it. Any other glob is one when its
# fixed part, up to its first `*` or `?`, starts inside a test-paths glob that
# is a whole folder: `<folder>/**` or `<folder>/`. A . or .. part, or an empty
# one, never is: it could name a path outside the folder.
factory_scope_is_tests() {
	local s="$1" g dir
	while [ "${s#./}" != "$s" ]; do s="${s#./}"; done
	case "/${s%/}/" in */./* | */../* | *//*) return 1 ;; esac
	case "$s" in
		*'*'* | *'?'* | */) ;;
		*)
			factory_is_test_file "$s"
			return
			;;
	esac
	for g in "${TEST_PATHS[@]}"; do
		case "$g" in
			*/'**') dir="${g%'**'}" ;;
			*/) dir="$g" ;;
			*) continue ;;
		esac
		case "$dir" in *'*'* | *'?'*) continue ;; esac
		[[ ${s%%[*?]*} == "$dir"* ]] && return 0
	done
	return 1
}

# factory_brief_sealed_kind <brief>: print the Kind of the brief when the
# checked-out branch's run state holds a seal (brief-sha) it matches; false when
# there is no seal, the brief changed since, or it names no Kind. Needs run.sh.
factory_brief_sealed_kind() {
	local branch sealed
	[ -f "$1" ] && branch="$(factory_current_branch)" && sealed="$(factory_state_get "$branch" brief-sha)" || return 1
	[ "$(factory_brief_hash "$1")" = "$sealed" ] || return 1
	BRIEF_KIND=""
	factory_brief_parse "$1" > /dev/null 2>&1
	factory_brief_lint "$1" > /dev/null 2>&1
	[ -n "$BRIEF_KIND" ] && printf '%s\n' "$BRIEF_KIND"
}

# factory_word_in <word> <item...>: true when <word> equals one of the items.
factory_word_in() {
	local w="$1" item
	shift
	for item in "$@"; do
		[ "$item" = "$w" ] && return 0
	done
	return 1
}

# factory_or_list <item...>: the items joined by " | ".
factory_or_list() {
	local IFS='|'
	printf '%s\n' "$*" | sed 's/|/ | /g'
}

# factory_brief_hash <brief>: the brief's git blob hash, as written (no filters).
factory_brief_hash() {
	git hash-object --no-filters -- "$1"
}

# factory_brief_seal_check <brief>: print a finding and return 1 when the checked-
# out branch's run state holds a seal (brief-sha, set by brief.sh seal) that the
# brief no longer matches. A branch with no seal passes: state.sh refuses a phase
# until the brief is sealed, so only a run state written by hand lacks one. Needs
# run.sh.
factory_brief_seal_check() {
	local brief="$1" branch sealed now
	branch="$(factory_current_branch)" || return 0
	sealed="$(factory_state_get "$branch" brief-sha)" || return 0
	if [ ! -f "$brief" ]; then
		factory_finding "$brief" 1 brief-changed "the Build Brief is gone since the Driver sealed it; it is the Driver's (Editor: report this and stop)"
		return 1
	fi
	now="$(factory_brief_hash "$brief")" || return 1
	[ "$now" = "$sealed" ] && return 0
	factory_finding "$brief" 1 brief-changed "the Build Brief changed after the Driver sealed it; only the Driver edits it, then seals it again with brief.sh seal (Editor: report this and stop)"
	return 1
}

# factory_glob_regex <glob>: the glob as an anchored extended regex.
factory_glob_regex() {
	local g="$1" re="" i c
	case "$g" in */) g="$g**" ;; esac
	for ((i = 0; i < ${#g}; i++)); do
		c="${g:i:1}"
		# shellcheck disable=SC1003 # the last pattern is a lone backslash
		case "$c" in
			'*')
				if [ "${g:i+1:1}" = '*' ]; then
					if [ "${g:i+2:1}" = / ]; then
						re+='(.*/)?'
						i=$((i + 2))
					else
						re+='.*'
						i=$((i + 1))
					fi
				else
					re+='[^/]*'
				fi
				;;
			'?') re+='[^/]' ;;
			'.' | '+' | '^' | '$' | '(' | ')' | '{' | '}' | '|' | '[' | ']' | '\') re+="\\$c" ;;
			*) re+="$c" ;;
		esac
	done
	printf '^%s$\n' "$re"
}

# factory_glob_match <glob> <path>: true when the path matches the glob.
factory_glob_match() {
	local re
	re="$(factory_glob_regex "$1")"
	[[ $2 =~ $re ]]
}

# factory_scope_overlap <glob> <glob>: true when two scope globs may name a common
# path. Two plain paths overlap when they are the same file, or one is a folder
# (a trailing /) that holds the other; otherwise the globs overlap when one's
# fixed part, up to its first * or ?, starts the other's. That errs toward an
# overlap, never away from one. A leading ./ and letter case don't count.
factory_scope_overlap() {
	local a="${1,,}" b="${2,,}"
	while [ "${a#./}" != "$a" ]; do a="${a#./}"; done
	while [ "${b#./}" != "$b" ]; do b="${b#./}"; done
	case "$a$b" in
		*'*'* | *'?'*) ;;
		*)
			case "$a" in */) ;; *) case "$b" in */) ;; *)
				[ "$a" = "$b" ]
				return
				;;
			esac ;; esac
			;;
	esac
	a="${a%%[*?]*}" b="${b%%[*?]*}"
	[[ $a == "$b"* || $b == "$a"* ]]
}

# factory_in_scope <path>: true when the path matches one of the parsed scope globs.
factory_in_scope() {
	local g
	for g in "${BRIEF_SCOPE[@]}"; do
		factory_glob_match "$g" "$1" && return 0
	done
	return 1
}

# factory_in_scope_plain <path>: factory_in_scope for a path the brief's prose
# names, with a leading ./ dropped from the path and from each scope glob.
factory_in_scope_plain() {
	local g p="$1"
	while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
	for g in "${BRIEF_SCOPE[@]}"; do
		while [ "${g#./}" != "$g" ]; do g="${g#./}"; done
		factory_glob_match "$g" "$p" && return 0
	done
	return 1
}
