---
name: tip
description: This skill should be used when the user types "/tip", gives a tip, says "good job" with a size keyword (small/medium/large/custom), or wants to reward Claude for good work. Handles natural language tip parsing and learning extraction.
---

# Tip Skill

User-facing entry point for tipping. Accepts tip size anywhere in the message: `/tip medium`, `/tip i think you deserve it medium`, `/tip custom 5 great work`, etc.

## Usage

1. **Use LLM intelligence to parse and extract learning:**
   - Identify the tip size keyword: `small`, `medium`, `large`, or `custom N`
   - For `custom`: extract the adjacent number (e.g., `custom 5`, `5 custom`, `custom10`)
   - **Analyze the tip in context of the recent conversation** (last 5-10 messages)
   - **Determine if this tip represents a meaningful learning:**
     - Has actionable lesson that can be applied in future?
     - Specific enough to guide future behavior?
     - If NO: treat as simple appreciation (just store summary)
     - If YES: extract structured learning

   **Learning extraction examples:**

   *Meaningful learning:*
   - "I want to give you a tip for a correct update of the plugin on github. first, apply changes to the repository where skill lies instead of a local .claude and then also upgrade the version. brilliant. large tip"
     → **Structured learning:**
       - Summary: `correct github workflow: repo first then version bump`
       - Lesson: Push repository changes before version bumping
       - Context: Publishing plugin updates to marketplace
       - Why: Prevents version conflicts and maintains proper release sequence

   *Simple appreciation (not a learning):*
   - "custom 10 amazing work you're the best"
     → **Simple tip:** Just store summary "positive feedback" (no structured learning)

   - "medium you did great"
     → **Simple tip:** Store "general appreciation" (too vague for learning)

2. Run: `bash "$(cat ~/.claude/respect/plugin_root)/scripts/tip.sh" <size> [N for custom] [summarized reason]`
   - Pass the tip size, number (if custom), AND the SHORT summarized reason
   - The script stores the summary in wallet history for tracking

3. If script exited non-zero: relay the error message to the user, stop
4. Parse the structured KEY=VALUE result and respond conversationally

5. **Write to auto-memory** (durable learning):
   - Read current respect-feedback.md from the auto-memory directory for the current working directory
     - Memory dir: `~/.claude/projects/[ENCODED_CWD]/memory/` where ENCODED_CWD = CWD with `/` and `.` replaced by `-`
   - If structured learning was extracted, add under "## Learnings" section:
     ```markdown
     ### YYYY-MM-DD | [Summary] (+N)
     **Lesson:** [What to do in the future]
     **Context:** [When this applies]
     **Why:** [Reasoning behind the approach]
     **Session:** N
     ```
   - If simple tip (no learning), add under "## What I Did Well" section:
     ```markdown
     - ✅ [summary] (+N pts, session S)
     ```
   - Keep file concise: if "## Learnings" exceeds 20 entries, remove oldest
   - If "## What I Did Well" exceeds 30 entries, remove oldest
   - This creates persistent, actionable memory across sessions

6. **Determine learning scope** (cross-project or local):
   - For each structured learning, decide if it is **global** or **local**:
     - **Global** — lesson applies regardless of project. Examples:
       - Environment/OS: "don't use `timeout` on macOS"
       - Universal practices: "run tests before claiming done"
       - Tool-agnostic habits: "don't hardcode secrets"
       - Workflow patterns: "push repo before bumping version"
     - **Local** — lesson is specific to this codebase. Examples:
       - "use the v2 API for this service"
       - "run `make integration-test` not `make test` in this repo"
       - "config lives in `src/config/` not project root"
   - If **global**, also append the learning to `~/.claude/respect/global-feedback.md`
     - If the file doesn't exist, create it with:
       ```markdown
       # Global Respect Feedback

       Learnings that apply across all projects.

       ## Learnings

       ## Mistakes to Avoid
       ```
     - Add under the `## Learnings` section using the same format
     - Keep the global file concise: max 30 entries under `## Learnings`, remove oldest if exceeded
   - Simple tips (no structured learning) are always local only
   - When writing globally, tell the user: "This learning applies globally across all projects."

## Response format

Parse the output lines:
- `DELTA=+N`
- `OLD_BALANCE=N`
- `NEW_BALANCE=N`
- `OLD_TIER=name`
- `NEW_TIER=name`
- `TIER_CHANGED=true|false`

**No tier change:** "Respect received (+3). Balance: 12 → 15. Tier: contributor."
**Tier up:** "Respect received (+5). Balance: 28 → 33. Tier: contributor → trusted. Applying more thorough reasoning from here."
**Error (non-zero exit):** Relay the error message verbatim.

## Important

Claude never modifies wallet.json. Only tip.sh writes to the wallet. This skill is a UI relay only.
