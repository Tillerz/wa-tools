#!/bin/bash
# Runs all tests (tests/test-*.sh) one after the other, and prints a summary.
# Exit code: 0 if all passed, 1 if one or more failed. The tests use a fake WA API, they need no token and no network.
# GitHub Actions runs this on every push (.github/workflows/tests.yml).
# Run it from anywhere:  ./tests/run-all.sh
cd "$(dirname "$0")/.." || exit 1

in_ci=${GITHUB_ACTIONS:-}
passed=()
failed=()
start=$SECONDS
for test in tests/test-*.sh; do
    name=$(basename "$test" .sh)
    name=${name#test-}
    [ -n "$in_ci" ] && echo "::group::$name"
    output=$(bash "$test" 2>&1)
    code=$?
    [ -n "$in_ci" ] && echo "$output" && echo "::endgroup::"
    if [ "$code" = 0 ]; then
        passed+=("$name")
        echo "  PASS  $name"
    else
        failed+=("$name")
        echo "  FAIL  $name"
        # on a machine, show what failed; in GitHub Actions the whole output is in the group above
        [ -z "$in_ci" ] && echo "$output" | grep -E "FAIL|Traceback|Error" | head -10 | sed 's/^/          /'
    fi
done

echo "---------------------------------------------------------------"
echo "${#passed[@]} passed, ${#failed[@]} failed, $((SECONDS - start)) seconds"
if [ "${#failed[@]}" -gt 0 ]; then
    echo "FAILED: ${failed[*]}"
    exit 1
fi
echo "ALL TESTS PASSED"
