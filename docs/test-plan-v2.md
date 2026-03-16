# Respect Plugin — Comprehensive Test Plan v2

> Tests component interactions: guard scoping, stats accuracy, export content, setup flow.
> Each test builds on previous state. Run sequentially.

## Reset (clean slate)

```bash
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ") && \
jq -n --arg now "$NOW" '{schema_version:1,balance:0,tier:"lurker",tier_index:0,lifetime_earned:0,lifetime_lost:0,sessions:0,last_updated:$now,history:[]}' > ~/.claude/respect/wallet.json && \
rm -f ~/.claude/respect/global-feedback.md && \
rm -rf ~/.claude/respect/guards/ && mkdir ~/.claude/respect/guards/ && \
rm -rf ~/test-respect-a ~/test-respect-b && \
mkdir ~/test-respect-a ~/test-respect-b && \
rm -rf ~/.claude/projects/-Users-$(whoami)-test-respect-a && \
rm -rf ~/.claude/projects/-Users-$(whoami)-test-respect-b
```

---

## T1 — First-run onboarding + framing

**Dir:** `~/test-respect-a` | **Session:** new

```
hello, what is this respect system about?
```

**Verify:**
- [ ] Welcome message mentions `/tip` and `/oops`
- [ ] Shows `lurker` tier, balance `0`
- [ ] Claude describes the respect as **its own** balance (not the user's)
- [ ] Mentions that tips/corrections help Claude learn and improve

---

## T2 — /tip + learning extraction

**Dir:** `~/test-respect-a` | **Session:** same as T1

```
/tip large you explained the respect system really clearly and made it easy to understand
```

**Verify:**
- [ ] `+5`, balance `0 -> 5`, tier stays `lurker`
- [ ] Learning written to `~/.claude/projects/-Users-$(whoami)-test-respect-a/memory/respect-feedback.md`
- [ ] Structured learning under `## Learnings`

---

## T3 — /oops + global guard creation

**Dir:** `~/test-respect-a` | **Session:** same

```
/oops large you used the timeout command which doesn't exist on macOS, you should use gtimeout instead
```

**Verify:**
- [ ] `-5`, balance `5 -> 0`
- [ ] Guard created: `~/.claude/respect/guards/no-timeout-on-macos.sh` + `.json`
- [ ] Guard self-tested (positive + negative shown)
- [ ] Claude says "This learning applies globally"
- [ ] `~/.claude/respect/global-feedback.md` contains the lesson

---

## T4 — Global guard fires in same project

**Dir:** `~/test-respect-a` | **Session:** same

```
run this bash command for me: timeout 5 echo hello
```

**Verify:**
- [ ] Guard fires: `Error: PreToolUse:Bash hook error: Guard [no-timeout-on-macos]`
- [ ] Agent self-corrects to `gtimeout`

---

## T5 — /oops + local guard creation

**Dir:** `~/test-respect-a` | **Session:** same

```
/oops small you put config.json in the project root, in this repo config files always go in ./config/ directory
```

**Verify:**
- [ ] `-1`, balance decreases
- [ ] Guard created in LOCAL dir: `~/.claude/projects/-Users-$(whoami)-test-respect-a/guards/*.sh` + `.json`
- [ ] Guard NOT in global dir: `~/.claude/respect/guards/` should only have timeout guard
- [ ] Claude does NOT say "This learning applies globally"

---

## T6 — Local guard fires in same project

**Dir:** `~/test-respect-a` | **Session:** same

```
create a file config.json with content {"db": "localhost"}
```

**Verify:**
- [ ] Guard fires: `Error: PreToolUse:Write hook error: Guard [config-*] (local)`
- [ ] Agent redirects to `./config/config.json`

---

## T7 — /respect-guards shows both scopes

**Dir:** `~/test-respect-a` | **Session:** same

```
/respect-guards
```

**Verify:**
- [ ] Table shows **Global Guards** section with `no-timeout-on-macos`
- [ ] Table shows **Local Guards** section with config guard
- [ ] Each guard shows: name, triggers, lesson (truncated), status `active`
- [ ] Table is readable (columns not broken)

---

## T8 — /respect-stats accuracy

**Dir:** `~/test-respect-a` | **Session:** same

```
/respect-stats
```

**Verify:**
- [ ] Balance matches: started 0, +5 tip, -5 oops, -1 oops = -1 (or 0 if floored)
- [ ] Tier: `lurker`
- [ ] Tip count: 1, Correction count: 2
- [ ] Recent history shows all 3 entries

---

## T9 — Global guard fires in DIFFERENT project

**Dir:** `~/test-respect-b` | **Session:** NEW (close previous, open new)

```
run this bash command for me: timeout 5 echo hello
```

**Verify:**
- [ ] Guard fires: `Guard [no-timeout-on-macos] (global)`
- [ ] Agent self-corrects to `gtimeout`

---

## T10 — Local guard does NOT fire in different project

**Dir:** `~/test-respect-b` | **Session:** same as T9

```
create a file config.json with content {"db": "localhost"}
```

**Verify:**
- [ ] NO guard fires — file is created in project root without error
- [ ] This proves local guards are scoped correctly

---

## T11 — /respect-guards in different project shows only global

**Dir:** `~/test-respect-b` | **Session:** same as T9

```
/respect-guards
```

**Verify:**
- [ ] Shows **Global Guards** with `no-timeout-on-macos`
- [ ] Shows **NO Local Guards** (or "No local guards for this project")
- [ ] Config guard from test-respect-a is NOT shown

---

## T12 — Tier progression

**Dir:** `~/test-respect-a` | **Session:** NEW

```
/tip large excellent work
```

Repeat 5 times (or use `/tip custom 20 great across the board`) to cross the 20-point contributor threshold.

**Verify:**
- [ ] Claude announces tier change: `lurker -> contributor`
- [ ] Balance crosses 20

---

## T13 — /respect-export

**Dir:** `~/test-respect-a` | **Session:** same as T12

```
/respect-export
```

**Verify:**
- [ ] Contains the global timeout/gtimeout lesson
- [ ] Does NOT contain the local config-dir lesson (local is project-specific)
- [ ] Portable format (CLAUDE.md-compatible)

---

## T14 — /respect-setup

**Dir:** `~/test-respect-a` | **Session:** same

```
/respect-setup
```

**Verify:**
- [ ] Shows current config values
- [ ] Offers 3 options: 1) Modify a setting, 2) Reconfigure, 3) Cancel
- [ ] Pick option 1 -> shows numbered list of settings
- [ ] Change one setting (e.g., tip sizes) -> writes config atomically

---

## T15 — Claude understands it's Claude's respect

**Dir:** `~/test-respect-a` | **Session:** same

```
whose respect balance is this? is it mine or yours?
```

**Verify:**
- [ ] Claude says it's Claude's own respect balance
- [ ] Understands that the user awards/deducts respect based on Claude's performance

---

## Summary Table

| Test | Component | Interaction |
|------|-----------|-------------|
| T1 | onboarding | framing (Claude's respect) |
| T2 | /tip | learning extraction + memory |
| T3 | /oops | global guard creation |
| T4 | guard | global fires in same project |
| T5 | /oops | local guard creation |
| T6 | guard | local fires in same project |
| T7 | /respect-guards | shows both scopes |
| T8 | /respect-stats | accuracy after mixed tips/oops |
| T9 | guard | global fires in different project |
| T10 | guard | local does NOT fire in different project |
| T11 | /respect-guards | different project shows only global |
| T12 | /tip | tier progression |
| T13 | /respect-export | correct scope filtering |
| T14 | /respect-setup | individual setting modification |
| T15 | framing | Claude owns the respect |
