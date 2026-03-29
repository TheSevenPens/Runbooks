# Micromamba Environment Setup Runbook

> **How to use this with Claude Code:** Open Claude Code in your terminal, point it at this file, and say: *"Follow the environment runbook at conda-env-runbook.md. Walk me through each section, automate what you can, and tell me when I need to do something manually."*
>
> **Prerequisites (Windows):** The following should already be installed. If not, see [setup-runbook-windows.md](setup-runbook-windows.md).
> - **Git for Windows** — provides Git Bash, needed for bash shell init
> - **winget** — ships with Windows 11; on Windows 10, install via Microsoft Store
>
> **Prerequisites (macOS):** The following should already be installed. If not, see [setup-runbook-mac.md](setup-runbook-mac.md).
> - **Homebrew** — used to install Micromamba
> - **Git** — install via Homebrew (recommended) or use Apple Git from Xcode CLI tools
>
> 📝 **Quick check (macOS):** Run `scripts/mac/verify-prerequisites.sh` to check what's already installed before starting.

---

## Section 0 — Remove Conda (if installed)

> ⚠️ **Claude Code note:** If Miniconda/Anaconda is already installed, remove it before proceeding. Keeping both conda and micromamba causes CMD shell hook conflicts — both `conda_hook.bat` and `mamba_hook.bat` use an `IF DEFINED CONDA_SHLVL GOTO :EOF` guard, so whichever loads second in the CMD AutoRun chain silently fails.

### Windows

#### 0a. Back up existing environments
```powershell
# List environments first
conda env list

# Copy envs to a backup location (skip base)
Copy-Item -Recurse "$env:USERPROFILE\miniconda3\envs" "$env:USERPROFILE\envs-backup"
```

#### 0b. Uninstall Miniconda
```powershell
winget uninstall --id Anaconda.Miniconda3
```

#### 0c. Clean up remaining files
The winget uninstaller may leave files behind. Remove them:
```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\miniconda3" -ErrorAction SilentlyContinue
```

#### 0d. Clean up shell hooks and PATH
```powershell
# Remove miniconda paths from user PATH
$key = Get-Item 'HKCU:\Environment'
$val = $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
$parts = $val -split ';' | Where-Object { $_ -ne '' -and $_ -notmatch 'miniconda3' }
$newPath = $parts -join ';'
Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value $newPath -Type ExpandString

# Clear CMD AutoRun (micromamba shell init will set it fresh)
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Command Processor' -Name AutoRun -ErrorAction SilentlyContinue

# Remove .condarc
Remove-Item "$env:USERPROFILE\.condarc" -ErrorAction SilentlyContinue
```

Remove the conda init block from `~/.bash_profile` and clear the PowerShell profile (`$PROFILE`) of conda hooks. Micromamba shell init (Section 1c) will write fresh hooks.

#### 0e. Verify removal
```powershell
conda --version   # should fail: not recognized
```

### macOS

#### 0a. Back up existing environments
```zsh
conda env list
cp -r ~/miniconda3/envs ~/envs-backup
```

#### 0b. Uninstall Miniconda
```zsh
brew uninstall miniconda
```

#### 0c. Clean up remaining files
```zsh
rm -rf ~/miniconda3
rm -f ~/.condarc
```

#### 0d. Clean up shell hooks
Remove the `# >>> conda initialize >>>` block from `~/.zshrc` and/or `~/.bash_profile`. Micromamba shell init (Section 1b) will write fresh hooks.

---

## Section 1 — Micromamba

### Windows

