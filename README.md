# Cursor Portable

A single-repo bootstrap that recreates your Cursor skills, rules, and MCP servers on any machine.

## What's inside

```
cursor-portable/
├── bin/mcp-bridge/      # MCP server source (node + ws + @modelcontextprotocol/sdk)
├── user/
│   └── mcp.json         # portable MCP config (uses ${userHome} — no hardcoded paths)
├── skills/              # mirrored from d:\ai\projects\.cursor\skills\
├── rules/               # mirrored from d:\ai\projects\.cursor\rules\
├── extensions.txt       # checklist of extensions to install
├── manifest.json        # declarative sync contract (what goes where, and why not)
├── setup.ps1 / setup.sh # idempotent bootstrapper (with -DryRun, -SkipUser, -SkipProject, -SkipNpm)
├── pull.ps1  / pull.sh  # native → repo mirror (capture edits)
├── tests/smoke.sh       # CI-friendly sanity check
├── .github/workflows/   # GitHub Actions: smoke test on every push
├── LICENSE              # MIT
├── .editorconfig        # editor consistency
└── .gitattributes       # lock line endings (LF for shell, CRLF for .ps1)
```

The repo is the **source of truth**. On a new machine you clone once, run `setup`, and you're done.

## First time setup (current machine)

Already done — see `user/mcp.json` and `~/.cursor/bin/mcp-bridge/`. Skip to "Daily use".

If you ever wipe state and want to re-bootstrap the current machine from this repo:

```powershell
cd d:\ai\projects\cursor-portable
.\setup.ps1
```

## New machine bootstrap

**Prerequisites on the new machine:** Git, Node.js ≥ 18, Cursor.

```bash
git clone <this-repo-url> cursor-portable
cd cursor-portable
# Windows:
./setup.ps1
# macOS / Linux:
chmod +x setup.sh && ./setup.sh
```

That single command:
1. Copies `bin/mcp-bridge/` → `~/.cursor/bin/mcp-bridge/` and runs `npm install`.
2. Writes `~/.cursor/mcp.json` (uses `${userHome}`, so no path edits needed).
3. Mirrors `skills/` into `~/.cursor/skills/`.
4. Mirrors `rules/` and `skills/` into `<project>/.cursor/` (current dir by default).

Flags (both shells):
```
./setup.ps1 -ProjectDir D:\other\workspace   # different project destination
./setup.ps1 -SkipUser                       # project-only install
./setup.ps1 -SkipProject                    # user-only install
./setup.ps1 -SkipNpm                        # faster re-runs (skip npm install)
./setup.ps1 -DryRun                         # print plan, change nothing
```

After setup, **restart Cursor** so the MCP server list reloads.

## Daily use — capture edits back into the repo

When you edit a rule or skill file in its native location, mirror it back:

```powershell
.\pull.ps1                       # captures ~/.cursor/skills + project/.cursor/rules
git add -A
git commit -m "update: <what changed>"
git push
```

Then on other machines: `git pull && ./setup.ps1`.

## Why `mcp.json` uses `${userHome}`

Original (broken across machines):
```json
"args": ["d:\\ai\\projects\\browser-mcp-bridge\\mcp-bridge.js"]
```

Portable (works anywhere):
```json
"args": ["${userHome}/.cursor/bin/mcp-bridge/mcp-bridge.js"]
```

`${userHome}` is resolved by VS Code/Cursor's MCP layer at server-spawn time. On Windows it becomes `C:\Users\<you>\.cursor\bin\mcp-bridge\mcp-bridge.js`; on macOS `/Users/<you>/.cursor/bin/mcp-bridge/mcp-bridge.js`. The forward slashes are accepted by Node on both platforms.

Other supported variables you can use: `${workspaceFolder}`, `${env:VAR}`.

## What this repo explicitly does NOT sync

These are documented in `manifest.json` under `explicitly_excluded`. Adding them would either leak machine-specific state or fail because of OS-specific binaries:

| What | Why excluded |
|---|---|
| `~/.cursor/argv.json` | Contains a machine-specific `crash-reporter-id` UUID. Writing the same ID to every machine makes crash reports correlatable across installs. Let Cursor regenerate on first launch. |
| `%APPDATA%\Cursor\User\settings.json` | May contain `http.proxy`, account IDs, machine paths. Sync selectively by editing the file and adding a partial-sync step. |
| Cursor extensions (binary) | OS-specific binaries. Use `extensions.txt` as a checklist and let Cursor Settings Sync pull them, or run `cursor --install-extension <id>` manually. |
| Workspace storage + conversation history | Path-keyed; recreated on first open. |

For partial sync of `settings.json`, the pattern is:
```powershell
$keys = 'editor.fontSize','editor.tabSize','workbench.colorTheme'
# extract those keys from %APPDATA%\Cursor\User\settings.json and merge into a tracked partial file
```

## Adding new MCP servers

1. Drop the server source into `bin/<name>/` (or symlink to an external path).
2. Add the entry to `user/mcp.json` using `${userHome}` or relative paths under `~/.cursor/bin/`.
3. Extend `setup.ps1` to copy the new dir into `~/.cursor/bin/`.
4. Update `manifest.json` so the contract stays explicit.
5. `git push`, then `git pull && ./setup.ps1` on the other machine.

## Verifying the repo (smoke test)

```bash
bash tests/smoke.sh
```

Runs in CI on every push (`.github/workflows/smoke.yml`). Checks: file layout, bridge JS syntax, manifest JSON validity, mcp.json portability (`${userHome}` present, no Windows paths), shell syntax, `.gitignore` / `.gitattributes` correctness, declared deps, and that `argv.json` stays untracked.

## Troubleshooting

- **MCP server fails to start after setup** — open Cursor → Settings → MCP. The error usually names the missing file. Most often: `node_modules` not installed (rerun without `-SkipNpm`), or `${userHome}` not supported (anything ≥ Cursor 0.40 supports it).
- **`pull.ps1` overwrites local changes** — it deliberately wipes `skills/` and `rules/` before re-copying. Commit or stash before pulling.
- **Wrong project destination** — pass `-ProjectDir <path>` to `setup.ps1` / `--project-dir <path>` to `setup.sh`.
- **Want a dry-run preview** — `./setup.ps1 -DryRun` or `bash setup.sh --dry-run`.
- **Sandboxed env where `gh auth login --web` times out** — generate a PAT at https://github.com/settings/tokens/new (scope: `repo`) and run `gh auth login --with-token -h github.com` in your own terminal; the token never enters the chat.