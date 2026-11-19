# The shell lint (shell-lint.sh): one run of it over every shell script the
# factory ships or the gate runs, then the lint itself on fixture projects.
#
# The scripts come from the lint's own list (--list) of the project this factory
# sits in, so a new script is linted with no list to update. They are linted in
# four parts (every fourth script, so the runner spreads them over its slots),
# each one run of the lint, which runs each tool once per dialect; a part fails
# naming each script with findings, then the findings. While a tool is missing or
# off its pin the parts skip, and test_the_tools_are_at_their_pins fails, naming
# the install command.

# shell_lint_batch: set SHELL_LINT_BATCH to the scripts the lint lists, relative
# to the project root.
shell_lint_batch() {
	local listing
	listing="$(bash "$FACTORY_CORE/shell-lint.sh" --list)" || fail "the lint could not list its scripts"
	SHELL_LINT_BATCH=()
	[ -z "$listing" ] || mapfile -t SHELL_LINT_BATCH <<< "$listing"
}

# shell_lint_failing <output>: print each script of SHELL_LINT_BATCH the lint's
# output names (a <file>:<line>: finding, a +++ <file> diff header or a <file>:
# exit), once, in the batch's order.
shell_lint_failing() {
	local f line
	local -A named=()
	while IFS= read -r line; do
		[[ $line =~ ^(.+):[0-9]+:[0-9]+:\  ]] && named["${BASH_REMATCH[1]}"]=1
		[[ $line == '+++ '* ]] && named["${line#+++ }"]=1
		[[ $line =~ ^(.+):\ (shellcheck|shfmt)\ exited\ [0-9]+$ ]] && named["${BASH_REMATCH[1]}"]=1
	done <<< "$1"
	for f in "${SHELL_LINT_BATCH[@]}"; do
		[ -z "${named["$f"]+set}" ] || printf '%s\n' "$f"
	done
}

# shell_lint_part <k> <parts>: lint, in one run, the scripts of the batch whose
# index is k modulo parts.
# shellcheck disable=SC2154 # out and status: set by run_cmd, in factory/core/tests/lib.sh
shell_lint_part() {
	local i
	local -a part=()
	shell_lint_batch
	[ "${#SHELL_LINT_BATCH[@]}" -gt 0 ] || fail "the lint lists no script"
	for ((i = $1; i < ${#SHELL_LINT_BATCH[@]}; i += $2)); do
		part+=("${SHELL_LINT_BATCH[i]}")
	done
	[ "${#part[@]}" -gt 0 ] || return 0
	run_cmd bash "$FACTORY_CORE/shell-lint.sh" "${part[@]}"
	case "$status" in
		0) ;;
		3) skip "the scripts are not linted: $(cat "$TEST_TMP/stderr")" ;;
		*) fail "these scripts fail the shell lint:"$'\n'"$(shell_lint_failing "$out")"$'\n'"$out"$'\n'"$(cat "$TEST_TMP/stderr")" ;;
	esac
}

test_every_script_of_this_factory_passes_the_lint_part_1() {
	shell_lint_part 0 4
}

test_every_script_of_this_factory_passes_the_lint_part_2() {
	shell_lint_part 1 4
}

test_every_script_of_this_factory_passes_the_lint_part_3() {
	shell_lint_part 2 4
}

test_every_script_of_this_factory_passes_the_lint_part_4() {
	shell_lint_part 3 4
}

test_the_tools_are_at_their_pins() {
	run_cmd bash "$FACTORY_CORE/shell-lint.sh" --tools
	[ "$status" -eq 0 ] || fail "$(cat "$TEST_TMP/stderr")"
}

