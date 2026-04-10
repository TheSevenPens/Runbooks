#!/usr/bin/env bash
# create-env.sh — Create a conda environment with specified packages (idempotent)
#
# On macOS this repo uses miniconda (not micromamba) because of a libmamba
# codesign bug on macOS 26. See macos_micromamba_debug_runbook.md for
# root cause. The Windows equivalent of this script uses micromamba.
#
# Usage:
#   bash create-env.sh --name node1 --packages nodejs,python,gh
#   bash create-env.sh --name node1 --packages nodejs,python,gh --recreate
#   bash create-env.sh --name node1 --spec-file ../../envs/node1.yml
#
# Parameters:
#   --name        Environment name (required)
#   --packages    Comma-separated package list (e.g. "nodejs,python,gh")
#   --channel     Channel to install from (default: conda-forge)
#   --spec-file   Path to a YAML spec file (overrides --packages and --channel)
#   --recreate    Remove and recreate the environment if it already exists
#
# Actions:
#   1. Locate conda binary (brew cask miniconda preferred)
#   2. Ensure conda-forge is the only configured channel with strict priority
#   3. Check if environment already exists (skip or recreate)
#   4. Create environment using `conda create --override-channels -c conda-forge`
#   5. Verify each package is installed and report versions
#
# Output: Structured lines prefixed with OK / SKIP / FAIL / INFO / WARN
# Exit code: 0 on success, 1 on failure

set -euo pipefail

NAME=""
PACKAGES=""
CHANNEL="conda-forge"
SPEC_FILE=""
RECREATE=false
FAIL_COUNT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)      NAME="$2";      shift 2 ;;
        --packages)  PACKAGES="$2";  shift 2 ;;
        --channel)   CHANNEL="$2";   shift 2 ;;
        --spec-file) SPEC_FILE="$2"; shift 2 ;;
        --recreate)  RECREATE=true;  shift ;;
        *)
            echo "Usage: $0 --name <env> --packages <pkg1,pkg2,...> [--channel <ch>] [--spec-file <path>] [--recreate]"
            exit 2
            ;;
    esac
done

if [[ -z "$NAME" ]]; then
    echo "FAIL: --name is required"
    exit 2
fi

if [[ -z "$PACKAGES" && -z "$SPEC_FILE" ]]; then
    echo "FAIL: Either --packages or --spec-file is required"
    exit 2
fi

# --- Locate conda binary ---
#
# Preferred order:
#   1. CONDA_EXE env var (set by `conda init` hooks)
#   2. `conda` on PATH
#   3. brew cask miniconda canonical path

CONDA_EXE_BIN=""

if [[ -n "${CONDA_EXE:-}" && -x "${CONDA_EXE:-}" ]]; then
    CONDA_EXE_BIN="$CONDA_EXE"
elif command -v conda &>/dev/null; then
    CONDA_EXE_BIN="$(command -v conda)"
elif [[ -x "/opt/homebrew/Caskroom/miniconda/base/bin/conda" ]]; then
    CONDA_EXE_BIN="/opt/homebrew/Caskroom/miniconda/base/bin/conda"
elif [[ -x "/usr/local/Caskroom/miniconda/base/bin/conda" ]]; then
    CONDA_EXE_BIN="/usr/local/Caskroom/miniconda/base/bin/conda"
fi

if [[ -z "$CONDA_EXE_BIN" ]]; then
    echo "FAIL: conda not found — install with: brew install --cask miniconda"
    exit 1
fi

echo "INFO: Using conda at $CONDA_EXE_BIN"

# --- Ensure conda is configured for conda-forge only with strict priority ---
#
# Modern conda requires accepting Anaconda's Terms of Service for the default
# channels (repo.anaconda.com/pkgs/main, pkgs/r). We don't want them at all.

echo ""
echo "--- Ensuring conda-forge-only channel config ---"

# Remove any configured channels key (idempotent — silent if absent)
"$CONDA_EXE_BIN" config --remove-key channels &>/dev/null || true

if "$CONDA_EXE_BIN" config --add channels conda-forge &>/dev/null; then
    echo "OK: conda-forge set as the only channel"
else
    echo "WARN: Could not set conda-forge as the only channel"
fi

if "$CONDA_EXE_BIN" config --set channel_priority strict &>/dev/null; then
    echo "OK: Channel priority set to strict"
else
    echo "WARN: Could not set channel_priority=strict"
fi

# --- Resolve packages ---

IFS=',' read -ra PACKAGE_LIST <<< "$PACKAGES"
# Trim whitespace
CLEAN_PACKAGES=()
for pkg in "${PACKAGE_LIST[@]}"; do
    trimmed="$(echo "$pkg" | xargs)"
    if [[ -n "$trimmed" ]]; then
        CLEAN_PACKAGES+=("$trimmed")
    fi
