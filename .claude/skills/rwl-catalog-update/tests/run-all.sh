#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for t in "$DIR"/test-*.sh; do echo "### $t"; bash "$t" || rc=1; done
exit "$rc"
