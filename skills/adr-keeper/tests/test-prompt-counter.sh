#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_test-helpers.sh"

SCRIPT="$HERE/../scripts/prompt-counter.sh"

# Resolve the counter path the same way the script does, under a fake HOME.
counter_path() {
    local fakehome="$1" root="$2"
    HOME="$fakehome" bash -c "source '$HERE/../scripts/_common.sh'; adr_counter_file '$root'"
}

adr_test_begin "silent in non-project dir"
NONPROJ=$(adr_make_tmp_nonproject)
FAKEHOME=$(adr_make_tmp_nonproject)
OUT=$( cd "$NONPROJ" && echo '{}' | HOME="$FAKEHOME" bash "$SCRIPT" )
adr_assert_eq "" "$OUT" "no output outside project"
adr_cleanup_tmp "$NONPROJ"
adr_cleanup_tmp "$FAKEHOME"

adr_test_begin "first call creates counter outside project, no output"
PROJ=$(adr_make_tmp_project)
FAKEHOME=$(adr_make_tmp_nonproject)
OUT=$( cd "$PROJ" && echo '{}' | HOME="$FAKEHOME" bash "$SCRIPT" )
CF=$(counter_path "$FAKEHOME" "$PROJ")
adr_assert_eq "" "$OUT" "no output at count=1"
adr_assert_file_exists "$CF" "counter file created under \$HOME/.claude/adr-keeper"
adr_assert_eq "1" "$(cat "$CF")" "counter = 1"
if [ -e "$PROJ/.claude/.adr-counter" ]; then
    adr_assert_eq "absent" "present" "nothing written inside project .claude/"
else
    adr_assert_eq "absent" "absent" "nothing written inside project .claude/"
fi
adr_cleanup_tmp "$PROJ"
adr_cleanup_tmp "$FAKEHOME"

adr_test_begin "10th call emits reminder with decision criteria"
PROJ=$(adr_make_tmp_project)
FAKEHOME=$(adr_make_tmp_nonproject)
CF=$(counter_path "$FAKEHOME" "$PROJ")
mkdir -p "$(dirname "$CF")"
echo "9" > "$CF"
OUT=$( cd "$PROJ" && echo '{}' | HOME="$FAKEHOME" bash "$SCRIPT" )
adr_assert_contains "$OUT" "additionalContext" "emits reminder at 10"
adr_assert_contains "$OUT" "判定标准" "reminder includes shared decision criteria"
adr_assert_contains "$OUT" "就这么定了" "criteria mention user confirmation phrases"
adr_assert_eq "10" "$(cat "$CF")" "counter incremented to 10"
adr_cleanup_tmp "$PROJ"
adr_cleanup_tmp "$FAKEHOME"

adr_test_begin "11th call silent again"
PROJ=$(adr_make_tmp_project)
FAKEHOME=$(adr_make_tmp_nonproject)
CF=$(counter_path "$FAKEHOME" "$PROJ")
mkdir -p "$(dirname "$CF")"
echo "10" > "$CF"
OUT=$( cd "$PROJ" && echo '{}' | HOME="$FAKEHOME" bash "$SCRIPT" )
adr_assert_eq "" "$OUT" "no output at count=11"
adr_assert_eq "11" "$(cat "$CF")" "counter = 11"
adr_cleanup_tmp "$PROJ"
adr_cleanup_tmp "$FAKEHOME"

adr_test_begin "20th call emits reminder again"
PROJ=$(adr_make_tmp_project)
FAKEHOME=$(adr_make_tmp_nonproject)
CF=$(counter_path "$FAKEHOME" "$PROJ")
mkdir -p "$(dirname "$CF")"
echo "19" > "$CF"
OUT=$( cd "$PROJ" && echo '{}' | HOME="$FAKEHOME" bash "$SCRIPT" )
adr_assert_contains "$OUT" "additionalContext" "emits reminder at 20"
adr_cleanup_tmp "$PROJ"
adr_cleanup_tmp "$FAKEHOME"

adr_test_begin "two projects with same basename get distinct counters"
BASE1=$(adr_make_tmp_nonproject)
BASE2=$(adr_make_tmp_nonproject)
FAKEHOME=$(adr_make_tmp_nonproject)
mkdir -p "$BASE1/myproj" "$BASE2/myproj"
(cd "$BASE1/myproj" && git init -q)
(cd "$BASE2/myproj" && git init -q)
( cd "$BASE1/myproj" && echo '{}' | HOME="$FAKEHOME" bash "$SCRIPT" >/dev/null )
( cd "$BASE2/myproj" && echo '{}' | HOME="$FAKEHOME" bash "$SCRIPT" >/dev/null )
CF1=$(counter_path "$FAKEHOME" "$BASE1/myproj")
CF2=$(counter_path "$FAKEHOME" "$BASE2/myproj")
if [ "$CF1" != "$CF2" ]; then
    adr_assert_eq "distinct" "distinct" "counter paths differ for same-basename projects"
else
    adr_assert_eq "distinct" "same" "counter paths differ for same-basename projects"
fi
adr_assert_eq "1" "$(cat "$CF1")" "project 1 counter = 1"
adr_assert_eq "1" "$(cat "$CF2")" "project 2 counter = 1"
adr_cleanup_tmp "$BASE1"
adr_cleanup_tmp "$BASE2"
adr_cleanup_tmp "$FAKEHOME"

adr_test_summary
