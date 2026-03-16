# Status Line Integration

Add this snippet to `~/.claude/statusline.sh` to show the respect balance in the status line:

```bash
# Respect Economy status
WALLET="$HOME/.claude/respect/wallet.json"
R_CONFIG="$HOME/.claude/respect/config.json"
if [ -f "$WALLET" ] && [ -f "$R_CONFIG" ]; then
  R_BALANCE=$(jq -r '.balance // 0' "$WALLET")
  R_NAME=$(jq -r '.tier // ""' "$WALLET")
  R_EMOJI=$(jq -r --arg name "$R_NAME" '.tiers[] | select(.name == $name) | .emoji // ""' "$R_CONFIG")
  R_FORMAT=$(jq -r '.statusline.format // "{emoji} {balance} ({name})"' "$R_CONFIG")
  R_STATUS=$(echo "$R_FORMAT" | sed "s/{emoji}/$R_EMOJI/g; s/{balance}/$R_BALANCE/g; s/{name}/$R_NAME/g")
  STATUS="$STATUS | $R_STATUS"
fi
```

**Known limitation:** The snippet reads the cached `tier` name from wallet.json rather than recalculating from balance. If you edit tier thresholds in config.json, the displayed tier may be stale until the next session start (which recalculates and updates the cached value).
