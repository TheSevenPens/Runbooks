# Archived Scripts

These bash scripts were the original macOS automation scripts. They were replaced during two migrations:

1. **PowerShell 7 migration (2026-04-09):** All active macOS scripts were rewritten as `.ps1` files in `scripts/mac/` to standardize on PowerShell across both platforms.

2. **mise migration (2026-04-09):** The conda/micromamba environment scripts became obsolete when the repo switched to mise for tool version management.

## Replaced by PowerShell ports

| Archived script | Replacement |
|-----------------|-------------|
| `prepare-for-runbooks.sh` | `scripts/mac/prepare-for-runbooks.ps1` |
| `bundle-install.sh` | `scripts/mac/bundle-install.ps1` |
| `install-apps.sh` | `scripts/mac/install-apps.ps1` |
| `verify-prerequisites.sh` | `scripts/mac/verify-prerequisites.ps1` |

## Obsolete (mise migration)

| Archived script | Why |
|-----------------|-----|
| `create-env.sh` | Replaced by `mise use -g` |
| `verify-shell-integration.sh` | Trivial with mise (no shell hooks needed) |
| `remove-conda.sh` | One-time cleanup, already executed |
| `remove-micromamba.sh` | One-time cleanup, already executed |

## Debug artifacts

| File | Why |
|------|-----|
| `repro_posix_spawn.c` | Reproducer for the libmamba codesign bug (see `mac-micromamba-debug-runbook.md`) |
