#!/usr/bin/env bash
# Run all test scenes and aggregate results.
# Usage: bash test/run_all.sh
# Exit code: 0 if all pass, 1 if any fail.

set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
FAILED=0

for tscn in test/*.tscn; do
    echo "──────────────────────────────────────"
    echo "Running: $tscn"
    echo "──────────────────────────────────────"
    if ! "$GODOT" --headless --scene "res://$tscn" 2>&1; then
        FAILED=1
    fi
    echo ""
done

echo "══════════════════════════════════════"
if [ "$FAILED" -eq 0 ]; then
    echo "ALL TEST SUITES PASSED"
else
    echo "SOME TEST SUITES FAILED"
    exit 1
fi
