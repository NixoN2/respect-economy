#!/usr/bin/env bats
# tests/test_guards.bats - Tests for the guard script pre-action system

setup() {
  TEST_DIR="$(mktemp -d)"
  export RESPECT_WALLET_DIR="$TEST_DIR"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  SCRIPT="$PLUGIN_ROOT/scripts/pre-action-check.sh"

  # Override GUARDS_DIR via HOME
  export HOME="$TEST_DIR"
  mkdir -p "$TEST_DIR/.claude/respect/guards"
  GUARDS_DIR="$TEST_DIR/.claude/respect/guards"

  # Default CWD for local guard tests
  TEST_CWD="/Users/testuser/my-project"
  ENCODED_CWD=$(echo "$TEST_CWD" | sed 's/[\/.]/-/g')
  LOCAL_GUARDS_DIR="$TEST_DIR/.claude/projects/${ENCODED_CWD}/guards"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: pipe JSON tool context into the script, capture stdout and stderr
# When guard fires: exit 2, reason on stderr. When no guard: exit 0, {} on stdout.
run_check() {
  local tool_name="$1"
  local tool_input="$2"
  local cwd="${3:-$TEST_CWD}"
  local input="{\"tool_name\": \"$tool_name\", \"tool_input\": {\"command\": \"$tool_input\"}, \"cwd\": \"$cwd\"}"
  # Capture both stdout and stderr, and exit code
  local tmpout="$TEST_DIR/_stdout"
  local tmperr="$TEST_DIR/_stderr"
  set +e
  echo "$input" | bash "$SCRIPT" >"$tmpout" 2>"$tmperr"
  CHECK_EXIT=$?
  set -e
  CHECK_STDOUT=$(cat "$tmpout")
  CHECK_STDERR=$(cat "$tmperr")
}

# ── Basic passthrough ──────────────────────────

@test "returns empty JSON when no guards directory exists" {
  rm -rf "$GUARDS_DIR"
  run_check "Bash" "echo hello"
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

@test "returns empty JSON for non-action tools like Read" {
  run_check "Read" "/some/file.txt"
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

@test "returns empty JSON for Glob tool" {
  run_check "Glob" "**/*.ts"
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

@test "returns empty JSON when guards dir is empty" {
  run_check "Bash" "git push origin main"
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

# ── Trigger matching ──────────────────────────

@test "guard fires when trigger keyword matches tool input" {
  cat > "$GUARDS_DIR/no-timeout.json" <<'EOF'
{"triggers": ["timeout"], "lesson": "timeout not available on macOS"}
EOF
  cat > "$GUARDS_DIR/no-timeout.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "timeout is not available on macOS"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/no-timeout.sh"

  run_check "Bash" "timeout 5 curl http://example.com"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"timeout is not available on macOS"* ]]
}

@test "trigger matching is case-insensitive" {
  cat > "$GUARDS_DIR/no-timeout.json" <<'EOF'
{"triggers": ["timeout"], "lesson": "timeout not available on macOS"}
EOF
  cat > "$GUARDS_DIR/no-timeout.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "timeout is not available on macOS"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/no-timeout.sh"

  run_check "Bash" "TIMEOUT 10 some-command"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"timeout is not available on macOS"* ]]
}

@test "trigger does not fire on word prefix (gtimeout should not match timeout trigger)" {
  cat > "$GUARDS_DIR/no-timeout.json" <<'EOF'
{"triggers": ["timeout"], "lesson": "timeout not available on macOS"}
EOF
  cat > "$GUARDS_DIR/no-timeout.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "timeout is not available on macOS"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/no-timeout.sh"

  run_check "Bash" "gtimeout 5 curl http://example.com"
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

@test "guard does not fire when trigger does not match" {
  cat > "$GUARDS_DIR/no-timeout.json" <<'EOF'
{"triggers": ["timeout"], "lesson": "timeout not available on macOS"}
EOF
  cat > "$GUARDS_DIR/no-timeout.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "timeout is not available on macOS"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/no-timeout.sh"

  run_check "Bash" "echo hello world"
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

@test "multi-word trigger matches as substring" {
  cat > "$GUARDS_DIR/no-friday-deploy.json" <<'EOF'
{"triggers": ["git push"], "lesson": "Don't deploy on Fridays"}
EOF
  cat > "$GUARDS_DIR/no-friday-deploy.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Careful with pushes"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/no-friday-deploy.sh"

  run_check "Bash" "git push origin main --force"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"Careful with pushes"* ]]
}

# ── Guard script execution ─────────────────────

@test "guard that exits 0 allows the action (returns empty JSON)" {
  cat > "$GUARDS_DIR/check-day.json" <<'EOF'
{"triggers": ["git push"], "lesson": "Don't deploy on Fridays"}
EOF
  cat > "$GUARDS_DIR/check-day.sh" <<'SCRIPT'
#!/usr/bin/env bash
# Always pass for testing
exit 0
SCRIPT
  chmod +x "$GUARDS_DIR/check-day.sh"

  run_check "Bash" "git push origin main"
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

@test "guard exit 1 with output blocks via exit 2 and stderr" {
  cat > "$GUARDS_DIR/warn-guard.json" <<'EOF'
{"triggers": ["rm -rf"], "lesson": "Be careful with recursive deletes"}
EOF
  cat > "$GUARDS_DIR/warn-guard.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Dangerous recursive delete detected"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/warn-guard.sh"

  run_check "Bash" "rm -rf /tmp/test"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"Dangerous recursive delete"* ]]
  [[ "$CHECK_STDERR" == *"Be careful with recursive deletes"* ]]
}

