# Change History

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

### `setup-runbook-windows.md` — moved manual sign-ins to end

The manual sign-in steps for GitHub Desktop, Chrome, and Windows Terminal were in the middle of the runbook, interrupting the automated flow with a prompt. Moved them to a new "Post-Setup Manual Checklist" section at the end so the entire automated portion (dev tools, Oh My Posh, micromamba) runs without stopping. Updated the status tracker template to match the new order.
