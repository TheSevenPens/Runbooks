# Change History

## 2026-10-14 --- remove-conda.ps1 handles half-uninstalled miniconda3

### Fix: `scripts/windows/remove-conda.ps1`
- The "looks like a conda installation" check before `Remove-Item -Recurse` also accepts `Uninstall-Miniconda3.exe`, `pre_uninstall.bat`, and `_conda.exe`. A winget uninstall can leave only these plus runtime DLLs, and the old check refused to delete that directory (exit 1). The path-equals-expected and non-empty checks are unchanged.
- Known Issues row added to `conda-env-runbook.md`.

## 2026-10-14 — Claude Code guidance installed machine-wide

The shim guidance from the previous change lived only in this repo's `CLAUDE.md`, which Claude Code reads only inside this repo --- not in the other projects where the orphans piled up. Re-running the runbook also changed nothing on an existing machine.

### New: `scripts/windows/install-claude-guidance.ps1`
- Idempotently installs `scripts/windows/claude-guidance-mise-shims.md` into `%USERPROFILE%\.claude\CLAUDE.md` between BEGIN/END markers (append / replace if changed / skip if current), filling in this machine's Runbooks path. Preserves content outside the markers and the file's line endings; writes UTF-8 without BOM. `-Remove` deletes the block.

### Docs
- `mise-env-runbook.md` Section 5: new step, Known Issues row, discovery note, checklist item.
- `CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/FUTURES.md`: references.

## 2026-10-14 — Orphaned mise shim processes

During a long Claude Code session on Windows the machine became unresponsive with hundreds of `python.exe` and `mise.exe` processes. Cause: each mise shim call on Windows is a three-process chain (shim → `mise.exe` → real tool), Claude Code's Bash tool goes through shims, and Windows doesn't kill children with their parent, so every timed-out or stopped command left two processes behind. Full writeup in `mise-env-runbook.md` "Third-Run Discoveries".

### New: `scripts/shared/process-helpers.ps1`
- `PROC_Invoke`: run a child with a timeout, reading stdout/stderr asynchronously, and stop the whole tree on timeout.
- `PROC_StopTree`: `taskkill /T /F` wrapper (works on PS5.1, which has no `Kill(true)`).

### New: `scripts/windows/find-orphan-tool-processes.ps1`
- Lists `python`/`pythonw`/`mise`/`node` processes grouped by command line, flags those whose parent has exited, and stops their trees with `-Kill`.

### Fixed: blocking reads and single-process kills in runbook scripts
- `install-mise-tools.ps1`, `verify-mise.ps1`, `verify-shell-integration.ps1` read child output with `ReadToEnd()` before `WaitForExit(timeout)` (timeout never fired on a hang) and used `Process.Kill()` (orphaned grandchildren). Several steps in `install-mise-tools.ps1` also ignored timeouts entirely. All now use `PROC_Invoke`; timeouts are reported as `FAIL`.

### Docs
- `mise-env-runbook.md`: new Section 5 (shim process chain, Claude Code rules, orphan cleanup), Known Issues rows, Third-Run Discoveries, checklist item.
- `CLAUDE.md`: two new key lessons (shims orphan processes; use `PROC_Invoke`).
- `docs/ARCHITECTURE.md`: Windows gotchas for process trees and `PROC_Invoke`; shared helpers in repo structure.
- `windows-setup-runbook.md`: Known Issues pointer.
- `docs/FUTURES.md`: "Shim-free PATH for Claude Code and editors on Windows".

## 2026-03-30 — Script robustness audit and fixes

Reviewed all 10 Windows PowerShell scripts for robustness and reliability. Fixes applied at three priority levels (critical, high, medium) across 9 scripts.

### Critical fixes

**`remove-conda.ps1` — safe recursive deletion:**
- `Remove-Item -Recurse -Force` on the miniconda3 directory now validates three conditions before proceeding: the path variable matches the expected `$USERPROFILE\miniconda3`, the path is non-empty, and the directory actually looks like a conda installation (contains `conda-meta`, `Scripts\conda.exe`, or `pkgs`). Previously, a corrupted or empty variable could delete the wrong directory.
- Backup failure now aborts the entire removal instead of warning and continuing to delete the original.
- `environments.txt` handling wrapped in `@()` to prevent null vs empty array comparison bugs.

