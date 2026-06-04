#!/bin/bash
# SessionStart hook for adr-keeper.
# Reads hook payload from stdin (currently unused), checks project,
# and if docs/decisions/INDEX.md exists, emits it to Claude via additionalContext.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_common.sh"

# Drain stdin silently so the hook protocol stays happy.
cat >/dev/null 2>&1 || true

ROOT=$(adr_find_project_root "$PWD") || exit 0
if adr_is_blacklisted "$ROOT" || adr_is_blacklisted "$PWD"; then
    exit 0
fi

INDEX="$ROOT/docs/decisions/INDEX.md"
[ -f "$INDEX" ] || exit 0

# Build the system-reminder payload. Use python3 for JSON escaping
# of file contents; fall back to a stripped fallback if python missing.
if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    content = f.read()
reminder = "<system-reminder>\n本项目已有 ADR 决策记录（来自 docs/decisions/INDEX.md）：\n\n" + content + "\n引用 ADR 时用编号（如「按 0002 ...」）。不要重复讨论已确定的决策。\n</system-reminder>"
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": reminder}}))
' "$INDEX"
else
    echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<system-reminder>本项目存在 docs/decisions/INDEX.md，可通过 adr list 查看历史决策。</system-reminder>"}}'
fi
