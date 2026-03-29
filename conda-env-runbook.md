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
>
> ⚠️ **Claude Code note:** **Check where `micromamba.exe` lives before removing conda.** If micromamba was installed while conda was present, the binary may live inside `miniconda3\Scripts\` rather than the canonical `AppData\Local\micromamba\`. Removing conda in this case deletes the micromamba binary, breaking the `.bat` wrapper and all shell hooks that reference `MAMBA_EXE`. The `remove-conda.ps1` script detects this and reinstalls micromamba to the canonical location automatically, but if running manual steps, reinstall micromamba first.

### Windows

> 📝 **Script available:** Run `scripts/windows/remove-conda.ps1` to automate all Windows steps below (backup, uninstall, cleanup, verification) in one shot:
> ```bash
> powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/remove-conda.ps1
> ```

<details>
<summary>Manual steps (if not using the script)</summary>

#### 0a. Back up existing environments
```powershell
conda env list
Copy-Item -Recurse "$env:USERPROFILE\miniconda3\envs" "$env:USERPROFILE\envs-backup"
```

#### 0b. Uninstall Miniconda
```powershell
winget uninstall --id Anaconda.Miniconda3
```

#### 0c. Clean up remaining files
```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\miniconda3" -ErrorAction SilentlyContinue
```

#### 0d. Clean up shell hooks and PATH
```powershell
$key = Get-Item 'HKCU:\Environment'
$val = $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
$parts = $val -split ';' | Where-Object { $_ -ne '' -and $_ -notmatch 'miniconda3' }
$newPath = $parts -join ';'
Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value $newPath -Type ExpandString
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Command Processor' -Name AutoRun -ErrorAction SilentlyContinue
Remove-Item "$env:USERPROFILE\.condarc" -ErrorAction SilentlyContinue
```

Remove the conda init block from `~/.bash_profile` and clear the PowerShell profile of conda hooks.

#### 0e. Verify removal
```powershell
conda --version   # should fail: not recognized
```

</details>

### macOS

> 📝 **Script available:** Run `scripts/mac/remove-conda.sh` to automate all macOS steps below (backup, uninstall, cleanup, verification) in one shot:
> ```bash
> bash scripts/mac/remove-conda.sh
> ```

<details>
<summary>Manual steps (if not using the script)</summary>

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

</details>

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

#### 1b. Fix PATH registry and initialize shell hooks

> 📝 **Scripts available:** Run these two scripts to handle PATH fixes, shell init, and verification:
> ```bash
> powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/fix-path-registry.ps1
> powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/micromamba-shell-init.ps1
> ```
>
> ⚠️ **Manual step:** Close and reopen your terminal after running these. If you get an execution policy error, run this first:
> ```powershell
> Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

<details>
<summary>What the scripts do</summary>

**fix-path-registry.ps1:**
- Checks that `HKCU\Environment\Path` is `REG_EXPAND_SZ` (not `REG_SZ`), fixes if wrong
- Removes stale miniconda3 entries from PATH
- Ensures micromamba's `AppData\Local\micromamba` directory is on PATH

**micromamba-shell-init.ps1:**
- Runs `micromamba shell init` for powershell, bash, and cmd.exe with root prefix `$env:USERPROFILE\micromamba`
- Verifies the CMD AutoRun registry value points to `mamba_hook.bat`
- Verifies `.bash_profile` and PowerShell profile contain micromamba hooks

> ⚠️ **Claude Code note:** The `cmd.exe` init is sensitive to the working directory — micromamba may treat the `-r` root prefix as a relative path and produce a mangled `AutoRun` value. The script runs from PowerShell (not Git Bash) to avoid this, and verifies the result.

</details>

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

Test that `micromamba activate` works in every shell. Check that the command is recognized (not just that the binary is on PATH — the shell hook must be functional).

### Windows

> 📝 **Script available:**
> ```bash
> powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/verify-shell-integration.ps1
> ```
> Tests PowerShell 5.1, PowerShell 7 (if installed), Git Bash, and CMD automatically.

| Shell | Test command | What to check |
|---|---|---|
| PowerShell 7 | `pwsh -NoProfile -Command "micromamba activate base"` | Command succeeds without error |
| PowerShell 5.1 | `powershell -NoProfile -Command "micromamba activate base"` | Command succeeds without error |
| CMD | Open CMD → run `micromamba activate base` | Command succeeds without error |
| Git Bash | Open Git Bash → run `micromamba activate base` | Command succeeds without error |

### macOS

> 📝 **Script available:** Run `scripts/mac/verify-shell-integration.sh` to automate all checks below.

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
| Removing conda deletes micromamba binary | If `micromamba.exe` lives inside `miniconda3\Scripts\` (not the canonical `AppData\Local\micromamba\`), uninstalling conda removes it. `remove-conda.ps1` now detects this and reinstalls to the canonical location first. If manual, reinstall micromamba before removing conda. |
| PS7 profile has stale MAMBA_EXE after shell init | `micromamba shell init -s powershell` only writes the PS 5.1 profile. `micromamba-shell-init.ps1` now always syncs the PS7 profile block (replacing, not just checking for presence) and validates the MAMBA_EXE path matches the actual binary. |

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

> ⚠️ **Claude Code note:** Do NOT track status in this file — it lives in git and is shared across machines. Instead, create/update a local checklist at `~/Documents/runbook-status/conda-env-runbook.md`. At the start of each run:
> 1. Create the directory and file if they don't exist (use the template below for the current platform).
> 2. Reset all checkboxes to `[ ]`.
> 3. Check off items as each step completes.

<details>
<summary>Windows checklist template</summary>

```markdown
# conda-env-runbook status — Windows

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
```

</details>

<details>
<summary>macOS checklist template</summary>

```markdown
# conda-env-runbook status — macOS

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
```

</details>
