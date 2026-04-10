# Environment Setup Runbook

> **How to use this with Claude Code:** Open Claude Code in your terminal, point it at this file, and say: *"Follow the environment runbook at conda-env-runbook.md. Walk me through each section, automate what you can, and tell me when I need to do something manually."*
>
> **Platform policy:**
>
> | Platform | Environment manager | Why |
> |---|---|---|
> | Windows | **micromamba** | Standard. Fast, single binary, works reliably. |
> | macOS | **miniconda** | micromamba's `libmamba::codesign()` fails with `Could not codesign executable: Invalid argument` during the linking phase on macOS 26 due to a `reproc::env::empty` bug. Confirmed broken on macOS 26.3.1 and 26.4. Not fixed upstream. See [macos_micromamba_debug_runbook.md](macos_micromamba_debug_runbook.md) Section 15 for the full root-cause writeup. |
>
> **Prerequisites (Windows):** see [setup-runbook-windows.md](setup-runbook-windows.md).
> - **Git for Windows** — provides `git` CLI and Git Credential Manager
> - **winget** — ships with Windows 11; on Windows 10, install via Microsoft Store
>
> **Prerequisites (macOS):** see [setup-runbook-mac.md](setup-runbook-mac.md).
> - **Homebrew** — used to install Miniconda
> - **Git** — install via Homebrew (recommended) or use Apple Git from Xcode CLI tools
>
> 📝 **Quick check (macOS):** Run `scripts/mac/verify-prerequisites.sh` to check what's already installed before starting.

---

## Section 0 — Remove the wrong env manager (if present)

Each platform has a standard env manager (Windows: micromamba, macOS: miniconda). Before installing the correct one, remove the *other* one if it's somehow present — keeping both causes shell hook conflicts and confusion.

### Windows — Remove Conda (if installed)

> ⚠️ **Claude Code note:** If Miniconda/Anaconda is already installed, remove it before proceeding. Keeping both conda and micromamba causes CMD shell hook conflicts — both `conda_hook.bat` and `mamba_hook.bat` use an `IF DEFINED CONDA_SHLVL GOTO :EOF` guard, so whichever loads second in the CMD AutoRun chain silently fails.
>
> ⚠️ **Claude Code note:** **Check where `micromamba.exe` lives before removing conda.** If micromamba was installed while conda was present, the binary may live inside `miniconda3\Scripts\` rather than the canonical `AppData\Local\micromamba\`. Removing conda in this case deletes the micromamba binary, breaking the `.bat` wrapper and all shell hooks that reference `MAMBA_EXE`. The `remove-conda.ps1` script detects this and reinstalls micromamba to the canonical location automatically, but if running manual steps, reinstall micromamba first.

#### Windows details

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

### macOS — Remove Micromamba (if installed)

> 📝 **Script available:** Run `scripts/mac/remove-micromamba.sh` to automate all macOS steps below (brew uninstall, standalone binary removal, root prefix cleanup, shell hook removal, verification) in one shot:
> ```bash
> bash scripts/mac/remove-micromamba.sh
> ```
>
> The script is idempotent — safe to run on a machine that has never had micromamba.

<details>
<summary>Manual steps (if not using the script)</summary>

#### 0a. Uninstall via brew (if brew-managed)
```zsh
brew uninstall micromamba
```

#### 0b. Remove standalone binary (if present)
```zsh
rm -f ~/.local/bin/micromamba
```

#### 0c. Remove the root prefix and any envs inside it
```zsh
rm -rf ~/micromamba
```

#### 0d. Clean up shell hooks
Remove the `# >>> mamba initialize >>>` block from `~/.zshrc` and `~/.bash_profile`. Conda shell init (Section 1 macOS) will write fresh conda hooks.

</details>

---

## Section 1 — Install the environment manager

### Windows — Micromamba

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
- Repairs entries with missing semicolons (e.g. external installers that concatenate entries)
- Ensures micromamba's `AppData\Local\micromamba` directory is on PATH

**micromamba-shell-init.ps1:**
- Runs `micromamba shell init` for powershell and cmd.exe with root prefix `$env:USERPROFILE\micromamba`
- Verifies the CMD AutoRun registry value points to `mamba_hook.bat`
- Verifies PowerShell profile contains micromamba hooks

