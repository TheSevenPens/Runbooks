# Futures

Ideas, planned improvements, and known issues for the runbook system.

---

## Completed

These were previously planned and are now implemented.

### Cross-platform support (macOS)

Three-file structure is in place:

```
setup-runbook-windows.md    — Windows-specific installs & config
setup-runbook-mac.md        — macOS-specific installs & config (brew, zsh, iTerm, etc.)
conda-env-runbook.md        — Shared, with platform-specific callouts where needed
```

### Scriptable steps — extracted

Most deterministic runbook steps have been extracted into standalone idempotent scripts with structured output.

**Windows (10 scripts):**

| Script | Status |
|--------|--------|
| `prepare-for-runbooks.ps1` | Done |
| `install-apps.ps1` | Done |
| `export-apps.ps1` | Done |
| `import-apps.ps1` | Done |
| `fix-path-registry.ps1` | Done |
| `micromamba-shell-init.ps1` | Done |
| `remove-conda.ps1` | Done |
| `create-env.ps1` | Done |
| `verify-prerequisites.ps1` | Done |
| `verify-shell-integration.ps1` | Done |

**macOS (6 scripts):**

| Script | Status |
|--------|--------|
| `prepare-for-runbooks.sh` | Done |
| `install-apps.sh` | Done |
| `bundle-install.sh` | Done |
| `create-env.sh` | Done |
| `verify-prerequisites.sh` | Done |
| `verify-shell-integration.sh` | Done |

**Shared (declarative app specs):**

| File | Description |
|------|-------------|
| `apps/windows.json` | Winget export JSON — used by `import-apps.ps1` |
| `apps/Brewfile` | Homebrew Bundle file — used by `bundle-install.sh` |

---

## Scripts still to extract

### macOS: `remove-conda.sh`

Windows has a full removal script (`remove-conda.ps1`) that backs up environments, uninstalls via winget, cleans PATH, CMD AutoRun, .condarc, and shell profiles. The macOS equivalent is still inline in `conda-env-runbook.md` Section 0 as manual `brew uninstall` + `rm` commands.

A script would:
- Back up existing environments
- Run `brew uninstall miniconda` (or `anaconda`)
- Remove `~/miniconda3` and `~/.condarc`
- Strip `# >>> conda initialize >>>` blocks from `~/.zshrc` and `~/.bash_profile`
- Verify removal

### ~~Cross-platform: `create-env.sh` / `create-env.ps1`~~ — Done

Both scripts accept environment name, package list (or YAML spec file), and a recreate flag. They check for existing environments, create with verification, and output structured results. Runbook Section 3 updated to reference them.

### macOS: `micromamba-shell-init.sh`

Windows has `micromamba-shell-init.ps1` that runs shell init for all shells and verifies the results. The macOS equivalent is two manual commands in the runbook. A script could:
- Run `micromamba shell init` for zsh and bash
- Verify hooks were written to `~/.zshrc` and `~/.bash_profile`
- Report per-shell status

---

## Environment specs as files

Instead of hardcoding package lists in the runbook, define environments in YAML spec files:

```
envs/
  node1.yml
```

```yaml
name: node1
channels:
  - conda-forge
dependencies:
  - nodejs
  - python
  - gh
```

Both micromamba and conda support `--file` for environment creation. This makes it easy to version, diff, and reproduce environments. The `create-env` script could default to reading from `envs/` if no packages are passed on the command line.

---

## Post-setup smoke test

A single end-to-end validation script that confirms the entire setup is working. It would combine what `verify-prerequisites` and `verify-shell-integration` check, plus:
- Every expected tool on PATH with the correct source (not Apple Git, not standalone micromamba)
- Every shell hook functional (micromamba activate works)
- The `node1` environment exists with all expected packages
- VS Code `code` command works
- `gh auth status` reports logged in

Run it after completing a runbook to catch anything that was missed. Could also serve as a CI-like check for "is this machine still set up correctly?"

---

## Runbook versioning

Add a version or last-validated date to each runbook header so it's clear when the instructions were last tested end-to-end. Stale runbooks are worse than no runbook. Something like:

