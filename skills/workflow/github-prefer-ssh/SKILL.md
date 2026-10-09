---
description: When you need to interact with a GitHub repository from this machine — `git push`, `git pull`, `git clone`, `gh` CLI, GitHub API, or any related operation — use SSH keys by default. Load this skill before touching `git` or `gh` against a GitHub remote. It covers (1) detecting the current auth posture, (2) the SSH-first rule and the "why", (3) the safe path when SSH is not yet set up, (4) hygiene rules for tokens and credentials, and (5) the one-off cases where HTTPS is the right answer anyway.
---

# github-prefer-ssh

## Why this skill exists

Every Cursor session that touches a GitHub repo from this machine is a chance to either:

- **Reuse the user's existing SSH key** (durable, rotation-free, no token in chat), or
- **Generate a new HTTPS PAT** (one-time credential that gets pasted, leaks, rots, and breaks the next time the user is not at the keyboard).

This skill enforces the first path. It is the single source of truth for: "what does the agent do when it needs GitHub auth on this machine?"

## The default posture — SSH, always

When a task involves `git` or `gh` against a GitHub remote, **assume SSH is the answer** unless one of the few explicit exceptions below applies.

The remote URL you want, after this skill runs, is:

```
git@github.com:<owner>/<repo>.git
```

Not `https://github.com/<owner>/<repo>.git`. The former uses the user's SSH key. The latter asks the user for a token.

### Detection — what's the current posture?

Run these in order, stop at the first that gives a definitive answer:

1. **Is the remote already SSH?**
   ```powershell
   git remote get-url origin
   ```
   If it starts with `git@`, you're done. No work needed.

2. **Can the user's SSH key reach GitHub right now?**
   ```powershell
   ssh -T -o StrictHostKeyChecking=accept-new git@github.com
   ```
   Expected on success: `Hi <username>! You've successfully authenticated, but GitHub does not provide shell access.` (non-zero exit is normal — GitHub just refuses the shell.)

3. **Does the user have any SSH key registered?**
   ```powershell
   Get-ChildItem ~/.ssh -Filter *.pub
   ```
   If at least one public key exists, jump to **"Switch remote to SSH"**. If none, jump to **"First-time SSH setup"**.

4. **If neither 2 nor 3 produces a result** (no key, no working auth) — this is the rare case where you have to ask the user. Ask them once, give them the exact commands, do not paste their token back.

### Switch remote to SSH (the common path)

```powershell
git remote set-url origin git@github.com:<owner>/<repo>.git
git remote -v   # verify
```

Then proceed with `git push`, `git pull`, `git fetch` as normal. The SSH agent handles auth — the user is not prompted for a credential.

### First-time SSH setup (only if the user has no key)

Walk the user through these **in their own terminal** — never paste their key into chat, never write it to a file that gets committed:

```powershell
# 1. Generate a key (ed25519 is the modern default)
ssh-keygen -t ed25519 -C "<their-github-email>"
# Press Enter to accept the default path, set a passphrase if they want.

# 2. Start the ssh-agent and add the key (PowerShell)
Get-Service ssh-agent | Set-Service -StartupType Manual
Start-Service ssh-agent
ssh-add $env:USERPROFILE\.ssh\id_ed25519

# 3. Print the public key — user pastes it into https://github.com/settings/keys
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub

# 4. Verify
ssh -T -o StrictHostKeyChecking=accept-new git@github.com
```

Then point 3+4 above (switch the remote, run the test).

## Hygiene rules (do not break these)

These are non-negotiable. They are the reason the SSH-first rule exists.

