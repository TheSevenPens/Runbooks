# Claude Code Guide for This Repo

## What this repo is

A collection of runbooks for setting up development machines from scratch. The runbooks are designed to be executed by Claude Code — they contain automation instructions, manual step callouts, and Claude-specific notes that guide you through the process.

## Repo structure

```
setup-runbook-windows.md             — Windows machine setup (apps, tools, shell config)
setup-runbook-mac.md                 — macOS machine setup (apps, tools, shell config)
mise-env-runbook.md                  — Tool version management via mise (cross-platform)
conda-env-runbook.md                 — Legacy environment runbook (conda/micromamba)
macos_micromamba_debug_runbook.md    — Root-cause writeup for the macOS libmamba codesign bug
docs/FUTURES.md                      — Planned improvements and architectural decisions
apps/                                — Declarative app specs (winget JSON, Brewfile)
bootstrap/                           — One-liner bootstrap scripts for fresh machines
scripts/windows/                     — PowerShell automation scripts for Windows setup
scripts/mac/                         — PowerShell 7 automation scripts for macOS setup
scripts/archive/                     — Retired bash scripts (pre-PowerShell migration)
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
4. **Use the Status Tracker.** Each runbook has a Status Tracker section with a checklist template. Create/update the checklist as a local file in `~/Documents/runbook-status/` (not in the repo) so it doesn't conflict across machines. Reset checkboxes at the start of a new run.
5. **When something goes wrong**, document the fix in the runbook's Known Issues table and update the relevant steps so the next run avoids the problem.

## Key lessons learned (Windows)

These caused real issues during development and are documented in the runbooks, but worth highlighting:

- **PATH changes don't take effect in the current shell.** After modifying PATH, the user needs to open a new terminal. Don't tell them to "restart the terminal" if they don't have one open — be specific about what they need to do.
- **The Windows user PATH registry key must be `REG_EXPAND_SZ`**, not `REG_SZ`. If it's the wrong type, CMD silently ignores user PATH entries. Always verify after modifying PATH.
- **Git Bash is not a supported shell on Windows.** Git for Windows is installed (for `git` CLI), but Git Bash is not configured, tested, or maintained by the runbooks. `mise activate bash` breaks PATH, BOM issues affect `.bash_profile`, and MSYS2 path format mismatches cause tool failures. Use PowerShell 7 or CMD instead. See `docs/FUTURES.md` for the full rationale.
- **Conda and micromamba CMD hooks conflict.** Both `conda_hook.bat` and `mamba_hook.bat` guard on `CONDA_SHLVL` — whichever loads second silently exits. The runbook now removes conda entirely to avoid this.

## User preferences

- **Env manager is platform-specific: micromamba on Windows, miniconda on macOS.** On macOS, conda replaces micromamba because of a libmamba `codesign()` bug on macOS 26 (`reproc::env::empty` causes a spurious EINVAL during env creation — full root cause in `macos_micromamba_debug_runbook.md` Section 15, not fixed upstream). Do not install micromamba on macOS; do not install conda on Windows. If `verify-prerequisites.sh` detects the wrong manager for the platform, the runbook removes it via `scripts/mac/remove-micromamba.sh` (on macOS) or `scripts/windows/remove-conda.ps1` (on Windows) before installing the correct one. If the upstream libmamba bug is ever fixed, macOS can return to micromamba — the trigger is a successful run of `macos_micromamba_debug_runbook.md` Section 7.
- Wants runbooks that work on **both Windows and macOS**. Platform-specific setup runbooks stay separate; `conda-env-runbook.md` is the shared environment runbook with per-platform sections (Windows → micromamba, macOS → miniconda).
- Wants deterministic steps to eventually become **standalone scripts** (idempotent, structured output, no interactivity). See docs/FUTURES.md.
- Wants runbooks to be **living documents** — when you hit a problem and find a fix, update the runbook so the next run doesn't hit it again.

## File encoding rules

These rules exist because PowerShell 5.1 and bash have incompatible encoding requirements, and getting them wrong causes silent failures that are hard to diagnose. See `setup-runbook-windows.md` "First-Run Discoveries" items 2 and 6, and `mise-env-runbook.md` items 3 and the BOM known issue for the full incident history.

### The core conflict

- **PowerShell 5.1** parses UTF-8 files without BOM by assuming single-byte characters. Multi-byte UTF-8 (em-dash, smart quotes, etc.) misaligns its byte tracker, producing cascading parse errors on *subsequent* lines that look completely unrelated.
- **Bash** treats a UTF-8 BOM (`EF BB BF`) as literal bytes, prepending garbage to the first command (e.g., `$'\357\273\277eval': command not found`).
- **PowerShell 5.1's** `-Encoding UTF8` parameter **always adds a BOM**. PowerShell 7's `-Encoding UTF8` does **not** add a BOM (Microsoft fixed it in PS7). Since scripts in this repo may run under either version, treat `-Encoding UTF8` as "will add a BOM."

### Rules

1. **`.ps1` files: ASCII-only content, no BOM needed.** Never use em-dashes (`---`), smart quotes, or any non-ASCII character in PowerShell scripts. Use `-` (hyphen), `'` / `"` (straight quotes) instead. PS5.1 parses ASCII correctly regardless of BOM.

2. **`.bash_profile`, `.bashrc`, `.sh` files (macOS only): no BOM, UTF-8 is fine.** On Windows, Git Bash is not a supported shell, so there are no bash config files to manage. On macOS, never use PowerShell's `-Encoding UTF8` to write files that bash/zsh will read --- use `[System.IO.File]::WriteAllText($path, $content)` (UTF-8 without BOM) instead.

3. **When editing files with the Claude Code Edit/Write tools**, the output is UTF-8 without BOM (safe for both bash and PS5.1). But avoid introducing non-ASCII characters in `.ps1` files -- the Edit tool doesn't add a BOM to protect against them.

### Quick reference

| File type | BOM? | Non-ASCII? | Safe write method |
|-----------|------|------------|-------------------|
| `.ps1` | optional | **NO** (ASCII only) | Edit tool, `Set-Content` (any encoding) |
| `.bash_profile` / `.sh` (macOS) | **NO** | OK | Edit tool, `[System.IO.File]::WriteAllText()` |
| `.md` / docs | don't care | OK | Edit tool, anything |
| `.json` | no | OK | `Set-Content -Encoding UTF8` is fine (JSON parsers skip BOM) |

> 📝 **Note:** On Windows, there are no bash config files to manage --- Git Bash is not a supported shell. The BOM concern only applies to macOS scripts that write `~/.bash_profile` or `~/.zshrc`.

## When updating runbooks

- Keep Claude-specific instructions (callout markers, notes) — they're there to help future runs.
- When you add a workaround, add it to both the relevant step AND the Known Issues table.
- Keep the Status Tracker in sync with the actual steps.
- If you split or restructure, update all cross-references between files.
