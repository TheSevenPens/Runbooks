#!/usr/bin/env bash
# bundle-install.sh — Install macOS dev tools via Homebrew Bundle (Brewfile)
#
# Usage:
#   bash bundle-install.sh
#   bash bundle-install.sh --brewfile ../../apps/Brewfile
#
# Parameters:
#   --brewfile   Path to Brewfile (default: ../../apps/Brewfile relative to script)
#
# Actions:
#   1. Check what's already installed via brew bundle check
#   2. Install missing packages via brew bundle
#   3. Verify each package
#
# This is an alternative to install-apps.sh. Both install the same apps:
#   - install-apps.sh: per-app structured output, verify-after-install
#   - bundle-install.sh: one-shot declarative install via Brewfile
#
# Output: Structured lines prefixed with OK / SKIP / FAIL / INFO / WARN
# Exit code: 0 on success, 1 on failure

set -euo pipefail

FAIL_COUNT=0
BREWFILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --brewfile) BREWFILE="$2"; shift 2 ;;
        *)
            echo "Usage: $0 [--brewfile <path>]"
            exit 2
            ;;
    esac
done

# Default: apps/Brewfile relative to repo root
if [[ -z "$BREWFILE" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    BREWFILE="$SCRIPT_DIR/../../apps/Brewfile"
fi

if [[ ! -f "$BREWFILE" ]]; then
    echo "FAIL: Brewfile not found: $BREWFILE"
    exit 1
fi

BREWFILE="$(cd "$(dirname "$BREWFILE")" && pwd)/$(basename "$BREWFILE")"
echo "INFO: Using Brewfile at $BREWFILE"

# --- Pre-flight ---

if ! command -v brew &>/dev/null; then
    echo "FAIL: brew not found — install Homebrew first"
    exit 1
fi

# --- Check what's already installed ---

echo ""
echo "--- Checking installed packages ---"

check_output="$(brew bundle check --file="$BREWFILE" 2>&1)" && {
    echo "SKIP: All packages already installed"
    echo ""

    # Still verify each entry
    echo "--- Verifying packages ---"
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        read -r type name <<< "$line"
        name="${name//\"/}"
        case "$type" in
            brew)
                if brew list "$name" &>/dev/null; then
                    version="$(brew list "$name" --versions 2>/dev/null | head -1)"
                    echo "OK: $name ($version)"
                else
                    echo "WARN: $name not found"
                fi
                ;;
            cask)
                if brew list --cask "$name" &>/dev/null; then
                    echo "OK: $name (cask)"
                else
                    echo "WARN: $name not found"
                fi
                ;;
        esac
    done < "$BREWFILE"

    echo ""
    echo "RESULT: All packages already installed"
    exit 0
}

echo "INFO: Some packages need installation"
echo "  $check_output"

# --- Install ---

echo ""
echo "--- Installing via brew bundle ---"

if brew bundle --file="$BREWFILE" 2>&1; then
    echo "OK: brew bundle completed"
else
    echo "WARN: brew bundle completed with issues"
fi

# --- Verify ---

echo ""
echo "--- Verifying packages ---"

while IFS= read -r line; do
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
    read -r type name <<< "$line"
    name="${name//\"/}"
    case "$type" in
        brew)
            if brew list "$name" &>/dev/null; then
                version="$(brew list "$name" --versions 2>/dev/null | head -1)"
                echo "OK: $name ($version)"
            else
                echo "FAIL: $name not installed after bundle"
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
            ;;
        cask)
            if brew list --cask "$name" &>/dev/null; then
                echo "OK: $name (cask)"
            else
                echo "FAIL: $name not installed after bundle"
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
            ;;
    esac
done < "$BREWFILE"

# --- Summary ---

echo ""
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "RESULT: Bundle install completed with $FAIL_COUNT issue(s)"
    exit 1
else
    echo "RESULT: All packages installed and verified"
    echo "INFO: Open a new terminal for PATH changes to take effect"
    exit 0
fi
