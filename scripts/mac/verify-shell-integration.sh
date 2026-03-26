#!/usr/bin/env bash
# verify-shell-integration.sh — Test conda/micromamba activate across macOS shells
#
# Usage:
#   ./verify-shell-integration.sh
#
# Tests that shell hooks are properly initialized by attempting to activate
# the base environment in each shell. Uses the correct invocation flags:
#   - zsh: interactive (-i) so .zshrc is sourced
#   - bash: login + interactive (-l -i) so .bash_profile is sourced
#
# Output: Structured OK/FAIL lines, then a summary table
# Exit code: 0 if all pass, 1 if any fail

set -euo pipefail

FAIL_COUNT=0

# Results array: "shell tool status error_msg"
declare -a RESULTS=()

# --- Helpers ---

test_activate() {
    local shell_name="$1"
    local tool="$2"
    local shell_cmd="$3"

    local output
    local exit_code=0

    # Run the activate test, capture stderr (where errors go)
    output=$(eval "$shell_cmd" 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 && "$output" == *"ACTIVATE_OK"* ]]; then
        echo "OK: ${shell_name} ${tool}-activate"
        RESULTS+=("${shell_name}|${tool}|OK|")
    else
        # Extract first meaningful error line
        local err_line
        err_line="$(echo "$output" | grep -v '^$' | grep -vi 'ACTIVATE_OK' | grep -vi 'no job control' | head -1)"
        echo "FAIL: ${shell_name} ${tool}-activate — ${err_line}"
        RESULTS+=("${shell_name}|${tool}|FAIL|${err_line}")
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# --- Tests ---

# zsh uses -i (interactive) to source .zshrc where conda/micromamba init blocks live
test_activate "zsh" "conda" \
    'zsh -i -c "conda activate base && echo ACTIVATE_OK && conda deactivate"'

test_activate "zsh" "micromamba" \
    'zsh -i -c "micromamba activate base && echo ACTIVATE_OK && micromamba deactivate"'

# bash needs -l (login) for .bash_profile AND -i (interactive) for hooks
test_activate "bash" "conda" \
    'bash -l -i -c "conda activate base && echo ACTIVATE_OK && conda deactivate"'

test_activate "bash" "micromamba" \
    'bash -l -i -c "micromamba activate base && echo ACTIVATE_OK && micromamba deactivate"'

# --- Summary table ---

echo ""
echo "| Shell | conda activate | micromamba activate |"
echo "|-------|----------------|---------------------|"

for shell_name in zsh bash; do
    conda_status="—"
    mamba_status="—"
    for result in "${RESULTS[@]}"; do
        IFS='|' read -r r_shell r_tool r_status r_err <<< "$result"
        if [[ "$r_shell" == "$shell_name" && "$r_tool" == "conda" ]]; then
            conda_status="$r_status"
        elif [[ "$r_shell" == "$shell_name" && "$r_tool" == "micromamba" ]]; then
            mamba_status="$r_status"
        fi
    done
    printf "| %-5s | %-14s | %-19s |\n" "$shell_name" "$conda_status" "$mamba_status"
done

# --- Exit ---

echo ""
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "RESULT: ${FAIL_COUNT} failure(s)"
    exit 1
else
    echo "RESULT: All shell integrations working"
    exit 0
fi
