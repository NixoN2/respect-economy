# Respect Economy Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code plugin that implements a persistent respect economy — users tip Claude via `/tip`, the balance determines behavior tiers, corrections decrement it, and the current state is visible in the status line.

**Architecture:** All wallet accounting lives in bash scripts (`tip.sh`, `detect-feedback.sh`, `session-start.sh`); Claude is only a UI relay that never writes to `wallet.json` directly. A shared `lib.sh` provides common functions and uses `RESPECT_WALLET_DIR` env var for testability. Tests use bats-core with fixture files in a temp directory — no live `~/.claude/` files touched.

**Tech Stack:** bash, jq, bats-core (testing), Claude Code plugin system (hooks + skills)

---

## File Map

| File | Responsibility |
|---|---|
| `scripts/lib.sh` | Shared vars (`WALLET_FILE`, `CONFIG_FILE`), `calculate_tier_index`, `get_tier_name`, `write_wallet`, `trim_history` |
| `scripts/init-wallet.sh` | Creates `wallet.json` and `config.json` on first run, idempotent per-file |
| `scripts/tip.sh` | All tip accounting: resolve size, validate, update balance, write atomically, print structured result |
| `scripts/detect-feedback.sh` | Reads stdin JSON, detects correction patterns, decrements balance |
| `scripts/session-start.sh` | SessionStart hook: calls init, increments session, computes patterns, outputs `{"systemMessage": "..."}` |
| `skills/tip/skill.md` | `/tip` slash command — calls `tip.sh`, relays result conversationally |
| `skills/respect-setup/skill.md` | `/respect-setup` onboarding wizard — writes `config.json` interactively |
| `hooks/hooks.json` | Wires `SessionStart` → `session-start.sh`, `UserPromptSubmit` → `detect-feedback.sh` |
| `plugin.json` | Plugin manifest |
| `config.example.json` | Heavily commented reference config, copied by `init-wallet.sh` on first run |
| `docs/statusline-snippet.md` | Copy-paste snippet for `~/.claude/statusline.sh` |
| `tests/fixtures/wallet_zero.json` | Fixture: balance 0, no history |
| `tests/fixtures/wallet_trusted.json` | Fixture: balance 35, tier trusted, some history |
| `tests/fixtures/config_default.json` | Fixture: default config |
| `tests/test_tiers.bats` | Unit: tier calculation boundaries |
| `tests/test_tip.bats` | Unit: tip sizes, limits, history append |
| `tests/test_corrections.bats` | Unit: correction patterns, floor, lifetime_lost |
| `tests/test_session_start.bats` | Integration: system message content, session counter |
| `README.md` | Install instructions, usage, statusline setup |

---

## Chunk 1: Foundation

### Task 1: Project scaffold and bats install

**Files:**
- Create: `respect/` directory structure

- [ ] **Step 1: Initialize git repo and create directory structure**

```bash
cd ~/study/respect
git init
mkdir -p scripts skills/tip skills/respect-setup hooks tests/fixtures docs
```

- [ ] **Step 2: Install bats-core**

```bash
brew install bats-core
bats --version
```
Expected output: `Bats 1.x.x`

- [ ] **Step 3: Create .gitignore**

```
.DS_Store
*.swp
```

- [ ] **Step 4: Initial commit**

```bash
git add .gitignore
git commit -m "chore: initialize respect plugin repo"
```

---

### Task 2: Test fixtures

**Files:**
- Create: `tests/fixtures/wallet_zero.json`
- Create: `tests/fixtures/wallet_trusted.json`
- Create: `tests/fixtures/config_default.json`

- [ ] **Step 1: Write wallet_zero.json**

```json
{
  "schema_version": 1,
  "balance": 0,
  "tier": "lurker",
  "tier_index": 0,
  "lifetime_earned": 0,
  "lifetime_lost": 0,
  "sessions": 1,
  "last_updated": "2026-03-15T10:00:00Z",
  "history": []
}
```

- [ ] **Step 2: Write wallet_trusted.json**

```json
{
  "schema_version": 1,
  "balance": 35,
  "tier": "trusted",
  "tier_index": 2,
  "lifetime_earned": 36,
  "lifetime_lost": 1,
  "sessions": 5,
  "last_updated": "2026-03-15T10:00:00Z",
  "history": [
    {"date": "2026-03-14T09:00:00Z", "delta": 5, "reason": "great debugging", "session": 1},
    {"date": "2026-03-14T10:00:00Z", "delta": 5, "reason": "perfect explanation", "session": 2},
    {"date": "2026-03-15T08:00:00Z", "delta": 5, "reason": "tip", "session": 3},
    {"date": "2026-03-15T09:00:00Z", "delta": -1, "reason": "correction", "session": 4},
    {"date": "2026-03-15T09:30:00Z", "delta": 5, "reason": "tip", "session": 4},
    {"date": "2026-03-15T10:00:00Z", "delta": 3, "reason": "tip", "session": 5},
    {"date": "2026-03-15T10:05:00Z", "delta": 5, "reason": "excellent", "session": 5},
    {"date": "2026-03-15T10:10:00Z", "delta": 3, "reason": "tip", "session": 5}
  ]
}
```

Note: 5+5+5-1+5+3+5+3 = 30. Use balance: 30 instead of 35 to stay consistent.

- [ ] **Step 3: Correct wallet_trusted.json balance to match history**

Set `"balance": 30` in `wallet_trusted.json`. Tier `trusted` requires `min_balance: 11`, so balance 30 is in `contributor` range (11–30). Use balance 35 by adding one more `+5` history entry:

Final `wallet_trusted.json` history totals: 5+5+5+5-1+5+3+5+3 = 35. Add one more entry:
```json
{"date": "2026-03-14T11:00:00Z", "delta": 5, "reason": "tip", "session": 2}
```
Total: 5+5+5+5-1+5+3+5+3 = 35, `lifetime_earned`: 41, `lifetime_lost`: 1 (41-1=40, not 35).

Simplest approach: use balance 20 for `contributor` tier in `wallet_trusted.json` and rename to `wallet_contributor.json`, and create a separate `wallet_trusted.json` with balance 35.

**Revised fixtures:**

`tests/fixtures/wallet_contributor.json` (balance 20, tier contributor):
```json
{
  "schema_version": 1,
  "balance": 20,
  "tier": "contributor",
  "tier_index": 1,
  "lifetime_earned": 21,
  "lifetime_lost": 1,
  "sessions": 3,
  "last_updated": "2026-03-15T10:00:00Z",
  "history": [
    {"date": "2026-03-14T09:00:00Z", "delta": 5, "reason": "great debugging", "session": 1},
    {"date": "2026-03-14T10:00:00Z", "delta": 5, "reason": "tip", "session": 2},
    {"date": "2026-03-15T09:00:00Z", "delta": -1, "reason": "correction", "session": 3},
    {"date": "2026-03-15T09:30:00Z", "delta": 5, "reason": "tip", "session": 3},
    {"date": "2026-03-15T10:00:00Z", "delta": 3, "reason": "tip", "session": 3},
    {"date": "2026-03-15T10:05:00Z", "delta": 3, "reason": "excellent work", "session": 3}
  ]
}
```
(5+5-1+5+3+3 = 20 ✓, lifetime_earned: 5+5+5+3+3=21, lifetime_lost: 1)

