#!/usr/bin/env bats
# tests/test_init.bats

setup() {
  # Create a fresh temp dir for each test
  TEST_DIR="$(mktemp -d)"
  export RESPECT_WALLET_DIR="$TEST_DIR"
  # PLUGIN_ROOT needs to point to the repo root so init-wallet.sh can find config.example.json
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "creates wallet.json when missing" {
  run "$PLUGIN_ROOT/scripts/init-wallet.sh"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/wallet.json" ]
}

@test "creates config.json when missing" {
  run "$PLUGIN_ROOT/scripts/init-wallet.sh"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/config.json" ]
}

@test "wallet has balance 0 on fresh create" {
  run "$PLUGIN_ROOT/scripts/init-wallet.sh"
  [ "$status" -eq 0 ]
  result=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  [ "$result" = "0" ]
}

@test "does not overwrite existing wallet.json" {
  printf '{"sentinel": true}\n' > "$TEST_DIR/wallet.json"
  run "$PLUGIN_ROOT/scripts/init-wallet.sh"
  [ "$status" -eq 0 ]
  result=$(jq -r '.sentinel' "$TEST_DIR/wallet.json")
  [ "$result" = "true" ]
}

@test "does not overwrite existing config.json" {
  printf '{"sentinel": true}\n' > "$TEST_DIR/config.json"
  run "$PLUGIN_ROOT/scripts/init-wallet.sh"
  [ "$status" -eq 0 ]
  result=$(jq -r '.sentinel' "$TEST_DIR/config.json")
  [ "$result" = "true" ]
}

@test "creates RESPECT_WALLET_DIR if it does not exist" {
  export RESPECT_WALLET_DIR="$TEST_DIR/nonexistent/subdir"
  run "$PLUGIN_ROOT/scripts/init-wallet.sh"
  [ "$status" -eq 0 ]
  [ -d "$RESPECT_WALLET_DIR" ]
  [ -f "$RESPECT_WALLET_DIR/wallet.json" ]
}
