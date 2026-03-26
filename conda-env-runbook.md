# Conda & Micromamba Environment Setup Runbook

> **How to use this with Claude Code:** Open Claude Code in your terminal, point it at this file, and say: *"Follow the conda environment runbook at conda-env-runbook.md. Walk me through each section, automate what you can, and tell me when I need to do something manually."*
>
> **Prerequisites (Windows):** The following should already be installed. If not, see [setup-runbook-windows.md](setup-runbook-windows.md).
> - **PowerShell 7** (`pwsh`) — needed to run install commands and shell init
> - **Git for Windows** — provides Git Bash, needed for bash shell init
> - **winget** — used to install Miniconda (ships with Windows 11; on Windows 10, install via Microsoft Store)
>
> **Prerequisites (macOS):** The following should already be installed. If not, see [setup-runbook-mac.md](setup-runbook-mac.md).
> - **Homebrew** — used to install Miniconda and Micromamba
> - **Git** — ships with macOS (Xcode CLI tools) or install via brew

---

## Section 1 — Miniconda

**Method:** Winget (preferred) or direct download fallback.

### 1a. Install via Winget
```powershell
winget install -e --id Anaconda.Miniconda3 --silent
```

### 1b. Fallback — Direct Download
- Installer URL: https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe
- Download and run silently:
```powershell
$url = "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"
$dest = "$env:TEMP\MinicondaInstaller.exe"
Invoke-WebRequest -Uri $url -OutFile $dest
Start-Process -FilePath $dest -Args "/S /AddToPath=1 /RegisterPython=1" -Wait
```

### 1c. Add to PATH
> ⚠️ **Claude Code note:** The winget/silent installer does **not** reliably add conda to PATH. After install, verify the binary exists at `%USERPROFILE%\miniconda3\Scripts\conda.exe`, then ensure these three directories are on the **user** PATH:
> - `%USERPROFILE%\miniconda3`
> - `%USERPROFILE%\miniconda3\Scripts`
> - `%USERPROFILE%\miniconda3\condabin`
>
> Also verify the user `Path` registry key (`HKCU\Environment\Path`) is stored as `REG_EXPAND_SZ`, not `REG_SZ`. If it's `REG_SZ`, CMD will silently ignore the user PATH entries. Fix with:
> ```powershell
> $key = Get-Item 'HKCU:\Environment'
> $val = $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
> Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value $val -Type ExpandString
> ```

### 1d. Accept Terms of Service
> ⚠️ **Claude Code note:** Fresh installs of conda require accepting ToS for the default Anaconda channels before any environment can be created. Ask the user for permission, then run:
```powershell
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/msys2
```

