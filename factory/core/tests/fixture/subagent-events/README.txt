Hook events and a subagent transcript as Claude Code 2.1.329 (events) and
2.1.325 (transcript) wrote them for an editor-sonnet subagent, trimmed, with
their paths replaced by placeholders that editor_stop_test.sh fills in:
  @SESSION@   the session's transcript, without .jsonl
  @CWD@       the session's working directory
  @PROMPT@    the prompt file the main session sent by reference
  @WORKTREE@  the worktree the prompt file's last line names
  @MESSAGE@   the hand-back's message
  handback.json   the PreToolUse event of the subagent's SubagentHandback call
  stop.json       its SubagentStop event, which follows the hand-back: it has no
                  last_assistant_message
  transcript.jsonl  the subagent's transcript, at
                  @SESSION@/subagents/agent-a7a3358651159bebb.jsonl: the prompt
                  sent by reference, Claude Code's records of the system prompt
                  (a prompt_snapshot attachment, an api-request-shape line), both
                  holding editor-sonnet.md's sample worktree line, then the Read
                  of the prompt file, whose result holds the real line
