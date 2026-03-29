# Windows Machine Setup Runbook
> **How to use this with Claude Code:** Open Claude Code in your terminal, point it at this file, and say: *"Follow the setup runbook at setup-runbook-windows.md. Walk me through each section, automate what you can, and tell me when I need to do something manually. Be aware we may be using a machine where some components are already installed. And may be installed through an alternative means than described in the runbook. We need to decide how to handle them."*

---

## Section 1 — Git for Windows

**Installs:** Git CLI, Git Bash terminal, Git Credential Manager, and Explorer shell integration.

### 1a. Install via Winget
```powershell
winget install -e --id Git.Git --silent
```

### 1b. Verify
```powershell
git --version
```

> ⚠️ **Manual step:** After install, close and reopen your terminal so the updated PATH takes effect.

> 📝 **What you get:**
> - `git` CLI available in any terminal (PowerShell, CMD, Git Bash)
> - **Git Bash** — right-click any folder → "Open Git Bash here"
> - **Git Credential Manager** — handles GitHub credential storage automatically (works with `gh` too)

---

## Section 2 — GitHub Desktop

### 2a. Install via Winget
```powershell
winget install -e --id GitHub.GitHubDesktop --silent
```

### 2b. Verify
> ⚠️ **Manual step:** GitHub Desktop is a GUI app — after install, launch it from the Start Menu and sign in with your GitHub account. Git Credential Manager (installed with Git for Windows in Section 1) will handle credential storage automatically.

---

## Section 3 — Visual Studio Code

### 3a. Install via Winget
```powershell
winget install -e --id Microsoft.VisualStudioCode --silent
```

### 3b. Verify
```powershell
code --version
```

> ⚠️ **Manual step:** After install, reopen your terminal so `code` is available on PATH.

> 📝 **VS Code + Conda integration:** Once the `node1` environment is created (see Section 8), you can select it as your Python interpreter inside VS Code. Open any `.py` file, click the interpreter selector in the bottom status bar, and choose `node1` from the list. VS Code will then use that environment's Python for linting, IntelliSense, and the integrated terminal.

---

## Section 4 — Google Chrome

### 4a. Install via Winget
```powershell
winget install -e --id Google.Chrome --silent
```

### 4b. Verify
> ⚠️ **Manual step:** Launch Chrome from the Start Menu and sign in with your Google account to restore bookmarks, extensions, and saved passwords.

---

## Section 5 — Windows Terminal

A modern tabbed terminal that replaces the default PowerShell and CMD windows. Supports profiles for PowerShell, Git Bash, conda, and more.

### 5a. Install via Winget
```powershell
winget install -e --id Microsoft.WindowsTerminal --silent
```

### 5b. Verify
> ⚠️ **Manual step:** Launch Windows Terminal from the Start Menu. It should appear as the default terminal going forward. You can set it as the system default terminal in Settings → System → For developers → Terminal.

---

## Section 6 — PowerShell 7

Windows ships with PowerShell 5.1 by default. PowerShell 7 is the modern, cross-platform version with better performance, improved error handling, and active development.

### 6a. Install via Winget
```powershell
winget install -e --id Microsoft.PowerShell --silent
```

### 6b. Verify
```powershell
pwsh --version
```

> 📝 **Note:** PowerShell 7 installs alongside 5.1 — it does not replace it. In Windows Terminal it will appear as a new profile called "PowerShell" (vs the older "Windows PowerShell"). Use `pwsh` to launch it from any terminal.

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

## Notes & Known Issues

| Issue | Fix |
|---|---|
| Execution policy blocks scripts | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| `gh` auth needed after install | Run `gh auth login` manually |
| Micromamba issues | See [conda-env-runbook.md](conda-env-runbook.md) — Notes & Known Issues |

---

## Status Tracker
> Claude Code: Reset these checkboxes before starting a new run. Check them off as each step completes.

- [ ] Git for Windows installed
- [ ] Git for Windows verified (`git --version`)
- [ ] GitHub Desktop installed
- [ ] GitHub Desktop signed in (manual)
- [ ] VS Code installed
- [ ] VS Code verified (`code --version`)
- [ ] Chrome installed
- [ ] Chrome signed in (manual)
- [ ] Windows Terminal installed
- [ ] PowerShell 7 installed
- [ ] PowerShell 7 verified (`pwsh --version`)
- [ ] Oh My Posh installed (if chosen)
- [ ] Oh My Posh font configured (if chosen, manual)
- [ ] Micromamba setup complete (see [conda-env-runbook.md](conda-env-runbook.md))