# The batch is every script the lint lists, so the suite cannot pass by linting
# nothing.
test_every_script_of_this_factory_is_in_the_batch() {
	local f
	shell_lint_batch
	[ "${#SHELL_LINT_BATCH[@]}" -gt 0 ] || fail "the lint lists no script"
	for f in "${SHELL_LINT_BATCH[@]}"; do
		[ -f "$FACTORY_CORE/../../$f" ] || [ -f "$FACTORY_CORE/../$f" ] || fail "the batch holds $f, which is no file"
	done
	# In a project, paths start factory/; in a clone of the factory's repo, core/.
	printf '%s\n' "${SHELL_LINT_BATCH[@]}" | grep -qxE '(factory/)?core/shell-lint\.sh' || fail "the lint itself is not in the batch"
	printf '%s\n' "${SHELL_LINT_BATCH[@]}" | grep -qxE '(factory/)?core/tests/shell_lint_test\.sh' || fail "this suite is not in the batch"
}

# lint_project: $TEST_TMP/p, a git repo (nothing committed) that vendors the lint
# as a project does: factory/core/shell-lint.sh, the libs it sources and
# factory/.shellcheckrc, with an empty tools/verify/; cd there.
lint_project() {
	isolate_git
	mkdir -p "$TEST_TMP/p/factory/core/lib" "$TEST_TMP/p/tools/verify" || fail "could not make the project"
	cp "$FACTORY_CORE/shell-lint.sh" "$TEST_TMP/p/factory/core/" &&
		cp "$FACTORY_CORE/lib/steps.sh" "$FACTORY_CORE/lib/vendor.sh" "$TEST_TMP/p/factory/core/lib/" &&
		cp "$FACTORY_CORE/../.shellcheckrc" "$TEST_TMP/p/factory/" || fail "could not copy the lint"
	cd "$TEST_TMP/p" || fail "could not enter the project"
	git init -q -b dev . || fail "git init failed"
}

# run_lint [args...]: the project's lint.
run_lint() {
	run_cmd bash factory/core/shell-lint.sh "$@"
}

# stub_tool <name> <version text>: $TEST_TMP/bin/<name>, which prints the text for
# --version.
stub_tool() {
	mkdir -p "$TEST_TMP/bin"
	printf '#!%s\nprintf "%%s\\n" %q\n' "$BASH" "$2" > "$TEST_TMP/bin/$1"
	chmod +x "$TEST_TMP/bin/$1"
}

test_the_lint_finds_scripts_by_name_and_shebang() {
	lint_project
	mkdir -p factory/tools factory/core/hooks/githooks scripts
	printf 'echo a\n' > factory/core/a.sh
	printf '#!/usr/bin/env bash\necho b\n' > factory/tools/b
	printf '#!/bin/sh\necho c\n' > factory/core/hooks/githooks/c
	printf '#!/usr/bin/env -S bash -e\necho d\n' > factory/tools/d
	printf '#! /bin/dash\necho e\n' > factory/tools/e
	printf '#!/usr/bin/awk -f\n{ print }\n' > factory/core/f.awk
	printf '#!/usr/bin/env python3\nprint(1)\n' > factory/tools/g
	printf '#!/bin/zsh\necho h\n' > factory/tools/h
	printf '#!/usr/bin/env bashful\n' > factory/tools/i
	printf '#!/usr/bin/env --split-string=bash -e\necho $1\n' > factory/tools/j
	printf '#!/usr/bin/env -u HOME -S LC_ALL=C bash\necho k\n' > factory/tools/k
	printf '#!/usr/bin/env -S -u HOME bash\nprintf "ok\\n"\n' > factory/tools/p
	printf '#!/usr/bin/env -S -u "UNUSED bash NAME" python3\nprint("ok")\n' > factory/tools/q
	printf '#!/tmp/bash\vpython3\nprint("ok")\n' > factory/tools/r
	printf '#!/usr/bin/env -Sdash\necho l\n' > factory/tools/l
	printf '#!/usr/bin/env -i python3\nprint(1)\n' > factory/tools/m
	printf '#!/bin/sh\r\necho n\r\n' > factory/tools/n
	printf '#!/usr/bin/env -C /bin sh-not\n' > factory/tools/o
	printf 'notes\n' > factory/notes.md
	printf '#!/usr/bin/env bash\necho step\n' > tools/verify/step
	printf 'tool 1.0\n' > tools/verify/pins
	printf 'echo other\n' > tools/other.sh
	printf 'echo x\n' > scripts/x.sh
	printf 'echo ignored\n' > factory/ignored.sh
	printf 'echo gone\n' > factory/core/gone.sh
	printf '/factory/ignored.sh\n' > .gitignore
	git add -A && git commit -q -m fixture || fail "could not commit the fixture"
	rm factory/core/gone.sh
	printf 'echo new\n' > factory/core/new.sh
	ln -s a.sh factory/core/link.sh
	run_lint --list
	assert_status 0
	assert_eq "factory/core/a.sh
factory/core/hooks/githooks/c
factory/core/lib/steps.sh
factory/core/lib/vendor.sh
factory/core/new.sh
factory/core/shell-lint.sh
factory/tools/b
factory/tools/d
factory/tools/e
factory/tools/j
factory/tools/l
factory/tools/n
factory/tools/p
tools/verify/step" "$out"
}

