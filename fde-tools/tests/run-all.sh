#!/usr/bin/env bash
# run-all.sh - Run every fde-tools test suite.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for t in "$SCRIPT_DIR"/test-*.sh; do
    echo "### $t"
    bash "$t" || rc=1
done
exit "$rc"
