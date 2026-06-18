#!/usr/bin/env bash
# run-all.sh - Run every rwl-install-wizard test suite + the data secret-guard.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for t in "$SCRIPT_DIR"/test-*.sh; do
    echo "### $t"
    bash "$t" || rc=1
done
# Catalog + data must be secret-clean.
echo "### secret-guard over data/"
bash "$SCRIPT_DIR/../lib/secret-guard.sh" "$SCRIPT_DIR/../data" || rc=1
exit "$rc"