```markdown
> Last validated: 2026-03-29 on macOS 15.4 (Apple Silicon)
```

This could also be automated — the smoke test script could stamp the date on success.

---

## Known issues to address

### ~~conda-env-runbook.md has a duplicate `### macOS` header in Section 4~~ — Fixed ([#1](https://github.com/TheSevenPens/Runbooks/issues/1))

Merged the duplicate headers into a single section.

### ~~Windows verify-shell-integration.ps1 CMD section describes itself as manual in the runbook~~ — Fixed ([#2](https://github.com/TheSevenPens/Runbooks/issues/2))

Updated Section 4 to say the script tests all four shells automatically.

### ~~macOS conda removal has no script parity with Windows~~ — Fixed ([#3](https://github.com/TheSevenPens/Runbooks/issues/3))

Created `scripts/mac/remove-conda.sh` with full parity. Updated conda-env-runbook.md to reference it.

### ~~verify-prerequisites naming inconsistency~~ — Fixed ([#4](https://github.com/TheSevenPens/Runbooks/issues/4))

Windows script renamed from `verify-installed.ps1` to `verify-prerequisites.ps1` to match macOS.

### ~~Removing conda deletes micromamba binary if it lives inside miniconda3~~ — Fixed ([#5](https://github.com/TheSevenPens/Runbooks/issues/5))

