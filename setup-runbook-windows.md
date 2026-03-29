# Windows Machine Setup Runbook
> **How to use this with Claude Code:** Open Claude Code in your terminal, point it at this file, and say: *"Follow the setup runbook at setup-runbook-windows.md. Walk me through each section, automate what you can, and tell me when I need to do something manually. Be aware we may be using a machine where some components are already installed. And may be installed through an alternative means than described in the runbook. We need to decide how to handle them."*

> 📝 **Quick check:** Run `scripts/windows/verify-installed.ps1` to see what's already installed before starting:
> ```bash
> powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/verify-installed.ps1
> ```

---

## Sections 1–6 — Install Dev Tools

Installs Git for Windows, GitHub Desktop, VS Code, Chrome, Windows Terminal, and PowerShell 7 via a single idempotent script. Already-installed apps are skipped.

### Run the install script
```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows/install-apps.ps1
```

> ⚠️ **Manual step:** After the script completes, close and reopen your terminal so PATH changes take effect.

> 📝 **What the script installs:**
>
> | App | Winget ID | Verify command |
> |-----|-----------|----------------|
> | Git for Windows | `Git.Git` | `git --version` |
> | GitHub Desktop | `GitHub.GitHubDesktop` | *(GUI app)* |
> | Visual Studio Code | `Microsoft.VisualStudioCode` | `code --version` |
> | Google Chrome | `Google.Chrome.EXE` | *(GUI app)* |
> | Windows Terminal | `Microsoft.WindowsTerminal` | *(GUI app)* |
> | PowerShell 7 | `Microsoft.PowerShell` | `pwsh --version` |

> 📝 **Notes:**
> - **Git for Windows** gives you: `git` CLI in any terminal, Git Bash (right-click → "Open Git Bash here"), and Git Credential Manager.
> - **VS Code + micromamba:** Once the `node1` environment is created (see Section 8), select it as your Python interpreter in VS Code — open a `.py` file, click the interpreter selector in the status bar, and choose `node1`.
> - **PowerShell 7** installs alongside 5.1 — it does not replace it. In Windows Terminal it appears as "PowerShell" (vs "Windows PowerShell"). Launch with `pwsh`.

---

## Section 7 — (Optional) Oh My Posh — Custom Prompt

> 🤔 **Claude Code: Ask the user before proceeding with this step.**
> *"Would you like to install Oh My Posh? It customizes your terminal prompt to show useful context like the current git branch, conda environment name, Node version, and more. It requires a Nerd Font to display icons correctly. Install it? (yes/no)"*

If yes, install Oh My Posh:
```powershell
winget install -e --id JanDeLaater.OhMyPosh --silent
```

Then install a Nerd Font (JetBrains Mono recommended):
```powershell
oh-my-posh font install JetBrainsMono
```

> ⚠️ **Manual step:** After installing the font, open Windows Terminal → Settings → your PowerShell profile → Appearance, and set the font to **JetBrainsMono Nerd Font**. Then add Oh My Posh to your PowerShell profile:
> ```powershell
> # Add this line to your $PROFILE file:
> oh-my-posh init pwsh | Invoke-Expression
> ```

---

## Section 8 — Micromamba & Environments

> 📘 **See [conda-env-runbook.md](conda-env-runbook.md)** for all steps related to installing Micromamba, removing Conda (if present), shell configuration, and creating the `node1` environment. This was separated into its own runbook due to the number of platform-specific workarounds involved.

---

## Post-Setup Manual Checklist

> ⚠️ **Manual step:** These GUI apps need manual sign-in/configuration after all automated setup is complete:
> - **GitHub Desktop** — launch from Start Menu, sign in with GitHub. Git Credential Manager (from Git for Windows) handles credential storage.
> - **Chrome** — launch from Start Menu, sign in with Google to restore bookmarks, extensions, and passwords.
> - **Windows Terminal** — launch from Start Menu. Optionally set as default terminal in Settings → System → For developers → Terminal.

---

## Notes & Known Issues

| Issue | Fix |
|---|---|
| Execution policy blocks scripts | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| `gh` auth needed after install | Run `gh auth login` manually |
| Micromamba issues | See [conda-env-runbook.md](conda-env-runbook.md) — Notes & Known Issues |

---

## Status Tracker

> ⚠️ **Claude Code note:** Do NOT track status in this file — it lives in git and is shared across machines. Instead, create/update a local checklist at `~/Documents/runbook-status/setup-runbook-windows.md`. At the start of each run:
> 1. Create the directory and file if they don't exist (use the template below).
> 2. Reset all checkboxes to `[ ]`.
> 3. Check off items as each step completes.

<details>
<summary>Checklist template</summary>

```markdown
# setup-runbook-windows status

- [ ] Dev tools installed (install-apps.ps1)
- [ ] Oh My Posh installed (if chosen)
- [ ] Oh My Posh font configured (if chosen, manual)
- [ ] Micromamba setup complete (see conda-env-runbook.md)
- [ ] GitHub Desktop signed in (manual)
- [ ] Chrome signed in (manual)
- [ ] Windows Terminal set as default (manual, optional)
```

</details>