@test "guard exit 1 with no output returns empty JSON (silent fail)" {
  cat > "$GUARDS_DIR/silent-guard.json" <<'EOF'
{"triggers": ["deploy"], "lesson": "Check before deploying"}
EOF
  cat > "$GUARDS_DIR/silent-guard.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/silent-guard.sh"

  run_check "Bash" "deploy production"
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

@test "reason includes guard name and lesson" {
  cat > "$GUARDS_DIR/no-timeout.json" <<'EOF'
{"triggers": ["timeout"], "lesson": "Use gtimeout on macOS instead"}
EOF
  cat > "$GUARDS_DIR/no-timeout.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "timeout command missing on macOS"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/no-timeout.sh"

  run_check "Bash" "timeout 5 curl example.com"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"[no-timeout]"* ]]
  [[ "$CHECK_STDERR" == *"Use gtimeout on macOS instead"* ]]
}

@test "global guard shows (global) scope in reason" {
  cat > "$GUARDS_DIR/no-timeout.json" <<'EOF'
{"triggers": ["timeout"], "lesson": "Use gtimeout on macOS"}
EOF
  cat > "$GUARDS_DIR/no-timeout.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "timeout blocked"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/no-timeout.sh"

  run_check "Bash" "timeout 5 echo hello"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"(global)"* ]]
}

# ── Edge cases ─────────────────────────────────

