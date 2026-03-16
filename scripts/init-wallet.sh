#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
source "$PLUGIN_ROOT/scripts/lib.sh"

# Create wallet dir if needed
mkdir -p "$RESPECT_WALLET_DIR"

# Create wallet.json if missing
if [ ! -f "$WALLET_FILE" ]; then
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  WALLET_JSON=$(jq -n \
    --arg now "$NOW" \
    '{schema_version: 1, balance: 0, tier: "lurker", tier_index: 0,
      lifetime_earned: 0, lifetime_lost: 0, sessions: 0,
      last_updated: $now, history: []}')
  write_wallet "$WALLET_JSON"
fi

# Create config.json if missing
if [ ! -f "$CONFIG_FILE" ]; then
  cp "$PLUGIN_ROOT/config.example.json" "$CONFIG_FILE"
fi
