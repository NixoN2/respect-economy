#!/usr/bin/env bash
# Echoes simulated Claude Code responses for the VHS demo.
# Usage: ./scripts/demo-simulate.sh <scene>

SCENE="$1"

print_slow() {
  local text="$1"
  local delay="${2:-0.03}"
  echo -n "$text" | while IFS= read -rn1 char; do
    echo -n "$char"
    sleep "$delay"
  done
  echo
}

case "$SCENE" in
  timeout_fail)
    # Simulates macOS shell error when `timeout` is not installed
    echo "zsh: command not found: timeout"
    ;;
  guard)
    # Simulates the respect guard hook firing automatically before a Bash command
    echo ""
    print_slow "⚠  Guard [no-timeout]: timeout is not available on macOS — use gtimeout" 0.02
    sleep 0.3
    print_slow "   Lesson: Don't use \`timeout\` on macOS" 0.02
    sleep 0.2
    print_slow "   [A]llow  [B]lock  (auto-blocking in 5s...)" 0.02
    sleep 5
    print_slow "   Blocked." 0.02
    sleep 1
    ;;
  config_parse)
    # Simulates Claude parsing a config file cleanly
    echo ""
    print_slow "> Sure. Reading config.yaml..." 0.03
    sleep 0.4
    print_slow "  database:" 0.02
    print_slow "    host: localhost" 0.02
    print_slow "    port: 5432" 0.02
    print_slow "    name: app_db" 0.02
    sleep 0.3
    print_slow "  Extracted 3 values using jq -r for safe quoting." 0.03
    sleep 0.3
    ;;
  oops)
    echo ""
    print_slow "> Noted. Running /oops: large — you used timeout which doesn't exist on macOS"
    sleep 0.3
    print_slow "  Extracting learning from conversation context..."
    sleep 0.5
    print_slow "  Learning saved: Don't use \`timeout\` on macOS — use \`gtimeout\` (brew install coreutils)"
    sleep 0.3
    print_slow "  Guard script created: ~/.claude/respect/guards/no-timeout/"
    print_slow "    trigger: 'timeout'"
    print_slow "    tools: bash"
    print_slow "    lesson: timeout is not available on macOS — use gtimeout"
    sleep 0.3
    print_slow "  Correction recorded. -5 pts  |  Balance: 5  |  Tier: lurker 👤"
    ;;
  tip)
    echo ""
    print_slow "> Noted. Running /tip: large — great work on the clean config parsing"
    sleep 0.3
    print_slow "  Extracting learning from conversation context..."
    sleep 0.5
    print_slow "  Learning saved (project-specific):"
    print_slow "    Lesson:  Parse config files with jq -r for clean, quoted-safe output"
    print_slow "    Context: User asked to extract values from a nested YAML-style config"
    print_slow "    Why:     Avoids whitespace bugs vs. manual grep/awk extraction"
    sleep 0.3
    print_slow "  Tip recorded. +5 pts  |  Balance: 10  |  Tier: lurker 👤"
    ;;
  stats)
    echo ""
    print_slow "  Respect Stats"
    print_slow "  ─────────────────────────────"
    print_slow "  Tier:     lurker 👤"
    print_slow "  Balance:  10 pts"
    print_slow "  ─────────────────────────────"
    print_slow "  Tips:       2  (+8 pts total)"
    print_slow "  Corrections: 1  (-5 pts total)"
    print_slow "  Ratio:      2:1  (on track)"
    print_slow "  ─────────────────────────────"
    print_slow "  Next tier:  contributor 🌱  (need 10 more pts)"
    print_slow "  ─────────────────────────────"
    print_slow "  Top learnings:"
    print_slow "    • Don't use \`timeout\` on macOS — use gtimeout"
    print_slow "    • Parse configs with jq -r for clean output"
    ;;
  *)
    echo "Usage: $0 <timeout_fail|guard|config_parse|oops|tip|stats>"
    exit 1
    ;;
esac
