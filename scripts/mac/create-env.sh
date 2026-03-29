#!/usr/bin/env bash
# create-env.sh — Create a micromamba environment with specified packages (idempotent)
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
#   1. Locate micromamba binary
#   2. Check if environment already exists (skip or recreate)
#   3. Create environment with specified packages
#   4. Verify each package is installed and report versions
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

# --- Locate micromamba binary ---

MM_EXE=""

if command -v micromamba &>/dev/null; then
    MM_EXE="$(command -v micromamba)"
elif [[ -x "$HOME/.local/bin/micromamba" ]]; then
    MM_EXE="$HOME/.local/bin/micromamba"
fi

if [[ -z "$MM_EXE" ]]; then
    echo "FAIL: micromamba not found"
    exit 1
fi

echo "INFO: Using micromamba at $MM_EXE"

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
if "$MM_EXE" env list 2>/dev/null | grep -qw "$NAME"; then
    ENV_EXISTS=true
fi

if $ENV_EXISTS; then
    if $RECREATE; then
        echo "INFO: Environment '$NAME' exists - removing for recreate"
        if "$MM_EXE" env remove -n "$NAME" -y &>/dev/null; then
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

        installed=$("$MM_EXE" list -n "$NAME" 2>/dev/null)

        if [[ -n "$SPEC_FILE" ]]; then
            mapfile -t verify_pkgs < <(parse_spec_packages "$SPEC_FILE")
        else
            verify_pkgs=("${CLEAN_PACKAGES[@]}")
        fi

        for pkg in "${verify_pkgs[@]}"; do
            if echo "$installed" | grep -qE "^\s+${pkg}\s"; then
                version_line=$(echo "$installed" | grep -E "^\s+${pkg}\s" | head -1 | xargs)
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
    if ! "$MM_EXE" create -n "$NAME" --file "$SPEC_FILE" -y 2>&1; then
        echo "FAIL: micromamba create failed"
        exit 1
    fi
else
    if ! "$MM_EXE" create -n "$NAME" -c "$CHANNEL" "${CLEAN_PACKAGES[@]}" -y 2>&1; then
        echo "FAIL: micromamba create failed"
        exit 1
    fi
fi

echo "OK: Environment '$NAME' created"

# --- Verify environment exists ---

if "$MM_EXE" env list 2>/dev/null | grep -qw "$NAME"; then
    echo "OK: Environment '$NAME' appears in env list"
else
    echo "FAIL: Environment '$NAME' not found after creation"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# --- Verify packages ---

echo ""
echo "--- Verifying packages ---"

installed=$("$MM_EXE" list -n "$NAME" 2>/dev/null)

if [[ -n "$SPEC_FILE" ]]; then
    mapfile -t verify_pkgs < <(parse_spec_packages "$SPEC_FILE")
else
    verify_pkgs=("${CLEAN_PACKAGES[@]}")
fi

for pkg in "${verify_pkgs[@]}"; do
    if echo "$installed" | grep -qE "^\s+${pkg}\s"; then
        version_line=$(echo "$installed" | grep -E "^\s+${pkg}\s" | head -1 | xargs)
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
