#!/usr/bin/env bats

setup() {
  export TEST_DIR
  TEST_DIR=$(mktemp -d)
  export RESPECT_WALLET_DIR="$TEST_DIR"
  cp "$BATS_TEST_DIRNAME/fixtures/config_default.json" "$TEST_DIR/config.json"
  # Minimal wallet used as base document for trim_history tests
  printf '{"schema_version":1,"balance":0,"tier":"lurker","tier_index":0,"lifetime_earned":0,"lifetime_lost":0,"sessions":1,"last_updated":"2026-01-01T00:00:00Z","history":[]}\n' \
    > "$TEST_DIR/wallet.json"
  export CLAUDE_PLUGIN_ROOT="$BATS_TEST_DIRNAME/.."
  source "$BATS_TEST_DIRNAME/../scripts/lib.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "balance 0 is tier index 0 (lurker)" {
  result=$(calculate_tier_index 0)
  [ "$result" = "0" ]
}

@test "balance 19 is still tier index 0 (just below contributor threshold)" {
  result=$(calculate_tier_index 19)
  [ "$result" = "0" ]
}

@test "balance 20 is tier index 1 (contributor)" {
  result=$(calculate_tier_index 20)
  [ "$result" = "1" ]
}

@test "balance 60 is tier index 2 (trusted)" {
  result=$(calculate_tier_index 60)
  [ "$result" = "2" ]
}

@test "balance 150 is tier index 3 (veteran)" {
  result=$(calculate_tier_index 150)
  [ "$result" = "3" ]
}

@test "balance 300 is tier index 4 (partner)" {
  result=$(calculate_tier_index 300)
  [ "$result" = "4" ]
}

@test "balance 25 is still tier index 1 (above contributor threshold)" {
  result=$(calculate_tier_index 25)
  [ "$result" = "1" ]
}

@test "balance 80 is still tier index 2 (above trusted threshold)" {
  result=$(calculate_tier_index 80)
  [ "$result" = "2" ]
}

@test "balance 400 is still tier index 4 (above partner threshold)" {
  result=$(calculate_tier_index 400)
  [ "$result" = "4" ]
}

@test "tier recalculates from balance when config thresholds change" {
  jq '.tiers[1].min_balance = 5' "$TEST_DIR/config.json" > "$TEST_DIR/config.json.tmp"
  mv "$TEST_DIR/config.json.tmp" "$TEST_DIR/config.json"
  result=$(calculate_tier_index 10)
  [ "$result" = "1" ]
}

@test "get_tier_name returns correct name for index 0" {
  result=$(get_tier_name 0)
  [ "$result" = "lurker" ]
}

@test "get_tier_name returns correct name for index 2" {
  result=$(get_tier_name 2)
  [ "$result" = "trusted" ]
}

@test "trim_history keeps all entries when under 500" {
  local json
  json=$(jq '.history = [range(10) | {"date": "2026-01-01T00:00:00Z", "delta": 1, "reason": "tip", "session": .}]' "$TEST_DIR/wallet.json")
  result=$(trim_history "$json" | jq '.history | length')
  [ "$result" = "10" ]
}

@test "trim_history trims to 500 when over" {
  local json
  json=$(jq '.history = [range(600) | {"date": "2026-01-01T00:00:00Z", "delta": 1, "reason": "tip", "session": .}]' "$TEST_DIR/wallet.json")
  result=$(trim_history "$json" | jq '.history | length')
  [ "$result" = "500" ]
}

@test "trim_history keeps the LAST 500 entries (oldest dropped)" {
  local json
  json=$(jq '.history = [range(501) | {"date": "2026-01-01T00:00:00Z", "delta": (. + 1), "reason": "tip", "session": .}]' "$TEST_DIR/wallet.json")
  first_delta=$(trim_history "$json" | jq '.history[0].delta')
  [ "$first_delta" = "2" ]
}
