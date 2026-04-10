# Tool Setup Runbook (mise)

> **How to use this with Claude Code:** Open Claude Code in your terminal, point it at this file, and say: *"Follow the tool setup runbook at mise-env-runbook.md. Walk me through each section, automate what you can, and tell me when I need to do something manually."*
>
> **What is mise?** [mise](https://mise.jdx.dev/) (formerly `rtx`) is a cross-platform tool version manager. It replaces the conda-family environment manager used in `conda-env-runbook.md`. One CLI, one config format, same behavior on every platform.
>
> **Why mise instead of conda/micromamba?** The runbooks only use conda-forge to install three tools (`nodejs`, `python`, `gh`) that are first-class in every mainstream package ecosystem. mise installs them directly without libmamba, shell hook complexity, channel config, or the per-platform manager split (micromamba on Windows, miniconda on macOS). See `docs/FUTURES.md` for the full rationale.
>
> **Prerequisites:**
> - **macOS:** Homebrew installed (see [setup-runbook-mac.md](setup-runbook-mac.md))
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

## Section 1 --- Install mise

### macOS

```zsh
brew install mise
```

### Windows

```powershell
winget install jdx.mise
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

## Section 2 --- Activate mise in your shell

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
| `mise use -g` from non-PS7 shell installs tools but `mise doctor` shows "(missing)" | When `mise use -g` runs outside of an activated PS7 session (e.g., from Claude Code's bash, CMD, or a PS5 terminal), mise installs tool files to disk but may not fully register them. `mise doctor` in PS7 then reports tools as "(missing)". Fix: run `mise install` from an activated PS7 session to re-register. To avoid the issue, run `mise use -g` from PS7 after activation. |
| `mise doctor` from CMD shows all tools as "(missing)" and shell as "(unknown)" | Expected. mise has no CMD support. Always use PowerShell 7 for mise operations. |

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
- [ ] mise installed via `winget install jdx.mise`
- [ ] mise --version verified
- [ ] Activation line added to PowerShell 7 profile
- [ ] Activation line added to PowerShell 5.1 profile
- [ ] Shims directory added to user PATH (for CMD)
- [ ] Terminal restarted
- [ ] `mise doctor` passes in PS7 (activation verified)
- [ ] `mise doctor` passes in PS5.1 (activation verified, chpwd warning OK)
- [ ] Tools installed: `mise use -g node@lts python@3.12 gh@latest`
- [ ] `mise doctor` passes (no tools missing)
- [ ] node --version verified
- [ ] python --version verified
- [ ] gh --version verified
- [ ] Shell integration verified (PS7 + PS5.1 + CMD, table shown to user)
```

</details>
