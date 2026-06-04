#!/bin/bash
# Usage: new-adr.sh <slug> [title]
# Creates docs/decisions/NNNN-<slug>.md from template, prints the absolute path.
# Exits 1 if not in a project dir or slug missing.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_common.sh"

SLUG="${1:-}"
TITLE="${2:-}"

if [ -z "$SLUG" ]; then
    echo "error: slug required" >&2
    exit 1
fi

ROOT=$(adr_find_project_root "$PWD") || { echo "error: not in project dir" >&2; exit 1; }
if adr_is_blacklisted "$ROOT" || adr_is_blacklisted "$PWD"; then
    echo "error: blacklisted dir" >&2
    exit 1
fi

DIR="$ROOT/docs/decisions"
mkdir -p "$DIR"

LOCK="$DIR/.lock"
if ! adr_acquire_lock "$LOCK" 5; then
    echo "error: could not acquire lock" >&2
    exit 1
fi
trap 'adr_release_lock "$LOCK"' EXIT

LAST=$(ls "$DIR" 2>/dev/null | grep -oE '^[0-9]{4}' | sort -n | tail -1)
if [ -z "$LAST" ]; then
    NEXT="0001"
else
    NEXT=$(printf "%04d" $((10#$LAST + 1)))
fi

FILE="$DIR/${NEXT}-${SLUG}.md"
TEMPLATE="$HERE/../templates/adr.md"
cp "$TEMPLATE" "$FILE"

DATE=$(date +%Y-%m-%d)
TITLE_DISPLAY="${TITLE:-$SLUG}"

awk -v num="$NEXT" -v date="$DATE" -v title="$TITLE_DISPLAY" -v tags="" '
{
    gsub(/\{\{NUMBER\}\}/, num)
    gsub(/\{\{DATE\}\}/, date)
    gsub(/\{\{TITLE\}\}/, title)
    gsub(/\{\{TAGS\}\}/, tags)
    print
}' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"

echo "$FILE"
