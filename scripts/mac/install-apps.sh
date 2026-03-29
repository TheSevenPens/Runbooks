#!/usr/bin/env bash
# install-apps.sh — Install macOS dev tools via Homebrew (idempotent)
#
# Usage:
#   bash install-apps.sh
#
# Actions:
#   For each app: check if already installed, install if missing, verify afterward.
#
# Apps installed:
#   - Git (git)
#   - GitHub Desktop (github) [cask]
#   - Visual Studio Code (visual-studio-code) [cask]
#   - Google Chrome (google-chrome) [cask]
#   - GitHub CLI (gh)
#
# Output: Structured lines prefixed with OK / SKIP / FAIL / INFO
# Exit code: 0 on success, 1 on any failure

set -euo pipefail

FAIL_COUNT=0

# --- Pre-flight: Homebrew must be available ---

if ! command -v brew &>/dev/null; then
    echo "FAIL: brew not found — install Homebrew first (see Section 1 of setup-runbook-mac.md)"
    exit 1
fi

# --- App definitions ---
# Format: "type|brew_id|display_name|verify_cmd|verify_flag|canonical_path|app_path"
# type: formula or cask
# verify_cmd: CLI command to check (empty string if GUI-only)
# canonical_path: fallback path if verify_cmd isn't on PATH yet
# app_path: /Applications/*.app path for GUI apps installed outside brew

APPS=(
    "formula|git|Git|git|--version|/opt/homebrew/bin/git|"
    "cask|github|GitHub Desktop||||/Applications/GitHub Desktop.app"
    "cask|visual-studio-code|Visual Studio Code|code|--version|/usr/local/bin/code|/Applications/Visual Studio Code.app"
    "cask|google-chrome|Google Chrome||||/Applications/Google Chrome.app"
    "formula|gh|GitHub CLI|gh|--version|/opt/homebrew/bin/gh|"
)

# --- Helpers ---

is_brew_installed() {
    local type="$1"
    local brew_id="$2"

    if [[ "$type" == "cask" ]]; then
        brew list --cask "$brew_id" &>/dev/null
    else
        brew list "$brew_id" &>/dev/null
    fi
}

resolve_exe() {
    local verify_cmd="$1"
    local canonical_path="$2"

    if [[ -z "$verify_cmd" ]]; then
        echo ""
        return
    fi

    local exe_path
    exe_path="$(command -v "$verify_cmd" 2>/dev/null || true)"

    # Canonical path fallback (matches Windows pattern for fresh installs)
    if [[ -z "$exe_path" && -n "$canonical_path" && -x "$canonical_path" ]]; then
        exe_path="$canonical_path"
    fi

    echo "$exe_path"
}

get_version() {
    local exe_path="$1"
    local verify_flag="$2"

    if [[ -n "$exe_path" && -n "$verify_flag" ]]; then
        "$exe_path" "$verify_flag" 2>&1 | head -1 || true
    fi
}

# --- Main loop ---

for app_def in "${APPS[@]}"; do
    IFS='|' read -r type brew_id name verify_cmd verify_flag canonical_path app_path <<< "$app_def"

    echo ""
    echo "--- ${name} (${type}: ${brew_id}) ---"

    already_installed=false

    # CLI-verifiable apps: check command first (faster than brew list)
    if [[ -n "$verify_cmd" ]]; then
        exe_path="$(resolve_exe "$verify_cmd" "$canonical_path")"
        if [[ -n "$exe_path" ]]; then
            version="$(get_version "$exe_path" "$verify_flag")"
            echo "SKIP: ${name} already installed — ${version}"
            already_installed=true
        fi
    fi

    # GUI apps: check /Applications bundle path (catches non-brew installs)
    if [[ "$already_installed" == false && -n "$app_path" && -d "$app_path" ]]; then
        echo "SKIP: ${name} already installed (${app_path})"
        already_installed=true
    fi

    # Fallback: check brew list
    if [[ "$already_installed" == false ]]; then
        if is_brew_installed "$type" "$brew_id"; then
            echo "SKIP: ${name} already installed (brew)"
            already_installed=true
        fi
    fi

    if [[ "$already_installed" == true ]]; then
        continue
    fi

    # Install
    echo "INFO: Installing ${name}..."
    if [[ "$type" == "cask" ]]; then
        install_output="$(brew install --cask "$brew_id" 2>&1)" || {
            echo "FAIL: ${name} install failed"
            echo "  ${install_output}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            continue
        }
    else
        install_output="$(brew install "$brew_id" 2>&1)" || {
            echo "FAIL: ${name} install failed"
            echo "  ${install_output}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            continue
        }
    fi
    echo "OK: ${name} installed"

    # Verify (CLI tools only)
    if [[ -n "$verify_cmd" ]]; then
        # Rehash to pick up newly installed commands
        hash -r 2>/dev/null || true

        exe_path="$(resolve_exe "$verify_cmd" "$canonical_path")"
        if [[ -n "$exe_path" ]]; then
            version="$(get_version "$exe_path" "$verify_flag")"
            echo "OK: ${name} verified — ${version}"
        else
            echo "WARN: ${name} installed but '${verify_cmd}' not found on PATH — open a new terminal"
        fi
    fi
done

# --- Summary ---

echo ""
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "RESULT: ${FAIL_COUNT} install(s) failed"
    exit 1
else
    echo "RESULT: All apps installed"
    echo "INFO: Open a new terminal for PATH changes to take effect"
    exit 0
fi