@test "missing guard script (no .sh file) is safely skipped" {
  cat > "$GUARDS_DIR/orphan-trigger.json" <<'EOF'
{"triggers": ["danger"], "lesson": "Watch out"}
EOF
  # No .sh file created

  run_check "Bash" "danger zone command"
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

@test "non-executable guard script is safely skipped" {
  cat > "$GUARDS_DIR/no-exec.json" <<'EOF'
{"triggers": ["badcmd"], "lesson": "Don't use badcmd"}
EOF
  cat > "$GUARDS_DIR/no-exec.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "should not run"
exit 1
SCRIPT
  # Deliberately NOT chmod +x

  run_check "Bash" "badcmd --force"
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

@test "malformed JSON trigger file is safely skipped" {
  echo "this is not json" > "$GUARDS_DIR/broken.json"

  run_check "Bash" "any command here"
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

@test "empty triggers array returns empty JSON" {
  cat > "$GUARDS_DIR/empty-triggers.json" <<'EOF'
{"triggers": [], "lesson": "Nothing to match"}
EOF
  cat > "$GUARDS_DIR/empty-triggers.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "should never fire"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/empty-triggers.sh"

  run_check "Bash" "anything at all"
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

@test "guard script that crashes (stderr) is handled gracefully" {
  cat > "$GUARDS_DIR/crasher.json" <<'EOF'
{"triggers": ["crash-test"], "lesson": "Testing crash recovery"}
EOF
  cat > "$GUARDS_DIR/crasher.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "intentional crash" >&2
exit 2
SCRIPT
  chmod +x "$GUARDS_DIR/crasher.sh"

  run_check "Bash" "crash-test here"
  # Guard output went to stderr (suppressed by 2>/dev/null in script),
  # so no GUARD_OUTPUT captured → empty JSON on stdout
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

# ── Multiple guards ────────────────────────────

@test "first matching guard wins (stops after first warning)" {
  cat > "$GUARDS_DIR/aaa-first.json" <<'EOF'
{"triggers": ["deploy"], "lesson": "First guard lesson"}
EOF
  cat > "$GUARDS_DIR/aaa-first.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "First guard warning"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/aaa-first.sh"

  cat > "$GUARDS_DIR/zzz-second.json" <<'EOF'
{"triggers": ["deploy"], "lesson": "Second guard lesson"}
EOF
  cat > "$GUARDS_DIR/zzz-second.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Second guard warning"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/zzz-second.sh"

  run_check "Bash" "deploy production"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"First guard"* ]]
  [[ "$CHECK_STDERR" != *"Second guard"* ]]
}

@test "passing guard does not block subsequent failing guard" {
  cat > "$GUARDS_DIR/aaa-pass.json" <<'EOF'
{"triggers": ["deploy"], "lesson": "This one passes"}
EOF
  cat > "$GUARDS_DIR/aaa-pass.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  chmod +x "$GUARDS_DIR/aaa-pass.sh"

  cat > "$GUARDS_DIR/zzz-fail.json" <<'EOF'
{"triggers": ["deploy"], "lesson": "This one fails"}
EOF
  cat > "$GUARDS_DIR/zzz-fail.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Deploy blocked by second guard"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/zzz-fail.sh"

  run_check "Bash" "deploy production"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"Deploy blocked by second guard"* ]]
}

# ── Tool type coverage ─────────────────────────

@test "guard fires for Write tool" {
  cat > "$GUARDS_DIR/no-secrets.json" <<'EOF'
{"triggers": ["password"], "lesson": "Don't hardcode passwords"}
EOF
  cat > "$GUARDS_DIR/no-secrets.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Possible hardcoded secret"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/no-secrets.sh"

  run_check "Write" "password = mysecret123"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"Possible hardcoded secret"* ]]
}

@test "guard fires for Edit tool" {
  cat > "$GUARDS_DIR/no-secrets.json" <<'EOF'
{"triggers": ["api_key"], "lesson": "Don't hardcode API keys"}
EOF
  cat > "$GUARDS_DIR/no-secrets.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Possible hardcoded API key"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/no-secrets.sh"

  run_check "Edit" "api_key = abc123xyz"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"Possible hardcoded API key"* ]]
}

# ── Performance / safety ───────────────────────

@test "guard script that hangs is killed by timeout (does not block hook)" {
  cat > "$GUARDS_DIR/slow-guard.json" <<'EOF'
{"triggers": ["slow-cmd"], "lesson": "Testing timeout"}
EOF
  cat > "$GUARDS_DIR/slow-guard.sh" <<'SCRIPT'
#!/usr/bin/env bash
sleep 30
echo "should never reach here"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/slow-guard.sh"

  # The hook itself has a 5s timeout from Claude, but we test that
  # the script doesn't hang forever. Run with a 3s timeout.
  local tmpout="$TEST_DIR/_timeout_out"
  result=$(timeout 3 bash -c 'echo "{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": \"slow-cmd\"}, \"cwd\": \"/tmp\"}" | bash "'"$SCRIPT"'"' 2>/dev/null) || result="{}"
  # Should either return {} or timeout - either is safe
  echo "$result" | jq -e '.' >/dev/null 2>&1
}

# ── MCP tool support ───────────────────────────

@test "guard with tools field fires only for matching MCP tools" {
  cat > "$GUARDS_DIR/no-slack-weekend.json" <<'EOF'
{"triggers": ["send_message"], "tools": ["mcp__.*slack.*"], "lesson": "Don't post to Slack on weekends"}
EOF
  cat > "$GUARDS_DIR/no-slack-weekend.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Slack guard triggered"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/no-slack-weekend.sh"

  # Should fire for Slack MCP tool
  run_check "mcp__plugin_slack_slack__slack_send_message" "send_message to #general"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"Slack guard triggered"* ]]
}