done

if [[ -n "$SPEC_FILE" ]]; then
    if [[ ! -f "$SPEC_FILE" ]]; then
        echo "FAIL: Spec file not found: $SPEC_FILE"
        exit 1
    fi
    echo "INFO: Using spec file $SPEC_FILE"
else
    if [[ ${#CLEAN_PACKAGES[@]} -eq 0 ]]; then
        echo "FAIL: No packages specified"
        exit 1
    fi
    echo "INFO: Packages: $(IFS=', '; echo "${CLEAN_PACKAGES[*]}")"
    echo "INFO: Channel: $CHANNEL"
fi

# --- Parse packages from spec file (for verification) ---

parse_spec_packages() {
    local spec="$1"
    local in_deps=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*dependencies: ]]; then
            in_deps=true
            continue
        fi
        if $in_deps; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*([^[:space:]]+) ]]; then
                echo "${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[^[:space:]] && ! "$line" =~ ^[[:space:]]*- ]]; then
                in_deps=false
            fi
        fi
    done < "$spec"
}

# --- Check if environment exists ---

echo ""
echo "--- Checking environment ---"

ENV_EXISTS=false
# `conda env list` prints `<name> <path>` — match on the first token
if "$CONDA_EXE_BIN" env list 2>/dev/null | awk '{print $1}' | grep -qx "$NAME"; then
    ENV_EXISTS=true
fi

if $ENV_EXISTS; then
    if $RECREATE; then
        echo "INFO: Environment '$NAME' exists — removing for recreate"
        if "$CONDA_EXE_BIN" env remove -n "$NAME" -y &>/dev/null; then
            echo "OK: Removed existing environment '$NAME'"
            ENV_EXISTS=false
        else
            echo "FAIL: Could not remove environment '$NAME'"
            exit 1
        fi
    else
        echo "SKIP: Environment '$NAME' already exists (use --recreate to replace)"

        echo ""
        echo "--- Verifying packages in existing environment ---"

        installed=$("$CONDA_EXE_BIN" list -n "$NAME" 2>/dev/null)

        if [[ -n "$SPEC_FILE" ]]; then
            mapfile -t verify_pkgs < <(parse_spec_packages "$SPEC_FILE")
        else
            verify_pkgs=("${CLEAN_PACKAGES[@]}")
        fi

        for pkg in "${verify_pkgs[@]}"; do
            if echo "$installed" | grep -qE "^${pkg}\s"; then
                version_line=$(echo "$installed" | grep -E "^${pkg}\s" | head -1 | xargs)
                echo "OK: $pkg installed ($version_line)"
            else
                echo "WARN: $pkg not found in environment '$NAME'"
            fi
        done

        echo ""
        echo "RESULT: Environment '$NAME' already exists - skipped creation"
        exit 0
    fi
fi

# --- Create environment ---

echo ""
echo "--- Creating environment '$NAME' ---"

if [[ -n "$SPEC_FILE" ]]; then
    if ! "$CONDA_EXE_BIN" env create -n "$NAME" --file "$SPEC_FILE" 2>&1; then
        echo "FAIL: conda env create failed"
        exit 1
    fi
else
    if ! "$CONDA_EXE_BIN" create -n "$NAME" --override-channels -c "$CHANNEL" "${CLEAN_PACKAGES[@]}" -y 2>&1; then
        echo "FAIL: conda create failed"
        exit 1
    fi
fi

echo "OK: Environment '$NAME' created"

# --- Verify environment exists ---

if "$CONDA_EXE_BIN" env list 2>/dev/null | awk '{print $1}' | grep -qx "$NAME"; then
    echo "OK: Environment '$NAME' appears in env list"
else
    echo "FAIL: Environment '$NAME' not found after creation"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# --- Verify packages ---

echo ""
echo "--- Verifying packages ---"

installed=$("$CONDA_EXE_BIN" list -n "$NAME" 2>/dev/null)

if [[ -n "$SPEC_FILE" ]]; then
    mapfile -t verify_pkgs < <(parse_spec_packages "$SPEC_FILE")
else
    verify_pkgs=("${CLEAN_PACKAGES[@]}")
fi

for pkg in "${verify_pkgs[@]}"; do
    if echo "$installed" | grep -qE "^${pkg}\s"; then
        version_line=$(echo "$installed" | grep -E "^${pkg}\s" | head -1 | xargs)
        echo "OK: $pkg installed ($version_line)"
    else
        echo "FAIL: $pkg not found in environment '$NAME' after creation"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

# --- Summary ---

echo ""
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "RESULT: Environment '$NAME' created with $FAIL_COUNT issue(s)"
    exit 1
else
    echo "RESULT: Environment '$NAME' created and verified"
    exit 0
fi
