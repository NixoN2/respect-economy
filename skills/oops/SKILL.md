---
name: oops
description: This skill should be used when the user types "/oops", reports a mistake, says "that was wrong", or wants to correct Claude's behavior. Handles natural language correction parsing, learning extraction, and guard script generation.
---

# Oops Skill

The opposite of /tip. Invoked when Claude made a mistake.

## Usage

Accepts correction size anywhere in the message: `/oops medium`, `/oops that was wrong medium`, `/oops custom 5 bad mistake`, etc.

1. **Use LLM intelligence to parse and extract learning:**
   - Identify the correction size keyword: `small`, `medium`, `large`, or `custom N`
   - For `custom`: extract the adjacent number (e.g., `custom 5`, `5 custom`)
   - **Analyze the mistake in context of the recent conversation** (last 5-10 messages)
   - **Corrections should ALMOST ALWAYS be structured learnings** (mistakes are valuable!)
   - Extract what went wrong, why it was wrong, and what to do instead

   **Learning extraction examples:**

   - "that was completely wrong you broke the tests medium"
     → **Structured learning:**
       - Summary: `broke tests`
       - Lesson: Run tests before claiming work is complete
       - Context: Making code changes without verification
       - Why: Prevents shipping broken functionality

   - "custom 5 bad mistake you forgot to update the version number"
     → **Structured learning:**
       - Summary: `forgot version bump`
       - Lesson: Always bump version when updating plugin
       - Context: Publishing plugin changes
       - Why: Version mismatch prevents proper updates

   - "large you didn't check the cached plugin directory"
     → **Structured learning:**
       - Summary: `missed cached plugin dir`
       - Lesson: Check both installed plugin AND cached ~/.claude directory
       - Context: Plugin development and testing
       - Why: Cached plugins override installed versions

2. Run: `bash "$(cat ~/.claude/respect/plugin_root)/scripts/correct.sh" <size> [N for custom] [summarized reason]`
   - Pass the correction size, number (if custom), AND the SHORT summarized reason
   - The script stores the summary in wallet history for tracking mistakes

3. If script exited non-zero: relay the error message to the user, stop
4. Parse the structured KEY=VALUE result and respond conversationally

5. **Write to auto-memory** (durable learning):
   - Read current respect-feedback.md from the auto-memory directory for the current working directory
     - Memory dir: `~/.claude/projects/[ENCODED_CWD]/memory/` where ENCODED_CWD = CWD with `/` and `.` replaced by `-`
   - Add structured learning under "## Mistakes to Avoid" section:
     ```markdown
     ### YYYY-MM-DD | [Summary] (-N)
     **Lesson:** [What NOT to do / What to do instead]
     **Context:** [When this mistake happened]
     **Why:** [Why this was wrong / Impact of the mistake]
     **Session:** N
     ```
   - Keep file concise: if "## Mistakes to Avoid" exceeds 20 entries, remove oldest
   - This creates persistent memory of mistakes to avoid across sessions

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
     - Add under the `## Mistakes to Avoid` section using the same format as step 5
     - Keep the global file concise: max 30 entries under `## Mistakes to Avoid`, remove oldest if exceeded
   - When writing globally, tell the user: "This learning applies globally across all projects."