`tests/fixtures/wallet_trusted.json` (balance 35, tier trusted):
```json
{
  "schema_version": 1,
  "balance": 35,
  "tier": "trusted",
  "tier_index": 2,
  "lifetime_earned": 36,
  "lifetime_lost": 1,
  "sessions": 5,
  "last_updated": "2026-03-15T10:00:00Z",
  "history": [
    {"date": "2026-03-13T09:00:00Z", "delta": 5, "reason": "great debugging", "session": 1},
    {"date": "2026-03-13T10:00:00Z", "delta": 5, "reason": "perfect explanation", "session": 1},
    {"date": "2026-03-14T09:00:00Z", "delta": 5, "reason": "tip", "session": 2},
    {"date": "2026-03-14T10:00:00Z", "delta": 5, "reason": "tip", "session": 3},
    {"date": "2026-03-15T09:00:00Z", "delta": 5, "reason": "tip", "session": 4},
    {"date": "2026-03-15T09:30:00Z", "delta": 5, "reason": "tip", "session": 4},
    {"date": "2026-03-15T10:00:00Z", "delta": -1, "reason": "correction", "session": 5},
    {"date": "2026-03-15T10:05:00Z", "delta": 5, "reason": "excellent", "session": 5},
    {"date": "2026-03-15T10:10:00Z", "delta": 1, "reason": "tip", "session": 5}
  ]
}
```
(5+5+5+5+5+5-1+5+1 = 35 ✓, lifetime_earned: 36, lifetime_lost: 1)

- [ ] **Step 4: Write config_default.json** (identical to the shipped default, used in all tests)

```json
{
  "schema_version": 1,
  "tiers": [
    { "name": "lurker",      "min_balance": 0,   "emoji": "👤" },
    { "name": "contributor", "min_balance": 11,  "emoji": "🌱" },
    { "name": "trusted",     "min_balance": 31,  "emoji": "⚡" },
    { "name": "veteran",     "min_balance": 61,  "emoji": "🔥" },
    { "name": "partner",     "min_balance": 101, "emoji": "🤝" }
  ],
  "behaviors": [
    {
      "id": "effort_scaling",
      "enabled": true,
      "min_tier": 1,
      "instruction": "Apply thorough reasoning. Do not abbreviate steps or skip explanations."
    },
    {
      "id": "suggestion_latitude",
      "enabled": true,
      "min_tier": 2,
      "instruction": "Proactively suggest improvements, refactors, and architecture ideas even when not asked."
    },
    {
      "id": "deep_insights",
      "enabled": true,
      "min_tier": 3,
      "instruction": "Provide educational insights about implementation choices. Explain the why behind decisions."
    },
    {
      "id": "confirmation_reduction",
      "enabled": false,
      "min_tier": 4,
      "instruction": "Proceed with multi-step actions without asking for confirmation on each step."
    }
  ],
  "corrections": {
    "enabled": true,
    "sensitivity": "medium",
    "delta": -1,
    "custom_patterns": []
  },
  "tips": {
    "sizes": {
      "small":  1,
      "medium": 3,
      "large":  5
    },
    "allow_custom": true,
    "max_custom": 10,
    "max_per_session": null,
    "require_reason": false
  },
  "statusline": {
    "format": "{emoji} {balance} ({name})"
  }
}
```

- [ ] **Step 5: Verify fixtures are valid JSON**

```bash
for f in tests/fixtures/*.json; do jq empty "$f" && echo "OK: $f"; done
```
Expected: `OK: ...` for each file, no errors.

- [ ] **Step 6: Commit fixtures**

```bash
git add tests/fixtures/
git commit -m "test: add wallet and config fixtures"
```

---

### Task 3: lib.sh — shared functions

**Files:**
- Create: `scripts/lib.sh`

- [ ] **Step 1: Write failing tier test first** (`tests/test_tiers.bats`)

```bash
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

@test "balance 10 is still tier index 0 (just below contributor threshold)" {
  result=$(calculate_tier_index 10)
  [ "$result" = "0" ]
}

@test "balance 11 is tier index 1 (contributor)" {
  result=$(calculate_tier_index 11)
  [ "$result" = "1" ]
}

@test "balance 31 is tier index 2 (trusted)" {
  result=$(calculate_tier_index 31)
  [ "$result" = "2" ]
}

@test "balance 61 is tier index 3 (veteran)" {
  result=$(calculate_tier_index 61)
  [ "$result" = "3" ]
}

@test "balance 101 is tier index 4 (partner)" {
  result=$(calculate_tier_index 101)
  [ "$result" = "4" ]
}

@test "balance 12 is still tier index 1 (above contributor threshold)" {
  result=$(calculate_tier_index 12)
  [ "$result" = "1" ]
}

@test "balance 32 is still tier index 2 (above trusted threshold)" {
  result=$(calculate_tier_index 32)
  [ "$result" = "2" ]
}

@test "balance 150 is still tier index 4 (above partner threshold)" {
  result=$(calculate_tier_index 150)
  [ "$result" = "4" ]
}

@test "tier recalculates from balance when config thresholds change" {
  # Lower the contributor threshold to 5 — balance 10 should now be contributor (index 1)
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
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
cd ~/study/respect
bats tests/test_tiers.bats
```
Expected: `not found` or `source: scripts/lib.sh: No such file` errors.

- [ ] **Step 3: Write scripts/lib.sh**

```bash
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
# Atomically writes JSON to WALLET_FILE via temp file + mv
# Uses same directory as WALLET_FILE to avoid cross-device link errors
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
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
bats tests/test_tiers.bats
```
Expected: all tests pass, output like:
```
ok 1 balance 0 is tier index 0 (lurker)
ok 2 balance 10 is still tier index 0 ...
...
```

- [ ] **Step 5: Commit**

```bash
git add scripts/lib.sh tests/test_tiers.bats
git commit -m "feat: add lib.sh with tier calculation and trim_history"
```

---

### Task 4: init-wallet.sh

**Files:**
- Create: `scripts/init-wallet.sh`

- [ ] **Step 1: Write failing test** (add to `tests/test_tiers.bats` or new file)

Create `tests/test_init.bats`:

```bash
#!/usr/bin/env bats

setup() {
  export TEST_DIR
  TEST_DIR=$(mktemp -d)
  export RESPECT_WALLET_DIR="$TEST_DIR"
  export CLAUDE_PLUGIN_ROOT="$BATS_TEST_DIRNAME/.."
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "creates wallet.json when missing" {
  rm -f "$TEST_DIR/wallet.json"
  bash "$BATS_TEST_DIRNAME/../scripts/init-wallet.sh"
  [ -f "$TEST_DIR/wallet.json" ]
}

@test "creates config.json when missing" {
  rm -f "$TEST_DIR/config.json"
  bash "$BATS_TEST_DIRNAME/../scripts/init-wallet.sh"
  [ -f "$TEST_DIR/config.json" ]
}

@test "wallet.json has balance 0 on fresh create" {
  bash "$BATS_TEST_DIRNAME/../scripts/init-wallet.sh"
  balance=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "0" ]
}

@test "does not overwrite existing wallet.json" {
  echo '{"schema_version":1,"balance":99}' > "$TEST_DIR/wallet.json"
  cp "$BATS_TEST_DIRNAME/fixtures/config_default.json" "$TEST_DIR/config.json"
  bash "$BATS_TEST_DIRNAME/../scripts/init-wallet.sh"
  balance=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "99" ]
}

@test "does not overwrite existing config.json" {
  cp "$BATS_TEST_DIRNAME/fixtures/wallet_zero.json" "$TEST_DIR/wallet.json"
  echo '{"schema_version":1,"custom":true}' > "$TEST_DIR/config.json"
  bash "$BATS_TEST_DIRNAME/../scripts/init-wallet.sh"
  custom=$(jq -r '.custom' "$TEST_DIR/config.json")
  [ "$custom" = "true" ]
}

@test "creates wallet dir if it does not exist" {
  rm -rf "$TEST_DIR"
  bash "$BATS_TEST_DIRNAME/../scripts/init-wallet.sh"
  [ -d "$TEST_DIR" ]
}
```

- [ ] **Step 2: Run — confirm fail**

```bash
bats tests/test_init.bats
```
Expected: `No such file: scripts/init-wallet.sh`

- [ ] **Step 3: Write scripts/init-wallet.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

mkdir -p "$RESPECT_WALLET_DIR"