test_a_shellcheck_finding_fails_the_lint_naming_the_file() {
	lint_project
	printf '#!/usr/bin/env bash\necho $1\n' > factory/core/bad.sh
	printf '#!/usr/bin/env bash\necho "$1"\n' > factory/core/good.sh
	run_lint
	assert_status 1
	assert_eq "factory/core/bad.sh:2:6: note: Double quote to prevent globbing and word splitting. [SC2086]" "$out"
	stderr_has "shell-lint: 1 of 5 scripts have findings"
	run_lint factory/core/good.sh
	assert_status 0
}

test_a_misformatted_script_fails_the_lint_naming_the_file() {
	lint_project
	printf '#!/usr/bin/env bash\nif true;then\necho x\nfi\n' > tools/verify/step
	run_lint tools/verify/step
	assert_status 1
	assert_line "+++ tools/verify/step"
	assert_line "-if true;then"
	assert_line "+if true; then"
}

# The flags: case items indented (-ci), a space after a redirect (-sr).
test_a_script_formatted_with_the_flags_passes() {
	lint_project
	printf '#!/usr/bin/env bash\ncase "$1" in\n\ta) echo a > /dev/null ;;\nesac\n' > tools/verify/step
	run_lint tools/verify/step
	assert_status 0
	printf '#!/usr/bin/env bash\ncase "$1" in\na) echo a >/dev/null ;;\nesac\n' > tools/verify/step
	run_lint tools/verify/step
	assert_status 1
}

test_a_script_without_a_shebang_is_linted_as_bash() {
	lint_project
	printf 'a=(1 2)\n[[ -n "${a[0]}" ]] && echo "${a[1]}"\n' > factory/core/lib/arrays.sh
	run_lint factory/core/lib/arrays.sh
	assert_status 0
}

test_a_sh_script_is_linted_as_sh() {
	lint_project
	mkdir -p factory/core/hooks/githooks
	printf '#!/bin/sh\n[[ -n "$1" ]] && echo yes\n' > factory/core/hooks/githooks/hook
	run_lint factory/core/hooks/githooks/hook
	assert_status 1
	printf '%s\n' "$out" | grep -q '^factory/core/hooks/githooks/hook:2:1: .*\[SC3010\]$' || fail "no SC3010 finding:"$'\n'"$out"
}

# An env -S shebang, which shellcheck cannot read by itself, is linted in the
# shell it runs; one that runs another program is left alone.
test_an_env_split_string_script_is_linted_in_its_shell() {
	lint_project
	mkdir -p factory/tools
	printf '#!/usr/bin/env -S -u HOME bash\nprintf "ok\\n"\n' > factory/tools/env-bash
	printf '#!/usr/bin/env -S -u "UNUSED bash NAME" python3\nprint("ok")\n' > factory/tools/env-python
	run_lint
	assert_status 0
	printf '#!/usr/bin/env -S LC_ALL=C sh\n[[ -n "$1" ]] && echo yes\n' > tools/verify/step
	run_lint tools/verify/step
	assert_status 1
	printf '%s\n' "$out" | grep -q '^tools/verify/step:2:1: .*\[SC3010\]$' || fail "no SC3010 finding:"$'\n'"$out"
}