7. **Generate a guard script** to prevent this mistake in the future:
   - Create directory `~/.claude/respect/guards/` if it doesn't exist
   - Generate a short, unique filename from the summary (e.g., `no-timeout-on-macos.sh`)
   - Write a guard script that can **programmatically detect** this mistake before it happens
   - Write a trigger file (same name with `.json` extension) with metadata

   **Guard script format:**
   ```bash
   #!/usr/bin/env bash
   # Guard: [summary]
   # Lesson: [lesson text]
   TOOL_NAME="$1"
   TOOL_INPUT="$2"

   # [Check logic here - exit 1 to warn, exit 0 to pass]
   exit 0
   ```

   **Trigger file format:**
   ```json
   {
     "triggers": ["command1", "command2"],
     "lesson": "The lesson text",
     "tools": ["Bash", "mcp__.*slack.*"],
     "created": "YYYY-MM-DD",
     "session": N
   }
   ```

   **Fields:**
   - `triggers` (required): keywords to match in tool input (case-insensitive substring match)
   - `lesson` (required): the lesson text for display
   - `tools` (optional): regex patterns for tool names. If omitted, defaults to `Bash|Write|Edit|NotebookEdit`. Use this to target specific MCP tools (e.g., `mcp__.*slack.*`, `mcp__.*datadog.*`) or any combination.
   - `created`, `session`: metadata

   **How to decide triggers, tools, and check logic:**
   - Analyze the mistake and identify which tool actions could repeat it
   - `triggers` is a list of keywords that appear in tool inputs (commands, filenames, etc.)
   - `tools` controls WHICH tools the guard applies to:
     - Omit for standard guards (Bash/Write/Edit/NotebookEdit)
     - Add MCP patterns like `mcp__.*slack.*` for Slack-specific guards
     - Add `mcp__.*` to match ALL MCP tools
     - Mix with standard tools: `["Bash", "mcp__.*datadog.*"]`
   - The guard script receives TOOL_NAME and TOOL_INPUT as arguments
   - Write a concrete, testable check: date checks, file existence, grep patterns, etc.
   - If the check CANNOT be automated (e.g., "use better variable names"), skip guard generation

   **Examples:**

   *"Don't deploy on Fridays":*
   ```bash
   #!/usr/bin/env bash
   TOOL_NAME="$1"
   TOOL_INPUT="$2"
   if [ "$(date +%u)" -eq 5 ]; then
     echo "It's Friday - avoid deploying"
     exit 1
   fi
   exit 0
   ```
   Triggers: `["git push", "deploy", "kubectl apply"]`

   *"Don't use timeout command on macOS":*
   ```bash
   #!/usr/bin/env bash
   TOOL_NAME="$1"
   TOOL_INPUT="$2"
   if echo "$TOOL_INPUT" | grep -qw "timeout"; then
     echo "timeout is not available on macOS - use gtimeout or alternatives"
     exit 1
   fi
   exit 0
   ```
   Triggers: `["timeout"]`

   *"Run tests before committing":*
   ```bash
   #!/usr/bin/env bash
   TOOL_NAME="$1"
   TOOL_INPUT="$2"
   if echo "$TOOL_INPUT" | grep -q "git commit"; then
     # Check if tests were run in the last 5 minutes
     TEST_LOG=$(find . -name "*.test.*" -newer /tmp/.last_test_run 2>/dev/null)
     if [ -z "$TEST_LOG" ]; then
       echo "No recent test run detected - consider running tests first"
       exit 1
     fi
   fi
   exit 0
   ```
   Triggers: `["git commit"]`

   *"Don't hardcode passwords":*
   ```bash
   #!/usr/bin/env bash
   TOOL_NAME="$1"
   TOOL_INPUT="$2"
   if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
     if echo "$TOOL_INPUT" | grep -qiE '(password|secret|api.key)\s*=\s*"[^"]{4,}"'; then
       echo "Possible hardcoded secret detected"
       exit 1
     fi
   fi
   exit 0
   ```
   Triggers: `["password", "secret", "api_key"]`

   *"Don't post to Slack outside work hours" (MCP guard):*
   ```bash
   #!/usr/bin/env bash
   TOOL_NAME="$1"
   TOOL_INPUT="$2"
   HOUR=$(date +%H)
   if [ "$HOUR" -lt 9 ] || [ "$HOUR" -ge 18 ]; then
     echo "Outside work hours (9-18) - avoid posting to Slack"
     exit 1
   fi
   exit 0
   ```
   Triggers: `["send_message", "send_message_draft"]`
   Tools: `["mcp__.*slack.*"]`

   **If guard generation is not possible** (too abstract, no programmatic check):
   - Skip guard generation silently
   - The learning still gets recorded in respect-feedback.md

8. After generating the guard, tell the user:
   - "Guard created: [filename]. This will warn you before [description]."
   - "If the guard misfires, just tell me 'fix the [name] guard' and I'll update it."

## Response format

Parse: DELTA, OLD_BALANCE, NEW_BALANCE, OLD_TIER, NEW_TIER, TIER_CHANGED

- No tier change: "Noted (-3). Balance: 12 → 9. Tier: trusted."
- Tier down: "Noted (-5). Balance: 33 → 28. Tier: trusted → contributor."
- At floor: "Already at zero. Correction recorded."

Claude never modifies wallet.json directly.