`remove-conda.ps1` now detects `MAMBA_EXE` references inside `miniconda3\`, reinstalls micromamba to the canonical location, and updates all shell configs before proceeding with removal.

### ~~PS7 profile retains stale MAMBA_EXE after shell init~~ — Fixed ([#6](https://github.com/TheSevenPens/Runbooks/issues/6))

`micromamba-shell-init.ps1` now always replaces (not skips) the PS7 init block and validates `MAMBA_EXE` paths across all profiles. `verify-prerequisites.ps1` gained a MAMBA_EXE consistency check.

---

## Ideas to explore

### PowerShell 7 as cross-platform scripting language

PowerShell 7 runs on both Windows and macOS (`brew install powershell`). The idea is not necessarily that identical `.ps1` files run on both platforms, but that both platforms use the same language, so there's one set of patterns to learn, one way to handle errors, and one style of script to maintain.

**What this would look like:**
- All macOS `.sh` scripts rewritten as `.ps1`
- Shared PowerShell module with common helpers (structured output, idempotency checks, version detection)
- `param()` blocks with typed parameters instead of `getopts` / positional args
- `try/catch` error handling instead of `set -euo pipefail` + exit code checks
- Object pipeline for passing structured data between functions instead of text parsing

**Benefits:**
- The Windows scripts are already more mature and battle-tested — their patterns (canonical path fallbacks, registry handling, verify-after-install) would transfer directly
- PowerShell's `param()` and type system make scripts more self-documenting than bash
- A shared helper module could enforce conventions (e.g., `Write-Status "OK" "git installed"`) rather than each script reimplementing prefix formatting

**Practical concerns to work through:**
- **Bootstrap problem.** `prepare-for-runbooks` must run before PowerShell 7 exists on a fresh Mac. At minimum, one bash bootstrap script is needed to install Homebrew + PowerShell 7, then hand off to `.ps1` for everything else
- **Shell hook testing.** `verify-shell-integration` tests that zsh/bash hooks work. This can be done from PowerShell (spawn `zsh -i -c "..."`), but it's an extra layer of indirection
- **macOS-native tooling.** `brew`, `defaults`, `launchctl`, dotfile editing are more natural in bash — PowerShell scripts would wrap these in `& bash -c "..."` calls
- **pwsh startup time.** ~500ms+ cold start vs near-instant for bash, which adds up for quick verification scripts
- **Contributor expectations.** PowerShell on macOS is unusual — anyone else touching these scripts would need to know it

**Migration path:** Start with scripts that have the most to gain from PowerShell's features (structured data handling, multi-step verification) and leave simple wrappers as bash. The bootstrap script (`prepare-for-runbooks.sh`) would always remain bash.

### Script contract standardization

An alternative (or complement) to a shared runtime: formalize the implicit contract that all scripts already follow into an explicit, documented specification. The scripts on both platforms already converge on the same patterns — codify that so new scripts are consistent by design, not by copy-paste.

**What the contract would define:**

1. **Output format.** Every script emits lines prefixed with `OK:`, `FAIL:`, `WARN:`, `SKIP:`, or `INFO:`. No other prefixes. Each prefix has a defined meaning:
   - `OK` — action succeeded or verification passed
   - `FAIL` — action failed, contributes to non-zero exit code
   - `WARN` — unexpected but non-blocking (e.g., Apple Git instead of Homebrew Git)
   - `SKIP` — already done or not applicable
   - `INFO` — progress update, no action needed

2. **Exit codes.** `0` = all checks passed / all actions succeeded. `1` = one or more failures. `2` = bad usage (wrong arguments). Scripts track `FAIL_COUNT` and exit accordingly.

3. **Idempotency.** Every script checks "already done?" before acting. Running twice produces the same result. Detection order: command lookup first (fast), then canonical path fallback, then package manager query (slow).

4. **No interactivity.** Scripts never prompt. All decisions come from the runbook via Claude Code. Scripts accept parameters, do their work, and report results.

5. **Verify after mutation.** Every install, file write, or config change is followed by a verification step. Don't trust that a command succeeded — confirm the expected state exists.

6. **Standard header.** Every script starts with: name, one-line description, usage example, output format note, exit code note.

7. **Canonical path fallbacks.** After a fresh install, the tool may not be on PATH in the current session. Scripts define known install locations and check them when `command -v` / `Get-Command` fails.

**What this enables:**
- New scripts can be written in either bash or PowerShell and still be predictable to Claude Code
- The structured output is already machine-parseable — formalizing it means tooling can be built on top (e.g., the smoke test script could run all verify scripts and aggregate results)
- Naming conventions, parameter patterns, and error handling become reviewable against the contract rather than "does it look like the other scripts"

**Where to document it:** Expand the "Script conventions" section of `docs/ARCHITECTURE.md` into a full contract specification. The current section covers the header and output prefixes but doesn't specify detection order, idempotency patterns, or verification requirements.

### Runbook diffing between machines

When setting up a second machine, it would be useful to compare what's installed on the new machine vs. an already-configured reference machine. The `verify-prerequisites` script output is structured enough to diff, but there's no tooling to capture a baseline and compare against it.

### ~~Homebrew Bundle for macOS~~ — Done

Added `apps/Brewfile` and `scripts/mac/bundle-install.sh` as an alternative fast path alongside `install-apps.sh`. Both install the same apps. The Brewfile approach is faster for fresh machines; `install-apps.sh` gives per-app structured output.

### Evaluate iTerm2 as default terminal

iTerm2 is a popular Terminal.app replacement with split panes, regex search, autocomplete, hotkey window, and per-profile customization. Currently listed as optional in the macOS runbook (Section 6). Worth evaluating whether it should be a recommended default or remain optional. If adopted, consider including a default profile/preferences export in the repo.

### Dotfile management

The runbooks touch several dotfiles (`~/.zshrc`, `~/.bash_profile`, `~/.zprofile`). Currently, each script appends to them independently. As the number of tools that modify dotfiles grows, consider:
- A managed section marker (like conda's `>>> conda initialize >>>`) for all runbook-managed blocks
- A `dotfiles/` directory with template fragments that get assembled
- Integration with a dotfile manager like `chezmoi` or `stow`

### Shell-agnostic environment activation

The current setup requires shell-specific init hooks. Fish, nushell, and other modern shells aren't covered. If the user adopts a new shell, they need to manually figure out the init command and test it. The `verify-shell-integration` scripts could be extended to detect all installed shells and test them dynamically.

### ~~Windows: winget export/import~~ — Done

Added `scripts/windows/export-apps.ps1`, `scripts/windows/import-apps.ps1`, and `apps/windows.json`. Export generates a winget JSON from the canonical app list; import bulk-installs from it. Offered as an alternative fast path alongside `install-apps.ps1`.
