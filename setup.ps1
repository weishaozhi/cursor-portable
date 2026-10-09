#!/usr/bin/env pwsh
# setup.ps1 — Cursor Portable Bootstrapper (Windows)
#
# Idempotent: safe to re-run. Run from a fresh clone:
#   git clone <this-repo> cursor-portable
#   cd cursor-portable
#   ./setup.ps1                       # installs to ~/.cursor and current dir
#   ./setup.ps1 -ProjectDir D:\work   # project rules/skills go to D:\work\.cursor
#   ./setup.ps1 -SkipUser             # don't touch ~/.cursor (project-only)
#   ./setup.ps1 -SkipProject          # don't touch current/project dir (user-only)
#   ./setup.ps1 -SkipNpm              # don't run npm install (faster re-runs)
#   ./setup.ps1 -DryRun               # print what would be done, change nothing

[CmdletBinding()]
param(
    [string]$ProjectDir = (Get-Location).Path,
    [switch]$SkipUser = $false,
    [switch]$SkipProject = $false,
    [switch]$SkipNpm = $false,
    [switch]$DryRun = $false
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$CursorUser = Join-Path $env:USERPROFILE ".cursor"
$BridgeDst = Join-Path $CursorUser "bin\mcp-bridge"
$UserSkillsDst = Join-Path $CursorUser "skills"
$UserMcpDst = Join-Path $CursorUser "mcp.json"
$ProjectCursor = Join-Path $ProjectDir ".cursor"
$ProjectSkillsDst = Join-Path $ProjectCursor "skills"
$ProjectRulesDst = Join-Path $ProjectCursor "rules"

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "  [ok] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  [warn] $msg" -ForegroundColor Yellow }
function Dry($msg)  { Write-Host "  [dry-run] $msg" -ForegroundColor DarkGray }

# ---------- PREFLIGHT ----------
Step "Preflight checks"

# PowerShell version: setup uses Get-Item, Join-Path, etc. PS 5.1+ fine.
if ($PSVersionTable.PSVersion.Major -lt 5) {
    throw "PowerShell 5.1+ required (you have $($PSVersionTable.PSVersion))."
}

# Git: required for the project workflow, optional for the bootstrap itself.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Warn "git not on PATH — sync workflow won't work, but setup can still install."
}

# Node + npm: required only for the MCP bridge.
if (-not (Test-Path (Join-Path $RepoRoot "bin\mcp-bridge\package.json"))) {
    Write-Output "  [skip] no bin/mcp-bridge/package.json — skipping node/npm check"
} else {
    $node = Get-Command node -ErrorAction SilentlyContinue
    $npm  = Get-Command npm  -ErrorAction SilentlyContinue
    if (-not $node) { Warn "node not on PATH — mcp-bridge will not run" }
    if (-not $npm)  { Warn "npm  not on PATH — bridge deps will not install" }
    if ($node) { Ok "node $($(node --version 2>$null))" }
    if ($npm)  { Ok "npm  $($(npm --version  2>$null))" }
}

# Verify repo layout is intact
$expected = @(
    "bin\mcp-bridge\mcp-bridge.js",
    "bin\mcp-bridge\package.json",
    "user\mcp.json"
)
foreach ($f in $expected) {
    $p = Join-Path $RepoRoot $f
    if (-not (Test-Path $p)) { throw "repo layout broken: missing $f" }
}
Ok "repo layout ok"