### 1e. Initialize conda for all shells
Initialize conda shell hooks so `conda activate` works in every shell type. Each command modifies the relevant profile/config for that shell.
```powershell
conda init powershell
conda init bash
conda init cmd.exe
```
> 📝 **What each does:**
> - `powershell` — modifies PowerShell 7 and 5.1 profile scripts
> - `bash` — modifies `~/.bash_profile` (used by Git Bash)
> - `cmd.exe` — adds a CMD AutoRun hook via the Windows registry (`HKCU\Software\Microsoft\Command Processor\AutoRun`)
>
> ⚠️ **Manual step:** Close and reopen your terminal after running these. If you get an execution policy error, run this first:
> ```powershell
> Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

### 1f. Verify
```powershell
conda --version
```

---

## Section 2 — Micromamba

**Method:** PowerShell install script from the official source.

### 2a. Install Micromamba
```powershell
Invoke-Expression ((Invoke-WebRequest -Uri https://micro.mamba.pm/install.ps1 -UseBasicParsing).Content)
```
> ⚠️ **Manual step:** If you get an execution policy error, run this first, then retry:
> ```powershell
> Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

### 2b. Copy binary to a reliable PATH location
> ⚠️ **Claude Code note:** The micromamba installer places the binary in `%USERPROFILE%\AppData\Local\micromamba\` and adds that directory to the user PATH. However, CMD may fail to find the binary at that location even when the PATH entry is correct (likely a Windows filesystem quirk). **Workaround:** copy `micromamba.exe` into `%USERPROFILE%\miniconda3\Scripts\` which is already on PATH and known to work reliably from all shells.
> ```powershell
> Copy-Item "$env:USERPROFILE\AppData\Local\micromamba\micromamba.exe" "$env:USERPROFILE\miniconda3\Scripts\micromamba.exe"
> ```

### 2c. Initialize micromamba shell hooks for all shells
For consistency with conda, initialize micromamba's shell integration for every shell type:
```powershell
micromamba shell init -s powershell -r $env:USERPROFILE\micromamba
micromamba shell init -s bash -r $env:USERPROFILE\micromamba
micromamba shell init -s cmd.exe -r $env:USERPROFILE\micromamba
```
> 📝 **What each does:**
> - `powershell` — modifies PowerShell 7 and 5.1 profile scripts
> - `bash` — modifies `~/.bash_profile` (used by Git Bash)
> - `cmd.exe` — adds to the CMD AutoRun hook via the Windows registry
>
> ⚠️ **Claude Code note:** The `cmd.exe` init is sensitive to the working directory — micromamba may treat the `-r` root prefix as a relative path and produce a mangled `AutoRun` value. **Always run the `cmd.exe` init from PowerShell** (not from Git Bash) to ensure correct path handling. After running, verify the registry value is correct:
> ```powershell
> Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Command Processor' -Name AutoRun | Select-Object -ExpandProperty AutoRun
> ```
> The `mamba_hook.bat` path should point to `C:\Users\<user>\micromamba\condabin\mamba_hook.bat`.

### 2d. Prevent double `(base)` prompt
Both conda and micromamba will auto-activate their `(base)` environment on shell startup, resulting in a double `(base) (base)` prompt. Disable auto-activate on one of them:
```powershell
# If you prefer micromamba as your primary tool:
conda config --set auto_activate_base false

# If you prefer conda as your primary tool:
micromamba config set auto_activate_base false
```
> 🤔 **Claude Code: Ask the user which they prefer** before choosing which to disable.

### 2e. Verify
```powershell
micromamba --version
```

---

## Section 3 — Verify Shell Integration

> 🤔 **Claude Code: Always run this verification and show the results to the user as a summary table.**

Test that `conda activate` and `micromamba activate` work in every shell. For each shell, check that the command is recognized (not just that the binary is on PATH — the shell hook must be functional).

| Shell | Test command | What to check |
|---|---|---|
| PowerShell 7 | `pwsh -NoProfile -Command "conda activate base; micromamba activate base"` | Both commands succeed without error |
| PowerShell 5.1 | `powershell -NoProfile -Command "conda activate base; micromamba activate base"` | Both commands succeed without error |
| CMD | Open CMD → run `conda activate base` then `micromamba activate base` | Both commands succeed without error |
| Git Bash | Open Git Bash → run `conda activate base` then `micromamba activate base` | Both commands succeed without error |

Present results to the user in this format:

```
| Shell          | conda activate | micromamba activate |
|----------------|----------------|---------------------|
| PowerShell 7   | works / broken | works / broken      |
| PowerShell 5.1 | works / broken | works / broken      |
| CMD            | works / broken | works / broken      |
| Git Bash       | works / broken | works / broken      |
```

> 📝 **Note:** Some shells may require closing and reopening after init. If a shell fails, re-run the relevant init command from Sections 1e/2c and retest.

---

## Section 4 — Create Environment: node1

Creates a new conda environment named `node1` with all required packages from conda-forge.

### 4a. Create the environment
```powershell
conda create -n node1 -c conda-forge nodejs python gh -y
```

> 📝 **Package notes:**
> - `nodejs` — installs Node.js and npm
> - `python` — latest stable Python
> - `gh` — GitHub CLI
> - `git` is intentionally omitted — Git for Windows should be installed system-wide and available everywhere, including inside this environment

### 4b. Activate and verify
```powershell
conda activate node1
node --version
python --version
git --version
gh --version
```

### 4c. (Optional) Activate via micromamba
```powershell
micromamba activate node1
```

---

## Notes & Known Issues

| Issue | Fix |
|---|---|
| `conda` not found after install | Restart terminal or re-run `conda init powershell`. Also check that miniconda3 paths are on user PATH (see Section 1c) |
| User PATH entries ignored by CMD | Check that `HKCU\Environment\Path` registry value type is `REG_EXPAND_SZ`, not `REG_SZ` (see Section 1c) |
| `micromamba` not found after install | Copy binary to `miniconda3\Scripts\` (see Section 2b) |
| Double `(base)` prompt | Disable auto_activate_base on one of conda/micromamba (see Section 2d) |
| Conda ToS blocks environment creation | Accept ToS for default channels (see Section 1d) |
| Execution policy blocks micromamba install | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| `gh` auth needed after install | Run `gh auth login` manually |
| conda-forge packages slow to resolve | Add `--solver=libmamba` flag or use micromamba instead |
| `micromamba shell init -s cmd.exe` produces mangled path | Run it from PowerShell, not Git Bash. Verify the AutoRun registry value afterward (see Section 2c) |

---

## Status Tracker
> Claude Code: Reset these checkboxes before starting a new run. Check them off as each step completes.

- [ ] Miniconda installed
- [ ] Miniconda PATH verified (three directories + REG_EXPAND_SZ check)
- [ ] Conda ToS accepted
- [ ] conda initialized for PowerShell (`conda init powershell`)
- [ ] conda initialized for Git Bash (`conda init bash`)
- [ ] conda initialized for CMD (`conda init cmd.exe`)
- [ ] Miniconda verified (`conda --version`)
- [ ] Micromamba installed
- [ ] Micromamba binary copied to miniconda3\Scripts
- [ ] Micromamba shell init completed (powershell, bash, cmd.exe)
- [ ] Micromamba CMD AutoRun path verified
- [ ] Double (base) prompt resolved
- [ ] Micromamba verified (`micromamba --version`)
- [ ] Shell integration verified across all shells (table shown to user)
- [ ] Environment `node1` created
- [ ] node verified in node1
- [ ] python verified in node1
- [ ] gh verified in node1