# The config's codes hold under tools/verify/ too, where shellcheck would not
# find factory/.shellcheckrc by itself.
test_the_config_disables_its_codes_under_tools_verify() {
	lint_project
	printf '#!/usr/bin/env bash\necho '"'"'$HOME stays literal'"'"'\n' > tools/verify/step
	run_lint tools/verify/step
	assert_status 0
	sed -i '/^disable=SC2016 /d' factory/.shellcheckrc
	run_lint tools/verify/step
	assert_status 1
	assert_line "tools/verify/step:2:6: note: Expressions don't expand in single quotes, use double quotes for that. [SC2016]"
}

test_a_config_line_without_its_reason_is_refused() {
	lint_project
	printf 'echo a\n' > factory/core/a.sh
	printf 'disable=SC2016\n' >> factory/.shellcheckrc
	run_lint factory/core/a.sh
	assert_status 2
	stderr_has "factory/.shellcheckrc:$(wc -l < factory/.shellcheckrc): expected 'disable=<code,...> # <reason>', got: disable=SC2016"
}

test_a_missing_tool_fails_the_lint_with_the_install_command() {
	lint_project
	stub_tool shfmt 3.8.0
	PATH="$TEST_TMP/bin" run_cmd "$BASH" factory/core/shell-lint.sh
	assert_status 3
	assert_eq "" "$out"
	stderr_has "shell-lint: shellcheck: expected 0.9.0, found none"
	stderr_has "shell-lint: install them with: sudo apt install -y shellcheck shfmt (Ubuntu 24.04 has shellcheck 0.9.0 and shfmt 3.8.0)"
}

test_a_tool_at_another_version_fails_the_lint() {
	lint_project
	printf '#!/usr/bin/env bash\necho $1\n' > factory/core/bad.sh
	stub_tool shellcheck $'ShellCheck - shell script analysis tool\nversion: 0.10.0\nlicense: GNU General Public License, version 3'
	stub_tool shfmt v3.8.1
	PATH="$TEST_TMP/bin:$PATH" run_lint
	assert_status 3
	assert_eq "" "$out" "the lint ran a tool off its pin"
	stderr_has "shell-lint: shellcheck: expected 0.9.0, found 0.10.0"
	stderr_has "shell-lint: shfmt: expected 3.8.0, found 3.8.1"
	stderr_has "install them with: sudo apt install -y shellcheck shfmt"
}

# An upstream shfmt build prints its version with a v.
test_an_upstream_shfmt_build_meets_its_pin() {
	lint_project
	stub_tool shfmt v3.8.0
	PATH="$TEST_TMP/bin:$PATH" run_lint --tools
	assert_status 0
}

# run_suite_test <function> [args...]: run one of this suite's own tests, or
# shell_lint_part, on the fixture project (cd'd into it); stdout gets
# "exit <its status>", then its stderr.
run_suite_test() {
	mkdir -p "$TEST_TMP/inner"
	run_cmd env TEST_TMP="$TEST_TMP/inner" bash -c '
		. "$1/tests/lib.sh"
		FACTORY_CORE="$2"
		. "$1/tests/shell_lint_test.sh"
		shift 2
		("$@") 2> "$TEST_TMP/test-err"
		echo "exit $?"
		cat "$TEST_TMP/test-err"
	' _ "$FACTORY_CORE" "$PWD/factory/core" "$@"
}

