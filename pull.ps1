#!/usr/bin/env pwsh
# pull.ps1 — Mirror native locations BACK into this repo (capture changes)
#
# Default sources (override with -ProjectDir):
#   ~/.cursor/skills/                  -> ./skills/
#   ~/.cursor/argv.json                -> ./user/argv.json
#   <ProjectDir>/.cursor/skills/       -> ./skills/   (overlay)
#   <ProjectDir>/.cursor/rules/         -> ./rules/
#
# After running: review `git status`, then commit + push.

[CmdletBinding()]
param(
    [string]$ProjectDir = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$CursorUser = Join-Path $env:USERPROFILE ".cursor"
$UserSkills = Join-Path $CursorUser "skills"
$UserArgv = Join-Path $CursorUser "argv.json"
$ProjectCursor = Join-Path $ProjectDir ".cursor"
$ProjectSkills = Join-Path $ProjectCursor "skills"
$ProjectRules = Join-Path $ProjectCursor "rules"

$DstSkills = Join-Path $RepoRoot "skills"
$DstRules = Join-Path $RepoRoot "rules"
$DstArgv = Join-Path $RepoRoot "user\argv.json"

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "  [ok] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  [warn] $msg" -ForegroundColor Yellow }

if (Test-Path $UserSkills) {
    New-Item -ItemType Directory -Path $DstSkills -Force | Out-Null
    # Wipe dst then re-copy (clean mirror)
    Get-ChildItem -Path $DstSkills -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
    Copy-Item -Path "$UserSkills\*" -Destination $DstSkills -Recurse -Force
    Ok "user skills pulled into $DstSkills"
} else { Warn "no $UserSkills" }

if (Test-Path $ProjectSkills) {
    New-Item -ItemType Directory -Path $DstSkills -Force | Out-Null
    Copy-Item -Path "$ProjectSkills\*" -Destination $DstSkills -Recurse -Force
    Ok "project skills overlaid into $DstSkills"
}

if ((Test-Path $ProjectRules) -and (Test-Path $ProjectDir)) {
    New-Item -ItemType Directory -Path $DstRules -Force | Out-Null
    Get-ChildItem -Path $DstRules -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
    Copy-Item -Path "$ProjectRules\*" -Destination $DstRules -Recurse -Force
    Ok "project rules pulled into $DstRules"
} else { Warn "no $ProjectRules (project rules unchanged)" }

if (Test-Path $UserArgv) {
    New-Item -ItemType Directory -Path (Split-Path $DstArgv) -Force | Out-Null
    Copy-Item $UserArgv $DstArgv -Force
    Ok "argv.json pulled"
}

Step "Done. Review with: git status  &&  git diff"