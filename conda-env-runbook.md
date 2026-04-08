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

> 📝 **Package notes:**
> - `nodejs` — installs Node.js and npm
> - `python` — latest stable Python
> - `gh` — GitHub CLI
> - `git` is intentionally omitted — Git should be installed system-wide and available everywhere, including inside this environment

### Windows

> 📝 **Script available:**
> ```bash
> powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/create-env.ps1 -Name node1 -Packages nodejs,python,gh
> ```
> The script checks if the environment already exists (skips if so), creates it, and verifies all packages. Use `-Recreate` to replace an existing environment. Supports `-SpecFile` for YAML spec files.

<details>
<summary>Manual steps (if not using the script)</summary>

```sh
micromamba create -n node1 -c conda-forge nodejs python gh -y
micromamba activate node1
node --version
python --version
gh --version
```

</details>

### macOS

> 📝 **Script available:**
> ```bash
> bash scripts/mac/create-env.sh --name node1 --packages nodejs,python,gh
> ```
> The script checks if the environment already exists (skips if so), creates it, and verifies all packages. Use `--recreate` to replace an existing environment. Supports `--spec-file` for YAML spec files.

<details>
<summary>Manual steps (if not using the script)</summary>

```sh
micromamba create -n node1 -c conda-forge nodejs python gh -y
micromamba activate node1
node --version
python --version
gh --version
```

</details>

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

## Section 5 — Exception: macOS libmamba fallback (conda)

> ⚠️ **This section is an EXCEPTION, not the standard path.**
>
> The standard setup on both Windows and macOS is **micromamba only** — conda is intentionally removed (see Section 0). Use this fallback **only** if `micromamba create` fails with the libmamba `Could not codesign executable: Invalid argument` bug on macOS 26.x (see Notes & Known Issues → macOS). Do not use this section on Windows, and do not use it on macOS unless the micromamba path has been verified broken on the specific machine.
>
> If you use this fallback, **document it as machine-specific in your Status Tracker**. Retry micromamba after each libmamba/macOS update — the goal is to return to the standard path when the upstream bug is fixed.

### 5a. Install Miniconda via Homebrew

```zsh
brew install --cask miniconda
```

### 5b. Remove conflicting micromamba shell init

Remove the `# >>> mamba initialize >>>` block from `~/.zshrc` and `~/.bash_profile`. Conda and micromamba hooks can coexist in principle, but since the micromamba path is known broken on this machine, keeping its hooks only causes confusion.

### 5c. Initialize conda shell hooks

```zsh
/opt/homebrew/Caskroom/miniconda/base/bin/conda init zsh bash
```

This adds a `# >>> conda initialize >>>` block to `~/.zshrc` and `~/.bash_profile`.

> ⚠️ **Manual step:** Close and reopen your terminal after running init.

### 5d. Configure conda-forge only (avoid Anaconda ToS prompt)

Modern conda requires accepting Anaconda's Terms of Service for the default channels (`repo.anaconda.com/pkgs/main`, `pkgs/r`). We only want conda-forge, so remove defaults entirely and set strict channel priority:

```zsh
conda config --remove-key channels 2>/dev/null; \
conda config --add channels conda-forge && \
conda config --set channel_priority strict
```

### 5e. Create the `node1` environment

Use `--override-channels` to force conda to ignore any stray defaults reference:

```zsh
conda create -n node1 --override-channels -c conda-forge nodejs python gh -y
```

### 5f. Verify

```zsh
conda activate node1
node --version
python --version
gh --version
```

### 5g. Shell integration check

| Shell | Test command | What to check |
|---|---|---|
| zsh  | `zsh -i -c "conda activate node1 && which node"`         | Prints a path under `/opt/homebrew/Caskroom/miniconda/base/envs/node1/bin` |
| bash | `bash -l -i -c "conda activate node1 && which node"`     | Same |

### 5h. Revisit micromamba periodically

After future libmamba releases (`brew upgrade micromamba`) or macOS updates, retry the standard path:

```zsh
brew install micromamba
micromamba shell init -s zsh -r ~/micromamba
# Reopen terminal
micromamba create -n node1-test -c conda-forge nodejs python gh -y
```

If it succeeds, you can migrate back to the standard path — uninstall miniconda, remove its shell init blocks, and update your Status Tracker to remove the exception flag.

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
| `micromamba-shell-init.ps1` fails to parse under PS5.1 | Em-dash characters in UTF-8 without BOM cause PS5.1 parse errors. Fixed: em-dashes replaced with ASCII, file saved with UTF-8 BOM. |
| `create-env.ps1` skips creation for ghost environments | When `micromamba env list` shows an environment but the directory doesn't exist, the script treated it as existing. Fixed: now verifies the prefix directory exists on disk before reporting the env as present. |
| `create-env.ps1` reports false WARNs for packages in existing envs | `micromamba list -n` failure was silently treated as empty output. Fixed: exit codes checked before parsing. |

### macOS

| Issue | Fix |
|---|---|
| `micromamba` not found after brew install | Run `micromamba shell init -s zsh -r ~/micromamba`, then open a new terminal |
| Shell init modifies wrong file | Ensure you're running init for the correct shell (`zsh` for macOS default, not `bash`) |
| Migrating from standalone micromamba to brew | Install via brew, re-run `micromamba shell init` to update `MAMBA_EXE` path in `.zshrc`/`.bash_profile`, then remove the old binary (e.g., `~/.local/bin/micromamba`). The `~/micromamba` root prefix and existing environments are preserved. |
| `critical libmamba Could not codesign executable: Invalid argument` during `micromamba create` (macOS 26.x / Tahoe) | **Machine-specific libmamba bug.** Reproduced on a clean macOS 26.4 install with CLT 26.4.0, micromamba 2.5.0 from brew and standalone 1.5.10. Fails on the first Mach-O binary during the linking phase; `codesign -s - --force` on the same file from the shell succeeds, so it is not the OS `codesign` tool. libmamba uses Security.framework's `com.apple.CodeSigningHelper.xpc` directly (not fork/exec of `codesign`), and that code path returns EINVAL. **Not fixed by:** updating macOS, updating CLT, `CONDA_OVERRIDE_OSX`, `CONDA_SOLVER=classic`, switching micromamba versions. Verified working on another Tahoe Mac — machine-specific, not OS-wide. **Workaround:** use the macOS conda fallback path (see Section 5 — Exception: macOS libmamba fallback). Pixi (`brew install pixi`) also works but is not currently part of the runbook. |

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

## If Section 5 exception path was used (libmamba codesign bug):
- [ ] EXCEPTION FLAG: this machine is on the conda fallback, not standard micromamba
- [ ] Miniconda installed via brew cask
- [ ] Micromamba shell init blocks removed from .zshrc and .bash_profile
- [ ] conda init zsh bash completed
- [ ] conda-forge set as only channel with strict priority
- [ ] `node1` created with `--override-channels -c conda-forge`
- [ ] Reminder: retry standard micromamba path after next `brew upgrade micromamba` or macOS update
```

</details>
