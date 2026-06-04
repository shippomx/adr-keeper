#!/bin/bash
# Run every adr-keeper test. Exit 1 if any test exits non-zero.
HERE="$(cd "$(dirname "$0")" && pwd)"
FAILED=0
for t in "$HERE"/test-*.sh; do
    echo ""
    echo "######### $(basename "$t") #########"
    if ! bash "$t"; then
        FAILED=$((FAILED + 1))
    fi
done
echo ""
echo "Total failing test files: $FAILED"
[ "$FAILED" -eq 0 ]
