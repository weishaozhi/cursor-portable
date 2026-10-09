#!/usr/bin/env bash
# pull.sh — Unix counterpart of pull.ps1
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURSOR_USER="${HOME}/.cursor"
USER_SKILLS="${CURSOR_USER}/skills"
USER_ARGV="${CURSOR_USER}/argv.json"
PROJECT_DIR="$(pwd)"
PROJECT_CURSOR="${PROJECT_DIR}/.cursor"
PROJECT_SKILLS="${PROJECT_CURSOR}/skills"
PROJECT_RULES="${PROJECT_CURSOR}/rules"

DST_SKILLS="${REPO_ROOT}/skills"
DST_RULES="${REPO_ROOT}/rules"
DST_ARGV="${REPO_ROOT}/user/argv.json"

step() { printf "\033[36m==> %s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m[ok]\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m[warn]\033[0m %s\n" "$*"; }

[[ -d "$USER_SKILLS" ]] && {
    mkdir -p "$DST_SKILLS"; rm -rf "${DST_SKILLS:?}/"*; cp -R "$USER_SKILLS/." "$DST_SKILLS/"; ok "user skills pulled"
} || warn "no $USER_SKILLS"

[[ -d "$PROJECT_SKILLS" ]] && {
    mkdir -p "$DST_SKILLS"; cp -R "$PROJECT_SKILLS/." "$DST_SKILLS/"; ok "project skills overlaid"
}

[[ -d "$PROJECT_RULES" ]] && {
    mkdir -p "$DST_RULES"; rm -rf "${DST_RULES:?}/"*; cp -R "$PROJECT_RULES/." "$DST_RULES/"; ok "project rules pulled"
} || warn "no project rules"

[[ -f "$USER_ARGV" ]] && { mkdir -p "$(dirname "$DST_ARGV")"; cp "$USER_ARGV" "$DST_ARGV"; ok "argv.json pulled"; }

step "Done. Review with: git status  &&  git diff"