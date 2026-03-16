# Respect Economy — Design Spec

**Date:** 2026-03-15
**Status:** Approved
**Project:** `~/study/respect`

---

## Overview

A Claude Code plugin that implements a persistent respect economy. Users tip Claude using `/tip N`, which increments a balance stored in `~/.claude/respect/wallet.json`. The balance determines a tier, and the active tier controls which behavior instructions are injected into Claude's context at session start. Negative feedback (corrections) decrements the balance. The current balance and tier are visible in the Claude Code status line.

The plugin is fully configurable — tiers, behaviors, correction sensitivity, and tip rules are all user-defined in `~/.claude/respect/config.json`. It ships with safe defaults (no risky behaviors enabled). Published as a standalone GitHub repo installable via `claude plugin add github:<user>/respect`.

---

## Architecture

### Repository Layout

```
respect/
├── plugin.json
├── README.md
├── config.example.json        # heavily commented reference config for power users
├── hooks/
│   └── hooks.json
├── scripts/
│   ├── session-start.sh       # loads wallet + config, injects system message + pattern analysis
│   ├── detect-feedback.sh     # detects corrections, decrements balance
│   ├── tip.sh                 # all tip accounting logic (called by skill, never by Claude)
│   └── init-wallet.sh         # creates wallet.json and config.json on first run
├── skills/
│   ├── tip/
│   │   └── skill.md           # /tip entry point — delegates entirely to tip.sh
│   └── respect-setup/
│       └── skill.md           # /respect-setup onboarding wizard
├── tests/
│   ├── test_tip.bats           # unit tests: tip accounting, sizes, limits
│   ├── test_corrections.bats   # unit tests: correction detection, floor, lifetime_lost
│   ├── test_tiers.bats         # unit tests: tier recalculation, history cap
│   ├── test_session_start.bats # integration tests: system message content per wallet state
│   └── fixtures/
│       ├── wallet_zero.json
│       ├── wallet_trusted.json
│       └── config_default.json
└── docs/
    ├── statusline-snippet.md
    └── superpowers/specs/
        └── 2026-03-15-respect-design.md
```

### Data Files (user-level, outside plugin)

```
~/.claude/respect/
├── wallet.json    # persistent balance + history
└── config.json    # user configuration
```

These files persist across plugin updates and reinstalls.

---

## Data Schemas

### wallet.json

```json
{
  "schema_version": 1,
  "balance": 0,
  "tier": "lurker",
  "tier_index": 0,
  "lifetime_earned": 0,
  "lifetime_lost": 0,
  "sessions": 0,
  "last_updated": "2026-03-15T10:00:00Z",
  "history": [
    {"date": "2026-03-15T10:00:00Z", "delta": 3, "reason": "tip", "session": 1},
    {"date": "2026-03-15T10:05:00Z", "delta": -1, "reason": "correction", "session": 1}
  ]
}
```

**Authoritative source for tier:** `tier` and `tier_index` in `wallet.json` are a cached display convenience only. All scripts must always recalculate the current tier by comparing `balance` against thresholds in `config.json` at the time of each read. If a user edits `config.json` to change tier thresholds, the recalculation at next session start will self-correct.

**History cap:** The `history` array is capped at 500 entries. When a write would exceed 500, the oldest entries are dropped to keep the array at 500. This prevents unbounded file growth.

### config.json (default, ships with plugin)

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

**Correction sensitivity patterns (all matched case-insensitively):**
- `low`: "that's wrong", "incorrect", "that is wrong"
- `medium`: above + "undo that", "not what i asked", "revert that", "that's not right"
- `high`: above + "no", "stop", "wrong"
- `custom_patterns`: additional regex patterns appended to the active set, also matched case-insensitively

**`require_reason` behavior:** When `true`, the `/tip` skill checks if the user provided a reason string after the amount (e.g., `/tip 3 great debugging`). If no reason is provided, the skill responds asking for one and does not update the wallet. The reason is recorded in the history entry's `reason` field instead of the default `"tip"`.

---

## Components

### `plugin.json`

Declares the plugin to the Claude Code runtime following the Claude Code plugin manifest format. All fields below are required except `description`:

```json
{
  "name": "respect",
  "version": "1.0.0",
  "description": "Persistent respect economy for Claude Code sessions",
  "hooks": "hooks/hooks.json",
  "skills": [
    { "name": "tip", "path": "skills/tip/skill.md" }
  ]
}
```

- `name`: plugin identifier, must be unique in the registry
- `version`: semver string
- `description`: human-readable summary (optional)
- `hooks`: relative path to the hooks configuration file
- `skills`: array of skill entries, each with a `name` (used as the slash command, e.g. `/tip`) and `path` (relative path to the skill markdown file)

### `scripts/init-wallet.sh`

Runs at session start to ensure data files exist. Checks and creates each file independently:
- If `~/.claude/respect/wallet.json` does not exist: create it with default values
- If `~/.claude/respect/config.json` does not exist: copy the plugin's bundled default config

Idempotent per-file — if one exists and the other does not, only the missing file is created. Never overwrites existing files.

### `scripts/session-start.sh`

Runs via `SessionStart` hook. Uses `$CLAUDE_PLUGIN_ROOT` (injected by the Claude Code plugin runtime, points to the installed plugin directory) to reference bundled files. Steps:

1. Call `init-wallet.sh` to ensure data files exist
2. Increment `sessions` counter in `wallet.json` using atomic write (write to temp file, then `mv`)
3. Read `wallet.json` and `config.json`
4. Recalculate current tier by comparing `balance` against `config.json` tier thresholds (do not trust stored `tier` or `tier_index`)
5. Update stored `tier` and `tier_index` in wallet with recalculated values
6. Filter `behaviors` where `enabled: true` and `min_tier <= current_tier_index`
7. Compute behavioral pattern analysis from full history (see Pattern Analysis below)
8. Build system message with: balance, tier name, session count, last 3 history entries, active behavior instructions, and pattern analysis summary
9. Output JSON `{"systemMessage": "..."}` to stdout

System message format:
```
Respect wallet loaded.
Balance: 15 | Tier: trusted | Session: 8
Recent: +3 tip/great debugging (s7), -1 correction (s7)

Active behaviors:
- Apply thorough reasoning. Do not abbreviate steps or skip explanations.
- Proactively suggest improvements, refactors, and architecture ideas even when not asked.

Behavioral patterns:
- Avg tip: 3.2 pts | Corrections last 10 sessions: 2
- Largest tips: "great debugging" (+5 s6), "perfect explanation" (+4 s4)
- Corrections cluster: 2 of 2 followed multi-file edits
- Net trend: improving (+8 last 3 sessions)
```

### Pattern Analysis

`session-start.sh` computes the following from `history` using `jq` and bash arithmetic. No AI inference — purely statistical:

- **Average tip size**: mean of all positive deltas
- **Correction frequency**: count of negative deltas in the last 10 sessions
- **Top tip reasons**: top 3 reason strings by associated delta value (excluding default `"tip"` label if a custom reason was given)
- **Correction clustering**: whether corrections share a common reason pattern (e.g. "correction_at_floor", or user-provided context visible in recent history)
- **Net trend**: sum of all deltas in the last 3 sessions (positive = improving, negative = declining)

These are injected as structured text so Claude can adjust behavior: e.g. if corrections cluster after file edits, Claude can apply extra care to file operations regardless of tier.

**Atomic writes:** All wallet writes in all scripts must use the temp-file-then-rename pattern:
```bash
tmp=$(mktemp)
echo "$updated_json" > "$tmp"
mv "$tmp" ~/.claude/respect/wallet.json
```
This prevents file corruption from concurrent writes.

### `scripts/detect-feedback.sh`

Runs via `UserPromptSubmit` hook. Steps:

1. Read `user_prompt` from stdin JSON
2. **If prompt starts with `/` (any slash command): exit 0 silently — do not process**
3. If `corrections.enabled` is false: exit 0 silently
4. Load correction patterns for configured sensitivity + any `custom_patterns`
5. Match against prompt case-insensitively
6. If a pattern matches:
   - Compute new balance as `max(0, balance + corrections.delta)`
   - If balance was already 0: still append a history entry with `delta: 0` and `reason: "correction_at_floor"` (so the event is recorded), but do not increment `lifetime_lost`
   - If balance decreased: append history entry, increment `lifetime_lost` by `abs(delta)`, write wallet atomically, output system message noting the change