> ⚠️ **Claude Code note:** The `cmd.exe` init is sensitive to the working directory — micromamba may treat the `-r` root prefix as a relative path and produce a mangled `AutoRun` value. The script runs from PowerShell to avoid this, and verifies the result.
>
> 📝 **Note:** Git Bash is no longer a supported shell on Windows. `micromamba shell init -s bash` is not run. See `docs/FUTURES.md` for rationale.

</details>

### macOS — Miniconda

> ⚠️ **Claude Code note:** macOS does not install micromamba. See the Platform policy table in the header for why.

#### 1a. Install Miniconda via Homebrew
```zsh
brew install --cask miniconda
```

> 📝 **Note:** `brew install --cask miniconda` installs into `/opt/homebrew/Caskroom/miniconda/base/` on Apple Silicon (`/usr/local/Caskroom/...` on Intel) and symlinks `/opt/homebrew/bin/conda`. No manual PATH workaround is needed.

#### 1b. Initialize conda shell hooks for zsh and bash
```zsh
/opt/homebrew/Caskroom/miniconda/base/bin/conda init zsh bash
```

> 📝 **What this does:** Adds a `# >>> conda initialize >>>` block to `~/.zshrc` and `~/.bash_profile`.
>
> ⚠️ **Manual step:** Close and reopen your terminal after running this.

#### 1c. Configure conda-forge only (avoid Anaconda ToS prompt)

Modern conda requires accepting Anaconda's Terms of Service for the default channels (`repo.anaconda.com/pkgs/main`, `pkgs/r`). This repo only uses conda-forge, so remove defaults entirely and set strict channel priority:

```zsh
conda config --remove-key channels 2>/dev/null; \
conda config --add channels conda-forge && \
conda config --set channel_priority strict
```

> 📝 **Note:** `scripts/mac/create-env.sh` also applies this config on every run, so it's idempotent.

#### 1d. Verify
```zsh
conda --version
```

### Cross-platform (Windows only)

On Windows, verify the micromamba install:
```sh
micromamba --version
```

---

## Section 2 — Restore Environments

> 📝 **Note:** Skip this section on a fresh machine with no previous environments to restore.

### Windows

If you backed up environments in Section 0 (Windows side), restore them into micromamba's envs directory:

```powershell
# Copy each environment (not base) into micromamba's envs directory
Copy-Item -Recurse "$env:USERPROFILE\envs-backup\*" "$env:USERPROFILE\micromamba\envs\"
```

> ⚠️ **Claude Code note:** Restored environments must contain a `conda-meta` directory to be recognized by micromamba. If an environment shows files but `micromamba env list` doesn't list it, delete and recreate it (see Section 3).

After restoring, verify:
```powershell
micromamba env list
```

Clean up the backup once verified:
```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\envs-backup"
```

### macOS

> ⚠️ **Claude Code note:** Do not bulk-copy micromamba envs from `~/micromamba/envs/` into conda's envs directory. Conda and micromamba write compatible `conda-meta/` contents *most of the time*, but the env's internal paths are hardcoded into activation scripts and many dylibs — moving the directory breaks them. **On macOS, recreate environments from scratch with Section 3** rather than restoring. If you want repeatable recreation, export the spec first and re-use it: `micromamba env export -n <name> > <name>.yml` (on the old machine, before `remove-micromamba.sh`), then `bash scripts/mac/create-env.sh --name <name> --spec-file <name>.yml` on the new setup.

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
> The script locates conda, ensures conda-forge is the only channel with strict priority, checks if the environment already exists (skips if so), creates it with `--override-channels -c conda-forge`, and verifies all packages. Use `--recreate` to replace an existing environment. Supports `--spec-file` for YAML spec files.

<details>
<summary>Manual steps (if not using the script)</summary>

```zsh
# One-time channel config (also done by create-env.sh)
conda config --remove-key channels 2>/dev/null
conda config --add channels conda-forge
conda config --set channel_priority strict

# Create the env, forcing conda-forge only
conda create -n node1 --override-channels -c conda-forge nodejs python gh -y

# Verify
conda activate node1
node --version
python --version
gh --version
```

</details>

---

## Section 4 — Verify Shell Integration

> 🤔 **Claude Code: Always run this verification and show the results to the user as a summary table.**

Test that the env manager's `activate` command works in every shell. Check that the command is recognized (not just that the binary is on PATH — the shell hook must be functional). Windows tests `micromamba activate`, macOS tests `conda activate`.

### Windows

> 📝 **Script available:**
> ```bash
> powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/verify-shell-integration.ps1
> ```
> Tests PowerShell 5.1, PowerShell 7 (if installed), and CMD automatically.