1. **Never paste a GitHub PAT into chat, a file, a commit, a log line, or a shell script.** Treat any token that crossed the chat as compromised and rotate it.
2. **Never write `GITHUB_TOKEN=...` or `Authorization: token ...` into a tracked file.** Use environment variables, OS keychain, or a `.gitignore`d `.env`.
3. **Never commit `~/.ssh/id_*` (private keys).** They should be in `.gitignore` (and they are by default in Cursor's template).
4. **If a token is exposed anyway** (user pasted it, it landed in a commit, a file got uploaded, etc.) — stop, tell the user, and walk them through rotation at https://github.com/settings/tokens. Do not continue with the exposed token.
5. **`gh auth login --web` from inside an agent sandbox is brittle** (browser callback times out). If `gh` is needed, use `gh auth login --with-token` in the user's own terminal, with a PAT they generated themselves.

## When HTTPS / a token is the right answer anyway

SSH is the default, not a religion. Use a token when:

- **The user explicitly asks for HTTPS** (some people prefer it for transparency or because they don't have SSH set up).
- **The remote is not GitHub** (GitLab, Bitbucket, self-hosted Gitea, etc.) — switch the rules to "match the host's auth model", not "force SSH".
- **GitHub Actions / CI / ephemeral envs** where you genuinely don't have a long-lived key and `GITHUB_TOKEN` (auto-issued) is the right choice.
- **The user is on a one-shot machine and will never come back** — then a fine-grained PAT with a 1-day expiry is acceptable.

In all other cases, SSH.

## Worked examples

### "I just made commits locally; push them."

```powershell
git remote get-url origin                           # check
# If https://...:
git remote set-url origin git@github.com:OWNER/REPO.git
git push origin main
# Done. No token prompt. No PAT in chat.
```

### "Set up this project on a new machine and push to GitHub."

```powershell
# In the user's terminal:
ssh-keygen -t ed25519 -C "user@example.com"   # if no key yet
ssh-add ~/.ssh/id_ed25519                     # if not already added
# Paste the .pub into https://github.com/settings/keys (user does this manually)

# Then, back in agent land:
git remote set-url origin git@github.com:OWNER/REPO.git
git push -u origin main
```

### "Create a GitHub release / file an issue / use `gh`."

```powershell
gh auth status                                 # tells you who/what
# If not logged in via SSH-key-backed `gh`:
gh auth login --ssh                            # gh can use the SSH key too
gh release create v1.2.3 ...
```

`gh auth login --ssh` reuses the user's existing SSH key. It is the equivalent of "use SSH" at the `gh` CLI layer.

### "CI / GitHub Actions needs to push back to the repo."

That's an exception. Use the auto-issued `${{ secrets.GITHUB_TOKEN }}` inside Actions. This skill does not apply inside CI.

## Failure modes and what to do

| Symptom | Cause | Fix |
|---|---|---|
| `git push` asks for username/password | Remote is HTTPS | Run `git remote set-url origin git@github.com:.../...git` |
| `Permission denied (publickey)` | SSH key not loaded, or not on GitHub | `ssh-add ~/.ssh/id_<name>`; verify the matching `.pub` is in https://github.com/settings/keys |
| `Could not resolve hostname github.com` | Network or DNS issue | Not an auth problem. Retry or check the network. |
| `Host key verification failed` | First-time connect to a host whose key is not in `known_hosts` | Use `-o StrictHostKeyChecking=accept-new` (one-shot) or have the user add the host key manually. Do not bypass with `StrictHostKeyChecking=no` for every call. |
| `git push` says "Bad credentials" even with SSH remote | Credential helper is cached an old HTTPS token | `git credential-manager clear` or `git config --global --unset credential.helper`, then retry. |
| User already leaked a token into the chat | Hygiene rule 4 | Stop, tell them, walk them through rotation, then continue with SSH. |

## Quick checklist for the agent

Before any `git` or `gh` call against a GitHub remote:

- [ ] Check the remote URL — is it `git@github.com:...`? If yes, proceed.
- [ ] If not, check whether SSH works (`ssh -T git@github.com`).
- [ ] If SSH works, switch the remote and proceed.
- [ ] If SSH does not work, walk the user through first-time setup **in their terminal**, never inline.
- [ ] Do not invent a token, ask the user to paste one, or write one to a file.

That's the whole skill. Use it.