7. If no match: exit 0 silently

The hook never blocks the prompt — it always exits 0. It only injects a `systemMessage` when a correction is detected.

### `skills/respect-setup/skill.md`

Onboarding wizard. Detects on invocation whether `~/.claude/respect/config.json` already exists. If it does, asks whether to reconfigure or cancel.

Interactively asks (one question at a time):
1. Tier names — accept defaults or name them (3–6 tiers)
2. Tier thresholds — balance required for each
3. Tip sizes — values for small/medium/large
4. Which behaviors to enable (lists all defaults, user confirms/disables each)
5. Correction sensitivity — low/medium/high

Writes the resulting `config.json` atomically. Reports summary of what was configured and how to edit it later.

The `config.example.json` in the repo root serves power users who want to pre-configure before installation: copy it to `~/.claude/respect/config.json`, edit, then install the plugin. `init-wallet.sh` will not overwrite it.

### `scripts/tip.sh`

All tip accounting logic lives here. Claude never calls this directly — it is only invoked by the skill and never by the agent itself. This is the trust boundary: the wallet is owned by scripts, not by the agent.

Accepts arguments: `<size_or_custom> [reason text]`
- `size_or_custom`: one of the named sizes from `tips.sizes` (e.g. `small`, `medium`, `large`) or `custom N` if `allow_custom: true`

Steps:
1. Resolve tip amount: look up named size in `tips.sizes`, or parse N from `custom N`
2. Validate: named size must exist in config; custom N must be a positive integer within `max_custom`; if `allow_custom: false` and `custom` is passed, exit with error
3. If `tips.require_reason` is true: check for reason text; if missing, print error message to stdout and exit non-zero (skill will relay this to user)
4. If `tips.max_per_session` is set: sum tip deltas from history for current session; if limit would be exceeded, print remaining budget and apply only the allowed amount
5. Compute new balance, recalculate tier from config thresholds, update `lifetime_earned`, append history entry (reason: `"tip"` or provided reason text), write wallet atomically
6. Print structured result to stdout (consumed by skill.md):
```
DELTA=+3
OLD_BALANCE=12
NEW_BALANCE=15
OLD_TIER=contributor
NEW_TIER=trusted
TIER_CHANGED=true
```

### `skills/tip/skill.md`

User-facing entry point only. Accepts `/tip small|medium|large [reason]` or `/tip custom N [reason]`.

Steps:
1. Pass all arguments verbatim to `bash $CLAUDE_PLUGIN_ROOT/scripts/tip.sh`
2. Read stdout result from the script
3. If script exited non-zero: relay the error message to the user, stop
4. Parse the structured result and respond conversationally

Claude never modifies `wallet.json`. It only reports what `tip.sh` wrote.

Example responses:
- No tier change: "Respect received (+3). Balance: 12 → 15. Tier: contributor."
- Tier up: "Respect received (+5). Balance: 28 → 33. Tier: contributor → trusted. Applying more thorough reasoning from here."
- Error: "Session tip budget reached. Remaining: 2 pts. Use `/tip small` to apply within budget."

### `hooks/hooks.json`

`$CLAUDE_PLUGIN_ROOT` is provided by the Claude Code plugin runtime and resolves to the installed plugin directory.

```json
{
  "description": "Respect economy hooks",
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

### Status Line Integration

The plugin cannot modify the user's `statusline.sh` directly. `docs/statusline-snippet.md` ships a copy-paste snippet that reads both wallet and config to honor the configured format string:

```bash
# Add to ~/.claude/statusline.sh
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

Since `statusline.sh` runs on every status line render, the balance update from `/tip` is visible immediately after the skill writes the wallet.

**Known limitation:** The snippet reads the `tier` name directly from `wallet.json`'s cached field rather than recalculating from balance + config thresholds. This means if a user edits tier thresholds in `config.json` between sessions, the displayed tier name may be stale until the next `SessionStart` hook fires (which recalculates and updates the cached value). This is an acceptable tradeoff for a status line renderer that must be fast and stateless.

