#!/usr/bin/env bash
# detect-drift.sh --chart <dir> [--catalog <f>] [--out <dir>]
# Deterministic drift detector. Writes <out>/findings.tsv; never edits sources.
set -uo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SKILL_DIR/../../.." && pwd)"
CATALOG="$REPO/rwl-install-wizard/data/knob-catalog.yaml"
CHART=""; OUT="./.rwl-catalog-drift"

while [ $# -gt 0 ]; do
  case "$1" in
    --chart)   CHART="$2"; shift 2 ;;
    --catalog) CATALOG="$2"; shift 2 ;;
    --out)     OUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$CHART" ] && [ -f "$CHART/Chart.yaml" ] || { echo "usage: --chart <dir with Chart.yaml>" >&2; exit 2; }
mkdir -p "$OUT"; FINDINGS="$OUT/findings.tsv"; : > "$FINDINGS"

# emit_finding <bucket:auto|decide> <kind> <option> <detail> <evidence> <current> <chart>
emit_finding() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" >> "$FINDINGS"
}

check_chartcompat() {
  local ver compat
  ver="$(awk '/^version:/{print $2; exit}' "$CHART/Chart.yaml")"
  compat="$(awk -F'"' '/^chartCompat:/{print $2; exit}' "$CATALOG")"
  local upper lower vmm
  upper="$(printf '%s' "$compat" | sed -nE 's/.*<([0-9]+\.[0-9]+).*/\1/p')"
  lower="$(printf '%s' "$compat" | sed -nE 's/.*>=([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p')"
  vmm="$(printf '%s' "$ver" | sed -nE 's/^([0-9]+\.[0-9]+).*/\1/p')"
  local outside=""
  # At/above the exclusive upper bound (0.3.x is outside `<0.3`).
  if [ -n "$upper" ] && [ -n "$vmm" ] && [ "$(printf '%s\n%s\n' "$vmm" "$upper" | sort -V | head -1)" = "$upper" ]; then
    outside="above"
  fi
  # Below the inclusive lower bound.
  if [ -n "$lower" ] && [ "$(printf '%s\n%s\n' "$ver" "$lower" | sort -V | head -1)" = "$ver" ] && [ "$ver" != "$lower" ]; then
    outside="below"
  fi
  if [ -n "$outside" ]; then
    emit_finding decide chartCompat "" "chart $ver is outside catalog range $compat ($outside bound)" "$CHART/Chart.yaml" "$compat" "$ver"
  else
    emit_finding auto chartCompat "" "chart $ver within catalog range $compat" "$CHART/Chart.yaml" "$compat" "$ver"
  fi
}

check_chartcompat
