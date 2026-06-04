#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_test-helpers.sh"

SCRIPT="$HERE/../scripts/session-start.sh"

adr_test_begin "silent in non-project dir"
NONPROJ=$(adr_make_tmp_nonproject)
OUT=$( cd "$NONPROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_eq "" "$OUT" "no output outside project"
adr_cleanup_tmp "$NONPROJ"

adr_test_begin "silent in project without INDEX"
PROJ=$(adr_make_tmp_project)
OUT=$( cd "$PROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_eq "" "$OUT" "no output when no INDEX.md"
adr_cleanup_tmp "$PROJ"

adr_test_begin "emits additionalContext when INDEX exists"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/docs/decisions"
cat > "$PROJ/docs/decisions/INDEX.md" <<EOF
# ADR Index

| ID | 标题 | 状态 | 日期 | 标签 |
|---|---|---|---|---|
| 0001 | use postgres | Accepted | 2026-05-01 | 架构 |
EOF
OUT=$( cd "$PROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_contains "$OUT" "additionalContext" "emits JSON with additionalContext"
adr_assert_contains "$OUT" "0001" "INDEX content included"
adr_assert_contains "$OUT" "use postgres" "INDEX content included"
adr_cleanup_tmp "$PROJ"

adr_test_summary
