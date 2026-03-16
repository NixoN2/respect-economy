#!/usr/bin/env bash
# tip.sh — apply a tip to the wallet
# Usage: tip.sh <small|medium|large|custom> [N] [reason text...]
set -euo pipefail

PLUGIN_ROOT="${PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
source "$PLUGIN_ROOT/scripts/lib.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: tip.sh <small|medium|large|custom N> [reason text...]" >&2
  exit 1
fi

SIZE="$1"
shift

# Determine delta and consume extra arg for custom
if [[ "$SIZE" == "custom" ]]; then
  if [[ $# -lt 1 ]]; then
    echo "Error: 'custom' requires a numeric argument (e.g. custom 7)" >&2
    exit 1
  fi
  CUSTOM_N="$1"
  shift
  # Validate: must be a positive integer
  if ! [[ "$CUSTOM_N" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: custom amount must be a positive integer, got: $CUSTOM_N" >&2
    exit 1
  fi
  # Check allow_custom
  ALLOW_CUSTOM=$(jq -r '.tips.allow_custom' "$CONFIG_FILE")
  if [[ "$ALLOW_CUSTOM" != "true" ]]; then
    echo "Error: custom tips are not allowed." >&2
    exit 1
  fi
  # Check max_custom
  MAX_CUSTOM=$(jq -r '.tips.max_custom' "$CONFIG_FILE")
  if [[ "$MAX_CUSTOM" != "null" ]] && [[ "$CUSTOM_N" -gt "$MAX_CUSTOM" ]]; then
    echo "Error: custom amount $CUSTOM_N exceeds max_custom ($MAX_CUSTOM)." >&2
    exit 1
  fi
  DELTA="$CUSTOM_N"
else
  # Named size: small / medium / large
  DELTA=$(jq -r --arg size "$SIZE" '.tips.sizes[$size] // empty' "$CONFIG_FILE")
  if [[ -z "$DELTA" ]]; then
    echo "Error: unknown tip size '$SIZE'. Use small, medium, large, or custom N." >&2
    exit 1
  fi
fi

# Remaining args are the reason (may be empty)
REASON="${*:-tip}"

# ---------------------------------------------------------------------------
# Validate require_reason
# ---------------------------------------------------------------------------
REQUIRE_REASON=$(jq -r '.tips.require_reason' "$CONFIG_FILE")
if [[ "$REQUIRE_REASON" == "true" ]] && [[ $# -eq 0 ]]; then
  echo "Error: a reason is required for tips (tips.require_reason is true)."
  exit 1
fi

# ---------------------------------------------------------------------------
# Read wallet
# ---------------------------------------------------------------------------
CURRENT_SESSION=$(jq -r '.sessions' "$WALLET_FILE")
OLD_BALANCE=$(jq -r '.balance' "$WALLET_FILE")
OLD_TIER_INDEX=$(jq -r '.tier_index' "$WALLET_FILE")
OLD_TIER=$(jq -r '.tier' "$WALLET_FILE")
LIFETIME_EARNED=$(jq -r '.lifetime_earned' "$WALLET_FILE")

# ---------------------------------------------------------------------------
# Enforce max_per_session
# ---------------------------------------------------------------------------
MAX_PER_SESSION=$(jq -r '.tips.max_per_session // "null"' "$CONFIG_FILE")
if [[ "$MAX_PER_SESSION" != "null" ]]; then
  SESSION_TOTAL=$(jq --argjson sess "$CURRENT_SESSION" \
    '[.history[] | select(.session == $sess and .delta > 0) | .delta] | add // 0' \
    "$WALLET_FILE")
  REMAINING=$((MAX_PER_SESSION - SESSION_TOTAL))
  if [[ $REMAINING -le 0 ]]; then
    echo "Session tip budget reached. Remaining: 0 pts." >&2
    exit 1
  fi
  ORIGINAL_DELTA=$DELTA
  if [[ $DELTA -gt $REMAINING ]]; then
    echo "Tip capped to session budget. Applying ${REMAINING} of ${ORIGINAL_DELTA} pts."
    DELTA=$REMAINING
  fi
fi

# ---------------------------------------------------------------------------
# Compute new state
# ---------------------------------------------------------------------------
NEW_BALANCE=$((OLD_BALANCE + DELTA))
NEW_LIFETIME_EARNED=$((LIFETIME_EARNED + DELTA))
NEW_TIER_INDEX=$(calculate_tier_index "$NEW_BALANCE")
NEW_TIER=$(get_tier_name "$NEW_TIER_INDEX")
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ---------------------------------------------------------------------------
# Build new wallet JSON (append history entry, update fields)
# ---------------------------------------------------------------------------
NEW_WALLET=$(jq \
  --argjson newbal "$NEW_BALANCE" \
  --arg newtier "$NEW_TIER" \
  --argjson newtieridx "$NEW_TIER_INDEX" \
  --argjson newlifetime "$NEW_LIFETIME_EARNED" \
  --arg now "$NOW" \
  --argjson delta "$DELTA" \
  --arg reason "$REASON" \
  --argjson session "$CURRENT_SESSION" \
  '.balance = $newbal |
   .tier = $newtier |
   .tier_index = $newtieridx |
   .lifetime_earned = $newlifetime |
   .last_updated = $now |
   .history += [{"date": $now, "delta": $delta, "reason": $reason, "session": $session}]' \
  "$WALLET_FILE")

NEW_WALLET=$(trim_history "$NEW_WALLET")
write_wallet "$NEW_WALLET"

# ---------------------------------------------------------------------------
# Print structured output
# ---------------------------------------------------------------------------
TIER_CHANGED="false"
if [[ "$NEW_TIER" != "$OLD_TIER" ]]; then
  TIER_CHANGED="true"
fi

if [[ $DELTA -ge 0 ]]; then
  DELTA_STR="+${DELTA}"
else
  DELTA_STR="${DELTA}"
fi

echo "DELTA=${DELTA_STR}"
echo "OLD_BALANCE=${OLD_BALANCE}"
echo "NEW_BALANCE=${NEW_BALANCE}"
echo "OLD_TIER=${OLD_TIER}"
echo "NEW_TIER=${NEW_TIER}"
echo "TIER_CHANGED=${TIER_CHANGED}"