# The suite's batched test, on a fixture project: it passes on clean scripts, and
# fails naming each script with findings, in the lint's order, then the findings.
test_the_suite_lints_every_script_and_names_each_failing_one() {
	lint_project
	run_suite_test shell_lint_part 0 1
	assert_eq "exit 0" "$out"
	mkdir -p factory/core/hooks factory/tools
	printf '#!/usr/bin/env bash\necho $1\n' > factory/core/bad.sh
	printf '#!/bin/sh\n[[ -n "$1" ]] && echo yes\n' > factory/core/hooks/hook
	printf '#!/usr/bin/env bash\nif true;then\necho x\nfi\n' > factory/tools/fmt
	printf '#!/usr/bin/env bash\necho "$1"\n' > factory/tools/good
	run_suite_test shell_lint_part 0 1
	assert_eq "exit 1
    these scripts fail the shell lint:
factory/core/bad.sh
factory/core/hooks/hook
factory/tools/fmt" "$(printf '%s\n' "$out" | sed -n 1,5p)"
	assert_line "factory/core/bad.sh:2:6: note: Double quote to prevent globbing and word splitting. [SC2086]"
	printf '%s\n' "$out" | grep -q '^factory/core/hooks/hook:2:1: .*\[SC3010\]$' || fail "no SC3010 finding:"$'\n'"$out"
	assert_line "+++ factory/tools/fmt"
	assert_line "shell-lint: 3 of 7 scripts have findings"
	# The four parts the suite runs name each of them once between them.
	local k all=""
	for k in 0 1 2 3; do
		run_suite_test shell_lint_part "$k" 4
		all+="$out"$'\n'
	done
	assert_eq "factory/core/bad.sh
factory/core/hooks/hook
factory/tools/fmt" "$(printf '%s' "$all" | grep -xE 'factory/(core/bad\.sh|core/hooks/hook|tools/fmt)' | LC_ALL=C sort)" "the scripts the parts name"
}

# Scripts whose paths a per-script test name once folded together are each linted
# and named.
test_scripts_with_like_paths_are_each_named() {
	lint_project
	mkdir -p factory/a
	printf 'echo $1\n' > factory/a/b.sh
	printf 'echo $2\n' > factory/a.b.sh
	printf 'echo $3\n' > factory/a+c.sh
	run_suite_test shell_lint_part 0 1
	assert_eq "exit 1
    these scripts fail the shell lint:
factory/a+c.sh
factory/a.b.sh
factory/a/b.sh" "$(printf '%s\n' "$out" | sed -n 1,5p)"
}

# The batch is the lint's list; a project with no script fails, and one without
# this suite's own script in it is told so.
test_the_batch_test_checks_the_list() {
	lint_project
	run_suite_test test_every_script_of_this_factory_is_in_the_batch
	assert_eq "exit 1
    this suite is not in the batch" "$out"
	mkdir -p factory/core/tests
	printf 'echo suite\n' > factory/core/tests/shell_lint_test.sh
	run_suite_test test_every_script_of_this_factory_is_in_the_batch
	assert_eq "exit 0" "$out"
}

# stub_counting <tool>: $TEST_TMP/bin/<tool>, which logs each call but --version's
# arguments to $TEST_TMP/<tool>.calls, a line per call, and runs the real tool.
stub_counting() {
	local real
	real="$(command -v "$1")" || fail "no $1 on PATH"
	mkdir -p "$TEST_TMP/bin"
	printf '#!%s\n[ "$1" = --version ] || echo "$*" >> %q\nexec %q "$@"\n' "$BASH" "$TEST_TMP/$1.calls" "$real" > "$TEST_TMP/bin/$1"
	chmod +x "$TEST_TMP/bin/$1"
}

