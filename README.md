# respect

> **Teach Claude once — it remembers forever.**

A feedback system for [Claude Code](https://claude.ai/code) that turns corrections into executable guard scripts and tips into persistent learnings — across every session and every project.

![respect demo](assets/demo-guard-loop.gif)

## Install in 30 seconds

```bash
claude plugin marketplace add NixoN2/respect
claude plugin install respect@respect
```

Restart Claude Code. Requires `jq` on your PATH.

## What Makes This Different

**🧠 AI-Powered Learning Extraction**
Write natural feedback like "great job on the github workflow, you updated the repo first then bumped the version" — Claude analyzes the conversation context and extracts a **structured learning** with lesson, context, and reasoning. Generic praise stays as appreciation. Only actionable feedback becomes a durable learning.

**🛡️ Guard Scripts — Executable Mistake Prevention**
`/oops` doesn't just record what went wrong — it generates a **guard script** that programmatically detects the mistake before it happens. Date checks, grep patterns, file existence — real code that runs on every action via a `PreToolUse` hook.

```
⚠️ Guard [no-timeout]: timeout is not available on macOS - use gtimeout
   Lesson: Don't use timeout command on macOS
   Action blocked.
```

Guards work on Bash commands, file writes, **and MCP tools** — target Slack, Datadog, GitHub, or any custom MCP server with regex patterns.

**🌍 Cross-Project Memory**
Claude decides if each learning is project-specific or universal. Universal lessons (like "don't use `timeout` on macOS" or "push repo before bumping version") are stored globally and loaded in **every project**. Teach once, apply everywhere.

**📊 Full Analytics Suite**
Six slash commands for the complete feedback loop:

| Command | What it does |
|---------|-------------|
| `/tip` | Reward good work. Natural language — size keyword anywhere in the message |
| `/oops` | Correct a mistake. Generates guard scripts + persistent learnings |
| `/respect-stats` | Tier progress, tip/correction ratio, trends, top patterns |
| `/respect-export` | Export learnings as portable CLAUDE.md — carry training to any project |
| `/respect-guards` | List, test, fix, or delete guard scripts |
| `/respect-setup` | Configure tiers, thresholds, tip sizes, and emoji |

**🏆 Tier Progression**
Earn points to climb tiers. A visible record of the trust you've built.

| Tier | Balance | |
|------|:-------:|---|
| lurker | 0 | 👤 |
| contributor | 20 | 🌱 |
| trusted | 60 | ⚡ |
| veteran | 150 | 🔥 |
| partner | 300 | 🤝 |

**🎉 First-Run Onboarding**
New users get a welcome message explaining the system on their first session. No setup required — just install and start using `/tip` and `/oops`.

## Quick Start

**Tip when Claude does something well:**
```
/tip large great work on the flexible parsing
/tip medium you handled the edge cases perfectly
/tip custom 10 amazing architecture decision
```

**Correct when Claude makes a mistake:**
```
/oops medium you forgot to bump the version
/oops large you used timeout which doesn't exist on macOS
/oops custom 5 missed the cached plugin directory
```

The size keyword (`small`, `medium`, `large`, `custom N`) can appear anywhere in your message. Claude extracts it intelligently.

**Check your progress:**
```
/respect-stats
/respect-export
/respect-guards
```

## How It Works

**Four systems working together:**

1. **Wallet** — `wallet.json` tracks balance, tier, and history. Scripts update atomically — Claude can't modify it directly.

2. **Learning Extraction** — Claude analyzes conversation context to extract structured learnings from your feedback. Only actionable insights survive. Stored per-project in auto-memory, with universal lessons also saved globally.

3. **Guard Scripts** — `/oops` generates executable bash scripts that run on every tool action. Each guard has a trigger file (keywords + tool patterns) and a script (the actual check). Guards cover Bash, Write, Edit, NotebookEdit, and any MCP tool.

4. **Cross-Project Memory** — Claude evaluates each learning's scope. Project-specific lessons stay local. Universal lessons are stored in `global-feedback.md` and loaded in every project at session start.

### Guard Script Examples

**"Don't use timeout on macOS"** — fires when Bash input contains "timeout":
```json
{"triggers": ["timeout"], "lesson": "Use gtimeout on macOS instead"}
```

**"Don't deploy on Fridays"** — checks the day before git push:
```json
{"triggers": ["git push", "deploy"], "lesson": "Avoid Friday deploys"}
```

**"Don't post to Slack outside work hours"** — targets Slack MCP tools:
```json
{
  "triggers": ["send_message"],
  "tools": ["mcp__.*slack.*"],
  "lesson": "Post during work hours only"
}
```

The `tools` field accepts regex patterns. Omit it to default to Bash/Write/Edit/NotebookEdit. Use `mcp__.*` to match all MCP tools, or target specific servers like `mcp__.*datadog.*`.

### What Becomes a Learning?

**Structured Learnings** (stored with Lesson/Context/Why):
- "You updated the repo first, then bumped version — perfect workflow"
- "You broke the tests by not running them before committing"

**Simple Tips** (stored as appreciation only):
- "Amazing work! You're the best!"
- "Thanks for the help, large tip"

### Points

| Command | Effect |
|---------|--------|
| `/tip small` | +1 pt |
| `/tip medium` | +3 pts |
| `/tip large` | +5 pts |
| `/tip custom N` | +N pts (max 10 by default) |
| `/oops small` | -1 pt |
| `/oops medium` | -3 pts |
| `/oops large` | -5 pts |
| `/oops custom N` | -N pts |

## Status Line

Add to `~/.claude/statusline.sh`:

```bash
WALLET="$HOME/.claude/respect/wallet.json"
R_CONFIG="$HOME/.claude/respect/config.json"
if [ -f "$WALLET" ] && [ -f "$R_CONFIG" ]; then
  R_BALANCE=$(jq -r '.balance // 0' "$WALLET")
  R_NAME=$(jq -r '.tier // ""' "$WALLET")
  R_EMOJI=$(jq -r --arg name "$R_NAME" '.tiers[] | select(.name == $name) | .emoji // ""' "$R_CONFIG")
  R_FORMAT=$(jq -r '.statusline.format // "{emoji} {balance} ({name})"' "$R_CONFIG")
  R_STATUS=$(echo "$R_FORMAT" | sed "s/{emoji}/$R_EMOJI/g; s/{balance}/$R_BALANCE/g; s/{name}/$R_NAME/g")
  echo "$STATUS"
  echo "$R_STATUS"
else
  echo "$STATUS"
fi
```

```
🌱 29 (contributor)
```

## Configuration

Run `/respect-setup` for an interactive wizard, or edit `~/.claude/respect/config.json` directly. See [`config.example.json`](config.example.json) for all available options.

Customizable: tier names, thresholds, emoji, tip sizes, status line format.

## Tests

Requires [bats-core](https://github.com/bats-core/bats-core).

```bash
bats tests/test_tiers.bats tests/test_init.bats tests/test_tip.bats tests/test_correct.bats tests/test_session_start.bats tests/test_guards.bats
```

81 tests covering wallet operations, tier calculations, guard execution, MCP tool matching, first-run onboarding, and global learnings.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