if [ ! -f "$WALLET_FILE" ]; then
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s\n' '{
  "schema_version": 1,
  "balance": 0,
  "tier": "lurker",
  "tier_index": 0,
  "lifetime_earned": 0,
  "lifetime_lost": 0,
  "sessions": 0,
  "last_updated": "'"$NOW"'",
  "history": []
}' > "$WALLET_FILE"
fi

if [ ! -f "$CONFIG_FILE" ]; then
  cp "$PLUGIN_ROOT/config.example.json" "$CONFIG_FILE"
fi
```

- [ ] **Step 4: Run — confirm pass**

```bash
bats tests/test_init.bats
```
Expected: all 6 tests pass.

Note: test "creates config.json when missing" will fail until `config.example.json` exists. Create a minimal placeholder now:

```bash
cp tests/fixtures/config_default.json config.example.json
```

Re-run: all pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/init-wallet.sh tests/test_init.bats config.example.json
git commit -m "feat: add init-wallet.sh with idempotent per-file creation"
```

---

## Chunk 2: Core Accounting

### Task 5: tip.sh

**Files:**
- Create: `scripts/tip.sh`
- Create: `tests/test_tip.bats`

- [ ] **Step 1: Write tests/test_tip.bats**

```bash
#!/usr/bin/env bats

setup() {
  export TEST_DIR
  TEST_DIR=$(mktemp -d)
  export RESPECT_WALLET_DIR="$TEST_DIR"
  export CLAUDE_PLUGIN_ROOT="$BATS_TEST_DIRNAME/.."
  cp "$BATS_TEST_DIRNAME/fixtures/config_default.json" "$TEST_DIR/config.json"
  cp "$BATS_TEST_DIRNAME/fixtures/wallet_zero.json" "$TEST_DIR/wallet.json"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# --- Named sizes ---

@test "tip small increases balance by 1" {
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" small
  [ "$status" -eq 0 ]
  balance=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "1" ]
}

@test "tip medium increases balance by 3" {
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" medium
  balance=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "3" ]
}

@test "tip large increases balance by 5" {
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" large
  balance=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "5" ]
}

# --- Output format ---

@test "tip small outputs DELTA line" {
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" small
  echo "$output" | grep -q "^DELTA="
}

@test "tip outputs OLD_BALANCE and NEW_BALANCE" {
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" medium
  echo "$output" | grep -q "^OLD_BALANCE=0"
  echo "$output" | grep -q "^NEW_BALANCE=3"
}

@test "tip outputs TIER_CHANGED=false when no tier change" {
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" small
  echo "$output" | grep -q "^TIER_CHANGED=false"
}

@test "tip outputs TIER_CHANGED=true when tier changes" {
  # Set balance to 10 (just below contributor threshold of 11)
  jq '.balance = 10' "$TEST_DIR/wallet.json" > "$TEST_DIR/wallet.json.tmp"
  mv "$TEST_DIR/wallet.json.tmp" "$TEST_DIR/wallet.json"
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" small
  echo "$output" | grep -q "^TIER_CHANGED=true"
  echo "$output" | grep -q "^NEW_TIER=contributor"
}

# --- Custom tips ---

@test "tip custom 7 increases balance by 7" {
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" custom 7
  balance=$(jq -r '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "7" ]
}

@test "tip custom rejected when allow_custom is false" {
  jq '.tips.allow_custom = false' "$TEST_DIR/config.json" > "$TEST_DIR/config.json.tmp"
  mv "$TEST_DIR/config.json.tmp" "$TEST_DIR/config.json"
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" custom 5
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "custom"
}

@test "tip custom rejected when over max_custom" {
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" custom 11
  [ "$status" -ne 0 ]
}

@test "unknown size name exits non-zero" {
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" enormous
  [ "$status" -ne 0 ]
}

# --- Reason ---

@test "tip with reason stores reason in history" {
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" large "great debugging"
  reason=$(jq -r '.history[-1].reason' "$TEST_DIR/wallet.json")
  [ "$reason" = "great debugging" ]
}

@test "tip without reason stores 'tip' in history" {
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" medium
  reason=$(jq -r '.history[-1].reason' "$TEST_DIR/wallet.json")
  [ "$reason" = "tip" ]
}

@test "require_reason blocks tip without reason" {
  jq '.tips.require_reason = true' "$TEST_DIR/config.json" > "$TEST_DIR/config.json.tmp"
  mv "$TEST_DIR/config.json.tmp" "$TEST_DIR/config.json"
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" medium
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "reason"
}

@test "require_reason allows tip with reason" {
  jq '.tips.require_reason = true' "$TEST_DIR/config.json" > "$TEST_DIR/config.json.tmp"
  mv "$TEST_DIR/config.json.tmp" "$TEST_DIR/config.json"
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" medium "good work"
  [ "$status" -eq 0 ]
}

# --- History ---

@test "tip appends history entry with correct fields" {
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" large "excellent"
  len=$(jq '.history | length' "$TEST_DIR/wallet.json")
  [ "$len" = "1" ]
  delta=$(jq '.history[0].delta' "$TEST_DIR/wallet.json")
  [ "$delta" = "5" ]
  session=$(jq '.history[0].session' "$TEST_DIR/wallet.json")
  [ "$session" = "1" ]
}

@test "tip updates lifetime_earned" {
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" large
  earned=$(jq '.lifetime_earned' "$TEST_DIR/wallet.json")
  [ "$earned" = "5" ]
}

@test "history capped at 500 on tip" {
  # Pre-fill wallet with 499 history entries
  many=$(jq '.history = [range(499) | {"date":"2026-01-01T00:00:00Z","delta":1,"reason":"tip","session":1}] | .balance = 499 | .lifetime_earned = 499' "$TEST_DIR/wallet.json")
  printf '%s\n' "$many" > "$TEST_DIR/wallet.json"
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" small
  len=$(jq '.history | length' "$TEST_DIR/wallet.json")
  [ "$len" = "500" ]
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" small
  len=$(jq '.history | length' "$TEST_DIR/wallet.json")
  [ "$len" = "500" ]
}

# --- max_per_session ---

@test "max_per_session null allows unlimited tips" {
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" large
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" large
  balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "10" ]
}

@test "max_per_session cap enforced" {
  jq '.tips.max_per_session = 6' "$TEST_DIR/config.json" > "$TEST_DIR/config.json.tmp"
  mv "$TEST_DIR/config.json.tmp" "$TEST_DIR/config.json"
  # First tip: 5 (large), session total = 5, under limit
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" large
  [ "$status" -eq 0 ]
  # Second tip: medium (3), would bring session total to 8 > 6, apply only remaining 1
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" medium
  [ "$status" -eq 0 ]
  balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "6" ]
  # Output must report the partial amount applied
  echo "$output" | grep -q "NEW_BALANCE=6"
}

@test "max_per_session exhausted reports error" {
  jq '.tips.max_per_session = 3' "$TEST_DIR/config.json" > "$TEST_DIR/config.json.tmp"
  mv "$TEST_DIR/config.json.tmp" "$TEST_DIR/config.json"
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" large  # 5 > 3, would exceed
  # The script should clamp to 3 and succeed, or reject — check spec: apply only allowed amount
  [ "$status" -eq 0 ]
  balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "3" ]
  # Exhaust the budget
  run bash "$BATS_TEST_DIRNAME/../scripts/tip.sh" small
  # Now at max, no budget remaining — should exit non-zero
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "budget"
}
```

- [ ] **Step 2: Run — confirm fail**

```bash
bats tests/test_tip.bats
```
Expected: failures, `No such file: scripts/tip.sh`

- [ ] **Step 3: Write scripts/tip.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

# --- Parse arguments ---
SIZE_ARG="${1:-}"
shift || true

if [ -z "$SIZE_ARG" ]; then
  echo "ERROR: usage: tip.sh <small|medium|large|custom N> [reason]" >&2
  exit 1
fi

# --- Resolve tip amount ---
AMOUNT=""

