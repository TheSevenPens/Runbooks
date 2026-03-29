#!/usr/bin/env bash
# verify-shell-integration.sh — Test micromamba activate across macOS shells
#
# Usage:
#   ./verify-shell-integration.sh
#
# Tests that shell hooks are properly initialized by attempting to activate
# the base environment in each shell. Uses the correct invocation flags:
#   - zsh: interactive (-i) so .zshrc is sourced
#   - bash: login + interactive (-l -i) so .bash_profile is sourced
#
# Output: Structured OK/FAIL/SKIP lines, then a summary table
# Exit code: 0 if all pass, 1 if any fail

set -euo pipefail

FAIL_COUNT=0

# Results array: "shell|status|error_msg"
declare -a RESULTS=()

# --- Helpers ---

test_activate() {
    local shell_name="$1"
    local shell_cmd="$2"

    local output
    local exit_code=0

    # Run the activate test, capture stderr (where errors go)
    output=$(eval "$shell_cmd" 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 && "$output" == *"ACTIVATE_OK"* ]]; then
        echo "OK: ${shell_name} micromamba-activate"
        RESULTS+=("${shell_name}|OK|")
    else
        # Extract first meaningful error line
        local err_line
        err_line="$(echo "$output" | grep -v '^$' | grep -vi 'ACTIVATE_OK' | grep -vi 'no job control' | head -1)"
        echo "FAIL: ${shell_name} micromamba-activate — ${err_line}"
        RESULTS+=("${shell_name}|FAIL|${err_line}")
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# --- Tests ---

# zsh uses -i (interactive) to source .zshrc where micromamba init blocks live
test_activate "zsh" \
    'zsh -i -c "micromamba activate base && echo ACTIVATE_OK && micromamba deactivate"'

# bash needs -l (login) for .bash_profile AND -i (interactive) for hooks
test_activate "bash" \
    'bash -l -i -c "micromamba activate base && echo ACTIVATE_OK && micromamba deactivate"'

# --- Summary table ---

echo ""
echo "| Shell | micromamba activate |"
echo "|-------|---------------------|"

for result in "${RESULTS[@]}"; do
    IFS='|' read -r r_shell r_status r_err <<< "$result"
    printf "| %-5s | %-19s |\n" "$r_shell" "$r_status"
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
