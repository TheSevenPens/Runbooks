# Windows Machine Setup Runbook
> **How to use this with Claude Code:** Open Claude Code in your terminal, point it at this file, and say: *"Follow the setup runbook at setup-runbook-windows.md. Walk me through each section, automate what you can, and tell me when I need to do something manually. Be aware we may be using a machine where some components are already installed. And may be installed through an alternative means than described in the runbook. We need to decide how to handle them."*

> 📝 **Quick check:** Run `scripts/windows/verify-prerequisites.ps1` to see what's already installed before starting:
> ```bash
> powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/verify-prerequisites.ps1
> ```

---

## Section 0 — Post-OneDrive Migration Cleanup

> 📝 **Note:** Skip this section if OneDrive Documents redirection was never enabled, or if this is a fresh machine where OneDrive "Known Folder Move" has already been disabled.

If you previously ran this runbook (or any scripts that write PowerShell profiles) while OneDrive Documents redirection was active, then disabled the redirection, stale profile files may be stranded in the old OneDrive location. These need to be cleaned up before rerunning the runbook, otherwise both old and new profiles may exist and cause confusion.

### 0a. Verify the redirection is actually off

> ⚠️ **Claude Code note:** Run this check and show the result to the user before proceeding.

```powershell
$docsDir = [Environment]::GetFolderPath('MyDocuments')
$defaultDir = Join-Path $env:USERPROFILE "Documents"
if ($docsDir -eq $defaultDir) {
    Write-Host "OK: Documents points to $docsDir (no OneDrive redirection)" -ForegroundColor Green
} else {
    Write-Host "WARN: Documents is still redirected to $docsDir" -ForegroundColor Yellow
    Write-Host "  Disable OneDrive Known Folder Move before continuing." -ForegroundColor Yellow
}
```

### 0b. Remove stale PowerShell profiles from the old OneDrive location

> ⚠️ **Claude Code note:** Only delete profiles that contain micromamba/conda init blocks or Oh My Posh lines. If a profile has user-customized content beyond what the runbook scripts write, show it to the user and ask before deleting.

Check for stale profiles:

```powershell
$staleLocations = @(
    "$env:USERPROFILE\OneDrive\Documents\WindowsPowerShell\profile.ps1",
    "$env:USERPROFILE\OneDrive\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1",
    "$env:USERPROFILE\OneDrive\Documents\PowerShell\profile.ps1",
    "$env:USERPROFILE\OneDrive\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
)
foreach ($p in $staleLocations) {
    if (Test-Path $p) {
        Write-Host "FOUND: $p" -ForegroundColor Yellow
    }
}
```

For each file found, inspect its contents. If it only contains runbook-managed blocks (micromamba init, conda init, Oh My Posh), delete it. If the containing directory is empty afterward, delete the directory too.

### 0c. Remove stale shell hook files

Micromamba's `shell init` may have written hook scripts to the old Documents path. Check and remove:

```powershell
$staleHookDirs = @(
    "$env:USERPROFILE\OneDrive\Documents\WindowsPowerShell\Modules",
    "$env:USERPROFILE\OneDrive\Documents\PowerShell\Modules"
)
foreach ($d in $staleHookDirs) {
    if (Test-Path $d) {
        Write-Host "FOUND: $d" -ForegroundColor Yellow
    }
}
```

### 0d. Verify clean state

