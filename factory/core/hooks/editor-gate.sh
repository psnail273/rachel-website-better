#!/usr/bin/env bash
# The Editor's gate, run by the hook that loops the Editor until it is green: the
# Sonnet Editor's stop hook (claude-subagent-stop.sh, at its SubagentStop and at
# its SubagentHandback call), which wraps this
# script's output in its answer to Claude Code.
# Run from the worktree root, with no arguments:
#   bash factory/core/hooks/editor-gate.sh
#
#   0. fails at once, with a brief-changed finding, when the Build Brief no
#      longer matches the Driver's seal (lib/brief.sh); no gate runs;
#   1. formats the files the branch changed (since the diff base, lib/diff.sh,
#      uncommitted and untracked ones included, locked tests left out) with the
#      project's `tools/verify/format --write <file...>`, unless that step is a
#      no-op; then, before any gate step runs, finds what is uncommitted: what
#      formatting just changed, and the Editor's own files. Land refuses a dirty
#      tree, so each one is an `editor-uncommitted` finding, the first line says
#      the gate did not run, and it exits 1 (#15: a formatter's change costs no
#      long step);
#   2. runs the gate the branch's run-state phase calls for (factory_gate in
#      lib/run.sh): verify.sh --red in the red phase; in Partial mode
#      baseline.sh gate, with the Baseline entries the brief removes; else the
#      full verify.sh. verify runs with --all-static: every static step's
#      findings at once, and no long step after a red one. In the green phase
#      (run state phase green: the small lane's, a test-only issue's and an
#      amend's too) it exports FACTORY_GATE_LOOP=editor, the Editor's loop: the
#      steps that take it run lighter (an adapter's smoke in Chromium alone, its
#      mutate incremental), and since the gate stamp's key holds every exported
#      FACTORY_ variable (lib/stamp.sh), that verdict keys apart from the full
#      gate's: the Driver's `verify.sh --reuse`, the Verifier's, lock.sh record
#      and Land never print it as theirs. The red and partial phases, and a
#      branch with no phase, run without it, as the Driver's gate does;
#   3. once that gate is green, finds what is still uncommitted: what the gate's
#      tools wrote as they ran.
#      Land refuses a dirty tree, so each one is an `editor-uncommitted` finding and
#      the gate counts as red. A red gate skips this: its findings come first.
#   4. records the gate's stamp in the run state (editor-gate, lib/run.sh: the
#      phase and HEAD's commit) when it exits 0 with HEAD where step 2 found it;
#      a run first clears the stamp of an earlier one. prompt.sh verifier and
#      lock.sh record go on only with the stamp for HEAD, and run this gate
#      themselves without it (factory_editor_gate_check), so a round whose stop
#      hook did not run is still gated;
#   5. in the small lane (run state lane small, from the sealed brief), a red
#      phase green on a clean tree moves on in the same chat: it records the Lock
#      at HEAD (factory_lock_record, lib/lock.sh; step 2 was the fresh run of the
#      red gate that lock.sh record would run again), sets the phase to green
#      (recording when it began, factory_state_set_phase in lib/run.sh)
#      and exits 3, with the green phase's instruction for the Editor: the
#      green round `prompt.sh green` prints, prompts/green.md then the footer,
#      the same the Driver sends after a Lock outside the small lane. HEAD
#      moved since step 2 began: no Lock, exit 1, as the gate never judged it;
#      nor when prompt.sh green fails, which it runs before the Lock.
#
# stdout: the first line names the gate that ran (`gate: not run: ...` at step
# 1's uncommitted files); then, when write mode printed
# findings, a block headed `format --write on the changed files:`; then the gate's
# own stdout; then the editor-uncommitted findings. On exit 3 the first line is
# followed by the green phase's instruction alone, and the gate's output goes to
# stderr. Everything else goes to stderr.
#
# Exit codes: 0 green on a clean tree, 1 red or uncommitted files, 2 usage,
# 3 the small lane moved on to the green phase.
set -u

core="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$core/lib/steps.sh"
. "$core/lib/findings.sh"
. "$core/lib/brief.sh"
. "$core/lib/diff.sh"
. "$core/lib/run.sh"
. "$core/lib/lock.sh"

if [ "$#" -ne 0 ]; then
	echo "usage: bash factory/core/hooks/editor-gate.sh" >&2
	exit 2
fi

phase=""
if branch="$(factory_current_branch)"; then
	phase="$(factory_state_get "$branch" phase)" || phase=""
	# A run voids the stamp of an earlier one until it passes itself.
	factory_state_unset "$branch" editor-gate 2> /dev/null
else
	branch=""
fi

# 0. The brief is the Driver's: a changed one stops the round.
if [ -n "$phase" ] && ! seal="$(factory_brief_seal_check "$(factory_brief_path)")"; then
	echo "gate: the Build Brief's seal"
	printf '%s\n' "$seal"
	exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/format"

# 1. Format the changed files, leaving the locked tests as the Lock holds them.
format="$(factory_step_script format)"
if [ -f "$format" ] && ! factory_step_is_noop "$format"; then
	{
		if base="$(factory_diff_base)"; then
			git diff --name-only --no-renames "$base" --
		fi
		git ls-files --others --exclude-standard
	} | tr -d '\r' | LC_ALL=C sort -u > "$tmp/changed"
	factory_locked_files > "$tmp/locked"
	files=()
	while IFS= read -r f; do
		[ -f "$f" ] && ! grep -qxF -- "$f" "$tmp/locked" && files+=("$f")
	done < "$tmp/changed"
	if [ "${#files[@]}" -gt 0 ]; then
		printf '%s\n' "${files[@]}" > "$tmp/formatted"
		git hash-object --stdin-paths < "$tmp/formatted" > "$tmp/before" 2> /dev/null || : > "$tmp/before"
		bash "$format" --write "${files[@]}" < /dev/null > "$tmp/format" || true
		git hash-object --stdin-paths < "$tmp/formatted" > "$tmp/after" 2> /dev/null || : > "$tmp/after"
		# The files whose bytes formatting changed.
		paste "$tmp/formatted" "$tmp/before" "$tmp/after" | awk -F '\t' '$2 != $3 { print $1 }' > "$tmp/reformatted"
	fi
