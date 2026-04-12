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

### Script robustness audit — Fixed (2026-03-30)

Reviewed all 10 Windows scripts for robustness. Key fixes:
- `remove-conda.ps1` validates path before recursive deletion and aborts on backup failure
- `create-env.ps1` checks exit codes on all micromamba calls and detects ghost environments
- `micromamba-shell-init.ps1` fixed PS5.1 parse failure (em-dashes, UTF-8 BOM, encoding)
- `import-apps.ps1` checks winget output string not just exit code
- All path substitutions in shell configs use `.Replace()` instead of `-replace` (regex safety)
- All profile writes use `-Encoding UTF8`

See `docs/HISTORY.md` for the full list of changes across 9 scripts.

---

## Ideas to explore

### ~~PowerShell 7 as cross-platform scripting language~~ -- Done (2026-04-09)

All macOS bash scripts rewritten as `.ps1` files in `scripts/mac/`. Both platforms now use PowerShell with the same conventions: `#Requires` version header, `$ErrorActionPreference`, `$FailCount` tracking, `OK/SKIP/FAIL/WARN/INFO` structured output with `Write-Host` colors.

The bootstrap problem was solved by keeping `bootstrap/bootstrap-mac.sh` as the ONE bash script -- it installs Homebrew + PowerShell 7 + Claude Code + clones the repo. Everything after that runs under `pwsh`.

Original bash scripts moved to `scripts/archive/` for reference.

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

### Drop the conda ecosystem and standardize on mise

**The observation.** The runbooks use a conda-family package manager (micromamba on Windows, miniconda on macOS) to install three developer tools: `nodejs`, `python`, `gh`. None of those three require `conda-forge` specifically — they're first-class in every mainstream package ecosystem. We're paying every conda-ecosystem cost (libmamba bugs, the ToS dance on `pkgs/main`, shell init hooks, channel priority config, 300 MB of metadata caches, a per-platform env manager split) for a use case where `conda-forge` isn't earning its keep.

This idea is to drop the conda ecosystem from the runbook entirely and standardize on [**mise**](https://mise.jdx.dev/) (formerly `rtx`): a Rust-based, asdf-compatible, cross-platform tool version manager.

**Why mise specifically.**

- Mature: 1.0+, actively developed, used in real production environments.
- Genuinely cross-platform: native Windows, native macOS, native Linux (including Fedora). One install story per platform, one CLI, one config format.
- Does not use `libmamba` or `reproc`, so it cannot hit the bug tracked in `macos_micromamba_debug_runbook.md` or anything in that family.
- Uses `conda-forge` for nothing, so the Anaconda ToS dance and `conda config --override-channels` workarounds disappear.
- Small (~15 MB binary). No Python runtime. No metadata cache.
- Plugin ecosystem covers `nodejs`, `python`, `gh`, and ~400+ other common tools via mise's own and asdf-compatible plugins.

**What the runbook would look like.**

`conda-env-runbook.md` — currently ~500 lines with platform-specific install, shell init, channel config, Section 0 removal logic, known-issues tables, and the libmamba fallback machinery — collapses to something like:

```markdown
# Tool Setup Runbook (mise)

1. Install mise
   macOS:    brew install mise
   Windows:  winget install jdx.mise
   Fedora:   dnf install mise   (or: curl https://mise.run | sh)

2. Add mise to your shell
   echo 'eval "$(mise activate zsh)"' >> ~/.zshrc         # macOS / Fedora
   Add-Content $PROFILE 'mise activate pwsh | Out-String | Invoke-Expression'  # Windows

3. Install the tools
   mise use -g node@lts python@3.12 gh@latest

4. Verify
   node --version
   python --version
   gh --version
```

That's the whole runbook. No Section 0, no create-env, no shell-integration verification, no channel config, no known-issues table — because none of those concerns exist in mise.

**Script impact.** Many of the scripts tracked above become unnecessary:

| Script | Status after mise migration |
|---|---|
| `scripts/mac/remove-conda.sh` | Obsolete (keep in archive/) |
| `scripts/mac/remove-micromamba.sh` | Obsolete (keep in archive/) |
| `scripts/mac/create-env.sh` | Obsolete — replaced by `mise use -g` |
| `scripts/mac/verify-shell-integration.sh` | Trivial / unnecessary |
| `scripts/windows/remove-conda.ps1` | Obsolete |
| `scripts/windows/fix-path-registry.ps1` | Obsolete (no PATH registry mangling needed) |
| `scripts/windows/micromamba-shell-init.ps1` | Obsolete |
| `scripts/windows/create-env.ps1` | Obsolete |
| `scripts/windows/verify-shell-integration.ps1` | Trivial / unnecessary |
| `scripts/mac/verify-prerequisites.sh` | Still needed, simplified (checks mise instead of conda) |
| `scripts/windows/verify-prerequisites.ps1` | Still needed, simplified |

New scripts needed: `install-mise.sh` (macOS). Windows scripts already exist: `install-mise.ps1`, `install-mise-tools.ps1`, `verify-mise.ps1`.

**What we would give up.**

1. **Named environments as a concept.** mise doesn't have `node1`-as-a-named-collection. It thinks in terms of "which version of `node` is on PATH in this directory (or globally)." If we ever want a named collection of tools, we'd fake it with a directory that has a `.mise.toml` in it. Most day-to-day dev work treats "node, python, gh are available" as the goal, which mise handles directly.

2. **Explicit activation.** No more `conda activate node1` / `micromamba activate node1`. Tools are just on PATH, and mise switches versions automatically when you `cd` between directories with different `.mise.toml` files. Most people call this an upgrade; anyone who liked the explicit "enter the env" ritual would miss it.

3. **Conda-forge as an escape hatch.** If we ever need a package that's only available (or meaningfully better) on conda-forge — e.g., a pre-built scientific Python stack with tuned MKL, or R with its conda-forge toolchain, or a bioinformatics tool — mise does not cover that. We would need to add a conda-family tool alongside mise for that one use case, or use [uv](https://github.com/astral-sh/uv) (Python-specific, covers most of what pip can't). As of 2026-04-08 the runbook has not needed conda-forge-specific packages; this is a hypothetical future need.

