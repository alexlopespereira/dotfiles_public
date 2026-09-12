#!/bin/bash
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

DIM='\033[2m'
CYAN='\033[2;36m'
YELLOW='\033[2;33m'
RESET='\033[0m'

if [ -n "$used" ]; then
  printf "${CYAN}%s${RESET} ${DIM}|${RESET} ${YELLOW}Contexto: %.0f%%${RESET}" "$model" "$used"
else
  printf "${CYAN}%s${RESET}" "$model"
fi