| Shell | Test command | What to check |
|---|---|---|
| PowerShell 7 | `pwsh -NoProfile -Command "micromamba activate base"` | Command succeeds without error |
| PowerShell 5.1 | `powershell -NoProfile -Command "micromamba activate base"` | Command succeeds without error |
| CMD | Open CMD → run `micromamba activate base` | Command succeeds without error |

### macOS

> 📝 **Script available:** Run `scripts/mac/verify-shell-integration.sh` to automate all checks below.

| Shell | Test command | What to check |
|---|---|---|
| zsh | `zsh -i -c "conda activate base && echo 'works'"` | Command succeeds without error |
| bash | `bash -l -i -c "conda activate base && echo 'works'"` | Command succeeds without error |

> ⚠️ **Claude Code note:** Shell hooks only load in interactive shells. Use `zsh -i` (not `zsh -l`) for zsh. For bash on macOS, use `bash -l -i` — the `-l` is needed because conda init blocks are in `~/.bash_profile` (login shell), and `-i` is needed for the hooks to activate. Terminal.app and iTerm2 open login shells by default, so this matches real-world usage.

Present results to the user in this format:

**Windows:**
```
| Shell          | micromamba activate |
|----------------|---------------------|
| PowerShell 7   | works / broken      |
| PowerShell 5.1 | works / broken      |
| CMD            | works / broken      |
```

**macOS:**
```
| Shell | conda activate |
|-------|----------------|
| zsh   | works / broken |
| bash  | works / broken |
```

> 📝 **Note:** Some shells may require closing and reopening after init. If a shell fails, re-run the relevant init command from Section 1 and retest.

---

## Notes & Known Issues

### Windows

| Issue | Fix |
|---|---|
| User PATH entries ignored by CMD | Check that `HKCU\Environment\Path` registry value type is `REG_EXPAND_SZ`, not `REG_SZ` (see Section 1b) |
| Missing semicolons in PATH after micromamba install | The micromamba installer may concatenate PATH entries without a semicolon separator. `fix-path-registry.ps1` step 2b detects and repairs these. |
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
| Why does macOS use miniconda instead of micromamba? | libmamba 2.5.0's `codesign()` fork/execs `/usr/bin/codesign` via `reproc::run()` with `reproc::env::empty`. On macOS 26, reproc returns `EINVAL` from that spawn even though `codesign` actually runs and correctly ad-hoc signs the file. libmamba checks reproc's `ec` rather than codesign's exit code and throws `Could not codesign executable: Invalid argument`, aborting the install. Confirmed broken on 26.3.1 and 26.4; not fixed on libmamba `main`. Full root-cause writeup and reproducer: [macos_micromamba_debug_runbook.md](macos_micromamba_debug_runbook.md) Section 15. |
| Is the macOS libmamba bug still broken? | Re-run `macos_micromamba_debug_runbook.md` Section 7 on any macOS machine after a `brew upgrade micromamba` or a macOS point release. If it now succeeds, the upstream bug is likely fixed and macOS can return to micromamba. |
| `conda create` complains about Anaconda ToS | Conda now prompts to accept Terms of Service for `repo.anaconda.com/pkgs/main` and `pkgs/r`. This repo only uses conda-forge; Section 1c configures conda to drop defaults entirely, and `scripts/mac/create-env.sh` re-applies that config on every run and passes `--override-channels` to force conda-forge only. |
| Conda init modifies `~/.zshrc` and `~/.bash_profile` | Expected. `conda init zsh bash` writes `# >>> conda initialize >>>` blocks to both. `scripts/mac/remove-micromamba.sh` correctly removes the *mamba* block without touching the conda block. |

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
- [ ] Micromamba shell init completed (powershell, cmd.exe)
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

- [ ] Micromamba removed (if previously installed) — `scripts/mac/remove-micromamba.sh`
- [ ] `# >>> mamba initialize >>>` blocks gone from .zshrc and .bash_profile
- [ ] Miniconda installed via `brew install --cask miniconda`
- [ ] Conda shell init completed (`conda init zsh bash`)
- [ ] conda-forge set as only channel with strict priority (Section 1c)
- [ ] Conda verified (`conda --version`)
- [ ] Shell integration verified across zsh and bash (table shown to user)
- [ ] Environment `node1` created via `scripts/mac/create-env.sh`
- [ ] node verified in node1
- [ ] python verified in node1
- [ ] gh verified in node1
```

</details>
