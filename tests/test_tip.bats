#!/usr/bin/env bats
# tests/test_tip.bats

setup() {
  TEST_DIR="$(mktemp -d)"
  export RESPECT_WALLET_DIR="$TEST_DIR"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  cp "$PLUGIN_ROOT/tests/fixtures/config_default.json" "$TEST_DIR/config.json"
  cp "$PLUGIN_ROOT/tests/fixtures/wallet_zero.json" "$TEST_DIR/wallet.json"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# 1. Named size small => delta=1
@test "small tip applies delta=1" {
  run "$PLUGIN_ROOT/scripts/tip.sh" small
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELTA=+1"* ]]
  result=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  [ "$result" = "1" ]
}

# 2. Named size medium => delta=3
@test "medium tip applies delta=3" {
  run "$PLUGIN_ROOT/scripts/tip.sh" medium
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELTA=+3"* ]]
  result=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  [ "$result" = "3" ]
}

# 3. Named size large => delta=5
@test "large tip applies delta=5" {
  run "$PLUGIN_ROOT/scripts/tip.sh" large
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELTA=+5"* ]]
  result=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  [ "$result" = "5" ]
}

# 4. custom 7 applies delta=7 when allow_custom:true
@test "custom 7 applies delta=7" {
  run "$PLUGIN_ROOT/scripts/tip.sh" custom 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELTA=+7"* ]]
  result=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  [ "$result" = "7" ]
}

@test "custom N rejected when allow_custom is false" {
  tmp=$(mktemp)
  jq '.tips.allow_custom = false' "$TEST_DIR/config.json" > "$tmp" && mv "$tmp" "$TEST_DIR/config.json"
  run bash "$PLUGIN_ROOT/scripts/tip.sh" custom 5
  [ "$status" -ne 0 ]
}

# 5. custom 11 rejected (exceeds max_custom=10)
@test "custom 11 is rejected when max_custom=10" {
  run "$PLUGIN_ROOT/scripts/tip.sh" custom 11
  [ "$status" -ne 0 ]
  [[ "$output" == *"max_custom"* ]] || [[ "$output" =~ "exceeds" ]]
}

# 6. require_reason:true blocks tip without reason
@test "require_reason blocks tip with no reason given" {
  tmp=$(mktemp)
  jq '.tips.require_reason = true' "$TEST_DIR/config.json" > "$tmp" && mv "$tmp" "$TEST_DIR/config.json"
  run "$PLUGIN_ROOT/scripts/tip.sh" small
  [ "$status" -ne 0 ]
  [[ "$output" == *"reason"* ]]
}

# 7. max_per_session stops tips at limit
@test "max_per_session=5 blocks tip when session total already at limit" {
  # Set max_per_session=5 in config
  tmp=$(mktemp)
  jq '.tips.max_per_session = 5' "$TEST_DIR/config.json" > "$tmp" && mv "$tmp" "$TEST_DIR/config.json"

  # Build a wallet that already has 5 pts tipped in session 1
  tmp=$(mktemp)
  jq '.sessions = 1 |
      .balance = 5 |
      .lifetime_earned = 5 |
      .history = [
        {"date": "2026-03-15T10:00:00Z", "delta": 5, "reason": "tip", "session": 1}
      ]' "$TEST_DIR/wallet.json" > "$tmp" && mv "$tmp" "$TEST_DIR/wallet.json"

  run "$PLUGIN_ROOT/scripts/tip.sh" small
  [ "$status" -ne 0 ]
  [[ "$output" == *"Remaining: 0"* ]]
}

# 8. History entry appended with correct fields
@test "history entry has correct date, delta, reason, session fields" {
  run "$PLUGIN_ROOT/scripts/tip.sh" medium "great work"
  [ "$status" -eq 0 ]
  entry=$(jq '.history[-1]' "$TEST_DIR/wallet.json")
  delta=$(echo "$entry" | jq -r '.delta')
  reason=$(echo "$entry" | jq -r '.reason')
  session=$(echo "$entry" | jq -r '.session')
  date=$(echo "$entry" | jq -r '.date')
  [ "$delta" = "3" ]
  [ "$reason" = "great work" ]
  [ "$session" = "1" ]
  # date should be non-empty ISO string
  [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

# 9. History capped at 500 entries
@test "history is capped at 500 entries after exceeding limit" {
  # Build wallet with 499 history entries
  history_entries=$(python3 -c "
import json
entries = [{'date': '2026-03-15T10:00:00Z', 'delta': 1, 'reason': 'tip', 'session': 1} for _ in range(499)]
print(json.dumps(entries))
")
  tmp=$(mktemp)
  jq --argjson hist "$history_entries" \
    '.balance = 499 | .lifetime_earned = 499 | .history = $hist' \
    "$TEST_DIR/wallet.json" > "$tmp" && mv "$tmp" "$TEST_DIR/wallet.json"

  # Add one more -> 500 total, still ok
  run "$PLUGIN_ROOT/scripts/tip.sh" small
  [ "$status" -eq 0 ]
  count=$(jq '.history | length' "$TEST_DIR/wallet.json")
  [ "$count" -eq 500 ]

  # Add another -> still 500 (oldest dropped)
  run "$PLUGIN_ROOT/scripts/tip.sh" small
  [ "$status" -eq 0 ]
  count=$(jq '.history | length' "$TEST_DIR/wallet.json")
  [ "$count" -eq 500 ]
}

# 10. Tier changes correctly when tipping past threshold
@test "tier changes correctly after tipping past threshold" {
  # pre-seed wallet at balance=19 (one away from contributor at 20)
  jq '.balance = 19 | .tier = "lurker" | .tier_index = 0' "$TEST_DIR/wallet.json" > "$TEST_DIR/wallet.json.tmp" && mv "$TEST_DIR/wallet.json.tmp" "$TEST_DIR/wallet.json"
  run bash "$PLUGIN_ROOT/scripts/tip.sh" medium  # medium=3, new balance=22
  [ "$status" -eq 0 ]
  [[ "$output" == *"TIER_CHANGED=true"* ]]
  [[ "$output" == *"NEW_TIER=contributor"* ]]
}