4. **The miniconda migration we just did.** `conda-env-runbook.md`, the new `remove-micromamba.sh`, the rewritten `create-env.sh`, the verify-prerequisites updates, and the memory policy files are all recent work against the conda-family abstraction. A mise migration would move all of it to an archive state. That churn is real.

**Why this is in FUTURES and not implemented now.**

- **We just finished a macOS → miniconda migration on 2026-04-08.** Doing a second migration of the same runbook a week later is avoidable churn. The current state works end-to-end and there's no active pain point.
- **A mise migration is a bigger lift than the miniconda one was.** The miniconda switch kept the overall conda-family architecture; swapping to mise rewrites the whole environment section of the runbook and obsoletes half the scripts. Not a blocker, but enough to not do it on a whim.
- **Adding Fedora to the runbook collection is the natural trigger for this conversation.** Right now we have two platforms with two tools; the platform-consistency payoff of mise is modest. Adding a third platform-tool pair is when the cross-platform simplification actually earns its keep.

**What would make me revisit this sooner rather than later.**

1. **Fedora setup runbook work begins.** That's the strongest case for "stop paying the per-platform env manager tax and consolidate."
2. **Miniconda hits its own macOS regression.** Not impossible — macOS 26 already bit us once. If conda starts chasing its own version-dependent breakage the way micromamba did, the "conda is stable, mise is young" framing weakens.
3. **A new tool needs to be added to `node1`** and the friction of "edit the runbook, edit the create-env script, edit the spec-file, run create-env --recreate" vs. "`mise use -g new-tool`" becomes annoying enough to matter.

**Low-commitment next step when we do pick this up.** Don't migrate the main runbook. Instead:

1. 10-minute prototype: `brew install mise`, `mise use -g node@lts python@3.12 gh@latest`, verify the three tools work, uninstall if it feels wrong.
2. If the feel is right, write a parallel `mise-env-runbook.md` as a draft alongside `conda-env-runbook.md`. Both are available; pick one when the next fresh machine needs setup.
3. Use the mise runbook on the next fresh machine. See if it's actually better in practice.
4. If yes, retire `conda-env-runbook.md` and move the conda scripts into `scripts/archive/`. If no, walk away — no harm done.

### Drop Git Bash as a supported shell on Windows --- Done (2026-04-09)

**The observation.** Git Bash (MSYS2) is the source of a disproportionate share of issues on Windows. Every tool that interacts with PATH, writes config files, or spawns subshells has to navigate the impedance mismatch between Unix-style paths (`/c/Users/...` with `:` separators) and Windows-style paths (`C:\Users\...` with `;` separators). Tools get this wrong regularly, and when they do, the failures are confusing and hard to diagnose.

**Problems caused by Git Bash during the 2026-04-09 ARM64 run:**

1. **`mise activate bash` destroys PATH.** mise's hook outputs Windows-style semicolon-separated paths, which replaces bash's colon-separated PATH. After activation, *every* command fails -- including basic Unix tools like `ls`, `tr`, and `head`. The workaround is to use shims instead of activation, but this loses mise's auto-switching feature.

