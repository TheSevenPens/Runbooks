# Claude Code Guide for This Repo

## What this repo is

A collection of runbooks for setting up development machines from scratch. The runbooks are designed to be executed by Claude Code — they contain automation instructions, manual step callouts, and Claude-specific notes that guide you through the process.

## Repo structure

```
setup-runbook-windows.md   — Windows machine setup (apps, tools, shell config)
setup-runbook-mac.md       — macOS machine setup (placeholder, in development)
conda-env-runbook.md       — Conda & Micromamba setup (shared across platforms)
FUTURES.md                 — Planned improvements and architectural decisions
scripts/windows/           — Future automation scripts for Windows
scripts/mac/               — Future automation scripts for macOS
```

## How to run a runbook

The user will tell you which runbook to follow. When executing one:

1. **Check what's already installed first.** Don't assume a fresh machine — tools may already be present via different install methods than the runbook describes. Report what you find and let the user decide.
2. **Follow the runbook sequentially.** Steps often depend on earlier steps.
3. **Respect the callout markers:**
   - `⚠️ Manual step` — tell the user they need to do this themselves
   - `🤔 Claude Code: Ask the user` — use AskUserQuestion before proceeding
   - `📝 Note` — informational, no action needed
   - `⚠️ Claude Code note` — guidance for you about known pitfalls
4. **Use the Status Tracker.** Check off items as you complete them. Reset checkboxes at the start of a new run.
5. **When something goes wrong**, document the fix in the runbook's Known Issues table and update the relevant steps so the next run avoids the problem.

## Key lessons learned (Windows)

These caused real issues during development and are documented in the runbooks, but worth highlighting:

- **PATH changes don't take effect in the current shell.** After modifying PATH, the user needs to open a new terminal. Don't tell them to "restart the terminal" if they don't have one open — be specific about what they need to do.
- **The Windows user PATH registry key must be `REG_EXPAND_SZ`**, not `REG_SZ`. If it's the wrong type, CMD silently ignores user PATH entries. Always verify after modifying PATH.
- **Micromamba's CMD shell init (`micromamba shell init -s cmd.exe`) mangles paths when run from Git Bash.** Always run it from PowerShell.
- **Micromamba's installer puts the binary in a location CMD can't reliably access.** Copy it to `miniconda3\Scripts\` as a workaround.
- **Conda requires ToS acceptance** on first use before any environment can be created. Ask the user before accepting.
- **Both conda and micromamba auto-activate base**, causing a double `(base)` prompt. Disable one of them.

## User preferences

- Prefers **micromamba over conda** and plans to transition fully to micromamba.
- Wants runbooks that work on **both Windows and macOS**. Platform-specific setup runbooks stay separate; the conda/micromamba runbook is shared with platform callouts.
- Wants deterministic steps to eventually become **standalone scripts** (idempotent, structured output, no interactivity). See FUTURES.md.
- Values **consistency** — if conda gets a shell init for all shells, micromamba should too.
- Wants runbooks to be **living documents** — when you hit a problem and find a fix, update the runbook so the next run doesn't hit it again.

## When updating runbooks

- Keep Claude-specific instructions (callout markers, notes) — they're there to help future runs.
- When you add a workaround, add it to both the relevant step AND the Known Issues table.
- Keep the Status Tracker in sync with the actual steps.
- If you split or restructure, update all cross-references between files.
