#!/usr/bin/env bash
# secret-guard.sh - Scan a file or directory for secret-shaped content.
#
# Usage: secret-guard.sh <path> [<path>...]
# Exit:  0 = clean, 2 = secret-shaped content found (locations printed to stderr),
#        64 = usage error
#
# The wizard is secret-free: generated overlays reference secrets by name
# (existingSecret / *Ref), never inline. This guard fails the build if a literal
# secret slips into the profile or generated kit. Bash 3.2 compatible.
set -uo pipefail

# Keys that must never carry an inline literal value (anchored full-match).
SECRET_KEY_RE='(pass(word|wd)?|token|api[_-]?key|secret[_-]?key|access[_-]?key|private[_-]?key|client[_-]?secret|credential)'

# Obvious secret material regardless of key.
MATERIAL_RE='(-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ghp_[0-9A-Za-z]{20,}|github_pat_[0-9A-Za-z_]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}|hvs\.[0-9A-Za-z]{15,})'

# Values allowed even on a secret-ish key (references / placeholders / empty).
is_allowed_value() {
    v="$(printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/#.*$//')"
    [ -z "$v" ] && return 0
    case "$v" in
        '""'|"''"|'|'|'>'|'{}'|'[]') return 0 ;;
        '<'*'>'|*CHANGEME*|*REPLACE*|*PLACEHOLDER*|*YOUR_*) return 0 ;;
        *existingSecret*|*Ref*|*secretKeyRef*|*valueFrom*) return 0 ;;
    esac
    return 1
}

found=0
report() { printf 'secret-guard: %s:%s: %s\n' "$1" "$2" "$3" >&2; found=1; }

scan_file() {
    f="$1"; lineno=0
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno+1))
        if printf '%s' "$line" | grep -Eiq "$MATERIAL_RE"; then
            report "$f" "$lineno" "secret material detected"
            continue
        fi
        key="$(printf '%s' "$line" | sed -n 's/^[[:space:]]*\([A-Za-z0-9_-]*\)[[:space:]]*:.*$/\1/p')"
        [ -z "$key" ] && continue
        if printf '%s' "$key" | grep -Eiq "^$SECRET_KEY_RE$"; then
            val="$(printf '%s' "$line" | sed -n 's/^[[:space:]]*[A-Za-z0-9_-]*[[:space:]]*:\(.*\)$/\1/p')"
            if ! is_allowed_value "$val"; then
                report "$f" "$lineno" "inline value for secret-ish key '$key'"
            fi
        fi
    done < "$f"
}

[ "$#" -ge 1 ] || { echo "usage: secret-guard.sh <path> [<path>...]" >&2; exit 64; }

# Collect target files into a newline-delimited list WITHOUT a pipe-to-while
# subshell, so `found` set inside scan_file persists in the main shell.
files=""
for target in "$@"; do
    [ -e "$target" ] || continue
    if [ -d "$target" ]; then
        while IFS= read -r f; do
            files="$files
$f"
        done <<EOF
$(find "$target" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.md' \))
EOF
    else
        files="$files
$target"
    fi
done

OLDIFS="$IFS"; IFS='
'
for f in $files; do
    [ -n "$f" ] || continue
    scan_file "$f"
done
IFS="$OLDIFS"

[ "$found" -eq 0 ] || exit 2
exit 0