#### 1a. Install Micromamba
```powershell
Invoke-Expression ((Invoke-WebRequest -Uri https://micro.mamba.pm/install.ps1 -UseBasicParsing).Content)
```
> ⚠️ **Manual step:** If you get an execution policy error, run this first, then retry:
> ```powershell
> Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```
>
> 📝 **Note:** The installer places the binary in `%USERPROFILE%\AppData\Local\micromamba\` and adds that directory to the user PATH.

#### 1b. Verify PATH registry type
> ⚠️ **Claude Code note:** The user `Path` registry key (`HKCU\Environment\Path`) must be stored as `REG_EXPAND_SZ`, not `REG_SZ`. If it's `REG_SZ`, CMD will silently ignore user PATH entries. Check and fix:
> ```powershell
> # Check type
> (Get-Item 'HKCU:\Environment').GetValueKind('Path')
>
> # Fix if it shows "String" instead of "ExpandString"
> $key = Get-Item 'HKCU:\Environment'
> $val = $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
> Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value $val -Type ExpandString
> ```

#### 1c. Initialize micromamba shell hooks for all shells (Windows)
Initialize micromamba's shell integration for every shell type. **Always run these from PowerShell** (not Git Bash) to ensure correct path handling:
```powershell
micromamba shell init -s powershell -r $env:USERPROFILE\micromamba
micromamba shell init -s bash -r $env:USERPROFILE\micromamba
micromamba shell init -s cmd.exe -r $env:USERPROFILE\micromamba
```
> 📝 **What each does:**
> - `powershell` — modifies PowerShell 7 and 5.1 profile scripts
> - `bash` — modifies `~/.bash_profile` (used by Git Bash)
> - `cmd.exe` — adds a CMD AutoRun hook via the Windows registry (`HKCU\Software\Microsoft\Command Processor\AutoRun`)
>
> ⚠️ **Claude Code note:** The `cmd.exe` init is sensitive to the working directory — micromamba may treat the `-r` root prefix as a relative path and produce a mangled `AutoRun` value. After running, verify the registry value is correct:
> ```powershell
> Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Command Processor' -Name AutoRun | Select-Object -ExpandProperty AutoRun
> ```
> The `mamba_hook.bat` path should point to `C:\Users\<user>\micromamba\condabin\mamba_hook.bat`.
>
> ⚠️ **Manual step:** Close and reopen your terminal after running these. If you get an execution policy error, run this first:
> ```powershell
> Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

### macOS

#### 1a. Install Micromamba
```zsh
brew install micromamba
```

> 📝 **Note:** Homebrew handles the binary placement and PATH. No manual copy or PATH workaround is needed on macOS.

#### 1b. Initialize micromamba shell hooks for all shells (macOS)
```zsh
micromamba shell init -s zsh -r ~/micromamba
micromamba shell init -s bash -r ~/micromamba
```
> 📝 **What each does:**
> - `zsh` — modifies `~/.zshrc`
> - `bash` — modifies `~/.bash_profile` or `~/.bashrc`
>
> ⚠️ **Manual step:** Close and reopen your terminal after running these.

### Cross-platform

#### Verify
```sh
micromamba --version
```

---

## Section 2 — Restore Environments

> 📝 **Note:** Skip this section on a fresh machine with no previous environments to restore.

If you backed up environments in Section 0, restore them into micromamba's envs directory:

### Windows
```powershell
# Copy each environment (not base) into micromamba's envs directory
Copy-Item -Recurse "$env:USERPROFILE\envs-backup\*" "$env:USERPROFILE\micromamba\envs\"
```

### macOS
```zsh
cp -r ~/envs-backup/* ~/micromamba/envs/
```

> ⚠️ **Claude Code note:** Restored environments must contain a `conda-meta` directory to be recognized by micromamba. If an environment shows files but `micromamba env list` doesn't list it, delete and recreate it (see Section 3).

After restoring, verify:
```sh
micromamba env list
```

Clean up the backup once verified:
```sh
# Windows
Remove-Item -Recurse -Force "$env:USERPROFILE\envs-backup"

# macOS
rm -rf ~/envs-backup
```

---

## Section 3 — Create Environment: node1

Creates a new environment named `node1` with all required packages from conda-forge.

### 3a. Create the environment
```sh
micromamba create -n node1 -c conda-forge nodejs python gh -y
```

> 📝 **Package notes:**
> - `nodejs` — installs Node.js and npm
> - `python` — latest stable Python
> - `gh` — GitHub CLI
> - `git` is intentionally omitted — Git should be installed system-wide and available everywhere, including inside this environment

### 3b. Activate and verify
```sh
micromamba activate node1
node --version
python --version
git --version
gh --version
```

---

## Section 4 — Verify Shell Integration

> 🤔 **Claude Code: Always run this verification and show the results to the user as a summary table.**
>
> 📝 **macOS shortcut:** Run `scripts/mac/verify-shell-integration.sh` to automate all checks below and produce the summary table.

Test that `micromamba activate` works in every shell. Check that the command is recognized (not just that the binary is on PATH — the shell hook must be functional).

### Windows

