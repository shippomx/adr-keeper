#!/bin/bash
# Exit 0 if cwd is inside a project directory, non-zero otherwise.

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_common.sh"

CWD="$PWD"

# Resolve project root by walking up. If not found, not a project.
ROOT=$(adr_find_project_root "$CWD") || exit 1

# Blacklist wins.
if adr_is_blacklisted "$ROOT" || adr_is_blacklisted "$CWD"; then
    exit 1
fi

exit 0
