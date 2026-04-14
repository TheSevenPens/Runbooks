#!/usr/bin/env bash
# bootstrap-mac.sh -- Bootstrap a fresh macOS machine for the Runbooks repo
#
# Usage (one-liner from GitHub):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/TheSevenPens/Runbooks/master/bootstrap/bootstrap-mac.sh)"
#
# Installs Homebrew, PowerShell 7, Claude Code, and clones the Runbooks repo.
# Each step is idempotent -- already-installed tools are skipped.
#
# This is the ONLY bash script in the repo. Everything after bootstrap runs
# under PowerShell 7 (pwsh).
#
# Output: Structured lines prefixed with OK / SKIP / FAIL / INFO
# Exit code: 0 on success, 1 on failure

set -euo pipefail

REPO_URL="https://github.com/TheSevenPens/Runbooks.git"
CLONE_DIR="$HOME/Documents/GitHub/Runbooks"
CLAUDE_BIN="$HOME/.local/bin"
CLAUDE_EXE="$CLAUDE_BIN/claude"
FAIL_COUNT=0

# Detect Apple Silicon vs Intel for Homebrew path
if [[ "$(uname -m)" == "arm64" ]]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi
BREW_EXE="$BREW_PREFIX/bin/brew"

# ---------------------------------------------------------------------------
# Step 1 -- Homebrew
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 1: Homebrew ---"

if command -v brew &>/dev/null; then
    echo "SKIP: Homebrew already installed -- $(brew --version | head -1)"
elif [[ -x "$BREW_EXE" ]]; then
    echo "INFO: Homebrew installed but not on PATH -- adding to current session"
    eval "$($BREW_EXE shellenv)"
    echo "OK: Homebrew available -- $(brew --version | head -1)"
else
    echo "INFO: Installing Homebrew..."
    echo "INFO: This will also install Xcode Command Line Tools (may take several minutes)"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [[ -x "$BREW_EXE" ]]; then
        eval "$($BREW_EXE shellenv)"
        echo "OK: Homebrew installed -- $(brew --version | head -1)"
    else
        echo "FAIL: Homebrew install failed -- $BREW_EXE not found"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

# Ensure brew shellenv is in ~/.zprofile for future shells
ZPROFILE="$HOME/.zprofile"
if [[ -f "$ZPROFILE" ]] && grep -q 'brew shellenv' "$ZPROFILE"; then
    : # already present
elif [[ -x "$BREW_EXE" ]]; then
    echo "" >> "$ZPROFILE"
    echo "# Homebrew" >> "$ZPROFILE"
    echo "eval \"\$($BREW_EXE shellenv)\"" >> "$ZPROFILE"
    echo "OK: Added brew shellenv to $ZPROFILE"
fi

# ---------------------------------------------------------------------------
# Step 2 -- PowerShell 7
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 2: PowerShell 7 ---"

if command -v pwsh &>/dev/null; then
    echo "SKIP: PowerShell 7 already installed -- $(pwsh --version)"
else
    echo "INFO: Installing PowerShell 7 via Homebrew..."
    brew install powershell 2>&1

    if command -v pwsh &>/dev/null; then
        echo "OK: PowerShell 7 installed -- $(pwsh --version)"
    else
        echo "FAIL: PowerShell 7 install failed -- pwsh not found"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

# ---------------------------------------------------------------------------
# Step 3 -- Claude Code
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 3: Claude Code ---"

if [[ -x "$CLAUDE_EXE" ]]; then
    echo "SKIP: Claude Code already installed -- $($CLAUDE_EXE --version 2>&1)"
else
    echo "INFO: Installing Claude Code via official installer..."
    curl -fsSL https://claude.ai/install.sh | sh

    if [[ -x "$CLAUDE_EXE" ]]; then
        echo "OK: Claude Code installed -- $($CLAUDE_EXE --version 2>&1)"
    else
        echo "FAIL: Claude Code install failed -- $CLAUDE_EXE not found"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

# Ensure Claude bin is on PATH for this session
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$CLAUDE_BIN"; then
    export PATH="$CLAUDE_BIN:$PATH"
fi

# ---------------------------------------------------------------------------
# Step 4 -- Git
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 4: Git ---"

if command -v git &>/dev/null; then
    echo "SKIP: Git already available -- $(git --version)"
else
    echo "FAIL: Git not found -- Xcode CLT should have been installed with Homebrew"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# Step 5 -- Clone the repo
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 5: Clone Runbooks repo ---"

if [[ -d "$CLONE_DIR/.git" ]]; then
    echo "SKIP: Repo already cloned at $CLONE_DIR"
else
    mkdir -p "$(dirname "$CLONE_DIR")"
    echo "INFO: Cloning $REPO_URL to $CLONE_DIR..."

    if git clone "$REPO_URL" "$CLONE_DIR" 2>&1; then
        echo "OK: Repo cloned successfully"
    else
        echo "FAIL: git clone failed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "RESULT: $FAIL_COUNT step(s) failed. Review the errors above, then re-run."
else
    echo "RESULT: Bootstrap complete."
    echo ""
    echo "Next steps:"

    # Determine the right claude command
    if command -v claude &>/dev/null; then
        claude_cmd="claude"
    elif [[ -x "$CLAUDE_EXE" ]]; then
        claude_cmd="$CLAUDE_EXE"
        echo "  Note: 'claude' is not on PATH yet. Open a new terminal, or use the full path below."
    else
        claude_cmd="claude"
    fi

    echo "  cd $CLONE_DIR"
    echo "  $claude_cmd"
    echo ""
    echo "  Then tell Claude: \"Follow the setup runbook at mac-setup-runbook.md\""
fi
