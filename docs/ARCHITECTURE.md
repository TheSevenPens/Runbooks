# Architecture

How the runbooks and scripts work, the principles behind them, and gotchas to keep in mind when developing new ones.

## How it works

A user opens Claude Code and tells it which runbook to follow. Claude Code reads the runbook sequentially, runs scripts where indicated, prompts the user at manual steps, and tracks progress in a local checklist file.

### Repo structure

```
setup-runbook-windows.md       — Windows machine setup
setup-runbook-mac.md           — macOS machine setup
conda-env-runbook.md           — Micromamba setup (shared, with platform callouts)
scripts/windows/*.ps1          — PowerShell automation scripts
scripts/mac/*.sh               — Bash automation scripts
docs/                          — Architecture and change history
CLAUDE.md                      — Operator guide for Claude Code
docs/FUTURES.md                — Roadmap and planned improvements
```

### Execution flow

**Windows:**
1. `prepare-for-runbooks.ps1` — execution policy, Claude Code install, PATH
2. `install-apps.ps1` — Git, GitHub Desktop, VS Code, Chrome, Terminal, PowerShell 7
3. Oh My Posh (optional, prompted)
4. `remove-conda.ps1` (if conda present)
5. Micromamba install (manual invoke of official installer)
6. `fix-path-registry.ps1` — fix registry type, clean stale entries
7. `micromamba-shell-init.ps1` — hooks for PowerShell 5.1/7, bash, CMD
8. `micromamba create -n node1` — create environment
9. `verify-shell-integration.ps1` — confirm all shells work
10. Post-setup manual sign-ins (GitHub Desktop, Chrome)

**macOS:**
1. Homebrew install
2. `install-apps.sh` — Git, GitHub Desktop, VS Code, Chrome via brew (idempotent)
3. iTerm2, shell customization (optional)
4. Micromamba via `brew install micromamba`
5. `micromamba shell init` for zsh and bash
6. Environment creation
7. `verify-shell-integration.sh` — confirm zsh and bash work
8. Post-setup manual sign-ins (GitHub Desktop, Chrome)

### Callout markers

Runbooks use these markers to tell Claude Code how to handle each step:

| Marker | Meaning |
|--------|---------|
| `⚠️ Manual step` | User must do this themselves — tell them what to do |
| `🤔 Claude Code: Ask the user` | Prompt the user before proceeding |
| `📝 Note` | Informational — no action needed |
| `⚠️ Claude Code note` | Guidance for Claude about known pitfalls |

### Status tracking

Each runbook has a checklist template. Claude Code creates a local copy at `~/Documents/runbook-status/[runbook-name].md` (not in the repo) and checks items off as steps complete. Checkboxes are reset at the start of each run.

---

## Core principles

### 1. Idempotency

Every script checks "already done?" before acting. Running a script twice produces the same result with no side effects.

- CLI tools: `Get-Command` first, then canonical path fallback, then `winget list`
- Files: `Test-Path` before creating or modifying
- PATH entries: split, compare case-insensitively, only add if missing
- Registry: read current value/type before writing

### 2. Structured output

All scripts use the same prefix format so Claude Code can parse results:

```
OK:   — step succeeded
FAIL: — step failed (contributes to non-zero exit code)
WARN: — something unexpected but not blocking
SKIP: — already done or not applicable
INFO: — progress update, no action needed
```

Exit codes: 0 = success, 1 = failure. Scripts count failures and exit accordingly.

### 3. No interactivity

Scripts never prompt. All decisions come from the runbook (via Claude Code asking the user). Scripts accept parameters, do their work, and report results. This keeps the automation boundary clean — Claude Code decides what to run, scripts execute deterministically.

### 4. Verify after every mutation

Every install, registry write, or file modification is followed by a verification step. Don't trust that a command succeeded — confirm the expected state exists.

### 5. Canonical path fallbacks

