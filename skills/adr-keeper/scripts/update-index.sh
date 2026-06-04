#!/bin/bash
# Regenerates docs/decisions/INDEX.md from all NNNN-*.md files.
# Exits 1 if not in project dir.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_common.sh"

ROOT=$(adr_find_project_root "$PWD") || { echo "error: not in project dir" >&2; exit 1; }
if adr_is_blacklisted "$ROOT" || adr_is_blacklisted "$PWD"; then
    echo "error: blacklisted dir" >&2
    exit 1
fi

DIR="$ROOT/docs/decisions"
INDEX="$DIR/INDEX.md"
mkdir -p "$DIR"

extract_field() {
    local file="$1"
    local field="$2"
    grep -m1 "^- \*\*${field}\*\*:" "$file" 2>/dev/null \
        | sed -E "s/^- \*\*${field}\*\*:[[:space:]]*//"
}

extract_title() {
    local file="$1"
    head -1 "$file" 2>/dev/null \
        | sed -E 's/^# [0-9]+\. *//'
}

{
    echo "# ADR Index"
    echo ""
    echo "> 本文件由 update-index.sh 自动生成，请勿手动编辑。"
    echo ""
    echo "| ID | 标题 | 状态 | 日期 | 标签 |"
    echo "|---|---|---|---|---|"

    for f in $(ls "$DIR"/[0-9]*.md 2>/dev/null | sort); do
        ID=$(basename "$f" | grep -oE '^[0-9]{4}')
        TITLE=$(extract_title "$f")
        STATUS=$(extract_field "$f" "Status")
        DATE=$(extract_field "$f" "Date")
        TAGS=$(extract_field "$f" "Tags")
        [ -z "$TITLE" ] && TITLE="(no title)"
        echo "| $ID | $TITLE | $STATUS | $DATE | $TAGS |"
    done
} > "$INDEX"

echo "$INDEX"