if [ "$SIZE_ARG" = "custom" ]; then
  N="${1:-}"
  shift || true
  ALLOW_CUSTOM=$(jq -r '.tips.allow_custom // true' "$CONFIG_FILE")
  if [ "$ALLOW_CUSTOM" = "false" ]; then
    echo "ERROR: Custom tips are disabled. Use small, medium, or large." >&2
    exit 1
  fi
  if ! [[ "$N" =~ ^[0-9]+$ ]] || [ "$N" -le 0 ]; then
    echo "ERROR: Custom tip amount must be a positive integer." >&2
    exit 1
  fi
  MAX_CUSTOM=$(jq -r '.tips.max_custom // 10' "$CONFIG_FILE")
  if [ "$N" -gt "$MAX_CUSTOM" ]; then
    echo "ERROR: Custom tip exceeds max_custom ($MAX_CUSTOM)." >&2
    exit 1
  fi
  AMOUNT="$N"
else
  AMOUNT=$(jq -r --arg size "$SIZE_ARG" '.tips.sizes[$size] // empty' "$CONFIG_FILE")
  if [ -z "$AMOUNT" ]; then
    echo "ERROR: Unknown tip size '$SIZE_ARG'. Valid sizes: $(jq -r '.tips.sizes | keys | join(", ")' "$CONFIG_FILE")" >&2
    exit 1
  fi
  # Validate that the size resolved to a positive integer
  if ! [[ "$AMOUNT" =~ ^[0-9]+$ ]] || [ "$AMOUNT" -le 0 ]; then
    echo "ERROR: Config size '$SIZE_ARG' has invalid value '$AMOUNT' (must be a positive integer)." >&2
    exit 1
  fi
fi

# --- Reason (check arg count BEFORE consuming remaining args) ---
# $# here reflects args remaining after the size (and optional custom N) were shifted off
HAS_REASON=false
if [ "$#" -gt 0 ]; then
  HAS_REASON=true
fi
REASON="${*:-tip}"

REQUIRE_REASON=$(jq -r '.tips.require_reason // false' "$CONFIG_FILE")
if [ "$REQUIRE_REASON" = "true" ] && [ "$HAS_REASON" = "false" ]; then
  echo "ERROR: A reason is required. Usage: /tip $SIZE_ARG <reason text>" >&2
  exit 1
fi

# --- Read current wallet ---
WALLET_JSON=$(cat "$WALLET_FILE")
OLD_BALANCE=$(jq -r '.balance' <<< "$WALLET_JSON")
CURRENT_SESSION=$(jq -r '.sessions' <<< "$WALLET_JSON")

# --- Check max_per_session ---
MAX_PER_SESSION=$(jq -r '.tips.max_per_session // "null"' "$CONFIG_FILE")
if [ "$MAX_PER_SESSION" != "null" ]; then
  SESSION_TOTAL=$(jq -r --argjson s "$CURRENT_SESSION" \
    '[.history[] | select(.delta > 0 and .session == $s) | .delta] | add // 0' \
    <<< "$WALLET_JSON")
  REMAINING=$(( MAX_PER_SESSION - SESSION_TOTAL ))
  if [ "$REMAINING" -le 0 ]; then
    echo "ERROR: Session tip budget exhausted (max: $MAX_PER_SESSION)." >&2
    exit 1
  fi
  if [ "$AMOUNT" -gt "$REMAINING" ]; then
    AMOUNT="$REMAINING"
  fi
fi

# --- Compute new state ---
NEW_BALANCE=$(( OLD_BALANCE + AMOUNT ))
OLD_TIER_INDEX=$(calculate_tier_index "$OLD_BALANCE")
NEW_TIER_INDEX=$(calculate_tier_index "$NEW_BALANCE")
OLD_TIER=$(get_tier_name "$OLD_TIER_INDEX")
NEW_TIER=$(get_tier_name "$NEW_TIER_INDEX")
TIER_CHANGED="false"
if [ "$OLD_TIER_INDEX" != "$NEW_TIER_INDEX" ]; then
  TIER_CHANGED="true"
fi

# --- Update wallet ---
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
UPDATED=$(jq \
  --argjson delta "$AMOUNT" \
  --argjson new_balance "$NEW_BALANCE" \
  --argjson new_tier_index "$NEW_TIER_INDEX" \
  --arg new_tier "$NEW_TIER" \
  --arg reason "$REASON" \
  --argjson session "$CURRENT_SESSION" \
  --arg now "$NOW" \
  '.balance = $new_balance |
   .tier = $new_tier |
   .tier_index = $new_tier_index |
   .lifetime_earned += $delta |
   .last_updated = $now |
   .history += [{"date": $now, "delta": $delta, "reason": $reason, "session": $session}]' \
  <<< "$WALLET_JSON")

UPDATED=$(trim_history "$UPDATED")
write_wallet "$UPDATED"

# --- Print structured result ---
echo "DELTA=+${AMOUNT}"
echo "OLD_BALANCE=${OLD_BALANCE}"
echo "NEW_BALANCE=${NEW_BALANCE}"
echo "OLD_TIER=${OLD_TIER}"
echo "NEW_TIER=${NEW_TIER}"
echo "TIER_CHANGED=${TIER_CHANGED}"
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x scripts/tip.sh
bats tests/test_tip.bats
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/tip.sh tests/test_tip.bats
git commit -m "feat: add tip.sh with named sizes, custom tips, session limits"
```

---

### Task 6: detect-feedback.sh

**Files:**
- Create: `scripts/detect-feedback.sh`
- Create: `tests/test_corrections.bats`

- [ ] **Step 1: Write tests/test_corrections.bats**

```bash
#!/usr/bin/env bats

setup() {
  export TEST_DIR
  TEST_DIR=$(mktemp -d)
  export RESPECT_WALLET_DIR="$TEST_DIR"
  export CLAUDE_PLUGIN_ROOT="$BATS_TEST_DIRNAME/.."
  cp "$BATS_TEST_DIRNAME/fixtures/config_default.json" "$TEST_DIR/config.json"
  # Start at balance 5 for easy floor testing
  jq '.balance = 5 | .sessions = 2' "$BATS_TEST_DIRNAME/fixtures/wallet_zero.json" \
    > "$TEST_DIR/wallet.json"
}

teardown() {
  rm -rf "$TEST_DIR"
}

send_prompt() {
  local prompt="$1"
  jq -n --arg p "$prompt" '{"user_prompt": $p, "session_id": "test"}' \
    | bash "$BATS_TEST_DIRNAME/../scripts/detect-feedback.sh"
}

@test "slash command skipped silently" {
  old_balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  send_prompt "/tip large"
  new_balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  [ "$old_balance" = "$new_balance" ]
}

@test "non-matching prompt skipped silently" {
  old_balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  send_prompt "can you help me refactor this?"
  new_balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  [ "$old_balance" = "$new_balance" ]
}

@test "low sensitivity: that's wrong triggers correction" {
  jq '.corrections.sensitivity = "low"' "$TEST_DIR/config.json" > "$TEST_DIR/config.json.tmp"
  mv "$TEST_DIR/config.json.tmp" "$TEST_DIR/config.json"
  send_prompt "that's wrong, try again"
  balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "4" ]
}

@test "low sensitivity: incorrect triggers correction" {
  jq '.corrections.sensitivity = "low"' "$TEST_DIR/config.json" > "$TEST_DIR/config.json.tmp"
  mv "$TEST_DIR/config.json.tmp" "$TEST_DIR/config.json"
  send_prompt "that is incorrect"
  balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "4" ]
}

@test "medium sensitivity: revert that triggers correction" {
  send_prompt "please revert that change"
  balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "4" ]
}

@test "medium sensitivity: not what i asked triggers correction" {
  send_prompt "that's not what i asked for"
  balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "4" ]
}

