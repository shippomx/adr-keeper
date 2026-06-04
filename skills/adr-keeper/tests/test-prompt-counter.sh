#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_test-helpers.sh"

SCRIPT="$HERE/../scripts/prompt-counter.sh"

adr_test_begin "silent in non-project dir"
NONPROJ=$(adr_make_tmp_nonproject)
OUT=$( cd "$NONPROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_eq "" "$OUT" "no output outside project"
adr_cleanup_tmp "$NONPROJ"

adr_test_begin "first call creates counter at 1, no output"
PROJ=$(adr_make_tmp_project)
OUT=$( cd "$PROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_eq "" "$OUT" "no output at count=1"
adr_assert_file_exists "$PROJ/.claude/.adr-counter" "counter file created"
adr_assert_eq "1" "$(cat "$PROJ/.claude/.adr-counter")" "counter = 1"
adr_cleanup_tmp "$PROJ"

adr_test_begin "10th call emits reminder"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/.claude"
echo "9" > "$PROJ/.claude/.adr-counter"
OUT=$( cd "$PROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_contains "$OUT" "additionalContext" "emits reminder at 10"
adr_assert_eq "10" "$(cat "$PROJ/.claude/.adr-counter")" "counter incremented to 10"
adr_cleanup_tmp "$PROJ"

adr_test_begin "11th call silent again"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/.claude"
echo "10" > "$PROJ/.claude/.adr-counter"
OUT=$( cd "$PROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_eq "" "$OUT" "no output at count=11"
adr_assert_eq "11" "$(cat "$PROJ/.claude/.adr-counter")" "counter = 11"
adr_cleanup_tmp "$PROJ"

adr_test_begin "20th call emits reminder again"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/.claude"
echo "19" > "$PROJ/.claude/.adr-counter"
OUT=$( cd "$PROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_contains "$OUT" "additionalContext" "emits reminder at 20"
adr_cleanup_tmp "$PROJ"

adr_test_summary
