#!/usr/bin/env bash
# lib.sh — shared functions sourced by all respect scripts
set -euo pipefail

# Data directory — overridable via env var for testing
RESPECT_WALLET_DIR="${RESPECT_WALLET_DIR:-$HOME/.claude/respect}"
WALLET_FILE="$RESPECT_WALLET_DIR/wallet.json"
CONFIG_FILE="$RESPECT_WALLET_DIR/config.json"

# calculate_tier_index <balance>
# Returns the highest tier index where min_balance <= balance
calculate_tier_index() {
  local balance="$1"
  jq -r --argjson bal "$balance" \
    '.tiers | to_entries | map(select(.value.min_balance <= $bal)) | last | .key // 0' \
    "$CONFIG_FILE"
}

# get_tier_name <index>
# Returns the tier name for a given index
get_tier_name() {
  local index="$1"
  jq -r --argjson idx "$index" '.tiers[$idx].name' "$CONFIG_FILE"
}

# write_wallet <json_string>
# Atomically writes JSON to WALLET_FILE via temp file in same directory (avoids cross-device mv)
write_wallet() {
  local json="$1"
  local tmp
  tmp=$(mktemp "${WALLET_FILE}.XXXXXX")
  printf '%s\n' "$json" > "$tmp"
  mv "$tmp" "$WALLET_FILE"
}

# trim_history <json_string>
# Returns JSON with history capped at 500 entries (oldest dropped)
trim_history() {
  local json="$1"
  jq 'if (.history | length) > 500 then .history = .history[-500:] else . end' <<< "$json"
}