@test "medium sensitivity: low-sensitivity-only phrase does NOT trigger on low mode" {
  jq '.corrections.sensitivity = "low"' "$TEST_DIR/config.json" > "$TEST_DIR/config.json.tmp"
  mv "$TEST_DIR/config.json.tmp" "$TEST_DIR/config.json"
  old_balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  send_prompt "please revert that"
  new_balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  [ "$old_balance" = "$new_balance" ]
}

@test "high sensitivity: stop triggers correction" {
  jq '.corrections.sensitivity = "high"' "$TEST_DIR/config.json" > "$TEST_DIR/config.json.tmp"
  mv "$TEST_DIR/config.json.tmp" "$TEST_DIR/config.json"
  send_prompt "stop doing that"
  balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "4" ]
}

@test "matching is case-insensitive" {
  send_prompt "That Is Incorrect!"
  balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "4" ]
}

@test "corrections.enabled false skips all processing" {
  jq '.corrections.enabled = false' "$TEST_DIR/config.json" > "$TEST_DIR/config.json.tmp"
  mv "$TEST_DIR/config.json.tmp" "$TEST_DIR/config.json"
  old_balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  send_prompt "that's wrong"
  new_balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  [ "$old_balance" = "$new_balance" ]
}

@test "custom pattern triggers correction" {
  jq '.corrections.custom_patterns = ["terrible"]' "$TEST_DIR/config.json" \
    > "$TEST_DIR/config.json.tmp"
  mv "$TEST_DIR/config.json.tmp" "$TEST_DIR/config.json"
  send_prompt "that was terrible"
  balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "4" ]
}

@test "balance floor enforced at 0" {
  jq '.balance = 0' "$TEST_DIR/wallet.json" > "$TEST_DIR/wallet.json.tmp"
  mv "$TEST_DIR/wallet.json.tmp" "$TEST_DIR/wallet.json"
  send_prompt "that's wrong"
  balance=$(jq '.balance' "$TEST_DIR/wallet.json")
  [ "$balance" = "0" ]
}

@test "at floor: history entry written with delta 0" {
  jq '.balance = 0' "$TEST_DIR/wallet.json" > "$TEST_DIR/wallet.json.tmp"
  mv "$TEST_DIR/wallet.json.tmp" "$TEST_DIR/wallet.json"
  send_prompt "that's wrong"
  delta=$(jq '.history[-1].delta' "$TEST_DIR/wallet.json")
  reason=$(jq -r '.history[-1].reason' "$TEST_DIR/wallet.json")
  [ "$delta" = "0" ]
  [ "$reason" = "correction_at_floor" ]
}

@test "at floor: lifetime_lost not incremented" {
  jq '.balance = 0 | .lifetime_lost = 3' "$TEST_DIR/wallet.json" > "$TEST_DIR/wallet.json.tmp"
  mv "$TEST_DIR/wallet.json.tmp" "$TEST_DIR/wallet.json"
  send_prompt "that's wrong"
  lost=$(jq '.lifetime_lost' "$TEST_DIR/wallet.json")
  [ "$lost" = "3" ]
}

@test "above floor: lifetime_lost incremented" {
  send_prompt "that's wrong"
  lost=$(jq '.lifetime_lost' "$TEST_DIR/wallet.json")
  [ "$lost" = "1" ]
}

@test "output includes systemMessage JSON when correction fires" {
  output=$(send_prompt "that's wrong")
  echo "$output" | jq -e '.systemMessage' > /dev/null
}

@test "output is empty when no correction" {
  output=$(send_prompt "looks good, continue")
  [ -z "$output" ]
}
```

- [ ] **Step 2: Run — confirm fail**

```bash
bats tests/test_corrections.bats
```
Expected: failures.

- [ ] **Step 3: Write scripts/detect-feedback.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

# Read hook input from stdin
INPUT=$(cat)
PROMPT=$(jq -r '.user_prompt // ""' <<< "$INPUT")

# Skip slash commands
if [[ "$PROMPT" == /* ]]; then
  exit 0
fi

# Load config
CORRECTIONS_ENABLED=$(jq -r '.corrections.enabled // true' "$CONFIG_FILE")
if [ "$CORRECTIONS_ENABLED" = "false" ]; then
  exit 0
fi

SENSITIVITY=$(jq -r '.corrections.sensitivity // "medium"' "$CONFIG_FILE")
DELTA=$(jq -r '.corrections.delta // -1' "$CONFIG_FILE")

# Build pattern list based on sensitivity (case-insensitive matching done with grep -i)
declare -a PATTERNS=()

# low patterns
PATTERNS+=("that's wrong" "that is wrong" "incorrect")

if [ "$SENSITIVITY" = "medium" ] || [ "$SENSITIVITY" = "high" ]; then
  PATTERNS+=("undo that" "not what i asked" "revert that" "that's not right")
fi

if [ "$SENSITIVITY" = "high" ]; then
  # Use POSIX word boundaries compatible with both macOS (BSD grep) and Linux (GNU grep)
  PATTERNS+=("(^|[^[:alpha:]])no([^[:alpha:]]|$)" "(^|[^[:alpha:]])stop([^[:alpha:]]|$)" "(^|[^[:alpha:]])wrong([^[:alpha:]]|$)")
fi

# Add custom patterns
while IFS= read -r pattern; do
  [ -n "$pattern" ] && PATTERNS+=("$pattern")
done < <(jq -r '.corrections.custom_patterns[]? // empty' "$CONFIG_FILE")

# Test prompt against patterns — lowercase once, match without -i flag
MATCHED=false
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')
for pattern in "${PATTERNS[@]}"; do
  if echo "$PROMPT_LOWER" | grep -qE "$pattern"; then
    MATCHED=true
    break
  fi
done

if [ "$MATCHED" = "false" ]; then
  exit 0
fi

# Load wallet
WALLET_JSON=$(cat "$WALLET_FILE")
OLD_BALANCE=$(jq -r '.balance' <<< "$WALLET_JSON")
CURRENT_SESSION=$(jq -r '.sessions' <<< "$WALLET_JSON")
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ "$OLD_BALANCE" -le 0 ]; then
  # At floor: record event but don't decrement
  UPDATED=$(jq \
    --argjson session "$CURRENT_SESSION" \
    --arg now "$NOW" \
    '.last_updated = $now |
     .history += [{"date": $now, "delta": 0, "reason": "correction_at_floor", "session": $session}]' \
    <<< "$WALLET_JSON")
  UPDATED=$(trim_history "$UPDATED")
  write_wallet "$UPDATED"
  # Still inject system message so Claude is aware
  jq -n --arg msg "Correction noted. Balance is already at 0 (floor)." '{"systemMessage": $msg}'
  exit 0
fi

# Decrement balance
NEW_BALANCE=$(( OLD_BALANCE + DELTA ))
if [ "$NEW_BALANCE" -lt 0 ]; then
  NEW_BALANCE=0
fi
ACTUAL_DELTA=$(( NEW_BALANCE - OLD_BALANCE ))
ABS_DELTA=$(( ACTUAL_DELTA < 0 ? -ACTUAL_DELTA : ACTUAL_DELTA ))

NEW_TIER_INDEX=$(calculate_tier_index "$NEW_BALANCE")
NEW_TIER=$(get_tier_name "$NEW_TIER_INDEX")

UPDATED=$(jq \
  --argjson new_balance "$NEW_BALANCE" \
  --argjson new_tier_index "$NEW_TIER_INDEX" \
  --arg new_tier "$NEW_TIER" \
  --argjson delta "$ACTUAL_DELTA" \
  --argjson abs_delta "$ABS_DELTA" \
  --argjson session "$CURRENT_SESSION" \
  --arg now "$NOW" \
  '.balance = $new_balance |
   .tier = $new_tier |
   .tier_index = $new_tier_index |
   .lifetime_lost += $abs_delta |
   .last_updated = $now |
   .history += [{"date": $now, "delta": $delta, "reason": "correction", "session": $session}]' \
  <<< "$WALLET_JSON")

UPDATED=$(trim_history "$UPDATED")
write_wallet "$UPDATED"

MSG="Balance decreased: ${OLD_BALANCE} → ${NEW_BALANCE} (correction detected). Tier: ${NEW_TIER}."
jq -n --arg msg "$MSG" '{"systemMessage": $msg}'
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x scripts/detect-feedback.sh
bats tests/test_corrections.bats
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/detect-feedback.sh tests/test_corrections.bats
git commit -m "feat: add detect-feedback.sh with correction detection and balance floor"
```