`Get-Command` fails when a tool is installed but PATH hasn't refreshed in the current session. Scripts define canonical install locations as fallbacks. Search multiple candidates to handle different install paths (e.g., `Program Files` vs `Program Files (x86)`, localized Windows installs):

```powershell
$exe = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $exe) {
    $candidates = @("$env:ProgramFiles\PowerShell\7\pwsh.exe", "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe")
    foreach ($c in $candidates) {
        if (Test-Path $c) { $exe = Get-Command $c -ErrorAction SilentlyContinue; break }
    }
}
```

This pattern avoids false SKIPs and WARNs after fresh installs.

### 6. Living documents

When a runbook step fails during execution, the fix goes into both the step itself and the Known Issues table. This way the next run doesn't hit the same problem.

---

## Windows-specific gotchas

### PATH registry type must be REG_EXPAND_SZ

The user PATH at `HKCU\Environment\Path` must be `REG_EXPAND_SZ`, not `REG_SZ`. If it's the wrong type, CMD silently ignores all user PATH entries. Some installers corrupt this. Always verify after modifying PATH:

```powershell
$key = Get-Item 'HKCU:\Environment'
$kind = $key.GetValueKind('Path')  # must be ExpandString
```

Write with the correct type:
```powershell
Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value $newPath -Type ExpandString
```

### PATH changes don't take effect in the current shell

After modifying the registry, broadcast `WM_SETTINGCHANGE` so new processes pick up the change. Existing shells still won't see it — the user must open a new terminal. Scripts can also manually refresh `$env:Path` for their own session:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')
```

### Read PATH without expanding variables

When reading PATH for modification, preserve `%USERPROFILE%` tokens — don't let PowerShell expand them:

```powershell
$key = Get-Item 'HKCU:\Environment'
$raw = $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
```

### Micromamba CMD init is sensitive to working directory

`micromamba shell init -s cmd.exe` treats the `-r` root prefix as relative to the current directory when run from Git Bash, producing a mangled `AutoRun` registry value. Always run it from PowerShell. `micromamba-shell-init.ps1` enforces this.

### Conda and micromamba CMD hooks conflict

Both `conda_hook.bat` and `mamba_hook.bat` guard on `IF DEFINED CONDA_SHLVL GOTO :EOF`. Whichever loads second in the CMD AutoRun chain silently exits. The solution is to remove conda entirely before installing micromamba.

### PowerShell 5.1 vs 7 have separate profiles

Micromamba shell init writes hooks to the PowerShell 5.1 profile by default. If PowerShell 7 is installed, the hooks must be copied to its profile separately. The paths:

- 5.1: `$USERPROFILE\Documents\WindowsPowerShell\profile.ps1`
- 7: `$USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`

### PowerShell 5.1 requires UTF-8 BOM for non-ASCII characters

PS5.1 defaults to the system's ANSI codepage when reading scripts without a Byte Order Mark (BOM). If a script contains non-ASCII characters (em-dashes, curly quotes, etc.), PS5.1 will misparse them, causing syntax errors that don't appear under PS7. Two rules:

1. **Avoid non-ASCII characters** in `.ps1` files (use `--` instead of `—`, ASCII quotes instead of curly quotes)
2. **Save with UTF-8 BOM** if non-ASCII is unavoidable. Also add `-Encoding UTF8` to any `Set-Content` / `Add-Content` calls that write profile files

### Execution policy blocks scripts by default

Windows ships with `Restricted` execution policy. `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` must be set before any `.ps1` script can run. `prepare-for-runbooks.ps1` handles this, but scripts invoked with `-ExecutionPolicy Bypass` sidestep it for themselves — the policy setting is for downstream scripts.

---

## macOS-specific gotchas

### Homebrew path differs on Apple Silicon

Homebrew installs to `/opt/homebrew` on Apple Silicon (M1+) and `/usr/local` on Intel. The Apple Silicon path isn't on `$PATH` by default — it requires adding `eval "$(/opt/homebrew/bin/brew shellenv)"` to `~/.zprofile`.

### Apple Git shadows Homebrew Git

`/usr/bin/git` (Apple's Xcode CLI tools) may take precedence over Homebrew's git. After installing via brew, a new terminal is needed for Homebrew's path to take priority.

In normal interactive terminals, Homebrew's `/opt/homebrew/bin` comes first on PATH, so brew git wins. However, non-interactive sessions (including Claude Code) may have a different PATH order where Apple Git at `/usr/bin/git` takes precedence. This is cosmetic — both versions are functionally equivalent for runbook purposes. The `verify-prerequisites.sh` script warns when Apple Git is the resolved version, which is useful for catching machines where brew git was never installed, but the warning can be safely ignored in Claude Code sessions where brew git is confirmed installed.

### Shell testing requires correct flags

| Shell | Flags | Why |
|-------|-------|-----|
| zsh | `-i` | Interactive — loads `~/.zshrc` where micromamba hooks live |
| bash | `-l -i` | Login (`-l`) loads `~/.bash_profile`; interactive (`-i`) activates hooks |

Using wrong flags means hooks don't load and `micromamba activate` fails even when correctly configured.

### Micromamba is a shell function on macOS

After `brew install micromamba` and shell init, `micromamba` exists as a shell function, not a standalone binary on PATH. Detection scripts must check `MAMBA_EXE` environment variable or the brew cellar path, not just `which micromamba`.

---

## Script conventions

### Standard script header

```powershell
# script-name.ps1 - One-line description
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File script-name.ps1
#
# Output: Structured lines prefixed with OK / SKIP / FAIL / INFO
# Exit code: 0 on success, 1 on any failure

