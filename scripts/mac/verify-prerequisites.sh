#!/usr/bin/env bash
# verify-prerequisites.sh — Check macOS dev tool prerequisites
#
# Usage:
#   ./verify-prerequisites.sh              # Check system-level tools only
#   ./verify-prerequisites.sh --env node1  # Also check packages in an environment
#
# Output: Structured lines prefixed with OK / WARN / FAIL
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
    case "$path" in
        /opt/homebrew/*) echo "homebrew" ;;
        *) echo "unknown" ;;
    esac
}

detect_micromamba_source() {
    local path="$1"
    case "$path" in
        /opt/homebrew/*) echo "homebrew" ;;
        */.local/bin/micromamba) echo "standalone" ;;
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

# --- Check: conda ---

if command -v conda &>/dev/null; then
    conda_path="$(command -v conda)"
    conda_version="$(conda --version 2>/dev/null | sed 's/conda //')"
    conda_source="$(detect_conda_source "$conda_path")"
    echo "OK: conda ${conda_version} (${conda_path}) [${conda_source}]"
else
    echo "FAIL: conda not found — install with: brew install miniconda"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# --- Check: micromamba ---

# micromamba may be a shell function (not visible to `command -v` in a non-interactive shell).
# Check MAMBA_EXE first, then fall back to command lookup.
if [[ -n "${MAMBA_EXE:-}" && -x "${MAMBA_EXE:-}" ]]; then
    mm_path="$MAMBA_EXE"
    mm_version="$("$MAMBA_EXE" --version 2>/dev/null)"
    mm_source="$(detect_micromamba_source "$mm_path")"

    if [[ "$mm_source" == "standalone" ]]; then
        echo "WARN: micromamba ${mm_version} (${mm_path}) [${mm_source}] — brew version recommended"
    else
        echo "OK: micromamba ${mm_version} (${mm_path}) [${mm_source}]"
    fi
elif command -v micromamba &>/dev/null; then
    mm_path="$(command -v micromamba)"
    mm_version="$(micromamba --version 2>/dev/null)"
    mm_source="$(detect_micromamba_source "$mm_path")"

    if [[ "$mm_source" == "standalone" ]]; then
        echo "WARN: micromamba ${mm_version} (${mm_path}) [${mm_source}] — brew version recommended"
    else
        echo "OK: micromamba ${mm_version} (${mm_path}) [${mm_source}]"
    fi
else
    # Last resort: check the brew cellar directly
    brew_mm="/opt/homebrew/opt/micromamba/bin/micromamba"
    if [[ -x "$brew_mm" ]]; then
        mm_version="$("$brew_mm" --version 2>/dev/null)"
        echo "OK: micromamba ${mm_version} (${brew_mm}) [homebrew] — note: MAMBA_EXE not set in this shell"
    else
        echo "FAIL: micromamba not found — install with: brew install micromamba"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

# --- Check: envs_dirs alignment ---

if command -v conda &>/dev/null; then
    conda_envs_first="$(conda config --show envs_dirs 2>/dev/null | head -2 | tail -1 | sed 's/^  - //')"
    mambarc="${HOME}/.mambarc"
    if [[ -f "$mambarc" ]]; then
        mamba_envs_first="$(grep -A1 'envs_dirs:' "$mambarc" 2>/dev/null | tail -1 | sed 's/^  - //')"
        # Expand ~ to $HOME for comparison
        conda_envs_expanded="${conda_envs_first/#\~/$HOME}"
        mamba_envs_expanded="${mamba_envs_first/#\~/$HOME}"
        if [[ "$conda_envs_expanded" == "$mamba_envs_expanded" ]]; then
            echo "OK: envs_dirs aligned — both use ${conda_envs_first}"
        else
            echo "WARN: envs_dirs mismatch — conda uses ${conda_envs_first}, micromamba uses ${mamba_envs_first}"
        fi
    else
        echo "WARN: ~/.mambarc not found — micromamba envs_dirs may not be configured"
    fi
fi

# --- Check: environment packages (optional) ---

if [[ -n "$ENV_NAME" ]]; then
    echo ""
    echo "--- Environment: ${ENV_NAME} ---"

    env_path=""
    # Find the environment
    if command -v conda &>/dev/null; then
        env_path="$(conda info --envs 2>/dev/null | grep "^${ENV_NAME} " | awk '{print $NF}' || true)"
    fi
    if [[ -z "$env_path" && -x "${MAMBA_EXE:-}" ]]; then
        env_path="$("$MAMBA_EXE" env list 2>/dev/null | grep "^${ENV_NAME} " | awk '{print $NF}' || true)"
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
