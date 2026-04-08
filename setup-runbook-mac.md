# macOS Machine Setup Runbook

> **How to use this with Claude Code:** Open Claude Code in your terminal, point it at this file, and say: *"Follow the setup runbook at setup-runbook-mac.md. Walk me through each section, automate what you can, and tell me when I need to do something manually. Be aware we may be using a machine where some components are already installed. And may be installed through an alternative means than described in the runbook. We need to decide how to handle them."*

> 📝 **Quick check:** Run `scripts/mac/verify-prerequisites.sh` to see what's already installed before starting:
> ```bash
> bash scripts/mac/verify-prerequisites.sh
> ```

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

## Sections 2–5 — Install Dev Tools

Installs Git, GitHub Desktop, VS Code, Chrome, and GitHub CLI declaratively from `apps/Brewfile`.

### Run the Brewfile bundle (standard path)

```bash
bash scripts/mac/bundle-install.sh
```

This reads `apps/Brewfile` and installs all packages via `brew bundle`. The Brewfile is the canonical source of truth for what gets installed on a machine — prefer this over the per-app script.

> 📝 **Alternative: per-app script.** `scripts/mac/install-apps.sh` loops app-by-app with structured per-app status output. Useful for debugging or when you want to know exactly which app failed. Otherwise use the bundle.

> ⚠️ **Manual step:** After the script completes, open a new terminal so PATH changes take effect.

> ⚠️ **Known pitfall: brew cask adoption of pre-existing GUI apps.** If Chrome, VS Code, or GitHub Desktop are already installed on the machine by a different method (direct download, manual install, pre-existing user data), `brew bundle` will try to "adopt" the existing app bundle and fail:
> - **Chrome / VS Code** — brew's adoption runs `sudo chmod -R a+rX` on the app, which cannot prompt for a password in a non-TTY context and fails with `sudo: a terminal is required to read the password`.
> - **GitHub Desktop** — brew tries to write the `com.apple.metadata:kMDItemAlternateNames` xattr on a file inside the bundle, which hits SIP / entitlement protection and fails with `xattr: Operation not permitted`.
>
> If this happens, the fix is to **delete the pre-existing app bundle** and re-run the bundle install. Deleting requires sudo when the app is owned by root:
> ```zsh
> sudo rm -rf "/Applications/Visual Studio Code.app" "/Applications/Google Chrome.app"
> ```
> GitHub Desktop is often already gone by the time the error surfaces (brew's failed adoption purges its own attempted install). After deletion, re-run `bundle-install.sh` and the apps will install cleanly as fresh brew-managed casks.

> 📝 **What the script installs:**
>
> | App | Brew ID | Type | Verify command |
> |-----|---------|------|----------------|
> | Git | `git` | formula | `git --version` |
> | GitHub Desktop | `github` | cask | *(GUI app)* |
> | Visual Studio Code | `visual-studio-code` | cask | `code --version` |
> | Google Chrome | `google-chrome` | cask | *(GUI app)* |
| GitHub CLI | `gh` | formula | `gh --version` |

> 📝 **Notes:**
> - **Git via Homebrew** replaces the older Apple Git that ships with Xcode CLI tools. Verify that `which git` points to `/opt/homebrew/bin/git` (Apple Silicon) or `/usr/local/bin/git` (Intel), **not** `/usr/bin/git`.
> - **VS Code:** If `code` is not found after install, open VS Code → `Cmd+Shift+P` → "Shell Command: Install 'code' command in PATH" → run it.
> - **VS Code + micromamba:** Once the `node1` environment is created (see conda-env-runbook.md), select it as your Python interpreter — open a `.py` file, click the interpreter selector in the status bar, and choose `node1`.

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

> ⚠️ **Claude Code note:** Before writing to `~/.zshrc`, check if it already exists and has content. If it does, append rather than overwrite — micromamba init may have already added lines to it.

---

## Section 8 — Micromamba & Environments

> 📘 **See [conda-env-runbook.md](conda-env-runbook.md)** for all steps related to installing the environment manager, shell configuration, and creating environments. That runbook covers both platforms — on Windows it installs **micromamba**, on macOS it installs **miniconda** (because of a libmamba codesign bug on macOS 26; see the platform policy table at the top of that runbook).

---

## Post-Setup Manual Checklist

> ⚠️ **Manual step:** These sign-ins can't be automated. Complete them when convenient.

- [ ] **GitHub Desktop** — Launch from Applications, sign in with your GitHub account
- [ ] **Chrome** — Launch from Applications, sign in with your Google account to restore bookmarks, extensions, and saved passwords
- [ ] **iTerm2** — If installed, launch and configure Nerd Font if desired

---

## Notes & Known Issues

| Issue | Fix |
|---|---|
| `brew` not found after install (Apple Silicon) | Add `eval "$(/opt/homebrew/bin/brew shellenv)"` to `~/.zprofile` and open a new terminal |
| `git --version` shows Apple Git after brew install | Open a new terminal — Homebrew's `/opt/homebrew/bin` should take PATH precedence over `/usr/bin` |
| `code` command not found after VS Code install | Open VS Code → `Cmd+Shift+P` → "Shell Command: Install 'code' command in PATH" |
| `brew bundle` fails adopting an already-installed cask (Chrome/VS Code/GitHub Desktop) | Pre-existing app bundles cannot be adopted: Chrome/VS Code fail on `sudo chmod` (no TTY for password), GitHub Desktop fails on an xattr write (SIP). Delete the pre-existing app with `sudo rm -rf /Applications/<App>.app` and re-run `bundle-install.sh`. |
| Miniconda / env issues | See [conda-env-runbook.md](conda-env-runbook.md) — Notes & Known Issues |
| Why is macOS using miniconda instead of micromamba? | libmamba codesign bug on macOS 26. Root cause and minimal repro in [macos_micromamba_debug_runbook.md](macos_micromamba_debug_runbook.md) Section 15. The setup runbook already removes micromamba if present — see [conda-env-runbook.md](conda-env-runbook.md) Section 0. |

---

## Status Tracker

> Claude Code: Reset these checkboxes before starting a new run. Check them off as each step completes.

- [ ] Homebrew installed
- [ ] Homebrew on PATH verified (`brew --version`)
- [ ] Dev tools installed via `install-apps.sh` (Git, GitHub Desktop, VS Code, Chrome, gh)
- [ ] Git verified (`git --version`, correct path — not Apple Git)
- [ ] VS Code verified (`code --version`)
- [ ] iTerm2 installed (if chosen)
- [ ] Shell configured (zsh)
- [ ] Miniconda setup complete (see [conda-env-runbook.md](conda-env-runbook.md))
- [ ] GitHub Desktop signed in (manual)
- [ ] Chrome signed in (manual)
