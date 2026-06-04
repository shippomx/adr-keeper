#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_test-helpers.sh"

SCRIPT="$HERE/../scripts/update-index.sh"

write_adr() {
    local proj="$1" num="$2" title="$3" status="$4" date="$5" tags="$6"
    local file="$proj/docs/decisions/${num}-test.md"
    mkdir -p "$proj/docs/decisions"
    cat > "$file" <<EOF
# ${num}. ${title}

- **Status**: ${status}
- **Date**: ${date}
- **Tags**: ${tags}

## Context

x
EOF
}

adr_test_begin "creates header-only index when no ADRs"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/docs/decisions"
( cd "$PROJ" && bash "$SCRIPT" )
adr_assert_file_exists "$PROJ/docs/decisions/INDEX.md" "INDEX created"
INDEX=$(cat "$PROJ/docs/decisions/INDEX.md")
adr_assert_contains "$INDEX" "# ADR Index" "has header"
adr_cleanup_tmp "$PROJ"

adr_test_begin "lists multiple ADRs in order"
PROJ=$(adr_make_tmp_project)
write_adr "$PROJ" "0001" "First decision" "Accepted" "2026-01-01" "架构"
write_adr "$PROJ" "0002" "Second decision" "Accepted" "2026-02-01" "数据模型"
write_adr "$PROJ" "0003" "Third decision" "Superseded by 0007" "2026-03-01" "架构"
( cd "$PROJ" && bash "$SCRIPT" )
INDEX=$(cat "$PROJ/docs/decisions/INDEX.md")
adr_assert_contains "$INDEX" "0001" "lists 0001"
adr_assert_contains "$INDEX" "First decision" "lists title 1"
adr_assert_contains "$INDEX" "0002" "lists 0002"
adr_assert_contains "$INDEX" "Superseded by 0007" "lists status with reference"
adr_cleanup_tmp "$PROJ"

adr_test_begin "handles ADR with missing fields gracefully"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/docs/decisions"
cat > "$PROJ/docs/decisions/0001-malformed.md" <<EOF
# 0001. Malformed
EOF
( cd "$PROJ" && bash "$SCRIPT" )
adr_assert_file_exists "$PROJ/docs/decisions/INDEX.md" "INDEX created despite malformed file"
adr_cleanup_tmp "$PROJ"

adr_test_begin "fails outside project"
NONPROJ=$(adr_make_tmp_nonproject)
( cd "$NONPROJ" && bash "$SCRIPT" >/dev/null 2>&1 )
adr_assert_exit_code 1 $? "exits 1 when not in project"
adr_cleanup_tmp "$NONPROJ"

adr_test_summary