| Shell | Test command | What to check |
|---|---|---|
| PowerShell 7 | `pwsh -NoProfile -Command "micromamba activate base"` | Command succeeds without error |
| PowerShell 5.1 | `powershell -NoProfile -Command "micromamba activate base"` | Command succeeds without error |
| CMD | Open CMD → run `micromamba activate base` | Command succeeds without error |
| Git Bash | Open Git Bash → run `micromamba activate base` | Command succeeds without error |

### macOS

| Shell | Test command | What to check |
|---|---|---|
| zsh | `zsh -i -c "micromamba activate base && echo 'works'"` | Command succeeds without error |
| bash | `bash -l -i -c "micromamba activate base && echo 'works'"` | Command succeeds without error |

> ⚠️ **Claude Code note:** Shell hooks only load in interactive shells. Use `zsh -i` (not `zsh -l`) for zsh. For bash on macOS, use `bash -l -i` — the `-l` is needed because micromamba init blocks are in `~/.bash_profile` (login shell), and `-i` is needed for the hooks to activate. Terminal.app and iTerm2 open login shells by default, so this matches real-world usage.

Present results to the user in this format:

**Windows:**
```
| Shell          | micromamba activate |
|----------------|---------------------|
| PowerShell 7   | works / broken      |
| PowerShell 5.1 | works / broken      |
| CMD            | works / broken      |
| Git Bash       | works / broken      |
```

**macOS:**
```
| Shell | micromamba activate |
|-------|---------------------|
| zsh   | works / broken      |
| bash  | works / broken      |
```

> 📝 **Note:** Some shells may require closing and reopening after init. If a shell fails, re-run the relevant init command from Section 1 and retest.

---

## Notes & Known Issues

### Windows

| Issue | Fix |
|---|---|
| User PATH entries ignored by CMD | Check that `HKCU\Environment\Path` registry value type is `REG_EXPAND_SZ`, not `REG_SZ` (see Section 1b) |
| `micromamba shell init -s cmd.exe` produces mangled path | Run it from PowerShell, not Git Bash. Verify the AutoRun registry value afterward (see Section 1c) |
| Execution policy blocks micromamba install | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| CMD AutoRun conflict when both conda and micromamba are installed | Both `conda_hook.bat` and `mamba_hook.bat` use `IF DEFINED CONDA_SHLVL GOTO :EOF` — whichever runs second silently exits. This is why the runbook removes conda first (Section 0) |

### macOS

| Issue | Fix |
|---|---|
| `micromamba` not found after brew install | Run `micromamba shell init -s zsh -r ~/micromamba`, then open a new terminal |
| Shell init modifies wrong file | Ensure you're running init for the correct shell (`zsh` for macOS default, not `bash`) |
| Migrating from standalone micromamba to brew | Install via brew, re-run `micromamba shell init` to update `MAMBA_EXE` path in `.zshrc`/`.bash_profile`, then remove the old binary (e.g., `~/.local/bin/micromamba`). The `~/micromamba` root prefix and existing environments are preserved. |

### Cross-platform

| Issue | Fix |
|---|---|
| `gh` auth needed after install | Run `gh auth login` manually |

---

## Status Tracker

> Claude Code: Reset these checkboxes before starting a new run. Check them off as each step completes.

### Windows
- [ ] Conda removed (if previously installed)
- [ ] Environments backed up (if migrating from conda)
- [ ] Conda shell hooks and PATH entries cleaned up
- [ ] Micromamba installed
- [ ] PATH registry type verified (`REG_EXPAND_SZ`)
- [ ] Micromamba shell init completed (powershell, bash, cmd.exe)
- [ ] Micromamba CMD AutoRun path verified
- [ ] Micromamba verified (`micromamba --version`)
- [ ] Environments restored (if migrating from conda)
- [ ] Shell integration verified across all shells (table shown to user)
- [ ] Environment `node1` created
- [ ] node verified in node1
- [ ] python verified in node1
- [ ] gh verified in node1

### macOS
- [ ] Conda removed (if previously installed)
- [ ] Environments backed up (if migrating from conda)
- [ ] Conda shell hooks cleaned up
- [ ] Micromamba installed via Homebrew
- [ ] Micromamba shell init completed (zsh, bash)
- [ ] Micromamba verified (`micromamba --version`)
- [ ] Environments restored (if migrating from conda)
- [ ] Shell integration verified across all shells (table shown to user)
- [ ] Environment `node1` created
- [ ] node verified in node1
- [ ] python verified in node1
- [ ] gh verified in node1