# Each tool runs once per dialect over its scripts; a script the run names is
# linted again by itself, and no other.
test_the_lint_runs_each_tool_once_per_dialect() {
	lint_project
	mkdir -p factory/tools
	printf '#!/bin/sh\necho a\n' > factory/tools/a
	printf '#!/bin/sh\necho b\n' > factory/tools/b
	printf '#!/usr/bin/env bash\necho c\n' > factory/tools/c
	stub_counting shellcheck
	stub_counting shfmt
	PATH="$TEST_TMP/bin:$PATH" run_lint
	assert_status 0
	assert_eq 2 "$(wc -l < "$TEST_TMP/shellcheck.calls")" "shellcheck runs, one per dialect:"$'\n'"$(cat "$TEST_TMP/shellcheck.calls")"
	assert_eq 2 "$(wc -l < "$TEST_TMP/shfmt.calls")" "shfmt runs, one per dialect:"$'\n'"$(cat "$TEST_TMP/shfmt.calls")"
	grep -q -- '-s sh -- factory/tools/a factory/tools/b$' "$TEST_TMP/shellcheck.calls" || fail "no sh batch:"$'\n'"$(cat "$TEST_TMP/shellcheck.calls")"
	printf '#!/usr/bin/env bash\necho $1\n' > factory/tools/c
	rm "$TEST_TMP/shellcheck.calls" "$TEST_TMP/shfmt.calls"
	PATH="$TEST_TMP/bin:$PATH" run_lint
	assert_status 1
	assert_eq "factory/tools/c:2:6: note: Double quote to prevent globbing and word splitting. [SC2086]" "$out"
	assert_eq 3 "$(wc -l < "$TEST_TMP/shellcheck.calls")" "shellcheck runs: two batches and c again:"$'\n'"$(cat "$TEST_TMP/shellcheck.calls")"
	assert_eq "-- factory/tools/c" "$(sed -n 3p "$TEST_TMP/shellcheck.calls" | grep -o -- '-- .*')"
}

# The batched lint prints what linting each script by itself prints, in the order
# given, with the same count: findings of both tools, in every dialect, a parse
# error and a script with another shebang.
test_the_batch_prints_what_each_script_by_itself_does() {
	lint_project
	mkdir -p factory/tools factory/core/hooks
	printf '#!/usr/bin/env bash\nif true;then\necho $1\nfi\n' > factory/tools/both
	printf '#!/bin/sh\n[[ -n "$1" ]] && echo yes\n' > factory/core/hooks/hook
	printf '#!/bin/dash\nif true;then echo x; fi\n' > factory/tools/dash
	printf '#!/usr/bin/env bash\nif [ x\n' > factory/tools/broken
	printf '#!/usr/bin/awk -f\n{ print $1 }\n' > factory/tools/awk.sh
	printf '#!/usr/bin/env bash\necho "$1"\n' > factory/tools/good
	local f expected="" n=0 each
	local -a files
	run_lint --list
	mapfile -t files <<< "$out"
	for f in "${files[@]}"; do
		run_lint "$f"
		[ "$status" -eq 0 ] || n=$((n + 1))
		[ -z "$out" ] || expected+="${expected:+$'\n'}$out"
	done
	each="$n"
	run_lint "${files[@]}"
	assert_status 1
	assert_eq "$expected" "$out" "the batch's output against each script's own"
	stderr_has "shell-lint: $each of ${#files[@]} scripts have findings"
	[ "$each" -ge 5 ] || fail "only $each scripts with findings by themselves:"$'\n'"$expected"
}