**`create-env.ps1` — exit code checking and ghost environment detection:**
- All `micromamba env list` and `micromamba list -n` calls now check `$LASTEXITCODE` before parsing output. Previously, a failed command produced empty output that was silently treated as success.
- Added ghost environment detection: when `env list` shows an environment but the prefix directory doesn't exist on disk, the script now treats it as non-existent and creates fresh. This was a real bug hit during a runbook run.
- Package list splatting changed from `@packageList` (PowerShell splatting syntax) to explicit `@createArgs` array to avoid issues with special characters.

**`micromamba-shell-init.ps1` — PS5.1 compatibility:**
- Replaced em-dash characters (`—`) with ASCII double-dashes in all strings and comments. PS5.1 misparses UTF-8 em-dashes in BOM-less files, causing a script-wide parse failure.
- File saved with UTF-8 BOM so PS5.1 reads it correctly.
- Added `-Encoding UTF8` to all `Set-Content` and `Add-Content` calls that write profile files.

**`import-apps.ps1` — winget list reliability:**
- Package detection now checks both `$LASTEXITCODE` and that the package ID appears in the output string (via `[regex]::Escape()`). Some Windows versions return exit code 0 from `winget list` even when the package isn't found.
- `winget import` output is now parsed and reported: success count, failure count, and non-zero exit code warnings.

**`export-apps.ps1` — JSON validation:**
- Added structure validation after parsing: checks that `$parsed`, `$parsed.Sources`, and `$parsed.Sources[0].Packages` are non-null before accessing nested properties. Previously, a malformed JSON file would crash with an unhandled null reference.

**`micromamba-shell-init.ps1` — regex escaping in MAMBA_EXE replacement:**
- Changed from `-replace [regex]::Escape(...)` to `.Replace()` for path substitution. The `-replace` operator treats `$` in the replacement string as a regex backreference, which can silently corrupt paths containing `$` (e.g., usernames).

**`prepare-for-runbooks.ps1` — install script validation:**
- Downloaded install script is now validated before `Invoke-Expression`: checked for non-empty content and basic PowerShell-like structure. Previously, a network failure returning an empty or HTML error page would be piped directly to `Invoke-Expression`.

### High-priority fixes

**`install-apps.ps1` — hardcoded paths and silent failures:**
- `VerifyPath` (single path) replaced with `VerifyPaths` (array) to search multiple candidate locations for PowerShell 7, including `Program Files (x86)`.
- Version check `catch` blocks now log the exception instead of silently swallowing it.

**`verify-shell-integration.ps1` — process cleanup and path search:**
- Added `$proc.WaitForExit(5000)` after `$proc.Kill()` to ensure timed-out processes are fully terminated before subsequent tests start.
- PowerShell 7 fallback path search now checks multiple candidates instead of a single hardcoded path.
- CMD section timeout extracted from hardcoded `30000` to a named variable.

**`fix-path-registry.ps1` — missing Path key:**
- `GetValueKind('Path')` now wrapped in try-catch. If the `Path` value doesn't exist (possible on fresh installs), the script creates it as `REG_EXPAND_SZ` instead of crashing.

**`remove-conda.ps1` — string replacement safety:**
- All `-replace [regex]::Escape(...)` calls for path substitution in shell configs changed to `.Replace()` (literal string replacement) to avoid regex special character issues in Windows paths.
- Bash path conversion rewritten: dead code removed, single clear conversion from `C:\Users\...` to `/c/Users/...`.

**`verify-prerequisites.ps1` — path conversion and error reporting:**
- `ConvertTo-WindowsPath` now handles WSL-style `/mnt/c/` paths in addition to Git Bash `/c/` style.
- MAMBA_EXE error messages now include both the original and normalized path when they differ.

### Medium-priority fixes

- `-Encoding UTF8` added to all `Set-Content` calls that write profile files in `remove-conda.ps1`.
- Consistent use of `.Replace()` over `-replace` for path operations across all scripts that modify shell configs.

---

## 2026-03-29 — macOS scripts aligned with Windows best practices

Reviewed all macOS scripts against the patterns established in the Windows scripts and applied the same conventions.

### `scripts/mac/prepare-for-runbooks.sh` — structured output

Replaced emoji output prefixes (✅/❌/⏳) with the standard `OK/FAIL/INFO/SKIP/WARN` structured output format used by all Windows scripts. Added `FAIL_COUNT` tracking and a summary exit section. Updated the shebang to `#!/usr/bin/env bash` and added a standard script header with Usage/Output/Exit code documentation.

