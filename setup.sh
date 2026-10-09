#!/usr/bin/env bash
# setup.sh — Cursor Portable Bootstrapper (macOS / Linux)
#
# Idempotent. Usage:
#   ./setup.sh                       # ~/.cursor and current dir
#   ./setup.sh --project-dir ~/work  # project rules/skills -> ~/work/.cursor
#   ./setup.sh --skip-user           # project-only
#   ./setup.sh --skip-project        # user-only
#   ./setup.sh --skip-npm            # skip npm install
#   ./setup.sh --dry-run             # print plan, change nothing

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURSOR_USER="${HOME}/.cursor"
BRIDGE_DST="${CURSOR_USER}/bin/mcp-bridge"
USER_SKILLS_DST="${CURSOR_USER}/skills"
USER_MCP_DST="${CURSOR_USER}/mcp.json"

PROJECT_DIR="$(pwd)"
SKIP_USER=0
SKIP_PROJECT=0
SKIP_NPM=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        --skip-user) SKIP_USER=1; shift ;;
        --skip-project) SKIP_PROJECT=1; shift ;;
        --skip-npm) SKIP_NPM=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        *) echo "unknown flag: $1"; exit 1 ;;
    esac
done

PROJECT_CURSOR="${PROJECT_DIR}/.cursor"
PROJECT_SKILLS_DST="${PROJECT_CURSOR}/skills"
PROJECT_RULES_DST="${PROJECT_CURSOR}/rules"

step() { printf "\033[36m==> %s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m[ok]\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m[warn]\033[0m %s\n" "$*"; }
dry()  { printf "  \033[90m[dry-run]\033[0m %s\n" "$*"; }

# ---------- PREFLIGHT ----------
step "Preflight checks"

command -v node >/dev/null 2>&1 && ok "node $(node --version 2>/dev/null || echo ?)" || warn "node not on PATH"
command -v npm  >/dev/null 2>&1 && ok "npm  $(npm  --version 2>/dev/null || echo ?)" || warn "npm not on PATH"
command -v git  >/dev/null 2>&1 && ok "git  $(git  --version 2>/dev/null | awk '{print $3}')" || warn "git not on PATH"

for f in bin/mcp-bridge/mcp-bridge.js bin/mcp-bridge/package.json user/mcp.json; do
    [[ -e "${REPO_ROOT}/$f" ]] || { echo "repo layout broken: missing $f" >&2; exit 1; }
done
ok "repo layout ok"

# ---------- USER LAYER ----------
if [[ $SKIP_USER -eq 0 ]]; then
    step "User layer: $CURSOR_USER"

    if [[ $DRY_RUN -eq 1 ]]; then
        dry "would create $BRIDGE_DST"
        dry "would copy bin/mcp-bridge/* -> $BRIDGE_DST"
    else
        mkdir -p "$BRIDGE_DST"
        cp -R "${REPO_ROOT}/bin/mcp-bridge/." "$BRIDGE_DST/"
        ok "bridge copied to $BRIDGE_DST"
    fi

    if [[ -f "${BRIDGE_DST}/package.json" && $SKIP_NPM -eq 0 && $DRY_RUN -eq 0 ]]; then
        if [[ -d "${BRIDGE_DST}/node_modules" && -z "${CURSOR_PORTABLE_FORCE_NPM:-}" ]]; then
            ok "node_modules present, skipping npm install"
        elif command -v npm >/dev/null 2>&1; then
            step "npm install in bridge dir"
            (cd "$BRIDGE_DST" && npm install --omit=dev --no-audit --no-fund) || warn "npm install failed"
            ok "deps installed"
        else
            warn "npm not found on PATH"
        fi
    fi

    if [[ -f "${REPO_ROOT}/user/mcp.json" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            dry "would write $USER_MCP_DST (uses \${userHome})"
        else
            cp "${REPO_ROOT}/user/mcp.json" "$USER_MCP_DST"
            ok "wrote $USER_MCP_DST (uses \${userHome})"
        fi
    fi

    if [[ -d "${REPO_ROOT}/skills" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            dry "would mirror skills/ -> $USER_SKILLS_DST"
        else
            mkdir -p "$USER_SKILLS_DST"
            cp -R "${REPO_ROOT}/skills/." "$USER_SKILLS_DST/"
            ok "user skills synced to $USER_SKILLS_DST"
        fi
    else
        warn "no skills/ in repo"
    fi
fi

# ---------- PROJECT LAYER ----------
if [[ $SKIP_PROJECT -eq 0 ]]; then
    step "Project layer: $PROJECT_CURSOR"
    if [[ ! -d "$PROJECT_DIR" ]]; then
        warn "project dir not found: $PROJECT_DIR"
    elif [[ $DRY_RUN -eq 1 ]]; then
        dry "would mirror rules/  -> $PROJECT_RULES_DST"
        dry "would mirror skills/ -> $PROJECT_SKILLS_DST"
    else
        mkdir -p "$PROJECT_CURSOR"
        [[ -d "${REPO_ROOT}/rules"  ]] && { mkdir -p "$PROJECT_RULES_DST";  cp -R "${REPO_ROOT}/rules/."  "$PROJECT_RULES_DST/";  ok "rules synced to $PROJECT_RULES_DST"; }
        [[ -d "${REPO_ROOT}/skills" ]] && { mkdir -p "$PROJECT_SKILLS_DST"; cp -R "${REPO_ROOT}/skills/." "$PROJECT_SKILLS_DST/"; ok "skills synced to $PROJECT_SKILLS_DST"; }
    fi
fi

step "Done."
echo ""
echo "Next:"
if [[ $DRY_RUN -eq 1 ]]; then
    echo "  (dry-run) no files were modified. re-run without --dry-run to apply."
else
    echo "  - Restart Cursor (or reload window) so the new mcp.json takes effect."
    echo "  - Install extensions: see extensions.txt (manual list)."
    echo "  - To capture future edits back into this repo, run: ./pull.sh"
fi