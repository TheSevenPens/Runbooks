# Runbooks

Machine setup runbooks designed to be executed by [Claude Code](https://claude.ai/code). They contain automation instructions, manual step callouts, and Claude-specific notes that guide you through setting up a development machine from scratch.

## Bootstrap

On a fresh machine, run the bootstrap script to install Claude Code, Git, and clone this repo. Then launch Claude Code and follow the runbooks.

### Windows

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/TheSevenPens/Runbooks/master/bootstrap/bootstrap-windows.ps1 | iex
```

This installs Git and Claude Code, then clones the repo to `~/Documents/GitHub/Runbooks`.

### macOS

*Coming soon.*

## After bootstrap

```sh
cd ~/Documents/GitHub/Runbooks
claude
```

Then tell Claude which runbook to follow:

- **Machine setup:** `setup-runbook-windows.md` or `setup-runbook-mac.md`
- **Tool versions (mise):** `mise-env-runbook.md`
- **Tool versions (conda):** `conda-env-runbook.md`

## Repo details

See [CLAUDE.md](CLAUDE.md) for repo structure, conventions, and instructions for Claude Code.
