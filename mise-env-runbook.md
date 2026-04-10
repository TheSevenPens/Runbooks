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
> 📝 **Note:** There is no `remove-micromamba.ps1` script yet. Manual steps:
> 1. Remove `%USERPROFILE%\AppData\Local\micromamba\` and `%USERPROFILE%\micromamba\`
> 2. Remove micromamba entries from user PATH
> 3. Remove the CMD AutoRun registry entry if it points to `mamba_hook.bat`
> 4. Remove micromamba init blocks from PowerShell profiles and `~/.bash_profile`

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
# Add to your PowerShell profile
Add-Content $PROFILE 'mise activate pwsh | Out-String | Invoke-Expression'
```

> ⚠️ **Claude Code note:** If `$PROFILE` doesn't exist yet, create it first: `New-Item -ItemType File -Path $PROFILE -Force`

### Windows (CMD)

> 📝 **Note:** mise does not have native CMD support. Use PowerShell 7 or Git Bash on Windows.

### Windows (Git Bash)

```bash
echo 'eval "$(mise activate bash)"' >> ~/.bash_profile
```

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

### macOS

| Shell | Test command | What to check |
|---|---|---|
| zsh | `zsh -i -c "node --version && python --version && gh --version"` | All three versions print |
| bash | `bash -l -i -c "node --version && python --version && gh --version"` | All three versions print |

### Windows

| Shell | Test command | What to check |
|---|---|---|
| PowerShell 7 | `pwsh -NoProfile -Command "node --version; python --version; gh --version"` | All three versions print |
| Git Bash | `bash -l -i -c "node --version && python --version && gh --version"` | All three versions print |

Present results to the user in this format:

**macOS:**
```
| Shell | node | python | gh |
|-------|------|--------|----|
| zsh   | OK / FAIL | OK / FAIL | OK / FAIL |
| bash  | OK / FAIL | OK / FAIL | OK / FAIL |
```

**Windows:**
```
| Shell        | node | python | gh |
|--------------|------|--------|----|
| PowerShell 7 | OK / FAIL | OK / FAIL | OK / FAIL |
| Git Bash     | OK / FAIL | OK / FAIL | OK / FAIL |
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
- [ ] `mise doctor` passes
- [ ] Tools installed: `mise use -g node@lts python@3.12 gh@latest`
- [ ] node --version verified
- [ ] python --version verified
- [ ] gh --version verified
- [ ] Shell integration verified (table shown to user)
```

</details>

<details>
<summary>Windows checklist template</summary>

```markdown
# mise-env-runbook status --- Windows

- [ ] Conda/micromamba removed (if previously installed)
- [ ] mise installed via `winget install jdx.mise`
- [ ] mise --version verified
- [ ] Activation line added to PowerShell profile
- [ ] Activation line added to ~/.bash_profile (Git Bash)
- [ ] Terminal restarted
- [ ] `mise doctor` passes
- [ ] Tools installed: `mise use -g node@lts python@3.12 gh@latest`
- [ ] node --version verified
- [ ] python --version verified
- [ ] gh --version verified
- [ ] Shell integration verified (table shown to user)
```

</details>
