#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_test-helpers.sh"

SCRIPT="$HERE/../scripts/is-project-dir.sh"

adr_test_begin "rejects \$HOME"
( cd "$HOME" && bash "$SCRIPT" )
adr_assert_exit_code 1 $? "HOME should not be a project dir"

adr_test_begin "rejects /tmp"
( cd /tmp && bash "$SCRIPT" )
adr_assert_exit_code 1 $? "/tmp should not be a project dir"

adr_test_begin "accepts a fresh git project"
PROJ=$(adr_make_tmp_project)
( cd "$PROJ" && bash "$SCRIPT" )
adr_assert_exit_code 0 $? "fresh git dir should be a project"
adr_cleanup_tmp "$PROJ"

adr_test_begin "accepts a dir with package.json"
PROJ=$(adr_make_tmp_nonproject)
touch "$PROJ/package.json"
( cd "$PROJ" && bash "$SCRIPT" )
adr_assert_exit_code 0 $? "package.json dir is project"
adr_cleanup_tmp "$PROJ"

adr_test_begin "accepts existing docs/decisions"
PROJ=$(adr_make_tmp_nonproject)
mkdir -p "$PROJ/docs/decisions"
( cd "$PROJ" && bash "$SCRIPT" )
adr_assert_exit_code 0 $? "docs/decisions dir alone marks it as project"
adr_cleanup_tmp "$PROJ"

adr_test_begin "rejects empty dir"
PROJ=$(adr_make_tmp_nonproject)
( cd "$PROJ" && bash "$SCRIPT" )
adr_assert_exit_code 1 $? "empty dir is not a project"
adr_cleanup_tmp "$PROJ"

adr_test_begin "rejects ~/.claude"
mkdir -p "$HOME/.claude/adr-test-stub"
( cd "$HOME/.claude/adr-test-stub" && bash "$SCRIPT" )
adr_assert_exit_code 1 $? "~/.claude subdirs are blacklisted"
rmdir "$HOME/.claude/adr-test-stub"

adr_test_begin "rejects ~/Desktop subdir even with .git"
PROJ="$HOME/Desktop/adr-test-stub"
mkdir -p "$PROJ"
( cd "$PROJ" && git init -q )
( cd "$PROJ" && bash "$SCRIPT" )
adr_assert_exit_code 1 $? "blacklist wins over git marker"
rm -rf "$PROJ"

adr_test_summary