---

## Chunk 3: Session Start

### Task 7: session-start.sh

**Files:**
- Create: `scripts/session-start.sh`
- Create: `tests/test_session_start.bats`

- [ ] **Step 1: Write tests/test_session_start.bats**

```bash
#!/usr/bin/env bats

setup() {
  export TEST_DIR
  TEST_DIR=$(mktemp -d)
  export RESPECT_WALLET_DIR="$TEST_DIR"
  export CLAUDE_PLUGIN_ROOT="$BATS_TEST_DIRNAME/.."
  cp "$BATS_TEST_DIRNAME/fixtures/config_default.json" "$TEST_DIR/config.json"
  cp "$BATS_TEST_DIRNAME/fixtures/wallet_zero.json" "$TEST_DIR/wallet.json"
}

teardown() {
  rm -rf "$TEST_DIR"
}

run_session_start() {
  bash "$BATS_TEST_DIRNAME/../scripts/session-start.sh"
}

@test "outputs valid JSON with systemMessage key" {
  output=$(run_session_start)
  echo "$output" | jq -e '.systemMessage' > /dev/null
}

@test "systemMessage contains balance" {
  output=$(run_session_start)
  msg=$(echo "$output" | jq -r '.systemMessage')
  echo "$msg" | grep -q "Balance:"
}

@test "systemMessage contains tier name" {
  output=$(run_session_start)
  msg=$(echo "$output" | jq -r '.systemMessage')
  echo "$msg" | grep -q "lurker"
}

@test "session counter incremented in wallet" {
  run_session_start > /dev/null
  sessions=$(jq '.sessions' "$TEST_DIR/wallet.json")
  [ "$sessions" = "2" ]
}

@test "session counter incremented each run" {
  run_session_start > /dev/null
  run_session_start > /dev/null
  sessions=$(jq '.sessions' "$TEST_DIR/wallet.json")
  [ "$sessions" = "3" ]
}

@test "tier recalculated from balance, not stored value" {
  # Set balance to trusted range but store wrong tier in wallet
  jq '.balance = 35 | .tier = "lurker" | .tier_index = 0' \
    "$TEST_DIR/wallet.json" > "$TEST_DIR/wallet.json.tmp"
  mv "$TEST_DIR/wallet.json.tmp" "$TEST_DIR/wallet.json"
  output=$(run_session_start)
  msg=$(echo "$output" | jq -r '.systemMessage')
  echo "$msg" | grep -q "trusted"
  tier=$(jq -r '.tier' "$TEST_DIR/wallet.json")
  [ "$tier" = "trusted" ]
}

@test "behaviors above current tier not included" {
  # At lurker (index 0): no behaviors (all have min_tier >= 1)
  output=$(run_session_start)
  msg=$(echo "$output" | jq -r '.systemMessage')
  # suggestion_latitude requires tier 2 — should not appear
  echo "$msg" | grep -qv "Proactively suggest improvements"
}

@test "behaviors for current tier included" {
  # Set to contributor tier (index 1): effort_scaling (min_tier 1) should appear
  jq '.balance = 15' "$TEST_DIR/wallet.json" > "$TEST_DIR/wallet.json.tmp"
  mv "$TEST_DIR/wallet.json.tmp" "$TEST_DIR/wallet.json"
  output=$(run_session_start)
  msg=$(echo "$output" | jq -r '.systemMessage')
  echo "$msg" | grep -q "Apply thorough reasoning"
}

@test "disabled behavior not included even if tier is sufficient" {
  jq '.balance = 101' "$TEST_DIR/wallet.json" > "$TEST_DIR/wallet.json.tmp"
  mv "$TEST_DIR/wallet.json.tmp" "$TEST_DIR/wallet.json"
  output=$(run_session_start)
  msg=$(echo "$output" | jq -r '.systemMessage')
  # confirmation_reduction is disabled
  echo "$msg" | grep -qv "Proceed with multi-step actions"
}

@test "pattern analysis section present" {
  cp "$BATS_TEST_DIRNAME/fixtures/wallet_trusted.json" "$TEST_DIR/wallet.json"
  output=$(run_session_start)
  msg=$(echo "$output" | jq -r '.systemMessage')
  echo "$msg" | grep -q "Behavioral patterns"
}

@test "creates wallet files if missing (calls init)" {
  rm "$TEST_DIR/wallet.json"
  run_session_start > /dev/null
  [ -f "$TEST_DIR/wallet.json" ]
}
```

- [ ] **Step 2: Run — confirm fail**

```bash
bats tests/test_session_start.bats
```
Expected: failures, `No such file: scripts/session-start.sh`

- [ ] **Step 3: Write scripts/session-start.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

# Ensure wallet and config exist
bash "$SCRIPT_DIR/init-wallet.sh"

# Increment session counter atomically
WALLET_JSON=$(cat "$WALLET_FILE")
WALLET_JSON=$(jq '.sessions += 1' <<< "$WALLET_JSON")
write_wallet "$WALLET_JSON"
WALLET_JSON=$(cat "$WALLET_FILE")

# Recalculate tier from balance (never trust stored value)
BALANCE=$(jq -r '.balance' <<< "$WALLET_JSON")
SESSIONS=$(jq -r '.sessions' <<< "$WALLET_JSON")
TIER_INDEX=$(calculate_tier_index "$BALANCE")
TIER_NAME=$(get_tier_name "$TIER_INDEX")

# Update cached tier in wallet
WALLET_JSON=$(jq \
  --argjson idx "$TIER_INDEX" \
  --arg name "$TIER_NAME" \
  '.tier_index = $idx | .tier = $name' \
  <<< "$WALLET_JSON")
write_wallet "$WALLET_JSON"

# --- Build active behaviors ---
BEHAVIORS=""
while IFS= read -r instruction; do
  BEHAVIORS="${BEHAVIORS}- ${instruction}"$'\n'
done < <(jq -r \
  --argjson tier "$TIER_INDEX" \
  '[.behaviors[] | select(.enabled == true and .min_tier <= $tier) | .instruction] | .[]' \
  "$CONFIG_FILE")

# --- Pattern analysis ---
HISTORY_LEN=$(jq '.history | length' <<< "$WALLET_JSON")

# Average tip size
if [ "$HISTORY_LEN" -gt 0 ]; then
  AVG_TIP=$(jq -r '[.history[] | select(.delta > 0) | .delta] | if length > 0 then (add / length * 10 | round / 10) else 0 end' <<< "$WALLET_JSON")
else
  AVG_TIP=0
fi

# Correction count in last 10 sessions
LAST_10_SESSION=$(( SESSIONS > 10 ? SESSIONS - 10 : 0 ))
CORRECTION_COUNT=$(jq -r \
  --argjson cutoff "$LAST_10_SESSION" \
  '[.history[] | select(.delta < 0 and .session > $cutoff)] | length' \
  <<< "$WALLET_JSON")

