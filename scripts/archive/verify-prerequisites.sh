#!/usr/bin/env bash
# verify-prerequisites.sh — Check macOS dev tool prerequisites
#
# Usage:
#   ./verify-prerequisites.sh              # Check system-level tools only
#   ./verify-prerequisites.sh --env node1  # Also check packages in an environment
#
# Output: Structured lines prefixed with OK / WARN / FAIL / SKIP
# Exit code: 0 if all required tools present, 1 if any FAIL

set -euo pipefail

ENV_NAME=""
FAIL_COUNT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)
            ENV_NAME="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--env <environment-name>]"
            exit 2
            ;;
    esac
done

# --- Helpers ---

detect_git_source() {
    local path="$1"
    case "$path" in
        /opt/homebrew/bin/git|/usr/local/bin/git) echo "homebrew" ;;
        /usr/bin/git) echo "apple" ;;
        *) echo "unknown" ;;
    esac
}

detect_conda_source() {
    local path="$1"
    # Resolve symlinks — `brew install --cask miniconda` links
    # /opt/homebrew/bin/conda → .../Caskroom/miniconda/base/condabin/conda
    local resolved
    resolved="$(readlink -f "$path" 2>/dev/null || readlink "$path" 2>/dev/null || echo "$path")"
    case "$resolved" in
        /opt/homebrew/Caskroom/miniconda/*|/usr/local/Caskroom/miniconda/*) echo "homebrew-cask" ;;
        "$HOME/miniconda3/"*) echo "direct-installer" ;;
        *) echo "unknown" ;;
    esac
}

# --- Check: Homebrew ---

if command -v brew &>/dev/null; then
    brew_path="$(command -v brew)"
    brew_version="$(brew --version 2>/dev/null | head -1 | sed 's/Homebrew //')"
    echo "OK: brew ${brew_version} (${brew_path})"
else
    echo "FAIL: brew not found — install from https://brew.sh"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# --- Check: Git ---

if command -v git &>/dev/null; then
    git_path="$(command -v git)"
    git_version="$(git --version 2>/dev/null | sed 's/git version //')"
    git_source="$(detect_git_source "$git_path")"

    if [[ "$git_source" == "apple" ]]; then
        echo "WARN: git ${git_version} (${git_path}) [${git_source}] — brew version recommended"
    else
        echo "OK: git ${git_version} (${git_path}) [${git_source}]"
    fi
else
    echo "FAIL: git not found"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# --- Check: micromamba (should NOT be present on macOS) ---
#
# macOS uses miniconda instead of micromamba because of a libmamba codesign
# bug on macOS 26 (see mac-micromamba-debug-runbook.md). If micromamba is
# detected, warn and recommend removal via scripts/mac/remove-micromamba.sh.

mm_found=false
if [[ -n "${MAMBA_EXE:-}" && -x "${MAMBA_EXE:-}" ]]; then
    echo "WARN: micromamba found at ${MAMBA_EXE} — should be removed (macOS uses miniconda). Run: bash scripts/mac/remove-micromamba.sh"
    mm_found=true
elif command -v micromamba &>/dev/null; then
    mm_path_now="$(command -v micromamba)"
    echo "WARN: micromamba found at ${mm_path_now} — should be removed (macOS uses miniconda). Run: bash scripts/mac/remove-micromamba.sh"
    mm_found=true
elif command -v brew &>/dev/null && brew list micromamba &>/dev/null 2>&1; then
    echo "WARN: micromamba installed via brew — should be removed (macOS uses miniconda). Run: bash scripts/mac/remove-micromamba.sh"
    mm_found=true
fi

if [[ "$mm_found" == false ]]; then
    echo "OK: micromamba not present (expected — macOS uses miniconda due to libmamba codesign bug on macOS 26)"
fi

# --- Check: conda (should be present on macOS) ---

conda_path=""
if [[ -n "${CONDA_EXE:-}" && -x "${CONDA_EXE:-}" ]]; then
    conda_path="$CONDA_EXE"
elif command -v conda &>/dev/null; then
    conda_path="$(command -v conda)"
elif [[ -x "/opt/homebrew/Caskroom/miniconda/base/bin/conda" ]]; then
    conda_path="/opt/homebrew/Caskroom/miniconda/base/bin/conda"
elif [[ -x "/usr/local/Caskroom/miniconda/base/bin/conda" ]]; then
    conda_path="/usr/local/Caskroom/miniconda/base/bin/conda"
fi

if [[ -n "$conda_path" ]]; then
    conda_version="$("$conda_path" --version 2>/dev/null | sed 's/conda //')"
    conda_source="$(detect_conda_source "$conda_path")"
    if [[ -z "${CONDA_EXE:-}" ]]; then
        echo "OK: conda ${conda_version} (${conda_path}) [${conda_source}] — note: CONDA_EXE not set in this shell"
    else
        echo "OK: conda ${conda_version} (${conda_path}) [${conda_source}]"
    fi
else
    echo "FAIL: conda not found — install with: brew install --cask miniconda"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# --- Check: environment packages (optional) ---

if [[ -n "$ENV_NAME" ]]; then
    echo ""
    echo "--- Environment: ${ENV_NAME} ---"

    env_path=""
    # Find the environment via conda
    if [[ -n "$conda_path" ]]; then
        env_path="$("$conda_path" env list 2>/dev/null | awk -v n="$ENV_NAME" '$1==n {print $NF}' || true)"
    fi

    if [[ -z "$env_path" ]]; then
        echo "FAIL: environment '${ENV_NAME}' not found"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo "OK: environment '${ENV_NAME}' found at ${env_path}"

        # Check expected binaries inside the environment
        for tool in node python gh; do
            tool_path="${env_path}/bin/${tool}"
            if [[ -x "$tool_path" ]]; then
                tool_version="$("$tool_path" --version 2>/dev/null | head -1)"
                echo "OK: ${tool} ${tool_version} (${tool_path})"
            else
                echo "FAIL: ${tool} not found in ${ENV_NAME}"
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
        done
    fi
fi

# --- Summary ---

echo ""
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "RESULT: ${FAIL_COUNT} issue(s) found"
    exit 1
else
    echo "RESULT: All checks passed"
    exit 0
fi