@test "guard with tools field does NOT fire for non-matching tools" {
  cat > "$GUARDS_DIR/no-slack-weekend.json" <<'EOF'
{"triggers": ["send_message"], "tools": ["mcp__.*slack.*"], "lesson": "Don't post to Slack on weekends"}
EOF
  cat > "$GUARDS_DIR/no-slack-weekend.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Slack guard triggered"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/no-slack-weekend.sh"

  # Should NOT fire for Bash tool (even though trigger keyword matches)
  run_check "Bash" "echo send_message"
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

@test "guard with tools field does NOT fire for unrelated MCP tools" {
  cat > "$GUARDS_DIR/no-slack-weekend.json" <<'EOF'
{"triggers": ["send_message"], "tools": ["mcp__.*slack.*"], "lesson": "Don't post to Slack on weekends"}
EOF
  cat > "$GUARDS_DIR/no-slack-weekend.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Slack guard triggered"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/no-slack-weekend.sh"

  # Should NOT fire for Datadog MCP tool
  run_check "mcp__plugin_acme_datadog__search_logs" "send_message query"
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

@test "guard without tools field uses default tools (Bash/Write/Edit/NotebookEdit)" {
  cat > "$GUARDS_DIR/default-guard.json" <<'EOF'
{"triggers": ["dangerous"], "lesson": "Be careful"}
EOF
  cat > "$GUARDS_DIR/default-guard.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Default guard fired"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/default-guard.sh"

  # Should fire for Bash
  run_check "Bash" "dangerous command"
  [ "$CHECK_EXIT" -eq 2 ]

  # Should NOT fire for MCP tool (no tools field = default only)
  run_check "mcp__some_server__some_tool" "dangerous input"
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

@test "guard with multiple tool patterns matches any" {
  cat > "$GUARDS_DIR/multi-tool.json" <<'EOF'
{"triggers": ["delete"], "tools": ["Bash", "mcp__.*datadog.*", "mcp__.*slack.*"], "lesson": "Be careful with deletes"}
EOF
  cat > "$GUARDS_DIR/multi-tool.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Delete guard fired"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/multi-tool.sh"

  # Should fire for Bash
  run_check "Bash" "delete something"
  [ "$CHECK_EXIT" -eq 2 ]

  # Should fire for Datadog MCP
  run_check "mcp__plugin_acme_datadog__delete_monitor" "delete monitor 123"
  [ "$CHECK_EXIT" -eq 2 ]

  # Should NOT fire for unmatched MCP
  run_check "mcp__plugin_github__create_issue" "delete from description"
  [ "$CHECK_EXIT" -eq 0 ]
}

@test "trigger file without lesson field still works" {
  cat > "$GUARDS_DIR/no-lesson.json" <<'EOF'
{"triggers": ["risky"]}
EOF
  cat > "$GUARDS_DIR/no-lesson.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Risky action detected"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/no-lesson.sh"

  run_check "Bash" "risky operation"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"Risky action detected"* ]]
  # No lesson appended
  [[ "$CHECK_STDERR" != *"Lesson:"* ]]
}

# ── Local guards ───────────────────────────────

@test "local guard fires for matching project CWD" {
  mkdir -p "$LOCAL_GUARDS_DIR"
  cat > "$LOCAL_GUARDS_DIR/config-path.json" <<'EOF'
{"triggers": ["config.json"], "lesson": "Config files go in ./config/"}
EOF
  cat > "$LOCAL_GUARDS_DIR/config-path.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Config files should be in ./config/ directory"
exit 1
SCRIPT
  chmod +x "$LOCAL_GUARDS_DIR/config-path.sh"

  run_check "Write" "config.json" "$TEST_CWD"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"Config files should be in ./config/"* ]]
  [[ "$CHECK_STDERR" == *"(local)"* ]]
}

