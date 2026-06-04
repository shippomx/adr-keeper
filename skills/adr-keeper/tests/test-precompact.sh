#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_test-helpers.sh"

SCRIPT="$HERE/../scripts/precompact.sh"

adr_test_begin "silent in non-project dir"
NONPROJ=$(adr_make_tmp_nonproject)
OUT=$( cd "$NONPROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_eq "" "$OUT" "no output outside project"
adr_cleanup_tmp "$NONPROJ"

adr_test_begin "emits instruction in project dir"
PROJ=$(adr_make_tmp_project)
OUT=$( cd "$PROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_contains "$OUT" "additionalContext" "outputs hook JSON"
adr_assert_contains "$OUT" "PreCompact" "mentions PreCompact"
adr_assert_contains "$OUT" "new-adr.sh" "references new-adr.sh"
adr_assert_contains "$OUT" "update-index.sh" "references update-index.sh"
adr_assert_contains "$OUT" "docs/decisions" "references docs/decisions path"
adr_assert_contains "$OUT" "判定标准" "includes shared decision criteria"
adr_assert_contains "$OUT" "就这么定了" "criteria mention user confirmation phrases"
adr_cleanup_tmp "$PROJ"

adr_test_summary
