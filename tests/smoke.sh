#!/usr/bin/env bash
# tests/smoke.sh — sanity check the repo layout and script syntax.
# Runs in CI on every push. Cheap (no network, no npm install).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

fail() { printf "\033[31m[FAIL]\033[0m %s\n" "$*"; exit 1; }
ok()   { printf "  \033[32m[ok]\033[0m %s\n" "$*"; }

echo "==> smoke test"

# 1. Required files
required=(
    "bin/mcp-bridge/mcp-bridge.js"
    "bin/mcp-bridge/package.json"
    "user/mcp.json"
    "setup.sh"
    "setup.ps1"
    "pull.sh"
    "pull.ps1"
    "manifest.json"
    "README.md"
    "LICENSE"
    ".gitignore"
    ".gitattributes"
    ".editorconfig"
    "extensions.txt"
)
for f in "${required[@]}"; do
    [[ -e "$f" ]] || fail "missing required file: $f"
done
ok "all required files present"

# 2. Bridge JS syntax
node --check bin/mcp-bridge/mcp-bridge.js || fail "bridge JS syntax error"
ok "bridge JS syntax"

# 3. manifest.json parses
node -e "JSON.parse(require('fs').readFileSync('manifest.json','utf8'))" || fail "manifest.json invalid"
ok "manifest.json valid JSON"

# 4. mcp.json parses + uses \${userHome}
node -e '
    const m = JSON.parse(require("fs").readFileSync("user/mcp.json","utf8"));
    if (!m.mcpServers) { console.error("mcp.json missing mcpServers"); process.exit(1); }
    const args = Object.values(m.mcpServers).flatMap(s => s.args || []);
    if (!args.some(a => String(a).includes("\${userHome}"))) {
        console.error("mcp.json has no \${userHome} arg (not portable)");
        process.exit(1);
    }
    if (args.some(a => /[a-zA-Z]:\\\\/.test(String(a)))) {
        console.error("mcp.json contains a hardcoded Windows path");
        process.exit(1);
    }
' || fail "mcp.json portability check"
ok "mcp.json is portable (uses \${userHome}, no Windows paths)"

# 5. setup.sh syntax
bash -n setup.sh || fail "setup.sh syntax error"
ok "setup.sh syntax"

# 6. pull.sh syntax
bash -n pull.sh || fail "pull.sh syntax error"
ok "pull.sh syntax"

# 7. .gitignore covers node_modules
grep -q "node_modules" .gitignore || fail ".gitignore missing node_modules"
ok ".gitignore covers node_modules"

# 8. .gitattributes declares *.ps1 eol=crlf
grep -q '\*.ps1.*eol=crlf' .gitattributes || fail ".gitattributes missing ps1 eol rule"
ok ".gitattributes covers ps1 line endings"

# 9. Bridge has dependencies declared
node -e '
    const p = JSON.parse(require("fs").readFileSync("bin/mcp-bridge/package.json","utf8"));
    const deps = Object.keys(p.dependencies || {});
    if (!deps.includes("@modelcontextprotocol/sdk")) { console.error("bridge missing @modelcontextprotocol/sdk"); process.exit(1); }
    if (!deps.includes("ws")) { console.error("bridge missing ws"); process.exit(1); }
' || fail "bridge dependencies"
ok "bridge deps declared (@modelcontextprotocol/sdk, ws)"

# 10. argv.json NOT tracked (privacy)
if git ls-files | grep -q "user/argv.json"; then
    fail "user/argv.json is tracked — should be excluded (machine-specific crash-reporter-id)"
fi
ok "argv.json correctly not tracked"

echo "==> all smoke checks passed"