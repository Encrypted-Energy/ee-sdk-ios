#!/usr/bin/env bash
# Test harness. Fails loudly: compile errors fail `swift test` itself, and a
# shrinking suite fails the count check (the Android harness's masking hazard,
# designed out — see NOTES.md).
set -euo pipefail
cd "$(dirname "$0")"

SWIFT="${SWIFT:-/home/clawuser/toolchain/swift/usr/bin/swift}"
[ -x "$SWIFT" ] || SWIFT="swift"

EXPECTED_TESTS=66

out=$("$SWIFT" test 2>&1) || { echo "$out" | tail -40; exit 1; }
summary=$(echo "$out" | grep -E "^Test Suite 'All tests' (passed|failed)" -A1 | tail -1)
echo "$summary"

count=$(echo "$summary" | sed -n "s/.*Executed \([0-9]*\) tests.*/\1/p")
if [ -z "$count" ] || [ "$count" -lt "$EXPECTED_TESTS" ]; then
    echo "FAIL: expected >= $EXPECTED_TESTS tests, saw '${count:-none}'" >&2
    exit 1
fi
echo "OK: $count tests"
