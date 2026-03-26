# Futures

Ideas and planned improvements for the runbook system.

---

## Cross-platform support (macOS) — ✅ Implemented

Three-file structure is now in place:

```
setup-runbook-windows.md    — Windows-specific installs & config
setup-runbook-mac.md        — macOS-specific installs & config (brew, zsh, iTerm, etc.)
conda-env-runbook.md        — Shared, with platform-specific callouts where needed
```

The main setup runbooks stay separate because there's almost no tool overlap (winget vs brew, PowerShell vs zsh, registry vs dotfiles). The conda/micromamba runbook is shared because the tools are cross-platform — platform differences are limited to install method, shell init targets, and PATH handling, which can be handled with clearly marked platform sections.

---

## Scriptable steps

Many runbook steps are deterministic and could be extracted into standalone scripts that:
- Are idempotent (safe to re-run)
- Return clear exit codes for success/failure
- Output structured results that Claude Code can parse
- Can be tested and debugged independently of the runbook

### Candidates for extraction

| Script | What it does | Why it's better as a script |
|---|---|---|
| `verify-prerequisites.ps1` | Check if required tools are installed, report versions and missing items | Replaces scattered `--version` checks with a single invocation |
| `fix-user-path.ps1` | Add directories to user PATH, fix REG_EXPAND_SZ type, broadcast WM_SETTINGCHANGE | The registry fix is fiddly and easy to get wrong inline |
| `init-all-shells.ps1` | Run conda/micromamba shell init for all shell types, verify results | The CMD init has a known path-mangling bug that needs post-verification |
| `verify-shell-integration.ps1` | Test conda/micromamba activate across all shells, output results table | Currently manual; a script could test programmatically and report pass/fail |
| `create-env.ps1` | Create a conda environment from a spec, verify all packages | Wraps ToS acceptance, environment creation, and package verification |

### macOS candidates for extraction

| Script | What it does | Why it's better as a script |
|---|---|---|
| `verify-prerequisites.sh` | Check if brew, git, conda, micromamba are installed; report versions, install method (brew vs standalone), and binary paths | Replaces scattered `--version` + `which` checks; catches stale binaries (e.g., old standalone micromamba vs brew) |
| `verify-shell-integration.sh` | Test `conda activate` and `micromamba activate` in zsh and bash, output results table | The correct shell flags are non-obvious (`zsh -i`, `bash -l -i`) and easy to get wrong; a script encodes the right invocation |
| `configure-shared-envs.sh` | Set `envs_dirs` in both conda config and `.mambarc` to a shared directory, verify both tools agree | Fiddly multi-file config that's easy to miss or leave inconsistent |
| `create-env.sh` | Create a conda/micromamba environment from a spec, verify all packages | Wraps ToS acceptance, environment creation, and package verification |
| `migrate-micromamba.sh` | Detect standalone micromamba, install brew version, update shell init blocks, remove old binary | The migration has multiple steps and touching the wrong `.zshrc` block could break things |

### Proposed structure

```
Runbooks/
  setup-runbook-windows.md
  setup-runbook-mac.md
  conda-env-runbook.md
  FUTURES.md
  scripts/
    windows/
      verify-prerequisites.ps1
      fix-user-path.ps1
      init-all-shells.ps1
      verify-shell-integration.ps1
      create-env.ps1
    mac/
      verify-prerequisites.sh
      verify-shell-integration.sh
      configure-shared-envs.sh
      create-env.sh
      migrate-micromamba.sh
```

### Design principles for scripts

- **Idempotent** — running twice produces the same result, no side effects on re-run
- **Exit codes** — 0 for success, non-zero for failure, so Claude Code can branch on results
- **Structured output** — print machine-readable status (e.g., `OK: conda 26.1.1`, `FAIL: micromamba not on PATH`) so Claude Code can parse and report without guessing
- **Parameterized** — accept arguments for paths, env names, package lists so they're reusable
- **No interactivity** — scripts should never prompt; all decisions come from the runbook (or from Claude Code asking the user)

---

## Other improvements

### Environment specs as files
Instead of hardcoding package lists in the runbook, define environments in YAML spec files (e.g., `envs/node1.yml`). This makes it easy to version, diff, and reproduce environments. Both conda and micromamba support `--file` for environment creation.

### Runbook versioning
Add a version or last-updated date to each runbook so it's clear when the instructions were last validated. Stale runbooks are worse than no runbook.

### Post-setup smoke test
A single script that validates the entire setup end-to-end: every tool on PATH, every shell hook working, every environment functional. Run it after completing a runbook to catch anything that was missed.