# Top 3 non-default tip reasons
TOP_REASONS=$(jq -r \
  '[.history[] | select(.delta > 0 and .reason != "tip")] |
   sort_by(-.delta) | .[0:3] |
   map("\"" + .reason + "\" (+" + (.delta|tostring) + " s" + (.session|tostring) + ")") |
   join(", ")' \
  <<< "$WALLET_JSON")

# Net trend: sum of deltas in last 3 sessions
TREND_CUTOFF=$(( SESSIONS > 3 ? SESSIONS - 3 : 0 ))
NET_TREND=$(jq -r \
  --argjson cutoff "$TREND_CUTOFF" \
  '[.history[] | select(.session > $cutoff) | .delta] | add // 0' \
  <<< "$WALLET_JSON")
TREND_LABEL="stable"
if [ "$NET_TREND" -gt 0 ]; then TREND_LABEL="improving (+${NET_TREND})"; fi
if [ "$NET_TREND" -lt 0 ]; then TREND_LABEL="declining (${NET_TREND})"; fi

# Recent history (last 3 entries)
RECENT=$(jq -r '.history[-3:] | reverse | .[] |
  (if .delta >= 0 then "+" else "" end) + (.delta|tostring) + " " + .reason + " (s" + (.session|tostring) + ")"' \
  <<< "$WALLET_JSON" | paste -sd ', ' -)

# --- Build system message ---
PATTERN_SECTION=""
if [ "$HISTORY_LEN" -gt 0 ]; then
  PATTERN_SECTION="
Behavioral patterns:
- Avg tip: ${AVG_TIP} pts | Corrections last 10 sessions: ${CORRECTION_COUNT}
- Net trend: ${TREND_LABEL}"
  if [ -n "$TOP_REASONS" ]; then
    PATTERN_SECTION="${PATTERN_SECTION}
- Top tip reasons: ${TOP_REASONS}"
  fi
fi

BEHAVIOR_SECTION=""
if [ -n "$BEHAVIORS" ]; then
  BEHAVIOR_SECTION="
Active behaviors:
${BEHAVIORS}"
fi

RECENT_SECTION=""
if [ -n "$RECENT" ]; then
  RECENT_SECTION="
Recent: ${RECENT}"
fi

MSG="Respect wallet loaded.
Balance: ${BALANCE} | Tier: ${TIER_NAME} | Session: ${SESSIONS}${RECENT_SECTION}${BEHAVIOR_SECTION}${PATTERN_SECTION}"

jq -n --arg msg "$MSG" '{"systemMessage": $msg}'
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x scripts/session-start.sh
bats tests/test_session_start.bats
```
Expected: all tests pass.

- [ ] **Step 5: Run full test suite**

```bash
bats tests/
```
Expected: all tests pass across all files.

- [ ] **Step 6: Commit**

```bash
git add scripts/session-start.sh tests/test_session_start.bats
git commit -m "feat: add session-start.sh with tier injection and behavioral patterns"
```

---

## Chunk 4: Plugin Wiring and Docs

### Task 8: hooks.json and plugin.json

**Files:**
- Create: `hooks/hooks.json`
- Create: `plugin.json`

- [ ] **Step 1: Write hooks/hooks.json**

```json
{
  "description": "Respect economy — loads wallet context at session start, detects corrections on every prompt",
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash $CLAUDE_PLUGIN_ROOT/scripts/session-start.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash $CLAUDE_PLUGIN_ROOT/scripts/detect-feedback.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Verify hooks.json is valid JSON**

```bash
jq empty hooks/hooks.json && echo "OK"
```

- [ ] **Step 3: Write plugin.json**

```json
{
  "name": "respect",
  "version": "1.0.0",
  "description": "Persistent respect economy for Claude Code sessions",
  "hooks": "hooks/hooks.json",
  "skills": [
    { "name": "tip", "path": "skills/tip/skill.md" },
    { "name": "respect-setup", "path": "skills/respect-setup/skill.md" }
  ]
}
```

- [ ] **Step 4: Commit**

```bash
git add hooks/hooks.json plugin.json
git commit -m "feat: add plugin manifest and hook wiring"
```

---

### Task 9: skills

**Files:**
- Create: `skills/tip/skill.md`
- Create: `skills/respect-setup/skill.md`

- [ ] **Step 1: Write skills/tip/skill.md**

```markdown
# /tip — Give respect to Claude

Use this command to tip Claude after a good session or task.

## Usage

- `/tip small` — tip 1 respect point
- `/tip medium` — tip 3 respect points
- `/tip large` — tip 5 respect points
- `/tip custom N [reason]` — tip a custom amount (if enabled in config)
- `/tip large great debugging` — tip with a reason (recorded in history)

## Instructions

When the user runs `/tip`:

1. Run the accounting script:
   ```
   bash $CLAUDE_PLUGIN_ROOT/scripts/tip.sh <args>
   ```
   Pass all arguments after `/tip` verbatim to the script.

2. If the script exits with a non-zero status: relay the error message to the user and stop.

3. Parse the structured output:
   - `DELTA` — amount added
   - `OLD_BALANCE` / `NEW_BALANCE` — balance before/after
   - `OLD_TIER` / `NEW_TIER` — tier before/after
   - `TIER_CHANGED` — true/false

4. Respond conversationally in one sentence. Keep it brief and warm.
   - No tier change: "Respect received (+{DELTA}). Balance: {OLD_BALANCE} → {NEW_BALANCE}. Tier: {NEW_TIER}."
   - Tier up: "Respect received (+{DELTA}). Balance: {OLD_BALANCE} → {NEW_BALANCE}. Tier: {OLD_TIER} → {NEW_TIER}. {brief note about new behaviors unlocked}"
   - Tier down is not possible from tipping.

Do not modify wallet.json yourself. The script owns all accounting.
```

- [ ] **Step 2: Write skills/respect-setup/skill.md**

```markdown
# /respect-setup — Configure the respect economy

Interactive wizard to set up or reconfigure your respect economy config.

## Instructions

When the user runs `/respect-setup`:

1. Check if `~/.claude/respect/config.json` exists.
   - If it exists: ask "A config already exists. Reconfigure from scratch, or cancel? (reconfigure/cancel)"
   - If user says cancel: stop.
   - If it does not exist: proceed.

2. Ask the following questions **one at a time**, waiting for the user's answer before proceeding:

   **Q1: Tier names**
   "How many tiers do you want? (3–6) And what should they be called? Or press Enter to use defaults: lurker, contributor, trusted, veteran, partner."

   **Q2: Tier thresholds**
   For each tier above the first, ask: "How many respect points to reach [tier name]? (default: 11, 31, 61, 101)"

   **Q3: Tip sizes**
   "What should small / medium / large tips be worth? (defaults: 1 / 3 / 5)"

   **Q4: Behaviors**
   List the 4 default behaviors and ask which to enable:
   - effort_scaling (min tier 1): Apply thorough reasoning
   - suggestion_latitude (min tier 2): Proactively suggest improvements
   - deep_insights (min tier 3): Provide educational insights
   - confirmation_reduction (min tier 4, RISKY): Proceed without confirmations — disabled by default
   "Which behaviors do you want enabled? (Enter numbers separated by commas, or 'all' for first 3)"

   **Q5: Correction sensitivity**
   "How sensitive should correction detection be? (low / medium / high, default: medium)
   - low: explicit wrong/incorrect only
   - medium: also revert/undo/not what I asked
   - high: also 'no', 'stop', 'wrong'"

3. Build the config JSON from the answers, using defaults for any skipped questions.

4. Write the config atomically:
   ```bash
   tmp=$(mktemp)
   echo '<config json>' > "$tmp"
   mv "$tmp" ~/.claude/respect/config.json
   ```

5. Confirm: "Config saved to ~/.claude/respect/config.json. Your respect economy is ready. Restart Claude Code for the session hook to pick up your new config."

6. Offer to show a summary of what was configured.
```

- [ ] **Step 3: Commit**

```bash
git add skills/
git commit -m "feat: add tip and respect-setup skills"
```

---

### Task 10: config.example.json

**Files:**
- Modify: `config.example.json` (replace placeholder with fully commented version)

- [ ] **Step 1: Write config.example.json with inline comments**

Since JSON does not support comments natively, use a `_comments` key pattern for documentation:

```json
{
  "_readme": "Copy this file to ~/.claude/respect/config.json to customize. Remove _readme and _comments keys.",
  "schema_version": 1,

  "_comments_tiers": "Define your tiers as an ordered array. First entry is the starting tier (min_balance: 0). Add as many as you like.",
  "tiers": [
    { "name": "lurker",      "min_balance": 0,   "emoji": "👤" },
    { "name": "contributor", "min_balance": 11,  "emoji": "🌱" },
    { "name": "trusted",     "min_balance": 31,  "emoji": "⚡" },
    { "name": "veteran",     "min_balance": 61,  "emoji": "🔥" },
    { "name": "partner",     "min_balance": 101, "emoji": "🤝" }
  ],

  "_comments_behaviors": "Each behavior injects its 'instruction' into Claude's context when enabled and the current tier_index >= min_tier. Write any instruction you want.",
  "behaviors": [
    {
      "id": "effort_scaling",
      "enabled": true,
      "min_tier": 1,
      "instruction": "Apply thorough reasoning. Do not abbreviate steps or skip explanations."
    },
    {
      "id": "suggestion_latitude",
      "enabled": true,
      "min_tier": 2,
      "instruction": "Proactively suggest improvements, refactors, and architecture ideas even when not asked."
    },
    {
      "id": "deep_insights",
      "enabled": true,
      "min_tier": 3,
      "instruction": "Provide educational insights about implementation choices. Explain the why behind decisions."
    },
    {
      "_comment": "RISKY: disabled by default. Enable only if you want Claude to act without confirmation.",
      "id": "confirmation_reduction",
      "enabled": false,
      "min_tier": 4,
      "instruction": "Proceed with multi-step actions without asking for confirmation on each step."
    }
  ],

  "_comments_corrections": "sensitivity: low/medium/high. delta should be negative. custom_patterns: array of regex strings (case-insensitive).",
  "corrections": {
    "enabled": true,
    "sensitivity": "medium",
    "delta": -1,
    "custom_patterns": []
  },

  "_comments_tips": "sizes: named tip amounts. allow_custom: enable /tip custom N. max_custom: ceiling for custom tips. max_per_session: null = unlimited.",
  "tips": {
    "sizes": {
      "small":  1,
      "medium": 3,
      "large":  5
    },
    "allow_custom": true,
    "max_custom": 10,
    "max_per_session": null,
    "require_reason": false
  },

  "_comments_statusline": "format supports {emoji}, {balance}, {name} placeholders.",
  "statusline": {
    "format": "{emoji} {balance} ({name})"
  }
}
```

- [ ] **Step 2: Verify valid JSON**

```bash
jq empty config.example.json && echo "OK"
```

- [ ] **Step 3: Commit**

```bash
git add config.example.json
git commit -m "docs: add heavily commented config.example.json"
```

---

### Task 11: statusline snippet and README

**Files:**
- Create: `docs/statusline-snippet.md`
- Create: `README.md`

- [ ] **Step 1: Write docs/statusline-snippet.md**

````markdown
# Status Line Integration

Add this snippet to your `~/.claude/statusline.sh` to show your respect balance in the Claude Code status line.

The snippet reads your current config's format string, so it respects any customization you've made to tier names or display format.

```bash
# Respect Economy — add to ~/.claude/statusline.sh
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

**Note:** The snippet reads the cached `tier` field from `wallet.json`. If you edit tier thresholds in `config.json` between sessions, the displayed tier may be stale until the next session start (which recalculates and updates the cache).
````

- [ ] **Step 2: Write README.md**

````markdown
# respect

A Claude Code plugin that implements a persistent respect economy. Tip Claude after good work, watch your balance grow, unlock richer behavior as trust accumulates.

## How it works

- You tip Claude using `/tip small|medium|large [reason]`
- Tips increment a balance stored at `~/.claude/respect/wallet.json`
- The balance determines your tier (lurker → contributor → trusted → veteran → partner)
- Each tier unlocks additional behavior instructions injected into Claude's context at session start
- Corrections ("that's wrong", "revert that") decrement the balance
- Current balance and tier are visible in the Claude Code status line

## Install

```bash
claude plugin add github:<your-username>/respect
```

Then restart Claude Code. On first session start, your wallet and config are created automatically.

To configure interactively:
```
/respect-setup
```

## Tip commands

```
/tip small              # +1 respect
/tip medium             # +3 respect
/tip large              # +5 respect
/tip large great work   # +5 respect, reason recorded in history
/tip custom 7           # custom amount (if allow_custom: true)
```

## Customize

### After install (recommended)

Edit `~/.claude/respect/config.json`. Changes take effect at next session start.

### Before install (power users)

Copy `config.example.json` from this repo to `~/.claude/respect/config.json`, edit it, then install. The plugin will not overwrite it.

What you can customize:
- **Tier names and thresholds** — rename tiers, change balance requirements, add or remove tiers
- **Behavior instructions** — write any instruction text for each tier
- **Tip sizes** — change what small/medium/large are worth
- **Correction sensitivity** — `low`, `medium`, or `high`
- **Status line format** — uses `{emoji}`, `{balance}`, `{name}` placeholders

## Status line integration

See [`docs/statusline-snippet.md`](docs/statusline-snippet.md) for a copy-paste snippet to add your balance to the Claude Code status line.

## Data files

| File | Purpose |
|---|---|
| `~/.claude/respect/wallet.json` | Balance, tier, history |
| `~/.claude/respect/config.json` | Your configuration |

These files are yours — never modified by plugin updates.

## Run tests

```bash
brew install bats-core
bats tests/
```

## Design notes

The wallet is owned by bash scripts, not by Claude. When you run `/tip`, Claude calls `scripts/tip.sh` and relays the result — it never writes to `wallet.json` directly. This keeps accounting trustworthy.
````

- [ ] **Step 3: Commit**

```bash
git add docs/statusline-snippet.md README.md
git commit -m "docs: add statusline snippet and README"
```

---

### Task 12: Wire statusline

**Files:**
- Modify: `~/.claude/statusline.sh`

- [ ] **Step 1: Read current statusline.sh to find insertion point**

```bash
cat ~/.claude/statusline.sh
```

- [ ] **Step 2: Add respect snippet before the final `echo "$STATUS"` line**

Open `~/.claude/statusline.sh` and add the snippet from `docs/statusline-snippet.md` before the final `echo "$STATUS"` line.

- [ ] **Step 3: Test the statusline script manually**

```bash
echo '{}' | bash ~/.claude/statusline.sh
```
Expected: output includes the respect balance segment (shows `0 (lurker)` on first run after wallet is created).

- [ ] **Step 4: Final commit**

```bash
cd ~/study/respect
git add .
git status  # confirm nothing unexpected
git commit -m "chore: final cleanup and verify all tests pass"
bats tests/
```
Expected: all tests pass.

---

## Verification

After implementation, run the full verification:

```bash
cd ~/study/respect

# All tests pass
bats tests/

# All JSON files valid
for f in $(find . -name '*.json' -not -path './.git/*'); do
  jq empty "$f" && echo "OK: $f"
done

# Scripts are executable
ls -la scripts/*.sh

# Plugin structure looks right
ls -la plugin.json hooks/ skills/ scripts/ tests/ docs/
```

To smoke-test end-to-end without a full Claude Code session:

```bash
export RESPECT_WALLET_DIR=$(mktemp -d)
export CLAUDE_PLUGIN_ROOT=~/study/respect
cp config.example.json "$RESPECT_WALLET_DIR/config.json"

# Simulate session start
bash scripts/session-start.sh | jq .

# Simulate a tip
bash scripts/tip.sh large "smoke test"
cat "$RESPECT_WALLET_DIR/wallet.json" | jq '{balance, tier, history}'

# Simulate a correction
echo '{"user_prompt": "that is wrong"}' | bash scripts/detect-feedback.sh | jq .
cat "$RESPECT_WALLET_DIR/wallet.json" | jq '{balance, tier}'
```
