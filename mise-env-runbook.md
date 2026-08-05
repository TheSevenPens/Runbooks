# Tool Setup Runbook (mise)

> **How to use this with Claude Code:** Open Claude Code in your terminal, point it at this file, and say: *"Follow the tool setup runbook at mise-env-runbook.md. Walk me through each section, automate what you can, and tell me when I need to do something manually."*
>
> **What is mise?** [mise](https://mise.jdx.dev/) (formerly `rtx`) is a cross-platform tool version manager. It replaces the conda-family environment manager used in `conda-env-runbook.md`. One CLI, one config format, same behavior on every platform.
>
> **Why mise instead of conda/micromamba?** The runbooks only use conda-forge to install three tools (`nodejs`, `python`, `gh`) that are first-class in every mainstream package ecosystem. mise installs them directly without libmamba, shell hook complexity, channel config, or the per-platform manager split (micromamba on Windows, miniconda on macOS). See `docs/FUTURES.md` for the full rationale.
>
> **Prerequisites:**
> - **macOS:** Homebrew installed (see [mac-setup-runbook.md](mac-setup-runbook.md))
> - **Windows:** winget available (ships with Windows 11; on Windows 10, install via Microsoft Store)
>
> **Parallel runbook:** This runbook exists alongside `conda-env-runbook.md`. Both are valid; pick one when setting up a machine. If you previously used the conda runbook, see Section 0 for cleanup.

---

## Section 0 --- Remove conda-family tools (if present)

> 📝 **Note:** Skip this section on a fresh machine with no previous conda/micromamba install.

If this machine was previously set up with `conda-env-runbook.md`, remove the conda-family tools before proceeding. Keeping both mise and conda on PATH is technically harmless but confusing --- `which python` could resolve to either.

### macOS

**Remove miniconda:**
```bash
bash scripts/mac/remove-conda.sh
```

**Remove micromamba (if present from an older setup):**
```bash
bash scripts/mac/remove-micromamba.sh
```

### Windows

**Remove conda:**
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/remove-conda.ps1
```

**Remove micromamba:**
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/remove-micromamba.ps1
```

> ⚠️ **Manual step:** Close and reopen your terminal after removal to pick up the cleaned PATH.

---

## Sections 1-2 --- Install mise and activate in shells

### Windows (automated)

> 📝 **Note:** The script installs mise, configures PS7/PS5.1 profiles with activation lines, adds shims to PATH for CMD, and broadcasts WM_SETTINGCHANGE. It is idempotent --- already-configured items are skipped.

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/install-mise.ps1
```

> ⚠️ **Manual step:** Close and reopen your terminal after running so activation takes effect.

### macOS

```zsh
brew install mise
```

### Linux (Fedora)

```bash
dnf install mise
```

> 📝 **Note:** Alternative install method for any platform: `curl https://mise.run | sh`

### Verify

```sh
mise --version
```

---

## Section 2 --- Activate mise in your shell (manual alternative)

> 📝 **Note:** On Windows, `install-mise.ps1` handles all activation setup. This section is only needed if you want to configure activation manually, or on macOS/Linux.

mise needs a single activation line in your shell config. This makes mise manage your PATH so installed tools are available.

### macOS (zsh)

```zsh
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
```

> ⚠️ **Claude Code note:** Check if the line already exists before appending. Don't duplicate it.

### macOS (bash)

```bash
echo 'eval "$(mise activate bash)"' >> ~/.bash_profile
```

### Windows (PowerShell 7)

```powershell
# Add to your PowerShell 7 profile ($PROFILE in pwsh)
Add-Content $PROFILE 'mise activate pwsh | Out-String | Invoke-Expression'
```

> ⚠️ **Claude Code note:** If `$PROFILE` doesn't exist yet, create it first: `New-Item -ItemType File -Path $PROFILE -Force`

### Windows (PowerShell 5.1)

```powershell
# Add to the PS5.1 profile (run this from powershell.exe, not pwsh)
$ps5Profile = "$([Environment]::GetFolderPath('MyDocuments'))\WindowsPowerShell\profile.ps1"
if (-not (Test-Path (Split-Path $ps5Profile))) { New-Item -ItemType Directory -Path (Split-Path $ps5Profile) -Force | Out-Null }
Set-Content -Path $ps5Profile -Value 'mise activate pwsh | Out-String | Invoke-Expression' -Encoding UTF8
```

> 📝 **Note:** PS5.1 activation works but prints a harmless `chpwd` warning (auto-switch-on-cd requires PS7). Suppress with `$env:MISE_PWSH_CHPWD_WARNING=0` before the activate line if desired. Tool activation itself works fine.

### Windows (CMD) --- via shims

mise does not have native CMD activation. Instead, add the mise **shims** directory to the user PATH. Shims are lightweight wrapper executables that forward calls to the correct tool version.

```powershell
# Add shims to user PATH (run from any PowerShell)
$regKey = Get-Item 'HKCU:\Environment'
$pathValue = $regKey.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
$shimsEntry = '%LOCALAPPDATA%\mise\shims'
if (-not $pathValue.Contains('mise\shims')) {
    $newPath = $shimsEntry + ';' + $pathValue
    Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value $newPath -Type ExpandString
}
```

> 📝 **Note:** Shims and activation coexist. In PS7/PS5.1, activation takes priority (shims are on PATH but activation injects the real binaries first). In CMD, shims provide tool access. Run `mise reshim` after installing new tools to regenerate shims.

### ~~Windows (Git Bash)~~ --- Dropped

> 📝 **Note:** Git Bash is no longer a supported shell on Windows. `mise activate bash` is broken on Git Bash (it replaces PATH with Windows-style paths, destroying the shell). See `docs/FUTURES.md` "Drop Git Bash as a supported shell on Windows" for the full rationale.

### Verify activation

> ⚠️ **Manual step:** Close and reopen your terminal, then run:

```sh
mise doctor
```

> 📝 **Note:** `mise doctor` checks that activation is working and reports any issues. All checks should pass. If "mise is not activated" appears, the shell config line from above wasn't picked up --- check the correct file was edited for your shell.

---

## Section 3 --- Install tools

### Windows (automated)

> 📝 **Note:** The script runs `mise use -g` from an activated PS7 session (avoiding the "installed but missing" issue), runs `mise install` as a safety net, regenerates shims for CMD, and verifies all tools are callable.

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/install-mise-tools.ps1
```

### Manual (any platform)

mise installs tools globally with `mise use -g`. This writes to `~/.config/mise/config.toml`.

```sh
mise use -g node@lts python@3.12 gh@latest
```

That's it. All three tools are now on PATH.

### Verify

> ⚠️ **Claude Code note:** Always run `mise doctor` after installing tools. If any tools show as `(missing)`, run `mise install` to re-register them, then re-check with `mise doctor`. This catches a known issue where `mise use -g` from a non-activated shell (e.g., Claude Code's bash or CMD) installs files to disk but doesn't fully register the tools.

```sh
mise doctor
```

Check the `toolset:` section --- all tools should appear without `(missing)`. If any are missing:

```sh
mise install
mise doctor
```

Then verify tools are callable:

```sh
node --version
python --version
gh --version
```

> 🤔 **Claude Code: Ask the user** if `gh auth login` is needed (it's a one-time manual step).

### What about named environments?

mise doesn't use named environments like conda's `node1`. Instead:
- **Global tools** (installed with `mise use -g`) are available everywhere
- **Per-directory tools** use a `.mise.toml` file in the project directory --- mise switches versions automatically when you `cd`

If you want to replicate the `node1` concept, create a directory with a `.mise.toml`:

```toml
# ~/environments/node1/.mise.toml
[tools]
node = "lts"
python = "3.12"
gh = "latest"
```

For most use cases, global tools are sufficient.

---

## Section 4 --- Verify shell integration

> 🤔 **Claude Code: Always run this verification and show the results to the user as a summary table.**

### Windows (automated)

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/verify-mise.ps1
```

> 📝 **Note:** The script checks mise installation, profile activation lines, shims on PATH, runs `mise doctor` in PS7 and PS5.1, and verifies tool versions across PS7, PS5.1, and CMD. It produces a summary table.

### Manual verification

Test that mise-managed tools are available in each shell. Unlike conda, there's no `activate` command to test --- tools should just be on PATH in any shell that has the activation line.

### Step 1: Run `mise doctor` in activated shells

`mise doctor` is the primary health check. Run it in each shell that uses **activation** (not CMD --- CMD uses shims and `mise doctor` will show `(unknown)` shell, which is expected). Confirm:
- `toolset:` section lists all tools **without** `(missing)`
- `shell:` shows the correct shell name (not `(unknown)`)
- `No problems found` at the bottom

### macOS

| Shell | Test command | What to check |
|---|---|---|
| zsh | `zsh -i -c "mise doctor"` | No problems, tools not missing |
| bash | `bash -l -i -c "mise doctor"` | No problems, tools not missing |

### Windows

| Shell | Test command | What to check |
|---|---|---|
| PowerShell 7 | `pwsh -Command "mise doctor"` | No problems, tools not missing |
| PowerShell 5.1 | `powershell.exe -Command "mise doctor"` | No problems, tools not missing (ignore chpwd warning) |

> 📝 **Note:** Git Bash is no longer a supported shell on Windows (see `docs/FUTURES.md`).

### Step 2: Verify tool versions in all shells

After `mise doctor` passes, confirm the tools are callable in **every** shell --- including CMD (which uses shims, not activation):

### macOS

| Shell | Test command | What to check |
|---|---|---|
| zsh | `zsh -i -c "node --version && python --version && gh --version"` | All three versions print |
| bash | `bash -l -i -c "node --version && python --version && gh --version"` | All three versions print |

### Windows

| Shell | Test command | What to check |
|---|---|---|
| PowerShell 7 | `pwsh -Command "node --version; python --version; gh --version"` | All three versions print |
| PowerShell 5.1 | `powershell.exe -Command "node --version; python --version; gh --version"` | All three versions print |
| CMD | `cmd.exe /c "node --version & python --version & gh --version"` | All three versions print (via shims) |

### Present results

**macOS:**
```
| Shell | mise doctor | node | python | gh |
|-------|-------------|------|--------|----|
| zsh   | OK / FAIL   | OK / FAIL | OK / FAIL | OK / FAIL |
| bash  | OK / FAIL   | OK / FAIL | OK / FAIL | OK / FAIL |
```

**Windows:**
```
| Shell          | method     | mise doctor | node      | python    | gh        |
|----------------|------------|-------------|-----------|-----------|-----------|
| PowerShell 7   | activation | OK / FAIL   | OK / FAIL | OK / FAIL | OK / FAIL |
| PowerShell 5.1 | activation | OK / FAIL   | OK / FAIL | OK / FAIL | OK / FAIL |
| CMD            | shims      | N/A         | OK / FAIL | OK / FAIL | OK / FAIL |
```

> ⚠️ **Claude Code note:** Shell activation only works in interactive shells. Use `zsh -i` for zsh. For bash on macOS, use `bash -l -i` (login + interactive) because `~/.bash_profile` is a login-shell file.

---

## Notes & Known Issues

| Issue | Fix |
|---|---|
| `mise is not activated` in `mise doctor` | The `eval "$(mise activate ...)"` line is missing or in the wrong shell config file. Check Section 2 for the correct file. |
| `gpg not found` warning during install | Non-fatal. mise tries to verify GitHub artifact attestations with gpg. Install `gnupg` via brew/winget if you want verification, or ignore the warning. |
| `gh auth` needed after install | Run `gh auth login` manually. This is a one-time step, same as with conda. |
| Tools not on PATH after install | Shell wasn't restarted after adding the activation line. Close and reopen terminal. |
| Want to pin a specific version | Use `mise use -g node@22.15.0` instead of `node@lts`. The version is recorded in `~/.config/mise/config.toml`. |
| Need a conda-forge-only package later | mise doesn't cover conda-forge. If you need a package only available there (e.g., scientific Python with MKL), install miniconda alongside mise for that specific use case. |
| `mise activate bash` breaks Git Bash on Windows | mise outputs Windows-style semicolon-separated paths (`C:\...;C:\...`) which replaces bash's colon-separated PATH, breaking all commands including basic ones like `ls`. Use shims instead of activation for Git Bash (see Section 2). |
| PowerShell 5.1 `chpwd` warning | `mise activate pwsh` prints `WARNING: mise: chpwd functionality requires PowerShell version 7 or higher`. Harmless -- tool activation still works, only the auto-switch-on-cd feature is unavailable. Suppress with `$env:MISE_PWSH_CHPWD_WARNING=0`. |
| `mise doctor` reports "shims not on PATH" | Expected when using activation (not shims) in PowerShell. Activation manages PATH dynamically instead of using shims. For Git Bash (where we use shims), add `$HOME/AppData/Local/mise/shims` to PATH. |
| PowerShell `-Encoding UTF8` adds BOM to `.bash_profile` | PowerShell's `Add-Content -Encoding UTF8` writes a UTF-8 BOM (`EF BB BF`) which bash interprets as a literal command (`$'\357\273\277eval'`). Write `.bash_profile` with a tool that doesn't add BOM, or use `[System.IO.File]::WriteAllText()`. |
| No `remove-micromamba.ps1` script | Fixed: `scripts/windows/remove-micromamba.ps1` now automates full removal (binary, root prefix, PATH, CMD AutoRun, PS profiles, WM_SETTINGCHANGE broadcast). |
| `mise use -g` from non-activated shell installs tools but `mise doctor` shows "(missing)" | When `mise use -g` runs outside of an activated session (e.g., from Claude Code's bash, or even `pwsh -Command` where activation doesn't fully take effect), mise writes config.toml but doesn't fully register the tools. A fresh interactive PS7 shell then reports all tools as "(missing)" and they aren't on PATH. Fix: run `mise install` from an interactive activated PS7 session. The `install-mise-tools.ps1` script now uses `-NoProfile` with explicit `mise activate` to avoid this. |
| `mise doctor` from CMD shows all tools as "(missing)" and shell as "(unknown)" | Expected. mise has no CMD support. Always use PowerShell 7 for mise operations. |
| `mise doctor` returns exit code 1 on version update warnings | `mise doctor` exits non-zero when it has warnings (including "new version available"). Scripts should check output for "No problems found" rather than relying on exit code alone. |
| Locked files during micromamba removal | Running processes (e.g., VS Code extensions using node from a micromamba env) hold file locks. Fixed: `remove-micromamba.ps1` now detects and stops these processes before attempting deletion (Step 0). |
| `verify-prerequisites.ps1` fails after mise migration | The script checked for micromamba unconditionally. Fixed: added `-ToolManager` parameter (`auto`/`mise`/`micromamba`). Auto-detect prefers mise over micromamba. |
| `install-mise-tools.ps1` reports "mise not found" right after `install-mise.ps1` succeeded | winget may install mise as a **portable** package under `%LOCALAPPDATA%\Microsoft\WinGet\Packages\jdx.mise_<sourcehash>\mise\bin\` rather than creating a shim in `WinGet\Links`. The scripts only checked `WinGet\Links` and `%LOCALAPPDATA%\mise\bin`, so they missed it. Fixed: `scripts/shared/mise-helpers.ps1` provides `MISE_ResolveExe`, which also searches the registry PATH and globs the `Packages\jdx.mise*` directory. All four scripts now use it. |
| mise found by path, but child `pwsh` steps still fail to run `mise` | `install-mise-tools.ps1` and `verify-mise.ps1` spawn child shells that invoke `mise` **by name**. A parent shell started before mise was installed has a stale `$env:Path`, which the children inherit. Fixed: `MISE_EnsureOnPath` prepends mise's directory to `$env:Path` before any child process is spawned. |
| `verify-prerequisites.ps1` crashes with "the value none is not a valid value for the ToolManager variable" | The `-ToolManager` parameter has `[ValidateSet('auto','micromamba','mise')]`, and the attribute stays bound to the variable for the life of the script -- so the auto-detect branch assigning `'none'` back to it threw. Fixed: detection now resolves into a separate `$Manager` variable. |
| `python` launches Microsoft Store instead of mise python | Windows ships App Execution Aliases that redirect `python.exe` to the Microsoft Store. These stubs at `WindowsApps\python.exe` may take priority over mise's PATH entries. Fix: Settings > Apps > Advanced app settings > App execution aliases > turn off `python.exe` and `python3.exe`. |

---

## Second-Run Discoveries (Windows on ARM, 2026-04-12)

Issues found when validating the mise runbook end-to-end and building automation scripts.

### 1. `mise use -g` from non-activated shell produces "(missing)" tools

**Symptom:** After running `mise use -g node@lts python@3.12 gh@latest` via Claude Code (which spawns pwsh as a subprocess), a fresh interactive PS7 shell reported all tools as `(missing)` in `mise doctor`. `node` was not found and `python` launched the Microsoft Store.

**Root cause:** When `pwsh -Command "mise use -g ..."` runs, the profile loads and `mise activate` runs, but in a non-interactive subprocess the activation doesn't fully take effect before `mise use -g` executes. mise writes `config.toml` correctly and downloads files to disk, but doesn't register them in a way that a subsequent activated session recognizes. Even the `mise install` safety net (run in the same non-interactive context) didn't fix it.

**Fix:** `install-mise-tools.ps1` now uses `-NoProfile` with explicit `mise activate pwsh | Out-String | Invoke-Expression` before every mise command, guaranteeing activation regardless of how the process was spawned. If tools still show as `(missing)`, run `mise install` from an interactive PS7 shell.

### 2. Windows App Execution Aliases intercept `python`

**Symptom:** `python` launched the Microsoft Store "Python Install Manager" instead of mise's Python 3.12.

**Root cause:** Windows ships App Execution Aliases (`python.exe`, `python3.exe`) at `WindowsApps\` that redirect to the Microsoft Store. These stubs appear on PATH via `WindowsApps` and can take priority over mise's injected paths depending on PATH order.

**Fix:** Disable the aliases: Settings > Apps > Advanced app settings > App execution aliases > turn off `python.exe` and `python3.exe`.

### 3. Locked files during micromamba removal

**Symptom:** `remove-micromamba.ps1` reported `WARN: Could not fully remove` for both micromamba directories. Directories remained on disk.

**Root cause:** VS Code extensions had 4 `node.exe` processes running from the micromamba `node1` environment, holding file locks.

**Fix:** `remove-micromamba.ps1` now includes Step 0 which detects processes using micromamba files, stops them with `Stop-Process -Force`, waits for handles to release, then proceeds with deletion. Post-deletion checks now report `FAIL` (not `WARN`) if directories survive.

---

## First-Run Discoveries (Windows on ARM, 2026-04-09)

This section documents issues found during the first run of the mise runbook on a Windows 11 ARM64 (Snapdragon) machine.

### 1. mise installs native ARM64 binaries

Unlike micromamba (which only has x86-64 builds), mise downloaded native ARM64 binaries for all three tools: `node-v24.14.1-win-arm64.zip`, `cpython-3.12.13-aarch64-pc-windows-msvc`, and `gh_2.89.0_windows_arm64.zip`. mise itself is also native ARM64 (`windows-arm64`). This is a significant improvement over the conda-family setup.

### 2. `mise activate bash` destroys Git Bash PATH

**Symptom:** After `eval "$(mise activate bash)"`, all commands including `ls`, `tr`, and `head` became unfindable.

**Root cause:** `mise activate bash` uses `mise hook-env` which outputs PATH entries in Windows format (`C:\Users\...`) with semicolons as separators. Git Bash expects Unix-style paths (`/c/Users/...`) with colons. The activation hook replaces the entire PATH with the Windows-format string, which bash can't parse.

**Fix:** Use shims for Git Bash instead of activation. Add `$HOME/AppData/Local/mise/shims` to PATH in `.bash_profile`.

### 3. PowerShell BOM in `.bash_profile`

**Symptom:** Bash reported `$'\357\273\277eval': command not found`.

**Root cause:** PowerShell's `Add-Content -Encoding UTF8` writes a UTF-8 BOM (byte order mark: `EF BB BF`) at the start of the file. Bash interprets these bytes as part of the first command, prepending garbage to `eval`.

**Fix:** Write `.bash_profile` without BOM (use a non-PowerShell tool, or `[System.IO.File]::WriteAllText()`).

### 4. Micromamba removal was fully manual

The runbook noted there's no `remove-micromamba.ps1` script. Removal required: deleting two directories (`AppData\Local\micromamba\` and `~/micromamba/`), cleaning PATH, removing the CMD AutoRun registry entry, and stripping mamba init blocks from PowerShell profiles and `.bash_profile`. All steps succeeded without issues.

---

## Status Tracker

> ⚠️ **Claude Code note:** Do NOT track status in this file --- it lives in git and is shared across machines. Instead, create/update a local checklist at `~/Documents/runbook-status/mise-env-runbook.md`. At the start of each run:
> 1. Create the directory and file if they don't exist (use the template below for the current platform).
> 2. Reset all checkboxes to `[ ]`.
> 3. Check off items as each step completes.

<details>
<summary>macOS checklist template</summary>

```markdown
# mise-env-runbook status --- macOS

- [ ] Conda/micromamba removed (if previously installed)
- [ ] mise installed via `brew install mise`
- [ ] mise --version verified
- [ ] Activation line added to ~/.zshrc
- [ ] Activation line added to ~/.bash_profile (optional)
- [ ] Terminal restarted
- [ ] `mise doctor` passes (activation verified)
- [ ] Tools installed: `mise use -g node@lts python@3.12 gh@latest`
- [ ] `mise doctor` passes (no tools missing)
- [ ] node --version verified
- [ ] python --version verified
- [ ] gh --version verified
- [ ] Shell integration verified (`mise doctor` + tool versions in each shell)
```

</details>

<details>
<summary>Windows checklist template</summary>

```markdown
# mise-env-runbook status --- Windows

- [ ] Conda/micromamba removed (if previously installed)
- [ ] mise installed and activated (install-mise.ps1)
- [ ] Terminal restarted
- [ ] Tools installed (install-mise-tools.ps1)
- [ ] Shell integration verified (verify-mise.ps1, table shown to user)
```

</details>
