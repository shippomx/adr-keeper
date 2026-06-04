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
adr_assert_contains "$OUT" "决策落定即写" "standing write-at-decision-time instruction included"
adr_assert_contains "$OUT" "就这么定了" "instruction mentions confirmation phrases"
adr_cleanup_tmp "$PROJ"

adr_test_begin "small INDEX injected in full (no truncation)"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/docs/decisions"
{
    echo "# ADR Index"
    echo ""
    echo "| ID | 标题 | 状态 | 日期 | 标签 |"
    echo "|---|---|---|---|---|"
    for i in $(seq 1 30); do
        printf "| %04d | decision %d | Accepted | 2026-05-01 | 架构 |\n" "$i" "$i"
    done
} > "$PROJ/docs/decisions/INDEX.md"
OUT=$( cd "$PROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_contains "$OUT" "0001" "first entry kept at 30 entries"
adr_assert_contains "$OUT" "0030" "last entry kept at 30 entries"
adr_cleanup_tmp "$PROJ"

adr_test_begin "large INDEX truncated to most recent 20"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/docs/decisions"
{
    echo "# ADR Index"
    echo ""
    echo "| ID | 标题 | 状态 | 日期 | 标签 |"
    echo "|---|---|---|---|---|"
    for i in $(seq 1 35); do
        printf "| %04d | decision %d | Accepted | 2026-05-01 | 架构 |\n" "$i" "$i"
    done
} > "$PROJ/docs/decisions/INDEX.md"
OUT=$( cd "$PROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_contains "$OUT" "0035" "most recent entry kept"
adr_assert_contains "$OUT" "0016" "20th-from-last entry kept"
if echo "$OUT" | grep -qF "| 0001 |"; then
    adr_assert_eq "dropped" "present" "oldest entry dropped when >30"
else
    adr_assert_eq "dropped" "dropped" "oldest entry dropped when >30"
fi
adr_assert_contains "$OUT" "共 35 条" "truncation note states total count"
adr_assert_contains "$OUT" "INDEX.md" "truncation note points to full index"
adr_cleanup_tmp "$PROJ"

adr_test_summary
