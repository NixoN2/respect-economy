---
name: respect-stats
description: This skill should be used when the user types "/respect-stats", asks about "my stats", "my balance", "tier progress", "how am I doing", or wants to see respect economy analytics and performance history.
---

# Respect Stats

Shows analytics about the respect economy: session history, tip/correction ratio, learning count, and tier progress.

## Usage

1. Read the wallet file at `~/.claude/respect/wallet.json`
2. Read the config file at `~/.claude/respect/config.json`
3. Read the feedback file from auto-memory (find it via the memory directory for current CWD)
4. Calculate and display:

**Format your response exactly like this:**

```
Respect Stats
═══════════════════════════════════

[emoji] [tier_name] | Balance: [N]
Progress to next tier: [balance]/[next_threshold] ([percentage]%)
[progress bar ████░░░░░░]

Sessions: [N]
Lifetime earned: [N] | Lifetime lost: [N]

Tips: [count] | Corrections: [count]
Tip/Correction ratio: [N]:1
Avg tip size: [N] pts

Learnings: [count from feedback file]
Mistakes recorded: [count from feedback file]
Simple tips: [count from feedback file]

Top valued patterns:
- [from wallet history, top 3 reasons by delta]

Performance trend: [improving/declining] ([+/-N] last 3 sessions)
```

5. For the progress bar: use █ for filled and ░ for empty, 20 chars wide
6. Count learnings by counting `### ` headers under `## Learnings` in respect-feedback.md
7. Count mistakes by counting `### ` headers under `## Mistakes to Avoid`
8. Count simple tips by counting `- ✅` lines under `## What I Did Well`
9. If no next tier exists (already at max), show "Max tier reached!"
