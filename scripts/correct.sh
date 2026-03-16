#!/usr/bin/env bash
# correct.sh — apply a correction (negative delta) to the wallet
# Usage: correct.sh <small|medium|large|custom N> [reason text...]
set -euo pipefail

PLUGIN_ROOT="${PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
source "$PLUGIN_ROOT/scripts/lib.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: correct.sh <small|medium|large|custom N> [reason text...]" >&2
  exit 1
fi

SIZE="$1"
shift

if [[ "$SIZE" == "custom" ]]; then
  if [[ $# -lt 1 ]]; then
    echo "Error: 'custom' requires a numeric argument (e.g. custom 7)" >&2
    exit 1
  fi
  CUSTOM_N="$1"
  shift
  if ! [[ "$CUSTOM_N" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: custom amount must be a positive integer, got: $CUSTOM_N" >&2
    exit 1
  fi
  ALLOW_CUSTOM=$(jq -r '.tips.allow_custom' "$CONFIG_FILE")
  if [[ "$ALLOW_CUSTOM" != "true" ]]; then
    echo "Error: custom corrections are not allowed." >&2
    exit 1
  fi
  MAX_CUSTOM=$(jq -r '.tips.max_custom' "$CONFIG_FILE")
  if [[ "$MAX_CUSTOM" != "null" ]] && [[ "$CUSTOM_N" -gt "$MAX_CUSTOM" ]]; then
    echo "Error: custom amount $CUSTOM_N exceeds max_custom ($MAX_CUSTOM)." >&2
    exit 1
  fi
  DELTA="$CUSTOM_N"
else
  DELTA=$(jq -r --arg size "$SIZE" '.tips.sizes[$size] // empty' "$CONFIG_FILE")
  if [[ -z "$DELTA" ]]; then
    echo "Error: unknown correction size '$SIZE'. Use small, medium, large, or custom N." >&2
    exit 1
  fi
fi

REASON="${*:-correction}"

OLD_BALANCE=$(jq -r '.balance' "$WALLET_FILE")
OLD_TIER=$(jq -r '.tier' "$WALLET_FILE")
CURRENT_SESSION=$(jq -r '.sessions' "$WALLET_FILE")
LIFETIME_LOST=$(jq -r '.lifetime_lost' "$WALLET_FILE")

# No floor — reputation can go negative
NEW_BALANCE=$(( OLD_BALANCE - DELTA ))
NEW_LIFETIME_LOST=$(( LIFETIME_LOST + DELTA ))
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

NEW_TIER_INDEX=$(calculate_tier_index "$NEW_BALANCE")
NEW_TIER=$(get_tier_name "$NEW_TIER_INDEX")

NEW_WALLET=$(jq \
  --argjson newbal "$NEW_BALANCE" \
  --arg newtier "$NEW_TIER" \
  --argjson newtieridx "$NEW_TIER_INDEX" \
  --argjson newlifetime_lost "$NEW_LIFETIME_LOST" \
  --arg now "$NOW" \
  --argjson delta "$(( DELTA * -1 ))" \
  --arg reason "$REASON" \
  --argjson session "$CURRENT_SESSION" \
  '.balance = $newbal |
   .tier = $newtier |
   .tier_index = $newtieridx |
   .lifetime_lost = $newlifetime_lost |
   .last_updated = $now |
   .history += [{"date": $now, "delta": $delta, "reason": $reason, "session": $session}]' \
  "$WALLET_FILE")

NEW_WALLET=$(trim_history "$NEW_WALLET")
write_wallet "$NEW_WALLET"

TIER_CHANGED="false"
if [[ "$NEW_TIER" != "$OLD_TIER" ]]; then
  TIER_CHANGED="true"
fi

echo "DELTA=-${DELTA}"
echo "OLD_BALANCE=${OLD_BALANCE}"
echo "NEW_BALANCE=${NEW_BALANCE}"
echo "OLD_TIER=${OLD_TIER}"
echo "NEW_TIER=${NEW_TIER}"
echo "TIER_CHANGED=${TIER_CHANGED}"