---

## Tests

Tests use [bats-core](https://github.com/bats-core/bats-core). Each test runs against fixture wallet/config files in `tests/fixtures/` — no live `~/.claude/` files touched.

### Unit Tests

**`test_tip.bats`**
- Named size resolves to correct delta from config
- `custom N` applies when `allow_custom: true`
- `custom N` rejected when `allow_custom: false`
- `max_custom` cap enforced
- `max_per_session` stops tips at limit, reports remaining budget
- `require_reason: true` blocks tip without reason
- History entry appended with correct fields
- History capped at 500 entries on write

**`test_corrections.bats`**
- Low/medium/high sensitivity patterns each fire correctly (case-insensitive)
- Custom patterns fire correctly
- Balance decrements by configured `corrections.delta`
- Balance floor: `max(0, balance + delta)` enforced
- At floor: history entry written with `delta: 0, reason: correction_at_floor`; `lifetime_lost` not incremented
- Prompt starting with `/` exits silently without modifying wallet
- `corrections.enabled: false` exits silently

**`test_tiers.bats`**
- Tier recalculates correctly for each threshold boundary (balance = threshold - 1, threshold, threshold + 1)
- Tier recalculates correctly after config threshold change (stored tier overridden by recalculation)
- `tier_index` stored correctly after recalculation

**`test_session_start.bats` (integration)**
- System message contains correct tier name for wallet state
- System message lists only behaviors where `enabled: true` and `min_tier <= tier_index`
- System message omits behaviors above current tier
- Pattern analysis fields present and numerically correct (avg tip, correction count, net trend)
- Session counter incremented on each run

---

## Data Flow

### Session start
```
Claude Code starts
  -> SessionStart hook fires
  -> session-start.sh runs
  -> init-wallet.sh creates files if missing (per-file)
  -> wallet + config loaded
  -> tier recalculated from balance + config thresholds
  -> active behaviors filtered
  -> system message injected into Claude context
```

### User tips
```
User: /tip large "great debugging"
  -> UserPromptSubmit hook fires -> detect-feedback.sh sees leading "/" -> exits silently
  -> tip skill.md runs
  -> skill delegates to scripts/tip.sh with args: "large great debugging"
  -> tip.sh resolves "large" = 5 from config, validates, updates wallet.json atomically
  -> tip.sh prints structured result to stdout
  -> skill reads result, responds conversationally
  -> status line re-renders with new balance
  (Claude never touches wallet.json directly)
```

### Correction detected
```
User: "that's wrong, revert that"
  -> UserPromptSubmit hook fires
  -> detect-feedback.sh: no leading "/", corrections enabled
  -> "revert that" matches medium sensitivity (case-insensitive)
  -> new balance = max(0, 15 + (-1)) = 14
  -> wallet.json updated atomically
  -> system message injected: "Balance decreased: 15 -> 14 (correction detected)"
  -> prompt continues to Claude normally
```

---

## Configuration Philosophy

All behavior names, tier names, thresholds, and instruction text are user-defined. The scripts contain no hardcoded tier names, tier counts, or behavior IDs — they iterate arrays from `config.json`. A user can:

- Rename all tiers ("padawan", "jedi", "master")
- Add or remove tiers entirely
- Write custom behavior instructions
- Disable any behavior
- Add custom correction patterns
- Enable `confirmation_reduction` if they want risky autonomy

The plugin ships with one opinionated default config. Users edit `~/.claude/respect/config.json` to customize.

**Schema versioning:** Both `wallet.json` and `config.json` carry a `schema_version` field. Future versions of the plugin may add new fields with safe defaults. Scripts check `schema_version` and warn (via stderr) if they encounter a version they do not recognize, but continue operating on known fields.

---

## Out of Scope

- Automatic quality detection (no AI-based reward signals)
- Cross-device wallet sync
- Multiple wallets / per-project wallets
- Tip cooldowns
- Automated config migration tooling (manual migration notes in README per version)
