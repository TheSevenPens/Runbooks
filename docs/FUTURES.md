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

**Windows (7 scripts):**

| Script | Status |
|--------|--------|
| `prepare-for-runbooks.ps1` | Done |
| `install-apps.ps1` | Done |
| `fix-path-registry.ps1` | Done |
| `micromamba-shell-init.ps1` | Done |
| `remove-conda.ps1` | Done |
| `verify-installed.ps1` | Done |
| `verify-shell-integration.ps1` | Done |

**macOS (4 scripts):**

| Script | Status |
|--------|--------|
| `prepare-for-runbooks.sh` | Done |
| `install-apps.sh` | Done |
| `verify-prerequisites.sh` | Done |
| `verify-shell-integration.sh` | Done |

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

### Cross-platform: `create-env.sh` / `create-env.ps1`

Environment creation is currently inline in the runbook (`micromamba create -n node1 ...`). A script could:
- Accept an environment name and package list as parameters
- Check if the environment already exists (skip or recreate)
- Create the environment and verify all packages
- Output structured results

This becomes more valuable when combined with environment spec files (see below).

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

### conda-env-runbook.md has a duplicate `### macOS` header in Section 4

Section 4 (Verify Shell Integration) contains two consecutive `### macOS` headers (around lines 249-253). The first introduces the script reference, the second introduces the manual test table. Should be merged into one section.

### Windows verify-shell-integration.ps1 CMD section describes itself as manual in the runbook

The runbook text at `conda-env-runbook.md` Section 4 still says "CMD requires manual testing" in its table description, but the script now automates CMD testing. The runbook text should be updated to reflect this.

### macOS conda removal has no script parity with Windows

Windows users get a one-command experience (`remove-conda.ps1`). macOS users follow 4 manual steps. This is a friction asymmetry — see "Scripts still to extract" above.

### verify-prerequisites naming inconsistency

Windows calls it `verify-installed.ps1`, macOS calls it `verify-prerequisites.sh`. They do the same thing. Consider aligning the names, or at least documenting the reason for the difference.

---

## Ideas to explore

### Runbook diffing between machines

When setting up a second machine, it would be useful to compare what's installed on the new machine vs. an already-configured reference machine. The `verify-prerequisites` script output is structured enough to diff, but there's no tooling to capture a baseline and compare against it.

### Homebrew Bundle for macOS

Homebrew supports `Brewfile` — a declarative list of everything to install. `brew bundle` installs everything in one shot and is inherently idempotent. This could replace `install-apps.sh` with a simpler approach:

```ruby
# Brewfile
brew "git"
cask "github"
cask "visual-studio-code"
cask "google-chrome"
cask "iterm2"   # optional
```

Trade-off: simpler install, but loses the per-app structured output and verify-after-install pattern that the current script provides. Could be offered as an alternative fast path.

### Dotfile management

The runbooks touch several dotfiles (`~/.zshrc`, `~/.bash_profile`, `~/.zprofile`). Currently, each script appends to them independently. As the number of tools that modify dotfiles grows, consider:
- A managed section marker (like conda's `>>> conda initialize >>>`) for all runbook-managed blocks
- A `dotfiles/` directory with template fragments that get assembled
- Integration with a dotfile manager like `chezmoi` or `stow`

### Shell-agnostic environment activation

The current setup requires shell-specific init hooks. Fish, nushell, and other modern shells aren't covered. If the user adopts a new shell, they need to manually figure out the init command and test it. The `verify-shell-integration` scripts could be extended to detect all installed shells and test them dynamically.

### Windows: winget export/import

Similar to Brewfile, `winget export` can dump installed packages to a JSON file and `winget import` can restore them. Could provide a faster setup path alongside the current script approach.
