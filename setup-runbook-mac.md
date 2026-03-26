# macOS Machine Setup Runbook

> **How to use this with Claude Code:** Open Claude Code in your terminal, point it at this file, and say: *"Follow the setup runbook at setup-runbook-mac.md. Walk me through each section, automate what you can, and tell me when I need to do something manually. Be aware we may be using a machine where some components are already installed. And may be installed through an alternative means than described in the runbook. We need to decide how to handle them."*

---

## Section 1 — Homebrew

**Installs:** The Homebrew package manager, which is used to install everything else in this runbook.

### 1a. Install Homebrew

```zsh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

> ⚠️ **Manual step:** The Homebrew installer is interactive — it will show what it plans to do and ask for confirmation. The user must run this themselves or approve the install when prompted.

> 📝 **Note:** On a fresh macOS install, this will also trigger installation of the **Xcode Command Line Tools** (includes Apple Git, compilers, and system headers). This can take several minutes.

### 1b. Add Homebrew to PATH

On Apple Silicon Macs, Homebrew installs to `/opt/homebrew` which is not on PATH by default. The installer will print instructions — typically you need to add this to `~/.zprofile`:

```zsh
eval "$(/opt/homebrew/bin/brew shellenv)"
```

> ⚠️ **Claude Code note:** After install, check if `brew` is on PATH. If not, add the `eval` line to `~/.zprofile` and source it. On Intel Macs, Homebrew installs to `/usr/local` and is usually already on PATH.

### 1c. Verify

```zsh
brew --version
```

---

## Section 2 — Git (via Homebrew)

**Installs:** The latest Git, replacing the older Apple Git that ships with Xcode CLI tools.

### 2a. Install via Homebrew

```zsh
brew install git
```

### 2b. Verify

```zsh
git --version
which git
```

> ⚠️ **Claude Code note:** After install, verify that `which git` points to `/opt/homebrew/bin/git` (Apple Silicon) or `/usr/local/bin/git` (Intel), **not** `/usr/bin/git` (Apple Git). If it still shows Apple Git, the user may need to open a new terminal so the updated PATH takes effect. Homebrew's paths should take precedence over `/usr/bin` in the default macOS PATH.

> 📝 **What you get:**
> - Latest `git` CLI available in any terminal
> - **Git Credential Manager** is not included — GitHub credentials are handled by `gh auth login` or by GitHub Desktop's built-in credential management

---

## Section 3 — GitHub Desktop

### 3a. Install via Homebrew

```zsh
brew install --cask github
```

### 3b. Verify

> ⚠️ **Manual step:** GitHub Desktop is a GUI app — after install, launch it from the Applications folder (or Spotlight) and sign in with your GitHub account.

---

## Section 4 — Visual Studio Code

### 4a. Install via Homebrew

```zsh
brew install --cask visual-studio-code
```

### 4b. Verify

```zsh
code --version
```

> ⚠️ **Claude Code note:** If `code` is not found after install, the user needs to install the shell command. Open VS Code → press `Cmd+Shift+P` → type "Shell Command: Install 'code' command in PATH" → run it. Then open a new terminal.

> 📝 **VS Code + Conda integration:** Once the `node1` environment is created (see conda-env-runbook.md), you can select it as your Python interpreter inside VS Code. Open any `.py` file, click the interpreter selector in the bottom status bar, and choose `node1` from the list.

---

## Section 5 — Google Chrome

### 5a. Install via Homebrew

```zsh
brew install --cask google-chrome
```

### 5b. Verify

> ⚠️ **Manual step:** Launch Chrome from the Applications folder and sign in with your Google account to restore bookmarks, extensions, and saved passwords.

---

## Section 6 — iTerm2 (Optional)

> 🤔 **Claude Code: Ask the user before proceeding with this step.**
> *"Would you like to install iTerm2? It's a popular terminal replacement for macOS with features like split panes, search, autocomplete, and better customization. The built-in Terminal.app works fine for most tasks. Install it? (yes/no)"*

### 6a. Install via Homebrew

```zsh
brew install --cask iterm2
```

### 6b. Verify

> ⚠️ **Manual step:** Launch iTerm2 from the Applications folder. If you installed a Nerd Font (e.g., via Oh My Zsh or Starship), set it in iTerm2 → Settings → Profiles → Text → Font.

---

## Section 7 — Shell Configuration (zsh)

macOS defaults to zsh — no separate install is needed.

> 🤔 **Claude Code: Ask the user before proceeding.**
> *"Would you like to set up shell customization? Options:*
> *1. **Oh My Zsh** — popular framework with themes, plugins, and a large community*
> *2. **Minimal config** — a lightweight .zshrc with useful defaults (completions, history, prompt) without a framework*
> *3. **Skip** — leave zsh as-is for now"*

### Option A — Oh My Zsh

```zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

> ⚠️ **Manual step:** The Oh My Zsh installer is interactive — the user needs to run it themselves or approve when prompted. After install, customize the theme and plugins by editing `~/.zshrc`. Popular plugins: `git`, `zsh-autosuggestions`, `zsh-syntax-highlighting`.

### Option B — Minimal .zshrc

Add the following to `~/.zshrc`:

```zsh
# History
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS

# Completions
autoload -Uz compinit && compinit

# Useful options
setopt AUTO_CD
setopt CORRECT

# Prompt (simple, shows current directory and git branch)
autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats ' (%b)'
setopt PROMPT_SUBST
PROMPT='%F{blue}%~%f%F{green}${vcs_info_msg_0_}%f %# '
```

> ⚠️ **Claude Code note:** Before writing to `~/.zshrc`, check if it already exists and has content. If it does, append rather than overwrite — conda/micromamba init may have already added lines to it.

---

## Section 8 — Conda, Micromamba & Environments

> 📘 **See [conda-env-runbook.md](conda-env-runbook.md)** for all steps related to installing Miniconda, Micromamba, shell configuration, and creating environments. That runbook covers both Windows and macOS with platform-specific callouts.

---

## Notes & Known Issues

| Issue | Fix |
|---|---|
| `brew` not found after install (Apple Silicon) | Add `eval "$(/opt/homebrew/bin/brew shellenv)"` to `~/.zprofile` and open a new terminal |
| `git --version` shows Apple Git after brew install | Open a new terminal — Homebrew's `/opt/homebrew/bin` should take PATH precedence over `/usr/bin` |
| `code` command not found after VS Code install | Open VS Code → `Cmd+Shift+P` → "Shell Command: Install 'code' command in PATH" |
| Conda/Micromamba issues | See [conda-env-runbook.md](conda-env-runbook.md) — Notes & Known Issues |

---

## Status Tracker

> Claude Code: Reset these checkboxes before starting a new run. Check them off as each step completes.

- [ ] Homebrew installed
- [ ] Homebrew on PATH verified (`brew --version`)
- [ ] Git installed via Homebrew
- [ ] Git verified (`git --version`, correct path)
- [ ] GitHub Desktop installed
- [ ] GitHub Desktop signed in (manual)
- [ ] VS Code installed
- [ ] VS Code verified (`code --version`)
- [ ] Chrome installed
- [ ] Chrome signed in (manual)
- [ ] iTerm2 installed (if chosen)
- [ ] Shell configured (zsh)
- [ ] Conda & Micromamba setup complete (see [conda-env-runbook.md](conda-env-runbook.md))
