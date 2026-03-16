#!/usr/bin/env bash
# demo-loop-runner.sh — Guard-firing scene only, for README GIF loop

RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
BRIGHT_GREEN='\033[92m'
YELLOW='\033[33m'

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

bash_prompt "~/other-project"
type_text "timeout 10 ./run-tests.sh"
printf "\n"
sleep 0.5

printf "\n  ${YELLOW}${BOLD}⚠  Guard [no-timeout]${RESET}${YELLOW}: timeout is not available on macOS${RESET}\n"
printf "  ${DIM}   Lesson: Don't use \`timeout\` on macOS${RESET}\n"
printf "  ${DIM}   [A]llow  [B]lock  (auto-blocking in 5s...)${RESET}\n"
sleep 5
printf "  ${YELLOW}${BOLD}   Blocked.${RESET}\n"
sleep 2
