# The shell lint (shell-lint.sh): one test per shell script the factory ships or
# the gate runs, named after the script, then the lint itself on fixture projects.
#
# The per-script tests come from the lint's own list (--list) of the project this
# factory sits in, so a new script gets its test with no list to update. Each is
# test_lint_<its path, with / as .>, and fails with the script's findings. While a
# tool is missing or off its pin they skip, and test_the_tools_are_at_their_pins
# fails, naming the install command.

# shell_lint_one <path>: lint the script, relative to the project root.
# shellcheck disable=SC2154 # out and status: set by run_cmd, in factory/core/tests/lib.sh
shell_lint_one() {
	run_cmd bash "$FACTORY_CORE/shell-lint.sh" "$1"
	case "$status" in
		0) ;;
		3) skip "$1 is not linted: $(cat "$TEST_TMP/stderr")" ;;
		*) fail "$1 fails the shell lint:"$'\n'"$out"$'\n'"$(cat "$TEST_TMP/stderr")" ;;
	esac
}

# shell_lint_name <path>: set SHELL_LINT_NAME to the name of the script's test,
# test_lint_<path, with / as .>, any other character a function name cannot hold
# as _ (no subshell: every test of the suite runs this per script).
shell_lint_name() {
	SHELL_LINT_NAME="test_lint_${1//\//.}"
	SHELL_LINT_NAME="${SHELL_LINT_NAME//[^A-Za-z0-9_.-]/_}"
}

# shell_lint_define: a test function per script the lint lists; a name two
# scripts share gets a _ added until it is free.
shell_lint_define() {
	local f
	while IFS= read -r f; do
		shell_lint_name "$f"
		while declare -F "$SHELL_LINT_NAME" > /dev/null; do
			SHELL_LINT_NAME="${SHELL_LINT_NAME}_"
		done
		eval "$SHELL_LINT_NAME() { shell_lint_one $(printf '%q' "$f"); }"
	done < <(bash "$FACTORY_CORE/shell-lint.sh" --list 2> /dev/null)
}
shell_lint_define

test_the_tools_are_at_their_pins() {
	run_cmd bash "$FACTORY_CORE/shell-lint.sh" --tools
	[ "$status" -eq 0 ] || fail "$(cat "$TEST_TMP/stderr")"
}

# A test per script, so the suite cannot pass by linting nothing.
test_every_script_of_this_factory_has_its_test() {
	local f n=0
	while IFS= read -r f; do
		n=$((n + 1))
		shell_lint_name "$f"
		declare -F "$SHELL_LINT_NAME" > /dev/null || fail "no test for $f"
	done < <(bash "$FACTORY_CORE/shell-lint.sh" --list)
	[ "$n" -gt 0 ] || fail "the lint lists no script"
	assert_eq "$n" "$(declare -F | grep -c ' test_lint_')" "not one test per script"
	# In a project, paths start factory/; in a clone of the factory's repo, core/.
	declare -F test_lint_factory.core.shell-lint.sh > /dev/null || declare -F test_lint_core.shell-lint.sh > /dev/null ||
		fail "no test for the lint itself"
	declare -F test_lint_factory.core.tests.shell_lint_test.sh > /dev/null || declare -F test_lint_core.tests.shell_lint_test.sh > /dev/null ||
		fail "no test for this suite"
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

# The suite's own tests, on a fixture project: one per script, named after it, and
# the one for a script with a finding fails with the finding.
test_the_suite_names_each_script_and_fails_its_findings() {
	lint_project
	printf '#!/usr/bin/env bash\necho $1\n' > factory/core/bad.sh
	mkdir "$TEST_TMP/inner"
	run_cmd env TEST_TMP="$TEST_TMP/inner" bash -c '
		. "$1/tests/lib.sh"
		FACTORY_CORE="$2"
		. "$1/tests/shell_lint_test.sh"
		declare -F | awk "{ print \$3 }" | grep "^test_lint_" | LC_ALL=C sort
		(test_lint_factory.core.shell-lint.sh)
		echo "clean: exit $?"
		(test_lint_factory.core.bad.sh)
		echo "bad: exit $?"
	' _ "$FACTORY_CORE" "$PWD/factory/core"
	assert_eq "test_lint_factory.core.bad.sh
test_lint_factory.core.lib.steps.sh
test_lint_factory.core.lib.vendor.sh
test_lint_factory.core.shell-lint.sh
clean: exit 0
bad: exit 1" "$out"
	stderr_has "factory/core/bad.sh fails the shell lint:"
	stderr_has "factory/core/bad.sh:2:6: note: Double quote to prevent globbing and word splitting. [SC2086]"
}

# Two scripts whose paths map to one name each get a test.
test_scripts_that_share_a_name_each_get_a_test() {
	lint_project
	mkdir -p factory/a
	printf 'echo a\n' > factory/a/b.sh
	printf 'echo b\n' > factory/a.b.sh
	printf 'echo c\n' > factory/a+c.sh
	mkdir "$TEST_TMP/inner"
	run_cmd env TEST_TMP="$TEST_TMP/inner" bash -c '
		. "$1/tests/lib.sh"
		FACTORY_CORE="$2"
		. "$1/tests/shell_lint_test.sh"
		declare -F | awk "{ print \$3 }" | grep "^test_lint_factory\.a" | LC_ALL=C sort
	' _ "$FACTORY_CORE" "$PWD/factory/core"
	assert_eq "test_lint_factory.a.b.sh
test_lint_factory.a.b.sh_
test_lint_factory.a_c.sh" "$out"
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
