#!/usr/bin/env bash
# Run all test scenes and aggregate results.
# Usage: bash test/run_all.sh
# Exit code: 0 if all pass, 1 if any fail.
#
# A suite fails on either of two things:
#   1. a failed assertion (the scene exits non-zero), or
#   2. a GDScript runtime error, even if every assertion passed.
#
# (2) matters because test_base only counts assertions — it never sees a
# runtime error. A null dereference in code a test calls prints "SCRIPT ERROR"
# to stderr, the statement is abandoned, and the suite still reports all-green.
# That hid a real regression once; now it can't.
#
# Only GDScript-level errors are gated. Engine shutdown noise ("N resources
# still in use at exit", PagedAllocator pages) is pre-existing and unrelated to
# test correctness, so plain ERROR: lines are left alone.

set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
FAILED=0
FAILED_SUITES=()

for tscn in test/*.tscn; do
    echo "──────────────────────────────────────"
    echo "Running: $tscn"
    echo "──────────────────────────────────────"

    OUTPUT=""
    STATUS=0
    OUTPUT="$("$GODOT" --headless --scene "res://$tscn" 2>&1)" || STATUS=$?
    echo "$OUTPUT"

    if [ "$STATUS" -ne 0 ]; then
        FAILED=1
        FAILED_SUITES+=("$tscn (assertions)")
    fi

    if printf '%s' "$OUTPUT" | grep -q "SCRIPT ERROR"; then
        echo ""
        echo "!! GDScript runtime errors in $tscn:"
        printf '%s' "$OUTPUT" | grep "SCRIPT ERROR" | sort | uniq -c
        FAILED=1
        FAILED_SUITES+=("$tscn (runtime errors)")
    fi

    # A suite that asserted nothing is not a passing suite — it usually means
    # _run_tests died partway (see above) or a test was never wired up.
    if ! printf '%s' "$OUTPUT" | grep -qE "Results: [1-9][0-9]* passed"; then
        echo ""
        echo "!! $tscn ran no assertions"
        FAILED=1
        FAILED_SUITES+=("$tscn (no assertions)")
    fi

    echo ""
done

echo "══════════════════════════════════════"
if [ "$FAILED" -eq 0 ]; then
    echo "ALL TEST SUITES PASSED"
else
    echo "SOME TEST SUITES FAILED"
    for suite in "${FAILED_SUITES[@]}"; do
        echo "  - $suite"
    done
    exit 1
fi
