# The factory's subagents and main session run Anthropic models only, each at an
# effort the policy allows (factory/CONTEXT.md, Models and effort): no Fable
# pinned, never max.

FACTORY_AGENTS_DIR="$FACTORY_CORE/../agents"

# frontmatter <key> <agent file>: the value of that key in the file's frontmatter.
frontmatter() {
	awk -v key="$1" '
		NR == 1 && $0 == "---" { inside = 1; next }
		inside && $0 == "---" { exit }
		inside && index($0, key ": ") == 1 { print substr($0, length(key) + 3); exit }
	' "$2"
}

test_every_agent_pins_an_opus_or_sonnet_model() {
	local f model n=0
	for f in "$FACTORY_AGENTS_DIR"/*.md; do
		n=$((n + 1))
		model="$(frontmatter model "$f")"
		case "$model" in
			claude-opus-5-5 | claude-sonnet-5-5) ;;
			*) fail "$(basename "$f") pins model '$model', not claude-opus-5-5 or claude-sonnet-5-5" ;;
		esac
	done
	[ "$n" -ge 5 ] || fail "only $n agents under factory/agents/"
}

# Opus for judgment, Sonnet for following clear instructions.
test_each_agent_runs_the_model_its_job_takes() {
	local agent want
	for agent in driver:claude-opus-5-5 verifier:claude-opus-5-5 amend-builder:claude-opus-5-5 \
		editor-sonnet:claude-sonnet-5-5 asset-fetcher:claude-sonnet-5-5; do
		want="${agent#*:}" agent="${agent%%:*}"
		assert_eq "$want" "$(frontmatter model "$FACTORY_AGENTS_DIR/$agent.md")" "the $agent agent's model"
	done
}

test_every_agent_sets_an_effort_below_max() {
	local f effort
	for f in "$FACTORY_AGENTS_DIR"/*.md; do
		effort="$(frontmatter effort "$f")"
		case "$effort" in
			low | medium | high | xhigh) ;;
			*) fail "$(basename "$f") sets effort '$effort', not one of low, medium, high, xhigh" ;;
		esac
	done
}

test_the_main_session_runs_opus_at_medium() {
	grep -qx 'FACTORY_MAIN_MODEL="claude-opus-5-5"' "$FACTORY_CORE/lib/hooks.sh" || fail "the main session's model is not claude-opus-5-5"
	grep -qx 'FACTORY_MAIN_EFFORT="medium"' "$FACTORY_CORE/lib/hooks.sh" || fail "the main session's effort is not medium"
}

# The retired Cursor Editor and Codex Verifier left no model behind in what the
# factory's sessions read.
test_no_agent_or_skill_names_a_retired_model() {
	local hits
	hits="$(grep -rlE 'composer-2|gpt-[0-9]|codex-verify|ai-pane' "$FACTORY_AGENTS_DIR" "$FACTORY_CORE/../skills" "$FACTORY_CORE/../CONTEXT.md" || true)"
	assert_eq "" "$hits" "files naming a retired model or tool"
}