2. **`micromamba shell init -s cmd.exe` mangles paths when run from Git Bash.** micromamba treats the `-r` root prefix as a relative path in the MSYS2 environment, producing incorrect `AutoRun` registry values. The workaround is to always run it from PowerShell.

3. **PowerShell's `-Encoding UTF8` adds BOM to `.bash_profile`.** Any time a PowerShell script writes a file that bash reads, it must avoid `-Encoding UTF8` (which adds a BOM on PS5.1) and use `[System.IO.File]::WriteAllText()` instead. This is an ongoing trap -- every new script that touches `.bash_profile` has to remember this.

4. **Git Bash subshells lose commands.** Non-interactive bash subshells spawned from Claude Code's environment have a broken PATH that's missing basic Git Bash utilities. The `ioctl` warnings and `command not found` errors on standard tools make testing unreliable.

**What we'd gain by dropping Git Bash support:**

- Remove `.bash_profile` management from all Windows scripts and runbooks
- Remove `micromamba shell init -s bash` / `mise activate bash` from the init flow
- Remove Git Bash from `verify-shell-integration.ps1` test matrix
- Eliminate the entire BOM-in-bash-files risk (no bash config files to write on Windows)
- Eliminate the path format translation problem
- Simplify encoding rules (ASCII-only in `.ps1` is the only rule left; no cross-shell encoding concerns)

**What we'd keep:**

- **Git for Windows** stays installed (provides `git` CLI, Git Credential Manager)
- **Git Bash itself still exists** for users who want it -- we just stop configuring/testing it
- PowerShell 7 + CMD cover all automation needs
- Any Unix shell needs (SSH, WSL) use their own bash, not Git Bash

**Supported shell matrix after this change:**

| Shell | Windows | macOS |
|-------|---------|-------|
| PowerShell 7 | Primary | Optional (`brew install powershell`) |
| PowerShell 5.1 | Supported (ships with Windows) | N/A |
| CMD | Supported | N/A |
| Git Bash | **Dropped** | N/A |
| zsh | N/A | Primary |
| bash | N/A | Supported (via `~/.bash_profile`) |

**Risk:** Users who prefer Git Bash as their daily shell would find that mise/micromamba tools aren't configured for it. This is mitigable -- the tools still work if the user manually adds shims to PATH. We just stop doing it for them and stop testing it.

**Recommendation:** Drop Git Bash. The complexity cost of supporting it (BOM rules, path format translation, broken subshells, per-tool workarounds) exceeds the value. PowerShell 7 is the natural Windows shell for this workflow.

**When to do this:** Next time the Windows runbook is revised for a fresh machine setup. It's a cleanup task, not urgent.

### Mise automation scripts for Windows --- Done (2026-04-12)

The mise runbook had no automation scripts (pure inline commands). Added three Windows scripts to match the robustness level of the conda path:

| Script | Purpose |
|--------|---------|
| `scripts/windows/install-mise.ps1` | Idempotent mise install + PS7/PS5.1 profile activation + CMD shims on PATH |
| `scripts/windows/install-mise-tools.ps1` | Install global tools via activated PS7 (avoids "missing" registration bug) + reshim + verify |
| `scripts/windows/verify-mise.ps1` | Cross-shell verification: mise doctor in PS7/PS5.1, tool versions in PS7/PS5.1/CMD, summary table |

Also updated:
- `verify-prerequisites.ps1`: Added `-ToolManager` parameter (`auto`/`mise`/`micromamba`) so it works after mise migration
- `remove-micromamba.ps1`: Added Step 0 (detect and stop processes using micromamba files before deletion)
- `mise-env-runbook.md`: References new scripts, updated Known Issues and checklist

**Implemented 2026-04-09.** Changes made:
- `verify-shell-integration.ps1`: Removed Git Bash test section
- `micromamba-shell-init.ps1`: Removed `shell init -s bash`, `.bash_profile` verification, and `.bash_profile` MAMBA_EXE check
- `remove-conda.ps1`: Removed `.bash_profile` cleanup (Step 7) and `.bash_profile` MAMBA_EXE check
- `verify-prerequisites.ps1`: Removed `.bash_profile` BOM check and MAMBA_EXE consistency check
- `conda-env-runbook.md`: Removed Git Bash from Windows shell matrix and checklist
- `mise-env-runbook.md`: Removed Windows Git Bash section, updated test matrix and checklist
- `setup-runbook-windows.md`: Updated Git for Windows note
- `CLAUDE.md`: Updated key lessons and encoding rules (bash concern now macOS-only)

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