# ---------- USER LAYER (~/.cursor) ----------
if (-not $SkipUser) {
    Step "User layer: $CursorUser"

    if ($DryRun) {
        Dry "would create $BridgeDst"
        Dry "would copy bin\mcp-bridge\* -> $BridgeDst"
    } else {
        New-Item -ItemType Directory -Path $BridgeDst -Force | Out-Null
        Copy-Item -Path (Join-Path $RepoRoot "bin\mcp-bridge\*") `
                   -Destination $BridgeDst -Recurse -Force
        Ok "bridge copied to $BridgeDst"
    }

    $bridgePkgJson = Join-Path $BridgeDst "package.json"
    if (Test-Path $bridgePkgJson) {
        if (-not $SkipNpm -and -not $DryRun) {
            $nodeModules = Join-Path $BridgeDst "node_modules"
            if ((Test-Path $nodeModules) -and -not $env:CURSOR_PORTABLE_FORCE_NPM) {
                Ok "node_modules present, skipping npm install (set CURSOR_PORTABLE_FORCE_NPM=1 to force)"
            } else {
                $npm = Get-Command npm -ErrorAction SilentlyContinue
                if ($npm) {
                    Step "npm install in bridge dir"
                    Push-Location $BridgeDst
                    try { npm install --omit=dev --no-audit --no-fund 2>&1 | Out-Null } catch { Warn "npm install failed: $_" }
                    Pop-Location
                    Ok "deps installed"
                } else {
                    Warn "npm not found on PATH; bridge deps will not install"
                }
            }
        }
    }

    $srcMcp = Join-Path $RepoRoot "user\mcp.json"
    if (Test-Path $srcMcp) {
        if ($DryRun) {
            Dry "would write $UserMcpDst (uses \${userHome} — portable)"
        } else {
            New-Item -ItemType Directory -Path (Split-Path $UserMcpDst) -Force | Out-Null
            Copy-Item $srcMcp $UserMcpDst -Force
            Ok "wrote $UserMcpDst (uses \${userHome} — portable)"
        }
    }

    $srcUserSkills = Join-Path $RepoRoot "skills"
    if (Test-Path $srcUserSkills) {
        if ($DryRun) {
            Dry "would mirror $srcUserSkills -> $UserSkillsDst"
        } else {
            New-Item -ItemType Directory -Path $UserSkillsDst -Force | Out-Null
            Get-ChildItem -Path $srcUserSkills -Force | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $UserSkillsDst -Recurse -Force
            }
            Ok "user skills synced to $UserSkillsDst"
        }
    } else {
        Warn "no skills/ in repo; skipping user skills"
    }
}

# ---------- PROJECT LAYER (<ProjectDir>/.cursor) ----------
if (-not $SkipProject) {
    Step "Project layer: $ProjectCursor"

    $srcSkills = Join-Path $RepoRoot "skills"
    $srcRules = Join-Path $RepoRoot "rules"

    if (-not (Test-Path $ProjectDir)) {
        Warn "project dir not found: $ProjectDir (skipping project layer)"
    } elseif ($DryRun) {
        Dry "would mirror $srcRules -> $ProjectRulesDst"
        Dry "would mirror $srcSkills -> $ProjectSkillsDst"
    } else {
        New-Item -ItemType Directory -Path $ProjectCursor -Force | Out-Null

        if (Test-Path $srcRules) {
            New-Item -ItemType Directory -Path $ProjectRulesDst -Force | Out-Null
            Copy-Item -Path "$srcRules\*" -Destination $ProjectRulesDst -Recurse -Force
            Ok "rules synced to $ProjectRulesDst"
        }

        if (Test-Path $srcSkills) {
            New-Item -ItemType Directory -Path $ProjectSkillsDst -Force | Out-Null
            Get-ChildItem -Path $srcSkills -Force | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $ProjectSkillsDst -Recurse -Force
            }
            Ok "skills synced to $ProjectSkillsDst"
        }
    }
}

# ---------- POST ----------
Step "Done."
Write-Host ""
Write-Host "Next:" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "  (dry-run) no files were modified. re-run without -DryRun to apply."
} else {
    Write-Host "  - Restart Cursor (or reload window) so the new mcp.json takes effect."
    Write-Host "  - Verify: open Cursor Settings -> MCP; browser-bridge should be listed."
    Write-Host "  - Install extensions: see extensions.txt (manual list)."
    Write-Host "  - To capture future edits back into this repo, run: ./pull.ps1"
}