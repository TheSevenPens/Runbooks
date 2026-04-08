#!/usr/bin/env bash
# remove-micromamba.sh — Remove micromamba and all artifacts on macOS
#
# On macOS this repo uses miniconda, not micromamba, because of a libmamba
# codesign bug on macOS 26 that aborts `micromamba create` during the
# linking phase. See macos_micromamba_debug_runbook.md for root cause.
# This script is the inverse of remove-conda.sh: it removes any existing
# micromamba install so we can switch to miniconda.
#
# Usage:
#   bash remove-micromamba.sh
#
# Actions:
#   1. Uninstall micromamba via brew (if brew-managed)
#   2. Remove standalone binary at ~/.local/bin/micromamba (if present)
#   3. Remove ~/micromamba root prefix and any envs inside it
#   4. Remove the `# >>> mamba initialize >>>` block from ~/.zshrc
#   5. Remove the `# >>> mamba initialize >>>` block from ~/.bash_profile
#   6. Verify removal
#
# Output: Structured lines prefixed with OK / WARN / SKIP / INFO / FAIL
# Exit code: 0 on success, 1 on failure

set -euo pipefail

FAIL_COUNT=0
MAMBA_ROOT="$HOME/micromamba"
STANDALONE_BIN="$HOME/.local/bin/micromamba"

# --- Pre-flight: Is micromamba installed anywhere? ---

mm_found=false
if command -v brew &>/dev/null && brew list micromamba &>/dev/null 2>&1; then
    mm_found=true
fi
if command -v micromamba &>/dev/null; then
    mm_found=true
fi
if [[ -x "$STANDALONE_BIN" ]]; then
    mm_found=true
fi
if [[ -d "$MAMBA_ROOT" ]]; then
    mm_found=true
fi

if [[ "$mm_found" == false ]]; then
    # Still check for stale init blocks — a prior removal may have left them
    if grep -q '# >>> mamba initialize >>>' "$HOME/.zshrc" 2>/dev/null \
       || grep -q '# >>> mamba initialize >>>' "$HOME/.bash_profile" 2>/dev/null; then
        echo "INFO: micromamba binary not found but stale init blocks detected — cleaning up"
    else
        echo "SKIP: Micromamba does not appear to be installed"
        echo ""
        echo "RESULT: Nothing to remove"
        exit 0
    fi
else
    echo "INFO: Micromamba installation detected — starting removal"
fi

# --- Step 1: Uninstall via brew ---

echo ""
echo "--- Step 1: Uninstall via brew ---"
if command -v brew &>/dev/null; then
    if brew list micromamba &>/dev/null 2>&1; then
        if brew uninstall micromamba 2>&1 | tail -3; then
            echo "OK: micromamba uninstalled via brew"
        else
            echo "WARN: brew uninstall micromamba returned non-zero"
        fi
    else
        echo "SKIP: micromamba not installed via brew"
    fi
else
    echo "SKIP: brew not available"
fi

# --- Step 2: Remove standalone binary ---

echo ""
echo "--- Step 2: Remove standalone binary ---"
if [[ -e "$STANDALONE_BIN" ]]; then
    if rm -f "$STANDALONE_BIN" 2>/dev/null; then
        echo "OK: Removed $STANDALONE_BIN"
    else
        echo "WARN: Could not remove $STANDALONE_BIN"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "SKIP: No standalone binary at $STANDALONE_BIN"
fi

# --- Step 3: Remove ~/micromamba root prefix ---

echo ""
echo "--- Step 3: Remove ~/micromamba root prefix ---"
if [[ -d "$MAMBA_ROOT" ]]; then
    env_count=$(find "$MAMBA_ROOT/envs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$env_count" -gt 0 ]]; then
        echo "WARN: $MAMBA_ROOT contains $env_count environment(s) — removing them too"
    fi
    if rm -rf "$MAMBA_ROOT" 2>/dev/null; then
        echo "OK: Removed $MAMBA_ROOT"
    else
        echo "WARN: Could not fully remove $MAMBA_ROOT"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "SKIP: $MAMBA_ROOT does not exist"
fi

# --- Step 4: Clean .zshrc ---

echo ""
echo "--- Step 4: Clean mamba init from .zshrc ---"
zshrc="$HOME/.zshrc"
if [[ -f "$zshrc" ]]; then
    if grep -q '# >>> mamba initialize >>>' "$zshrc" 2>/dev/null; then
        sed -i '' '/# >>> mamba initialize >>>/,/# <<< mamba initialize <<</d' "$zshrc"
        echo "OK: Removed mamba init block from .zshrc"
    else
        echo "SKIP: .zshrc has no mamba init block"
    fi
else
    echo "SKIP: .zshrc not found"
fi

# --- Step 5: Clean .bash_profile ---

echo ""
echo "--- Step 5: Clean mamba init from .bash_profile ---"
bash_profile="$HOME/.bash_profile"
if [[ -f "$bash_profile" ]]; then
    if grep -q '# >>> mamba initialize >>>' "$bash_profile" 2>/dev/null; then
        sed -i '' '/# >>> mamba initialize >>>/,/# <<< mamba initialize <<</d' "$bash_profile"
        echo "OK: Removed mamba init block from .bash_profile"
    else
        echo "SKIP: .bash_profile has no mamba init block"
    fi
else
    echo "SKIP: .bash_profile not found"
fi

# --- Step 6: Verify ---

echo ""
echo "--- Verification ---"
if command -v micromamba &>/dev/null; then
    mm_path_now="$(command -v micromamba)"
    echo "WARN: micromamba command still resolves to $mm_path_now — open a new terminal to confirm removal"
else
    echo "OK: micromamba command no longer available in this shell"
fi

if [[ -d "$MAMBA_ROOT" ]]; then
    echo "WARN: $MAMBA_ROOT still exists"
else
    echo "OK: $MAMBA_ROOT removed"
fi

# --- Summary ---

echo ""
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "RESULT: Removal completed with $FAIL_COUNT issue(s)"
    exit 1
else
    echo "RESULT: Micromamba removal complete"
    exit 0
fi