fi

# uncommitted: list what differs from HEAD, and what is untracked, in $tmp/uncommitted.
uncommitted() {
	{
		git diff --name-only --no-renames HEAD --
		git ls-files --others --exclude-standard
	} | tr -d '\r' | LC_ALL=C sort -u > "$tmp/uncommitted"
}

# 1b. An uncommitted tree before the gate: no gate step runs on it.
uncommitted
if [ -s "$tmp/uncommitted" ]; then
	echo "gate: not run: the tree has uncommitted changes, and the gate judges only a committed tree"
	if [ -s "$tmp/format" ]; then
		echo "format --write on the changed files:"
		tr -d '\r' < "$tmp/format"
	fi
	touch "$tmp/reformatted"
	while IFS= read -r f; do
		if grep -qxF -- "$f" "$tmp/reformatted"; then
			factory_finding "$f" 1 editor-uncommitted "format --write changed it, and Land refuses a dirty tree; commit it"
		else
			factory_finding "$f" 1 editor-uncommitted "uncommitted, and Land refuses a dirty tree; commit it"
		fi
	done < "$tmp/uncommitted"
	exit 1
fi

# 2. The phase's gate (lib/run.sh); the green phase's is the Editor's loop.
echo "gate: $(factory_gate_name "$phase")"
if [ "$phase" = green ]; then
	export FACTORY_GATE_LOOP=editor
else
	unset FACTORY_GATE_LOOP
fi
gate_head="$(git rev-parse HEAD 2> /dev/null)" || gate_head=""
factory_gate "$phase" "$core/verify.sh" --removes --all-static > "$tmp/gate"
gate=$?

{
	if [ -s "$tmp/format" ]; then
		echo "format --write on the changed files:"
		tr -d '\r' < "$tmp/format"
	fi
	tr -d '\r' < "$tmp/gate"
} > "$tmp/out"
if [ "$gate" -ne 0 ]; then
	cat "$tmp/out"
	exit 1
fi

# 3. A green gate must leave a clean tree.
uncommitted
if [ -s "$tmp/uncommitted" ]; then
	cat "$tmp/out"
	while IFS= read -r f; do
		factory_finding "$f" 1 editor-uncommitted "uncommitted, and Land refuses a dirty tree; commit it"
	done < "$tmp/uncommitted"
	exit 1
fi

# 4. The small lane: a green red phase locks its tests and goes on to green.
# Else the gate passed: its stamp, for HEAD as the gate judged it.
if [ "$phase" != red ] || [ "$(factory_state_get "$branch" lane 2> /dev/null)" != small ]; then
	if [ -n "$branch" ] && [ -n "$gate_head" ] && [ "$(git rev-parse HEAD 2> /dev/null)" = "$gate_head" ]; then
		factory_editor_gate_stamp "$branch" "$phase" "$gate_head" 2> /dev/null
	fi
	cat "$tmp/out"
	exit 0
fi
if [ -z "$gate_head" ] || [ "$(git rev-parse HEAD 2> /dev/null)" != "$gate_head" ]; then
	cat "$tmp/out"
	echo "the small lane could not record the Lock: HEAD moved while the gate ran, so the gate did not judge it"
	echo "This is the Driver's to fix: stop and report it."
	exit 1
fi
if ! base="$(factory_diff_base)"; then
	cat "$tmp/out"
	echo "the small lane could not record the Lock: no merge-base of HEAD and '${FACTORY_BASE_BRANCH:-dev}'"
	echo "This is the Driver's to fix: stop and report it."
	exit 1
fi
# The green round's prompt, before the Lock, so a missing one moves nothing.
if ! bash "$core/prompt.sh" green < /dev/null > "$tmp/green" 2> "$tmp/green-error"; then
	cat "$tmp/out"
	echo "the small lane could not record the Lock: prompt.sh green failed, so there is no green instruction to send: $(tr -d '\r' < "$tmp/green-error" | tr '\n' ' ')"
	echo "This is the Driver's to fix: stop and report it."
	exit 1
fi
if ! factory_lock_record "$branch" "$base" < /dev/null > "$tmp/locked" 2> "$tmp/lock-error"; then
	cat "$tmp/out"
	echo "the small lane could not record the Lock: $(tr -d '\r' < "$tmp/lock-error" | tr '\n' ' ')"
	echo "This is the Driver's to fix: stop and report it."
	exit 1
fi
if ! factory_state_set_phase "$branch" green; then
	cat "$tmp/out"
	echo "the small lane recorded the Lock but could not set the phase to green: stop and report it to the Driver."
	exit 1
fi
cat "$tmp/out" >&2
echo "The red gate passed, so the factory recorded the Lock at $(git rev-parse --short HEAD) and moved this issue to the green phase, in this chat. The locked test files:"
tr -d '\r' < "$tmp/locked" | sed 's/^/  /'
echo
tr -d '\r' < "$tmp/green"
exit 3