# A script that sources another of the batch is linted by itself: a run over both
# follows the source and loses the finding (pass 1's review).
test_a_script_sourcing_another_of_the_batch_is_linted_by_itself() {
	lint_project
	mkdir -p factory/tools
	printf '#!/usr/bin/env bash\n. factory/tools/b.sh\necho "$foo"\n' > factory/tools/a.sh
	printf '#!/usr/bin/env bash\nfoo=1\nexport foo\n' > factory/tools/b.sh
	printf '#!/usr/bin/env bash\n# shellcheck source=factory/tools/b.sh\n. "$1"\necho "$foo"\n' > factory/tools/c.sh
	printf '#!/usr/bin/env bash\n# shellcheck source=/dev/null\n. "$1/b.sh"\necho "${foo:-}"\n' > factory/tools/d.sh
	# A source= past another key, and a $ path a source-path directive resolves
	# (pass 2's review).
	printf '#!/usr/bin/env bash\n# shellcheck disable=SC2034 source=factory/tools/b.sh\n. "$1"\necho "$foo"\n' > factory/tools/e.sh
	printf '#!/usr/bin/env bash\n# shellcheck source-path=SCRIPTDIR\n. "$(dirname "$0")/b.sh"\necho "$foo"\n' > factory/tools/f.sh
	stub_counting shellcheck
	run_lint
	assert_status 1
	assert_eq "factory/tools/a.sh:3:7: warning: foo is referenced but not assigned. [SC2154]
factory/tools/c.sh:4:7: warning: foo is referenced but not assigned. [SC2154]
factory/tools/e.sh:4:7: warning: foo is referenced but not assigned. [SC2154]
factory/tools/f.sh:4:7: warning: foo is referenced but not assigned. [SC2154]" "$out"
	stderr_has "shell-lint: 4 of 9 scripts have findings"
	PATH="$TEST_TMP/bin:$PATH" run_lint
	# d.sh has a source=/dev/null directive, so it too is linted by itself.
	assert_eq 6 "$(wc -l < "$TEST_TMP/shellcheck.calls")" "the batch, then a, c, d, e and f:"$'\n'"$(cat "$TEST_TMP/shellcheck.calls")"
}

# A run whose output names no script of the batch has every script of the dialect
# linted by itself.
test_a_run_naming_no_script_lints_each_by_itself() {
	lint_project
	mkdir -p factory/tools
	printf '#!/usr/bin/env bash\necho a\n' > factory/tools/a
	local real
	real="$(command -v shellcheck)" || fail "no shellcheck on PATH"
	mkdir -p "$TEST_TMP/bin"
	# Two or more files after --: say something odd and fail, as no real run would.
	printf '#!%s\n[ "$1" = --version ] || echo "$*" >> %q\nn=0 seen=0\nfor a; do [ "$seen" = 1 ] && n=$((n + 1)); [ "$a" = -- ] && seen=1; done\n[ "$n" -ge 2 ] && { echo odd; exit 2; }\nexec %q "$@"\n' \
		"$BASH" "$TEST_TMP/shellcheck.calls" "$real" > "$TEST_TMP/bin/shellcheck"
	chmod +x "$TEST_TMP/bin/shellcheck"
	PATH="$TEST_TMP/bin:$PATH" run_lint
	assert_status 0
	assert_eq "" "$out"
	assert_eq 5 "$(wc -l < "$TEST_TMP/shellcheck.calls")" "the batch, then each of the four bash scripts:"$'\n'"$(cat "$TEST_TMP/shellcheck.calls")"
}

# In a clone of the factory's repo (VERSION and core/ at the top of a git
# checkout) the lint lists the clone's scripts, from its top.
test_the_lint_lists_a_factory_clones_scripts_from_its_top() {
	isolate_git
	local c="$TEST_TMP/clone"
	mkdir -p "$c/core/lib" "$c/tools" || fail "could not make the clone"
	cp "$FACTORY_CORE/shell-lint.sh" "$c/core/" &&
		cp "$FACTORY_CORE/lib/steps.sh" "$FACTORY_CORE/lib/vendor.sh" "$c/core/lib/" &&
		cp "$FACTORY_CORE/../.shellcheckrc" "$c/" || fail "could not copy the lint"
	echo 0.1.0 > "$c/VERSION"
	printf '#!/usr/bin/env bash\necho tool\n' > "$c/tools/a-tool"
	echo "not a script" > "$c/README.md"
	git -C "$c" init -q -b main || fail "could not init the clone"
	run_cmd bash "$c/core/shell-lint.sh" --list
	assert_status 0
	assert_eq "core/lib/steps.sh
core/lib/vendor.sh
core/shell-lint.sh
tools/a-tool" "$out" "the clone's scripts"
}
