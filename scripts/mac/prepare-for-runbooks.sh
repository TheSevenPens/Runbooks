#!/usr/bin/env bash
# prepare-for-runbooks.sh — Prepare a macOS machine to run the runbooks
#
# Usage:
#   bash prepare-for-runbooks.sh
#
# Installs Claude Code CLI and ensures it is on the user PATH.
# Designed to be idempotent.
#
# Output: Structured lines prefixed with OK / SKIP / FAIL / INFO
# Exit code: 0 on success, 1 on any failure

set -euo pipefail

FAIL_COUNT=0
CLAUDE_BIN="$HOME/.local/bin"
CLAUDE_EXE="$CLAUDE_BIN/claude"

# --- Detect user's shell and config file ---
USER_SHELL="$(basename "$SHELL")"
case "$USER_SHELL" in
    zsh)  SHELL_RC="$HOME/.zshrc" ;;
    bash) SHELL_RC="$HOME/.bash_profile" ;;
    *)    SHELL_RC="$HOME/.profile" ;;
esac

# --- Install Claude Code ---
if [ -x "$CLAUDE_EXE" ]; then
    version=$("$CLAUDE_EXE" --version 2>&1 || true)
    echo "SKIP: Claude Code already installed — $version"
else
    echo "INFO: Installing Claude Code..."
    if ! curl -fsSL https://claude.ai/install.sh | sh; then
        echo "FAIL: Claude Code install failed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    elif [ ! -x "$CLAUDE_EXE" ]; then
        echo "FAIL: Installation appeared to succeed but $CLAUDE_EXE was not found"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo "OK: Claude Code installed"
    fi
fi

# --- Ensure Claude bin directory is on PATH ---
if echo "$PATH" | tr ':' '\n' | grep -qx "$CLAUDE_BIN"; then
    echo "SKIP: $CLAUDE_BIN already on PATH"
else
    echo "INFO: Adding $CLAUDE_BIN to PATH in $SHELL_RC..."

    # Append the PATH export if not already in the rc file
    PATH_LINE="export PATH=\"$CLAUDE_BIN:\$PATH\""
    if ! grep -qF "$CLAUDE_BIN" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "# Claude Code CLI" >> "$SHELL_RC"
        echo "$PATH_LINE" >> "$SHELL_RC"
        echo "OK: PATH updated in $SHELL_RC"
    else
        echo "SKIP: $CLAUDE_BIN already referenced in $SHELL_RC"
    fi

    # Update current session so the verify step works
    export PATH="$CLAUDE_BIN:$PATH"
fi

# --- Verify claude is callable ---
if [ -x "$CLAUDE_EXE" ]; then
    if version=$("$CLAUDE_EXE" --version 2>&1); then
        echo "OK: Claude Code is ready — $version"
    else
        echo "WARN: Claude Code is installed but could not be executed — open a new terminal"
    fi
fi

# --- Summary ---
echo ""
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "RESULT: $FAIL_COUNT failure(s)"
    exit 1
else
    echo "RESULT: Ready — open a new terminal and run: claude"
    exit 0
fi
