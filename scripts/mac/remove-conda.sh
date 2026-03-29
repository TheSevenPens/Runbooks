#!/usr/bin/env bash
# remove-conda.sh — Remove Miniconda/Anaconda and all artifacts on macOS
#
# Usage:
#   bash remove-conda.sh
#
# Actions:
#   1. Back up environments to ~/envs-backup
#   2. Uninstall via brew
#   3. Remove leftover miniconda3 directory
#   4. Remove .condarc
#   5. Clean conda init block from .zshrc
#   6. Clean conda init block from .bash_profile
#   7. Clean stale conda entries from ~/.conda/environments.txt
#   8. Verify removal
#
# Output: Structured lines prefixed with OK / WARN / SKIP / INFO / FAIL
# Exit code: 0 on success, 1 on failure

set -euo pipefail

FAIL_COUNT=0
MINICONDA_DIR="$HOME/miniconda3"
BACKUP_DIR="$HOME/envs-backup"

# --- Pre-flight: Is conda installed? ---

conda_found=false
if [[ -x "$MINICONDA_DIR/bin/conda" ]]; then
    conda_found=true
elif command -v conda &>/dev/null; then
    conda_found=true
elif command -v brew &>/dev/null && brew list miniconda &>/dev/null 2>&1; then
    conda_found=true
elif [[ -d "$MINICONDA_DIR" ]]; then
    conda_found=true
fi

if [[ "$conda_found" == false ]]; then
    echo "SKIP: Conda does not appear to be installed"
    echo ""
    echo "RESULT: Nothing to remove"
    exit 0
fi

echo "INFO: Conda installation detected — starting removal"

# --- Step 1: Back up environments ---

echo ""
echo "--- Step 1: Back up environments ---"
envs_dir="$MINICONDA_DIR/envs"

if [[ -d "$BACKUP_DIR" ]]; then
    echo "SKIP: $BACKUP_DIR already exists — not overwriting previous backup"
elif [[ -d "$envs_dir" ]]; then
    env_count=$(find "$envs_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$env_count" -gt 0 ]]; then
        if cp -r "$envs_dir" "$BACKUP_DIR" 2>/dev/null; then
            echo "OK: Backed up $env_count environment(s) to $BACKUP_DIR"
        else
            echo "WARN: Backup failed — environments are still in $envs_dir"
        fi
    else
        echo "SKIP: No environments to back up"
    fi
else
    echo "SKIP: No envs directory found at $envs_dir"
fi

# --- Step 2: Uninstall via brew ---

echo ""
echo "--- Step 2: Uninstall via brew ---"
if command -v brew &>/dev/null; then
    brew_found=""
    brew_type=""

    # Check casks first — miniconda/anaconda are almost always casks
    for cask in miniconda anaconda; do
        if brew list --cask "$cask" &>/dev/null 2>&1; then
            brew_found="$cask"
            brew_type="cask"
            break
        fi
    done

    # Fall back to formula check
    if [[ -z "$brew_found" ]]; then
        for formula in miniconda anaconda; do
            if brew list "$formula" &>/dev/null 2>&1; then
                brew_found="$formula"
                brew_type="formula"
                break
            fi
        done
    fi

    if [[ -n "$brew_found" ]]; then
        if [[ "$brew_type" == "cask" ]]; then
            uninstall_output="$(brew uninstall --cask "$brew_found" 2>&1)" && {
                echo "OK: $brew_found cask uninstalled via brew"
            } || {
                echo "WARN: brew uninstall --cask $brew_found returned non-zero"
                echo "  $uninstall_output"
            }
        else
            uninstall_output="$(brew uninstall "$brew_found" 2>&1)" && {
                echo "OK: $brew_found uninstalled via brew"
            } || {
                echo "WARN: brew uninstall $brew_found returned non-zero"
                echo "  $uninstall_output"
            }
        fi
    else
        echo "SKIP: Neither miniconda nor anaconda found in brew"
    fi
else
    echo "SKIP: brew not available"
fi

# --- Step 3: Remove leftover directory ---

echo ""
echo "--- Step 3: Remove miniconda3 directory ---"
if [[ -d "$MINICONDA_DIR" ]]; then
    if rm -rf "$MINICONDA_DIR" 2>/dev/null; then
        echo "OK: Removed $MINICONDA_DIR"
    else
        echo "WARN: Could not fully remove $MINICONDA_DIR — some files may be in use"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "SKIP: $MINICONDA_DIR already removed"
fi

# --- Step 4: Remove .condarc ---

echo ""
echo "--- Step 4: Remove .condarc ---"
if [[ -f "$HOME/.condarc" ]]; then
    rm -f "$HOME/.condarc"
    echo "OK: Removed ~/.condarc"
else
    echo "SKIP: .condarc not found"
fi

# --- Step 5: Clean .zshrc ---

echo ""
echo "--- Step 5: Clean conda from .zshrc ---"
zshrc="$HOME/.zshrc"
if [[ -f "$zshrc" ]]; then
    if grep -q '# >>> conda initialize >>>' "$zshrc" 2>/dev/null; then
        # Remove the conda init block (everything between the markers)
        sed -i '' '/# >>> conda initialize >>>/,/# <<< conda initialize <<</d' "$zshrc"
        echo "OK: Removed conda init block from .zshrc"
    else
        echo "SKIP: .zshrc has no conda init block"
    fi
else
    echo "SKIP: .zshrc not found"
fi

# --- Step 6: Clean .bash_profile ---

echo ""
echo "--- Step 6: Clean conda from .bash_profile ---"
bash_profile="$HOME/.bash_profile"
if [[ -f "$bash_profile" ]]; then
    if grep -q '# >>> conda initialize >>>' "$bash_profile" 2>/dev/null; then
        sed -i '' '/# >>> conda initialize >>>/,/# <<< conda initialize <<</d' "$bash_profile"
        echo "OK: Removed conda init block from .bash_profile"
    else
        echo "SKIP: .bash_profile has no conda init block"
    fi
else
    echo "SKIP: .bash_profile not found"
fi

# --- Step 7: Clean stale entries from environments.txt ---

echo ""
echo "--- Step 7: Clean stale conda entries from environments.txt ---"
envs_txt="$HOME/.conda/environments.txt"
if [[ -f "$envs_txt" ]]; then
    if grep -q 'miniconda\|anaconda' "$envs_txt" 2>/dev/null; then
        grep -v 'miniconda\|anaconda' "$envs_txt" > "${envs_txt}.tmp" && mv "${envs_txt}.tmp" "$envs_txt"
        echo "OK: Removed stale conda entries from $envs_txt"
    else
        echo "SKIP: No conda entries in $envs_txt"
    fi
else
    echo "SKIP: $envs_txt not found"
fi

# --- Step 8: Verify ---

echo ""
echo "--- Verification ---"
if command -v conda &>/dev/null; then
    conda_path="$(command -v conda)"
    echo "WARN: conda command still resolves to $conda_path — open a new terminal to confirm removal"
else
    echo "OK: conda command no longer available"
fi

if [[ -d "$MINICONDA_DIR" ]]; then
    echo "WARN: $MINICONDA_DIR still exists — may have locked files"
else
    echo "OK: $MINICONDA_DIR removed"
fi

# --- Summary ---

echo ""
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "RESULT: Removal completed with $FAIL_COUNT issue(s)"
    exit 1
else
    echo "RESULT: Conda removal complete"
    exit 0
fi