After cleanup, confirm no stale profiles remain and that the current Documents path is correct:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/verify-prerequisites.ps1
```

The OneDrive redirection warning should no longer appear.

---

## Sections 1-6 — Install Dev Tools

Installs Git for Windows, GitHub Desktop, VS Code, Chrome, Windows Terminal, and PowerShell 7 via a single idempotent script. Already-installed apps are skipped.

### Run the install script
```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/install-apps.ps1
```

> 📝 **Alternative: winget import.** For a faster bulk install, use the declarative JSON file instead:
> ```bash
> powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/import-apps.ps1
> ```
> This reads `apps/windows.json` and installs all packages in one shot. Both approaches install the same apps — `install-apps.ps1` gives per-app structured output while `import-apps.ps1` is faster for fresh machines. To regenerate the JSON after changing the app list, run `export-apps.ps1`.

> ⚠️ **Manual step:** After the script completes, close and reopen your terminal so PATH changes take effect.

> 📝 **What the script installs:**
>
> | App | Winget ID | Verify command |
> |-----|-----------|----------------|
> | Git for Windows | `Git.Git` | `git --version` |
> | GitHub Desktop | `GitHub.GitHubDesktop` | *(GUI app)* |
> | Visual Studio Code | `Microsoft.VisualStudioCode` | `code --version` |
> | Google Chrome | `Google.Chrome.EXE` | *(GUI app)* |
> | Windows Terminal | `Microsoft.WindowsTerminal` | *(GUI app)* |
> | PowerShell 7 | `Microsoft.PowerShell` | `pwsh --version` |

> 📝 **Notes:**
> - **Git for Windows** gives you: `git` CLI in any terminal, Git Bash (right-click → "Open Git Bash here"), and Git Credential Manager.
> - **VS Code + micromamba:** Once the `node1` environment is created (see Section 8), select it as your Python interpreter in VS Code — open a `.py` file, click the interpreter selector in the status bar, and choose `node1`.
> - **PowerShell 7** installs alongside 5.1 — it does not replace it. In Windows Terminal it appears as "PowerShell" (vs "Windows PowerShell"). Launch with `pwsh`.

---

## Section 7 — (Optional) Oh My Posh — Custom Prompt

> 🤔 **Claude Code: Ask the user before proceeding with this step.**
> *"Would you like to install Oh My Posh? It customizes your terminal prompt to show useful context like the current git branch, conda environment name, Node version, and more. It requires a Nerd Font to display icons correctly. Install it? (yes/no)"*

If yes, install Oh My Posh:
```powershell
winget install -e --id JanDeLaater.OhMyPosh --silent
```

Then install a Nerd Font (JetBrains Mono recommended):
```powershell
oh-my-posh font install JetBrainsMono
```

> ⚠️ **Manual step:** After installing the font, open Windows Terminal → Settings → your PowerShell profile → Appearance, and set the font to **JetBrainsMono Nerd Font**. Then add Oh My Posh to your PowerShell profile:
> ```powershell
> # Add this line to your $PROFILE file:
> oh-my-posh init pwsh | Invoke-Expression
> ```

---

## Section 8 — Micromamba & Environments

> 📘 **See [conda-env-runbook.md](conda-env-runbook.md)** for all steps related to installing Micromamba, removing Conda (if present), shell configuration, and creating the `node1` environment. This was separated into its own runbook due to the number of platform-specific workarounds involved.

---

## Post-Setup Manual Checklist

> ⚠️ **Manual step:** These GUI apps need manual sign-in/configuration after all automated setup is complete:
> - **GitHub Desktop** — launch from Start Menu, sign in with GitHub. Git Credential Manager (from Git for Windows) handles credential storage.
> - **Chrome** — launch from Start Menu, sign in with Google to restore bookmarks, extensions, and passwords.
> - **Windows Terminal** — launch from Start Menu. Optionally set as default terminal in Settings → System → For developers → Terminal.

---

## Notes & Known Issues

| Issue | Fix |
|---|---|
| Execution policy blocks scripts | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| `gh` auth needed after install | `gh` is installed inside the `node1` micromamba env (not system-wide). Activate first: `micromamba activate node1 && gh auth login` |
| Fresh PS7 install left PS7 profile missing micromamba hook | Fixed: `install-apps.ps1` now auto-runs `micromamba-shell-init.ps1` after installing PS7 (if micromamba is present), and `verify-shell-integration.ps1` now checks `$LASTEXITCODE` + `$env:CONDA_PREFIX` so a missing hook can no longer pass silently. |
| `winget` not recognized when running scripts from Git Bash | winget is an AppX execution alias that isn't in the Machine/User PATH registry. Scripts refresh PATH from the registry (losing the AppX alias). Fixed: `install-apps.ps1` and `verify-prerequisites.ps1` now resolve winget via `Get-AppxPackage` at startup and call it by full path. |
| `install-apps.ps1` PATH refresh drops winget mid-run | After installing an app with a CLI verifier, the script refreshes `$env:Path` from the registry (lines 102-104). This overwrites the session PATH and drops the AppX winget alias. The first few apps install fine, then the rest fail. Fixed by resolving winget to its full path once at startup and using `$WingetExe` everywhere. |
| OneDrive Documents redirection breaks PowerShell profile lookups | When OneDrive redirects `Documents` to `~\OneDrive\Documents`, scripts that hardcode `$env:USERPROFILE\Documents\...` for PS profile paths look in the wrong place. Affected: `micromamba-shell-init.ps1`, `verify-prerequisites.ps1`, `remove-conda.ps1`. Fixed: all now use `[Environment]::GetFolderPath('MyDocuments')`. `verify-prerequisites.ps1` also prints a WARN when redirection is detected. |
| PATH registry type `REG_SZ` on fresh Windows machines | The micromamba installer (or Windows itself) may set `HKCU\Environment\Path` to `REG_SZ` instead of `REG_EXPAND_SZ`. CMD silently ignores user PATH entries when the type is wrong. Fixed by `fix-path-registry.ps1` (run during Section 8). |
| PowerShell 7 installs as MSIX on ARM, `pwsh` not at standard path | `winget install Microsoft.PowerShell` on ARM64 installs the MSIX package, placing `pwsh.exe` at `AppData\Local\Microsoft\WindowsApps\` instead of `Program Files\PowerShell\7\`. Fixed: `install-apps.ps1` now includes the WindowsApps path in `VerifyPaths`. |
| Em-dash characters in PS scripts cause parse errors | PowerShell 5.1 cannot parse UTF-8 files containing non-ASCII characters (like `---`) unless the file has a BOM. Scripts must use only ASCII characters. See `CLAUDE.md` "File encoding rules" for the full policy. |
| PS5.1 `-Encoding UTF8` adds BOM, breaking bash files | PowerShell 5.1's `Set-Content -Encoding UTF8` and `Add-Content -Encoding UTF8` always add a UTF-8 BOM (`EF BB BF`). Bash interprets these bytes as part of the first command, producing `$'\357\273\277eval': command not found`. PS7 does **not** add a BOM. Since scripts may run under either version, never use `-Encoding UTF8` when writing files that bash reads. Use `[System.IO.File]::WriteAllText()` instead. `verify-prerequisites.ps1` now checks `.bash_profile` and `.bashrc` for accidental BOMs. |
| Micromamba installer downloads x86-64 binary on ARM64 | The official installer at `micro.mamba.pm/install.ps1` downloads `micromamba-win-64` (x86-64), not a native ARM64 build. It works under Windows x86-64 emulation but is not optimal. No ARM64 build is currently published upstream. |
| Micromamba issues | See [conda-env-runbook.md](conda-env-runbook.md) — Notes & Known Issues |

---

## First-Run Discoveries (Windows on ARM, 2026-04-09)

This section documents issues found during the first run of the runbook on a Windows 11 ARM64 (Snapdragon) machine. All issues have been fixed in the scripts, and the relevant Known Issues entries above describe the fixes. This section provides the narrative for anyone trying to understand *what happened and why*.

### 1. winget exists but isn't callable

**Symptom:** `verify-prerequisites.ps1` and `install-apps.ps1` both failed with `winget: The term 'winget' is not recognized`. The Desktop App Installer package was installed (v1.28.220) and `winget.exe` existed at `C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_...\winget.exe`.

**Root cause:** winget is exposed via an AppX execution alias, not a standard PATH entry. The alias works in interactive terminals but not when scripts refresh `$env:Path` from the registry (which only contains Machine + User PATH, not AppX aliases). The `install-apps.ps1` script refreshed PATH after each CLI-verifiable install (to find the newly installed command), and this refresh *also* lost winget, causing the script to partially succeed (Git skipped, GitHub Desktop and VS Code installed) then fail for every remaining app.

**Fix:** Both scripts now resolve winget at startup via `Get-AppxPackage` and store the full path in `$WingetExe`.

### 2. OneDrive Documents folder redirection

**Symptom:** `micromamba-shell-init.ps1` reported `WARN: Could not find mamba init block in $ps5Profile to copy` even though the profile existed and contained the correct init block. `verify-prerequisites.ps1` couldn't find PS profiles for MAMBA_EXE consistency checks.

**Root cause:** OneDrive's "Known Folder Move" feature redirects `~\Documents` to `~\OneDrive\Documents`. The Windows shell folder registry key (`HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders\Personal`) points to the OneDrive location. PowerShell's `$PROFILE` correctly follows this redirection, and `micromamba shell init -s powershell` uses `$PROFILE` internally so it wrote the init block to the correct location. But our scripts hardcoded `$env:USERPROFILE\Documents\WindowsPowerShell\...` and `$env:USERPROFILE\Documents\PowerShell\...`, which don't exist when OneDrive redirects Documents.

**Impact:** Three scripts were affected: `micromamba-shell-init.ps1` (PS7 profile sync and MAMBA_EXE verification), `verify-prerequisites.ps1` (MAMBA_EXE consistency checks), and `remove-conda.ps1` (conda profile cleanup). In all cases the scripts silently looked in the wrong directory.

**Fix:** All scripts now use `[Environment]::GetFolderPath('MyDocuments')` to resolve the actual Documents path. `verify-prerequisites.ps1` prints a warning when OneDrive redirection is detected.

### 3. PATH registry type was REG_SZ

**Symptom:** `fix-path-registry.ps1` found `HKCU\Environment\Path` was type `String` (`REG_SZ`) instead of `ExpandString` (`REG_EXPAND_SZ`).

**Root cause:** The micromamba installer adds itself to the user PATH. On this fresh machine, this was the first modification to the user PATH, and the installer (or Windows default) set the type to `REG_SZ`. CMD ignores user PATH entries with the wrong type.

**Fix:** `fix-path-registry.ps1` detected and corrected this automatically.

### 4. PowerShell 7 installed as MSIX (not MSI)

**Symptom:** After `winget install Microsoft.PowerShell`, `pwsh` was not found on PATH and not at the expected `C:\Program Files\PowerShell\7\pwsh.exe`.

**Root cause:** On ARM64, winget installs the MSIX package of PowerShell 7, which places `pwsh.exe` at `AppData\Local\Microsoft\WindowsApps\pwsh.exe` via an AppX execution alias. The `install-apps.ps1` script only checked `Program Files\PowerShell\7\` as a fallback path.

**Fix:** Added `$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe` to the `VerifyPaths` array.

### 5. Micromamba is x86-64 under emulation

**Symptom:** No error, but `micromamba.exe` is an x86-64 binary running under Windows ARM64 emulation.

**Root cause:** The official micromamba installer (`micro.mamba.pm/install.ps1`) downloads `micromamba-win-64` regardless of architecture. There is no `micromamba-win-arm64` build published. The conda packages it installs *are* correct architecture (conda-forge has `win-64` packages that run under emulation, and some native ARM packages are becoming available).

**Impact:** Performance overhead from x86-64 emulation during env creation and package operations. Functionally correct.

### 6. Em-dash characters cause PowerShell parse errors

**Symptom:** After editing scripts, PowerShell 5.1 threw parse errors on unrelated lines (`Unexpected token`, `Missing type name after '['`).

**Root cause:** The Edit tool wrote UTF-8 em-dash characters (`---`, 3 bytes: `E2 80 94`) into `.ps1` files. PowerShell 5.1's parser cannot handle multi-byte UTF-8 without a BOM --- it misinterprets byte boundaries and produces cascading parse errors on lines *after* the offending character. The error messages point to valid regex patterns like `[^"]+` which are perfectly fine --- PS5.1 is just confused about byte alignment.

**Lesson:** All `.ps1` files in this repo must use ASCII-only characters. Use `-` (hyphen) instead of `---` (em-dash).

---

## Status Tracker

> ⚠️ **Claude Code note:** Do NOT track status in this file — it lives in git and is shared across machines. Instead, create/update a local checklist at `~/Documents/runbook-status/setup-runbook-windows.md`. At the start of each run:
> 1. Create the directory and file if they don't exist (use the template below).
> 2. Reset all checkboxes to `[ ]`.
> 3. Check off items as each step completes.

<details>
<summary>Checklist template</summary>

```markdown
# setup-runbook-windows status

- [ ] OneDrive cleanup complete (Section 0, if applicable)
- [ ] Dev tools installed (install-apps.ps1)
- [ ] Oh My Posh installed (if chosen)
- [ ] Oh My Posh font configured (if chosen, manual)
- [ ] Micromamba setup complete (see conda-env-runbook.md)
- [ ] GitHub Desktop signed in (manual)
- [ ] Chrome signed in (manual)
- [ ] Windows Terminal set as default (manual, optional)
```

</details>
