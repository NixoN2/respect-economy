#!/usr/bin/env bash
# Pre-action mistake prevention hook
# Executes guard scripts from global and project-local directories
# when tool actions match trigger keywords.

# Catch all errors - always return valid JSON
trap 'echo "{}"; exit 0' ERR

# Read tool context from stdin
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input | del(.description) | [.. | strings] | join(" ")' 2>/dev/null || echo "")
TOOL_INPUT_RAW=$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null || echo "{}")
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || echo "")

# Default allowed tools (when guard has no "tools" field)
DEFAULT_TOOLS="Bash|Write|Edit|NotebookEdit"

# Build list of guard directories to scan: global + project-local
GUARD_DIRS=""
GLOBAL_GUARDS="$HOME/.claude/respect/guards"
[ -d "$GLOBAL_GUARDS" ] && GUARD_DIRS="$GLOBAL_GUARDS"

if [ -n "$CWD" ]; then
  # Encode CWD the same way Claude does for project memory: replace / and . with -
  ENCODED_CWD=$(echo "$CWD" | sed 's/[\/.]/-/g')
  LOCAL_GUARDS="$HOME/.claude/projects/${ENCODED_CWD}/guards"
  if [ -d "$LOCAL_GUARDS" ]; then
    GUARD_DIRS="${GUARD_DIRS:+$GUARD_DIRS }$LOCAL_GUARDS"
  fi
fi

if [ -z "$GUARD_DIRS" ]; then
  echo '{}'
  exit 0
fi

# Convert tool input to lowercase for trigger matching
TOOL_INPUT_LOWER=$(echo "$TOOL_INPUT" | tr '[:upper:]' '[:lower:]')

# Scan trigger files for keyword matches across all guard directories
for guards_dir in $GUARD_DIRS; do
  for trigger_file in "$guards_dir"/*.json; do
    [ -f "$trigger_file" ] || continue

    # Check if this guard applies to the current tool
    # If "tools" field exists, match TOOL_NAME against the regex patterns
    # If "tools" field is absent, use default tools list
    TOOL_PATTERNS=$(jq -r '.tools[]? // empty' "$trigger_file" 2>/dev/null) || true

    TOOL_MATCH=false
    if [ -z "$TOOL_PATTERNS" ]; then
      # No tools field — use default filter
      if echo "$TOOL_NAME" | grep -qE "^($DEFAULT_TOOLS)$"; then
        TOOL_MATCH=true
      fi
    else
      # Match TOOL_NAME against each pattern from the tools array
      while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        if echo "$TOOL_NAME" | grep -qE "$pattern"; then
          TOOL_MATCH=true
          break
        fi
      done <<< "$TOOL_PATTERNS"
    fi

    if [ "$TOOL_MATCH" != true ]; then
      continue
    fi

    # Read triggers array from JSON
    TRIGGERS=$(jq -r '.triggers[]? // empty' "$trigger_file" 2>/dev/null) || continue
    [ -z "$TRIGGERS" ] && continue

    MATCHED=false
    while IFS= read -r trigger; do
      [ -z "$trigger" ] && continue
      trigger_lower=$(echo "$trigger" | tr '[:upper:]' '[:lower:]')
      # Use -w (word boundary) only for pure-word triggers (letters/numbers/underscore)
      # Use plain -F for triggers containing punctuation (e.g., "config.", ".env")
      if echo "$trigger_lower" | grep -qE '[^[:alnum:]_]'; then
        GREP_FLAGS="-qF"
      else
        GREP_FLAGS="-qwF"
      fi
      if echo "$TOOL_INPUT_LOWER" | grep $GREP_FLAGS -- "$trigger_lower"; then
        MATCHED=true
        break
      fi
    done <<< "$TRIGGERS"

    if [ "$MATCHED" = true ]; then
      # Find the corresponding guard script
      GUARD_SCRIPT="${trigger_file%.json}.sh"
      if [ -x "$GUARD_SCRIPT" ]; then
        # Execute guard script with tool context
        GUARD_OUTPUT=""
        if GUARD_OUTPUT=$(bash "$GUARD_SCRIPT" "$TOOL_NAME" "$TOOL_INPUT_RAW" 2>/dev/null); then
          # Guard passed (exit 0) - no warning needed
          continue
        fi

        if [ -n "$GUARD_OUTPUT" ]; then
          LESSON=$(jq -r '.lesson // ""' "$trigger_file" 2>/dev/null) || true
          GUARD_NAME=$(basename "$trigger_file" .json)
          SCOPE="global"
          [ "$guards_dir" != "$GLOBAL_GUARDS" ] && SCOPE="local"
          REASON="Guard [$GUARD_NAME] ($SCOPE): ${GUARD_OUTPUT}"
          if [ -n "$LESSON" ]; then
            REASON="${REASON} (Lesson: ${LESSON})"
          fi
          echo "$REASON" >&2
          exit 2
        fi
      fi
    fi
  done
done

echo '{}'
