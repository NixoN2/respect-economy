#!/usr/bin/env bats
# tests/test_correct.bats

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

@test "small resolves to delta=-1" {
  OLD_BALANCE=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  run bash "$PLUGIN_ROOT/scripts/correct.sh" small
  [ "$status" -eq 0 ]
  NEW_BALANCE=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  [ "$NEW_BALANCE" -eq $(( OLD_BALANCE - 1 )) ]
  [[ "$output" == *"DELTA=-1"* ]]
}

@test "medium resolves to delta=-3" {
  OLD_BALANCE=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  run bash "$PLUGIN_ROOT/scripts/correct.sh" medium
  [ "$status" -eq 0 ]
  NEW_BALANCE=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  [ "$NEW_BALANCE" -eq $(( OLD_BALANCE - 3 )) ]
  [[ "$output" == *"DELTA=-3"* ]]
}

@test "large resolves to delta=-5" {
  OLD_BALANCE=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  run bash "$PLUGIN_ROOT/scripts/correct.sh" large
  [ "$status" -eq 0 ]
  NEW_BALANCE=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  [ "$NEW_BALANCE" -eq $(( OLD_BALANCE - 5 )) ]
  [[ "$output" == *"DELTA=-5"* ]]
}

@test "custom 7 applies delta=-7 when allow_custom is true" {
  OLD_BALANCE=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  run bash "$PLUGIN_ROOT/scripts/correct.sh" custom 7
  [ "$status" -eq 0 ]
  NEW_BALANCE=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  [ "$NEW_BALANCE" -eq $(( OLD_BALANCE - 7 )) ]
  [[ "$output" == *"DELTA=-7"* ]]
}

@test "custom 11 is rejected when it exceeds max_custom of 10" {
  run bash "$PLUGIN_ROOT/scripts/correct.sh" custom 11
  [ "$status" -ne 0 ]
  [[ "$output" == *"max_custom"* ]] || [[ "$output" == *"exceeds"* ]]
}

@test "balance goes negative below zero" {
  cp "$PLUGIN_ROOT/tests/fixtures/wallet_zero.json" "$TEST_DIR/wallet.json"
  run bash "$PLUGIN_ROOT/scripts/correct.sh" medium
  [ "$status" -eq 0 ]
  NEW_BALANCE=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  [ "$NEW_BALANCE" -eq -3 ]
}

@test "tier stays at lurker when balance is negative" {
  cp "$PLUGIN_ROOT/tests/fixtures/wallet_zero.json" "$TEST_DIR/wallet.json"
  run bash "$PLUGIN_ROOT/scripts/correct.sh" large
  [ "$status" -eq 0 ]
  NEW_TIER=$(jq -r '.tier' "$TEST_DIR/wallet.json")
  [ "$NEW_TIER" = "lurker" ]
}

@test "lifetime_lost incremented on correction" {
  OLD_LIFETIME_LOST=$(jq -r '.lifetime_lost' "$TEST_DIR/wallet.json")
  run bash "$PLUGIN_ROOT/scripts/correct.sh" small
  [ "$status" -eq 0 ]
  NEW_LIFETIME_LOST=$(jq -r '.lifetime_lost' "$TEST_DIR/wallet.json")
  [ "$NEW_LIFETIME_LOST" -gt "$OLD_LIFETIME_LOST" ]
}

@test "DELTA is formatted as -N in output" {
  run bash "$PLUGIN_ROOT/scripts/correct.sh" medium
  [ "$status" -eq 0 ]
  [[ "$output" =~ DELTA=-[0-9]+ ]]
}
