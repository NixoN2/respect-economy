#!/usr/bin/env bats
# tests/test_session_start.bats

setup() {
  TEST_DIR="$(mktemp -d)"
  export RESPECT_WALLET_DIR="$TEST_DIR"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  cp "$PLUGIN_ROOT/tests/fixtures/config_default.json" "$TEST_DIR/config.json"
  cp "$PLUGIN_ROOT/tests/fixtures/wallet_trusted.json" "$TEST_DIR/wallet.json"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: extract AI context (additionalContext)
get_ai_ctx() {
  echo "$output" | jq -r '.hookSpecificOutput.additionalContext'
}

# Helper: extract user-visible message (systemMessage)
get_user_msg() {
  echo "$output" | jq -r '.systemMessage'
}

# ── AI context (additionalContext) ──────────────

@test "AI context contains correct tier name for trusted wallet" {
  run bash "$PLUGIN_ROOT/scripts/session-start.sh"
  [ "$status" -eq 0 ]
  ctx=$(get_ai_ctx)
  [[ "$ctx" == *"trusted"* ]]
}

@test "AI context contains tier emoji" {
  run bash "$PLUGIN_ROOT/scripts/session-start.sh"
  [ "$status" -eq 0 ]
  ctx=$(get_ai_ctx)
  [[ "$ctx" == *"⚡"* ]]
}

@test "AI context contains pattern analysis fields" {
  run bash "$PLUGIN_ROOT/scripts/session-start.sh"
  [ "$status" -eq 0 ]
  ctx=$(get_ai_ctx)
  [[ "$ctx" == *"Avg tip: 4.5"* ]]
  [[ "$ctx" == *"Corrections last 10 sessions: 1"* ]]
  [[ "$ctx" == *"improving (+15 last 3 sessions)"* ]]
  [[ "$ctx" == *"Largest tips:"* ]]
}

@test "session counter increments on each run" {
  run bash "$PLUGIN_ROOT/scripts/session-start.sh"
  [ "$status" -eq 0 ]
  sessions=$(jq -r '.sessions' "$TEST_DIR/wallet.json")
  [ "$sessions" -eq 6 ]

  run bash "$PLUGIN_ROOT/scripts/session-start.sh"
  [ "$status" -eq 0 ]
  sessions=$(jq -r '.sessions' "$TEST_DIR/wallet.json")
  [ "$sessions" -eq 7 ]
}

@test "empty history wallet produces valid AI context" {
  cp "$PLUGIN_ROOT/tests/fixtures/wallet_zero.json" "$TEST_DIR/wallet.json"
  run bash "$PLUGIN_ROOT/scripts/session-start.sh"
  [ "$status" -eq 0 ]
  ctx=$(get_ai_ctx)
  [[ "$ctx" == *"Respect wallet context"* ]]
  [[ "$ctx" == *"lurker"* ]]
}

# ── Output structure ──────────────────────────

@test "output has correct hook JSON structure" {
  run bash "$PLUGIN_ROOT/scripts/session-start.sh"
  [ "$status" -eq 0 ]
  # Must have systemMessage and hookSpecificOutput
  echo "$output" | jq -e '.systemMessage' >/dev/null
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName' >/dev/null

  # hookEventName must be SessionStart
  event=$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName')
  [ "$event" = "SessionStart" ]

  # systemMessage is user-visible (clean, no detailed history)
  user_msg=$(get_user_msg)
  [[ "$user_msg" == *"Balance:"* ]]
  [[ "$user_msg" != *"Recent history"* ]]

  # additionalContext is AI-only (contains detailed context)
  ctx=$(get_ai_ctx)
  [[ "$ctx" == *"Recent history"* ]]
}

@test "user message shows tier emoji and name" {
  run bash "$PLUGIN_ROOT/scripts/session-start.sh"
  [ "$status" -eq 0 ]
  user_msg=$(get_user_msg)
  [[ "$user_msg" == *"⚡"* ]]
  [[ "$user_msg" == *"trusted"* ]]
}

# ── First-run onboarding ──────────────────────

@test "first run shows welcome message to user" {
  cp "$PLUGIN_ROOT/tests/fixtures/wallet_fresh.json" "$TEST_DIR/wallet.json"
  run bash "$PLUGIN_ROOT/scripts/session-start.sh"
  [ "$status" -eq 0 ]
  user_msg=$(get_user_msg)
  [[ "$user_msg" == *"Welcome to the respect economy"* ]]
  [[ "$user_msg" == *"/tip"* ]]
  [[ "$user_msg" == *"/oops"* ]]
}

@test "first run includes first-session context in AI context" {
  cp "$PLUGIN_ROOT/tests/fixtures/wallet_fresh.json" "$TEST_DIR/wallet.json"
  run bash "$PLUGIN_ROOT/scripts/session-start.sh"
  [ "$status" -eq 0 ]
  ctx=$(get_ai_ctx)
  [[ "$ctx" == *"FIRST SESSION"* ]]
}

@test "second session does not show welcome message" {
  # wallet_zero has sessions=1, so after increment it will be 2
  cp "$PLUGIN_ROOT/tests/fixtures/wallet_zero.json" "$TEST_DIR/wallet.json"
  run bash "$PLUGIN_ROOT/scripts/session-start.sh"
  [ "$status" -eq 0 ]
  user_msg=$(get_user_msg)
  [[ "$user_msg" != *"Welcome to the respect economy"* ]]
}

# ── Global learnings ──────────────────────────

@test "global learnings are included in AI context when file exists" {
  mkdir -p "$TEST_DIR/.claude/respect"
  cat > "$TEST_DIR/.claude/respect/global-feedback.md" <<'EOF'
# Global Respect Feedback

## Learnings

### 2026-03-15 | Push before version bump (+5)
**Lesson:** Push repository changes before version bumping
**Context:** Publishing plugin updates
**Why:** Prevents version conflicts
**Session:** 10

## Mistakes to Avoid

### 2026-03-15 | timeout missing on macOS (-3)
**Lesson:** Don't use timeout command on macOS
**Context:** Shell scripting
**Why:** Command not found errors
**Session:** 12
EOF

  # The script uses $RESPECT_WALLET_DIR/global-feedback.md
  cp "$TEST_DIR/.claude/respect/global-feedback.md" "$TEST_DIR/global-feedback.md"

  run bash "$PLUGIN_ROOT/scripts/session-start.sh"
  [ "$status" -eq 0 ]
  ctx=$(get_ai_ctx)
  [[ "$ctx" == *"Global learnings"* ]]
  [[ "$ctx" == *"Push repository changes before version bumping"* ]]
  [[ "$ctx" == *"timeout"* ]]
}

@test "AI context works fine without global feedback file" {
  # No global-feedback.md exists in TEST_DIR
  run bash "$PLUGIN_ROOT/scripts/session-start.sh"
  [ "$status" -eq 0 ]
  ctx=$(get_ai_ctx)
  [[ "$ctx" != *"Global learnings"* ]]
  # But normal content still present
  [[ "$ctx" == *"Respect wallet context"* ]]
}
