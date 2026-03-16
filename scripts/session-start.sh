#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
source "$PLUGIN_ROOT/scripts/lib.sh"

# 1. Ensure data files exist
bash "$PLUGIN_ROOT/scripts/init-wallet.sh"

# Write plugin root to wallet dir so skills can find scripts
echo "$PLUGIN_ROOT" > "$RESPECT_WALLET_DIR/plugin_root"

# 2. Increment sessions counter atomically
CURRENT_SESSIONS=$(jq -r '.sessions // 0' "$WALLET_FILE")
NEW_SESSIONS=$(( CURRENT_SESSIONS + 1 ))
WALLET_JSON=$(jq --argjson s "$NEW_SESSIONS" '.sessions = $s' "$WALLET_FILE")
write_wallet "$WALLET_JSON"

# 3. Read data
BALANCE=$(jq -r '.balance // 0' "$WALLET_FILE")

# 4. Recalculate tier
TIER_INDEX=$(calculate_tier_index "$BALANCE")
TIER_NAME=$(get_tier_name "$TIER_INDEX")
TIER_EMOJI=$(jq -r --argjson idx "$TIER_INDEX" '.tiers[$idx].emoji // ""' "$CONFIG_FILE")

# 5. Update tier in wallet
WALLET_JSON=$(jq --arg name "$TIER_NAME" --argjson idx "$TIER_INDEX" \
  '.tier = $name | .tier_index = $idx' "$WALLET_FILE")
write_wallet "$WALLET_JSON"

# 6. Pattern analysis

# Avg tip size: mean of all positive deltas
AVG_TIP=$(jq '[.history[] | select(.delta > 0) | .delta] |
  if length > 0 then
    (add / length * 10 | floor) / 10
  else
    0
  end' "$WALLET_FILE")

# Correction frequency: negative deltas in last 10 sessions
CORRECTIONS_LAST_10=$(jq --argjson sess "$NEW_SESSIONS" \
  '[.history[] | select(.delta < 0 and .session > ($sess - 10))] | length' \
  "$WALLET_FILE")

# Top tip reasons: up to 3, delta > 0, reason != "tip", sorted by delta desc
TOP_REASONS_RAW=$(jq -r '[.history[] | select(.delta > 0 and .reason != "tip")] |
  sort_by(-.delta) | .[0:3] |
  .[] | "\"\(.reason)\" (+\(.delta) s\(.session))"' "$WALLET_FILE")

if [ -z "$TOP_REASONS_RAW" ]; then
  TOP_REASONS_LINE="None"
else
  # Join lines with ", "
  TOP_REASONS_LINE=$(echo "$TOP_REASONS_RAW" | paste -sd ', ' -)
fi

# Net trend: sum of deltas in last 3 sessions
LAST_3_TREND=$(jq --argjson sess "$NEW_SESSIONS" \
  '[.history[] | select(.session > ($sess - 3)) | .delta] | add // 0' \
  "$WALLET_FILE")

if [ "$LAST_3_TREND" -ge 0 ]; then
  TREND_LINE="improving (+${LAST_3_TREND} last 3 sessions)"
else
  TREND_LINE="declining (${LAST_3_TREND} last 3 sessions)"
fi

# 7. Recent history (last 3 entries, most recent first)
RECENT_RAW=$(jq -r '.history[-3:] | reverse | .[] |
  (if .delta >= 0 then "+\(.delta)" else "\(.delta)" end) + " " + .reason + " (s\(.session))"' \
  "$WALLET_FILE")

if [ -z "$RECENT_RAW" ]; then
  RECENT_LINE="(none)"
else
  RECENT_LINE=$(echo "$RECENT_RAW" | paste -sd ', ' -)
fi

# 8. Build user-visible message (clean summary)
USER_MSG="${TIER_EMOJI} ${TIER_NAME} | Balance: ${BALANCE}

Performance patterns:
- Avg tip: ${AVG_TIP} pts | Corrections last 10 sessions: ${CORRECTIONS_LAST_10}
- Net trend: ${TREND_LINE}"

# 9. Build AI-only system message (context for learning)
AI_MSG="Respect wallet context for session ${NEW_SESSIONS}:
${TIER_EMOJI} ${TIER_NAME} (tier_index: ${TIER_INDEX}) | Balance: ${BALANCE}

Recent history (last 3):
${RECENT_RAW}

Performance patterns:
- Avg tip: ${AVG_TIP} pts | Corrections last 10 sessions: ${CORRECTIONS_LAST_10}
- Largest tips: ${TOP_REASONS_LINE}
- Net trend: ${TREND_LINE}

When asked about performance, feedback, tips, corrections, or what you did well/poorly:
- Reference the wallet data shown above (Recent, Largest tips, patterns)
- Tips show what the user valued - learn from these successes
- Corrections show mistakes to avoid - learn from these failures
- Use this feedback to understand user preferences and improve"

# 10. Load global learnings (cross-project)
GLOBAL_FEEDBACK="$RESPECT_WALLET_DIR/global-feedback.md"
GLOBAL_LEARNINGS=""

if [ -f "$GLOBAL_FEEDBACK" ]; then
  # Extract lessons from both sections
  GLOBAL_LESSONS=$(sed -n '/^\*\*Lesson:\*\*/p' "$GLOBAL_FEEDBACK" | sed 's/\*\*Lesson:\*\* /- /' | head -10) || true
  if [ -n "$GLOBAL_LESSONS" ]; then
    GLOBAL_LEARNINGS="
Global learnings (apply in all projects):
${GLOBAL_LESSONS}"
  fi
fi

AI_MSG="${AI_MSG}${GLOBAL_LEARNINGS}"

# 11. Detect first run for welcome message
IS_FIRST_RUN=false
if [ "$NEW_SESSIONS" -eq 1 ]; then
  IS_FIRST_RUN=true
fi

if [ "$IS_FIRST_RUN" = true ]; then
  USER_MSG="Welcome to the respect economy!

Use /tip when Claude does good work, /oops when it makes a mistake.
Tips and corrections become persistent learnings that improve Claude over time.

Type /respect-stats for analytics, /respect-export to export your preferences.

${USER_MSG}"

  AI_MSG="FIRST SESSION: The user just installed the respect economy plugin. Be helpful and demonstrate value. Mention that tips and corrections help you learn and improve over time.

${AI_MSG}"
fi

# 12. Clean up any behavior instructions from MEMORY.md (legacy)
ENCODED_CWD=$(pwd | tr '/.' '-')
MEMORY_DIR="$HOME/.claude/projects/$ENCODED_CWD/memory"

if [ -d "$MEMORY_DIR" ] && [ -f "$MEMORY_DIR/MEMORY.md" ]; then
  sed -i '' '/^## Respect Behavior Instructions$/,/^## [^R]/{ /^## [^R]/!d; }' "$MEMORY_DIR/MEMORY.md" 2>/dev/null || true
  sed -i '' '/^## Respect Behavior Instructions$/,$ { /^## Respect Behavior Instructions$/d; /^$/d; /^[^#]/d; }' "$MEMORY_DIR/MEMORY.md" 2>/dev/null || true
fi

# 13. Output: systemMessage = user-visible, additionalContext = AI-only
jq -n \
  --arg user "$USER_MSG" \
  --arg ai "$AI_MSG" \
  '{
    systemMessage: $user,
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: $ai
    }
  }'
