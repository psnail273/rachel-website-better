# The factory's subagents and main session run Anthropic models only, each at an
# effort the policy allows (factory/CONTEXT.md, Models and effort): never max,
# and Fable pinned only for the designer, which the human approved on #42.

FACTORY_AGENTS_DIR="$FACTORY_CORE/../agents"

# frontmatter <key> <agent file>: the value of that key in the file's frontmatter.
frontmatter() {
	awk -v key="$1" '
		NR == 1 && $0 == "---" { inside = 1; next }
		inside && $0 == "---" { exit }
		inside && index($0, key ": ") == 1 { print substr($0, length(key) + 3); exit }
	' "$2"
}

# bad_models <agents dir>: a line for each agent there whose model the policy
# refuses: Opus or Sonnet, or Fable for the designer alone.
bad_models() {
	local f model
	for f in "$1"/*.md; do
		model="$(frontmatter model "$f")"
		case "$(basename "$f" .md):$model" in
			*:claude-opus-5-5 | *:claude-sonnet-5-5 | designer:claude-fable-5-2) ;;
			*) echo "$(basename "$f") pins model '$model'" ;;
		esac
	done
}

test_every_agent_pins_a_model_the_policy_allows() {
	local n
	assert_eq "" "$(bad_models "$FACTORY_AGENTS_DIR")" "agents pinning a model the policy refuses"
	n="$(find "$FACTORY_AGENTS_DIR" -maxdepth 1 -name '*.md' | wc -l)"
	[ "$n" -ge 6 ] || fail "only $n agents under factory/agents/"
}

# Fable is the designer's alone: another agent that pins it is refused, and so
# is the designer on a model nobody approved.
test_fable_is_refused_to_any_agent_but_the_designer() {
	mkdir -p agents
	printf -- '---\nname: designer\nmodel: claude-fable-5-2\n---\n' > agents/designer.md
	printf -- '---\nname: verifier\nmodel: claude-fable-5-2\n---\n' > agents/verifier.md
	printf -- '---\nname: driver\nmodel: claude-opus-5-5\n---\n' > agents/driver.md
	assert_eq "verifier.md pins model 'claude-fable-5-2'" "$(bad_models agents)" "the Verifier on Fable"
	printf -- '---\nname: designer\nmodel: claude-fable-9-9\n---\n' > agents/designer.md
	rm agents/verifier.md
	assert_eq "designer.md pins model 'claude-fable-9-9'" "$(bad_models agents)" "the designer on another Fable"
}

# Opus for judgment, Sonnet for following clear instructions, Fable for the
# design directions (the human's call on #42).
test_each_agent_runs_the_model_its_job_takes() {
	local agent want
	for agent in driver:claude-opus-5-5 verifier:claude-opus-5-5 amend-builder:claude-opus-5-5 \
		editor-sonnet:claude-sonnet-5-5 asset-fetcher:claude-sonnet-5-5 designer:claude-fable-5-2; do
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

# skills_of <agent file>: the skills its frontmatter preloads, one per line.
skills_of() {
	awk '
		NR == 1 && $0 == "---" { inside = 1; next }
		inside && $0 == "---" { exit }
		inside && /^skills:/ { list = 1; next }
		list && /^  - / { sub(/^  - /, ""); print; next }
		{ list = 0 }
	' "$1"
}

# frontend-design is for the design and Verifier roles only: never the Editor's
# (claude_deny_test holds the deny refusing the Editor's Skill call of it).
test_frontend_design_is_preloaded_by_the_designer_and_verifier_only() {
	local f agent
	for agent in designer verifier; do
		skills_of "$FACTORY_AGENTS_DIR/$agent.md" | grep -qxF frontend-design || fail "the $agent doesn't preload frontend-design"
	done
	for f in "$FACTORY_AGENTS_DIR"/*.md; do
		agent="$(basename "$f" .md)"
		case "$agent" in designer | verifier) continue ;; esac
		! grep -qF frontend-design "$f" || fail "$agent.md names frontend-design"
	done
	grep -q '^skills:' "$FACTORY_AGENTS_DIR/editor-sonnet.md" || fail "the Editor's skills list is gone, so this test checks nothing"
}

# The vendored skill is exactly what its source had: each file's blob id is the
# one third-party/README.md records.
test_the_vendored_frontend_design_is_as_recorded() {
	local dir="$FACTORY_CORE/../third-party" f id
	for f in SKILL.md LICENSE.txt; do
		id="$(git hash-object "$dir/frontend-design/$f")"
		grep -qF "\`$f\` $id" "$dir/README.md" || fail "frontend-design/$f is $id, not the blob third-party/README.md records"
	done
	grep -qx 'name: frontend-design' "$dir/frontend-design/SKILL.md" || fail "the vendored skill isn't named frontend-design"
}
