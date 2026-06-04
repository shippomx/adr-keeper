#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_test-helpers.sh"

SCRIPT="$HERE/../scripts/new-adr.sh"

adr_test_begin "creates 0001 in empty project"
PROJ=$(adr_make_tmp_project)
OUT=$( cd "$PROJ" && bash "$SCRIPT" "test-decision" )
adr_assert_eq "$PROJ/docs/decisions/0001-test-decision.md" "$OUT" "returns full path"
adr_assert_file_exists "$PROJ/docs/decisions/0001-test-decision.md" "file was created"
adr_assert_contains "$(cat "$PROJ/docs/decisions/0001-test-decision.md")" "# 0001." "number substituted"
adr_assert_contains "$(cat "$PROJ/docs/decisions/0001-test-decision.md")" "$(date +%Y-%m-%d)" "date substituted"
adr_cleanup_tmp "$PROJ"

adr_test_begin "increments from existing max"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/docs/decisions"
touch "$PROJ/docs/decisions/0001-foo.md" \
      "$PROJ/docs/decisions/0002-bar.md"
OUT=$( cd "$PROJ" && bash "$SCRIPT" "third" )
adr_assert_eq "$PROJ/docs/decisions/0003-third.md" "$OUT" "next is 0003"
adr_cleanup_tmp "$PROJ"

adr_test_begin "uses max+1 even with gaps"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/docs/decisions"
touch "$PROJ/docs/decisions/0001-foo.md" \
      "$PROJ/docs/decisions/0005-baz.md"
OUT=$( cd "$PROJ" && bash "$SCRIPT" "next" )
adr_assert_eq "$PROJ/docs/decisions/0006-next.md" "$OUT" "next is max+1 = 0006"
adr_cleanup_tmp "$PROJ"

adr_test_begin "fails on non-project dir"
NONPROJ=$(adr_make_tmp_nonproject)
( cd "$NONPROJ" && bash "$SCRIPT" "foo" >/dev/null 2>&1 )
adr_assert_exit_code 1 $? "exits 1 when not in project"
adr_cleanup_tmp "$NONPROJ"

adr_test_begin "rejects empty slug"
PROJ=$(adr_make_tmp_project)
( cd "$PROJ" && bash "$SCRIPT" "" >/dev/null 2>&1 )
adr_assert_exit_code 1 $? "exits 1 on empty slug"
adr_cleanup_tmp "$PROJ"

adr_test_begin "concurrent invocations get different numbers"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/docs/decisions"
(
    cd "$PROJ"
    bash "$SCRIPT" "a" > /tmp/adr-a.out &
    bash "$SCRIPT" "b" > /tmp/adr-b.out &
    wait
)
A=$(cat /tmp/adr-a.out)
B=$(cat /tmp/adr-b.out)
if [ "$A" != "$B" ] && [ -f "$A" ] && [ -f "$B" ]; then
    echo "  ✓ both files exist with distinct numbers"
    ADR_TEST_PASS=$((ADR_TEST_PASS + 1))
else
    echo "  ✗ concurrent run produced collision or missing file"
    echo "    A=$A B=$B"
    ADR_TEST_FAIL=$((ADR_TEST_FAIL + 1))
fi
rm -f /tmp/adr-a.out /tmp/adr-b.out
adr_cleanup_tmp "$PROJ"

adr_test_summary