### `scripts/mac/verify-shell-integration.sh` — micromamba-only

Removed all `conda activate` tests. The user uses micromamba exclusively (conda has been fully removed), so testing conda was producing guaranteed FAILs. Now matches the Windows version which only tests micromamba. Updated the summary table to a single `micromamba activate` column.

### `scripts/mac/verify-prerequisites.sh` — micromamba-only, canonical path fallback

Flipped the conda check: instead of treating it as required (`FAIL: conda not found`), now warns if conda is present since it should have been removed. Removed the `envs_dirs` alignment check between conda and micromamba configs (no longer relevant). Added canonical path fallback for micromamba — checks the brew cellar at `/opt/homebrew/opt/micromamba/bin/micromamba` when neither `MAMBA_EXE` nor `command -v` find it (matches the Windows pattern of checking canonical install paths).

### New script: `scripts/mac/install-apps.sh`

Created the macOS equivalent of `install-apps.ps1` — an idempotent script that installs Git, GitHub Desktop, VS Code, and Chrome via Homebrew. Features:

- Data-driven app definitions (type, brew ID, verify command, canonical path)
- CLI check first (fast), then `brew list` fallback, matching the Windows two-tier detection
- Canonical path fallback for freshly installed CLI tools not yet on PATH
- Verify-after-install for CLI tools
- Standard structured output (OK/SKIP/FAIL/INFO/WARN)

### `mac-setup-runbook.md` — consolidated app install, manual steps at end

Replaced individual brew install sections (2–5) with a single section pointing to `install-apps.sh`, matching the Windows runbook pattern. Moved manual sign-in steps (GitHub Desktop, Chrome) to a new "Post-Setup Manual Checklist" section at the end so the automated flow isn't interrupted. Added a quick-check command at the top (`verify-prerequisites.sh`). Updated the Status Tracker to reflect the new structure.

---

## 2026-03-29 — Robustness and prompt-reduction improvements

Ran the full Windows setup runbook end-to-end and identified several friction points where scripts gave false negatives, left steps as manual, or interrupted the automated flow with unnecessary prompts. Made the following changes:

### New script: `scripts/windows/prepare-for-runbooks.ps1`

Converted `prepare_for_runbooks.md` (a short markdown doc with manual copy-paste instructions) into a proper PowerShell script that:

- Sets `ExecutionPolicy RemoteSigned` for the current user so downstream scripts don't get blocked
- Installs Claude Code via the official installer (skips if already present)
- Adds the Claude bin directory to the user PATH only if not already there
- Uses `REG_EXPAND_SZ` for the PATH registry key (avoids the known CMD issue)
- Broadcasts `WM_SETTINGCHANGE` so new shells pick up PATH changes immediately
- Verifies the install succeeded and reports the version

### `scripts/windows/verify-shell-integration.ps1` — two fixes

**PowerShell 7 false SKIP:** The script used `Get-Command pwsh` to find PowerShell 7, which fails when pwsh is installed but not yet on PATH (common right after `winget install`). Added a fallback that checks the canonical install path `$env:ProgramFiles\PowerShell\7\pwsh.exe`. This matches the pattern already used in `micromamba-shell-init.ps1`.

**CMD left as manual test:** The script printed "CMD requires manual testing" and skipped it. Replaced this with an automated test that checks for the `mamba_hook.bat` AutoRun registry entry, then launches `cmd.exe /c` (which triggers AutoRun automatically) and verifies `micromamba activate base` succeeds. All four shells are now fully automated.

### `scripts/windows/install-apps.ps1` — canonical path fallback

After installing PowerShell 7 via winget, the script tried to verify with `Get-Command pwsh`, which fails in the same session because PATH hasn't refreshed. Added a `VerifyPath` property to the app definition that points to the canonical install location. Both the pre-install check and post-install verification now fall back to this path. Also fixed version reporting to use the resolved full path instead of the short command name (was showing blank version strings).

### `windows-setup-runbook.md` — moved manual sign-ins to end

The manual sign-in steps for GitHub Desktop, Chrome, and Windows Terminal were in the middle of the runbook, interrupting the automated flow with a prompt. Moved them to a new "Post-Setup Manual Checklist" section at the end so the entire automated portion (dev tools, Oh My Posh, micromamba) runs without stopping. Updated the status tracker template to match the new order.
