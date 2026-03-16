#!/usr/bin/env bash
# demo-runner.sh — Fully scripted respect plugin demo
# Simulates a styled Claude Code session from start to finish.

# ── Colors ───────────────────────────────────────────────────
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
BRIGHT_GREEN='\033[92m'
CYAN='\033[36m'
YELLOW='\033[33m'
RED='\033[31m'
PURPLE='\033[35m'
GRAY='\033[90m'

# Clear the terminal, then pause so VHS Show resumes on a clean screen before content
printf '\033[2J\033[H'
sleep 0.6

# ── Helpers ───────────────────────────────────────────────────
type_text() {
  local text="$1"
  local delay="${2:-0.04}"
  for ((i=0; i<${#text}; i++)); do
    printf "%s" "${text:$i:1}"
    sleep "$delay"
  done
}

bash_prompt() {
  local dir="${1:-~}"
  printf "\n${BRIGHT_GREEN}${BOLD}  ${dir}${RESET} ${BOLD}\$${RESET} "
}

claude_say() {
  printf "  ${CYAN}${1}${RESET}\n"
}

# ── Scene 1: timeout fails (0-3s) ─────────────────────────────
bash_prompt "~/my-project"
type_text "timeout 5 echo 'deploy complete'" 0.03
printf "\n"
sleep 0.2
printf "  ${RED}zsh: command not found: timeout${RESET}\n"
sleep 1

# ── Scene 2: /oops creates a guard (3-9s) ─────────────────────
printf "\n"
bash_prompt "~/my-project"
type_text "/oops large you used timeout which doesn't exist on macOS" 0.03
printf "\n"
sleep 0.3
printf "\n  ${PURPLE}${BOLD}Claude${RESET}\n"
claude_say "Learning saved: Don't use \`timeout\` on macOS — use \`gtimeout\`"
claude_say "Guard created: fires before every bash command containing 'timeout'"
printf "\n  ${RED}−5 pts${RESET}  Balance: 5  •  Tier: lurker 👤\n"
sleep 1

# ── Scene 3: New session — guard fires (9-14s) ────────────────
clear
printf "  ${GRAY}─── new session  ·  ~/other-project ───${RESET}\n"
sleep 0.5
bash_prompt "~/other-project"
type_text "timeout 10 ./run-tests.sh" 0.03
printf "\n"
sleep 0.3
printf "\n  ${YELLOW}${BOLD}⚠  Guard [no-timeout]${RESET}${YELLOW}: timeout is not available on macOS${RESET}\n"
printf "  ${DIM}   Lesson: Don't use \`timeout\` on macOS${RESET}\n"
sleep 1
printf "  ${YELLOW}${BOLD}   Action blocked.${RESET}\n"
sleep 1

# ── Scene 4: /tip rewards good work (14-18s) ──────────────────
printf "\n"
bash_prompt "~/other-project"
type_text "/tip large great refactor on the auth module" 0.03
printf "\n"
sleep 0.3
printf "\n  ${PURPLE}${BOLD}Claude${RESET}\n"
claude_say "Learning saved: Extract auth logic into dedicated middleware"
printf "\n  ${GREEN}+5 pts${RESET}  Balance: 10  •  Tier: lurker 👤\n"
sleep 1.5
printf "\n  ${GRAY}Every session, Claude gets better.${RESET}\n"
sleep 1.5