$ErrorActionPreference = 'Continue'
$FailCount = 0
```

### Adding a new app to install-apps.ps1

Add an entry to the `$Apps` array. For CLI tools, set `Verify` to the command name and `VerifyFlag` to the version flag. If the tool installs to a known location that may not be on PATH immediately, add `VerifyPaths` (an array of candidate locations to search):

```powershell
@{ Id = "Some.WingetId"; Name = "Display Name"; Verify = "cmd"; VerifyFlag = "--version";
   VerifyPaths = @("$env:ProgramFiles\SomeApp\cmd.exe", "${env:ProgramFiles(x86)}\SomeApp\cmd.exe") }
```

### Adding a new shell to verify-shell-integration.ps1

Use the `Test-ShellActivate` helper for shells that can be tested via process spawn. For shells that need special pre-checks (like CMD's AutoRun registry), implement the test inline following the CMD pattern.

### String replacement in paths

Use `.Replace()` (literal string replacement) instead of `-replace` (regex) when substituting file paths in shell configs:

```powershell
# GOOD: literal replacement, no regex surprises
$content = $content.Replace($oldPath, $newPath)

# BAD: -replace treats $ as backreference, \ as escape
$content = $content -replace [regex]::Escape($oldPath), $newPath
```

Even with `[regex]::Escape()` on the pattern, the replacement string is still interpreted for regex backreferences (`$1`, `$&`, etc.). Windows paths containing `$` (e.g., in usernames) will silently corrupt the replacement.

### Exit code checking on external commands

Always check `$LASTEXITCODE` after calling external tools before parsing their output. Empty output from a failed command can silently pass validation:

```powershell
# GOOD: check exit code before parsing
$output = & $mmExe env list 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "FAIL: command failed (exit code $LASTEXITCODE)"
} elseif ($output -match $pattern) {
    # safe to use the output
}

# BAD: empty output from a failed command matches nothing, silently treated as "not found"
$output = & $mmExe env list 2>$null
if ($output -match $pattern) { ... }
```

### Cross-platform runbook sections

Use platform headers (`### Windows` / `### macOS`) within shared runbooks. Keep platform-specific commands in their own code blocks. Use `### Cross-platform` for steps that work everywhere.