@test "local guard does NOT fire for different project CWD" {
  mkdir -p "$LOCAL_GUARDS_DIR"
  cat > "$LOCAL_GUARDS_DIR/config-path.json" <<'EOF'
{"triggers": ["config.json"], "lesson": "Config files go in ./config/"}
EOF
  cat > "$LOCAL_GUARDS_DIR/config-path.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Config files should be in ./config/ directory"
exit 1
SCRIPT
  chmod +x "$LOCAL_GUARDS_DIR/config-path.sh"

  # Different CWD — local guard should NOT fire
  run_check "Write" "config.json" "/Users/testuser/other-project"
  [ "$CHECK_EXIT" -eq 0 ]
  [ "$CHECK_STDOUT" = "{}" ]
}

@test "global guard fires even when local guards directory does not exist" {
  cat > "$GUARDS_DIR/no-timeout.json" <<'EOF'
{"triggers": ["timeout"], "lesson": "Use gtimeout on macOS"}
EOF
  cat > "$GUARDS_DIR/no-timeout.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "timeout blocked"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/no-timeout.sh"

  # No local guards dir exists — global should still fire
  run_check "Bash" "timeout 5 echo hello" "$TEST_CWD"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"timeout blocked"* ]]
  [[ "$CHECK_STDERR" == *"(global)"* ]]
}

@test "both global and local guards are checked (global fires first)" {
  # Global guard
  cat > "$GUARDS_DIR/no-timeout.json" <<'EOF'
{"triggers": ["timeout"], "lesson": "Global: use gtimeout"}
EOF
  cat > "$GUARDS_DIR/no-timeout.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Global timeout guard"
exit 1
SCRIPT
  chmod +x "$GUARDS_DIR/no-timeout.sh"

  # Local guard for same trigger
  mkdir -p "$LOCAL_GUARDS_DIR"
  cat > "$LOCAL_GUARDS_DIR/no-timeout-local.json" <<'EOF'
{"triggers": ["timeout"], "lesson": "Local: use gtimeout"}
EOF
  cat > "$LOCAL_GUARDS_DIR/no-timeout-local.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Local timeout guard"
exit 1
SCRIPT
  chmod +x "$LOCAL_GUARDS_DIR/no-timeout-local.sh"

  # Global dir is scanned first
  run_check "Bash" "timeout 5 echo hello" "$TEST_CWD"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"Global timeout guard"* ]]
  [[ "$CHECK_STDERR" == *"(global)"* ]]
}

@test "local guard fires when global guard passes" {
  # Global guard that passes
  cat > "$GUARDS_DIR/check-deploy.json" <<'EOF'
{"triggers": ["deploy"], "lesson": "Global deploy check"}
EOF
  cat > "$GUARDS_DIR/check-deploy.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  chmod +x "$GUARDS_DIR/check-deploy.sh"

  # Local guard that blocks
  mkdir -p "$LOCAL_GUARDS_DIR"
  cat > "$LOCAL_GUARDS_DIR/no-deploy-here.json" <<'EOF'
{"triggers": ["deploy"], "lesson": "This project uses a different deploy flow"}
EOF
  cat > "$LOCAL_GUARDS_DIR/no-deploy-here.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Use the custom deploy script in this project"
exit 1
SCRIPT
  chmod +x "$LOCAL_GUARDS_DIR/no-deploy-here.sh"

  run_check "Bash" "deploy production" "$TEST_CWD"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"Use the custom deploy script"* ]]
  [[ "$CHECK_STDERR" == *"(local)"* ]]
}

@test "local guard works when no global guards directory exists" {
  rm -rf "$GUARDS_DIR"
  mkdir -p "$LOCAL_GUARDS_DIR"
  cat > "$LOCAL_GUARDS_DIR/local-only.json" <<'EOF'
{"triggers": ["special"], "lesson": "Local-only guard"}
EOF
  cat > "$LOCAL_GUARDS_DIR/local-only.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "Local guard fired"
exit 1
SCRIPT
  chmod +x "$LOCAL_GUARDS_DIR/local-only.sh"

  run_check "Bash" "special command" "$TEST_CWD"
  [ "$CHECK_EXIT" -eq 2 ]
  [[ "$CHECK_STDERR" == *"Local guard fired"* ]]
}
