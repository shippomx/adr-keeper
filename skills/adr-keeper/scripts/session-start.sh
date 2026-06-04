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

MAX_FULL = 30   # inject the whole INDEX up to this many entries
KEEP = 20       # beyond that, keep only the most recent N

with open(sys.argv[1], "r", encoding="utf-8") as f:
    lines = f.read().splitlines()

def is_entry(line):
    parts = line.split("|")
    return len(parts) > 2 and parts[1].strip()[:4].isdigit()

entry_idx = [i for i, l in enumerate(lines) if is_entry(l)]
if len(entry_idx) > MAX_FULL:
    head = lines[:entry_idx[0]]
    kept = [lines[i] for i in entry_idx[-KEEP:]]
    note = "（共 %d 条 ADR，此处仅注入最近 %d 条；完整列表见 docs/decisions/INDEX.md）" % (len(entry_idx), KEEP)
    content = "\n".join(head + kept + ["", note])
else:
    content = "\n".join(lines)

reminder = (
    "<system-reminder>\n本项目已有 ADR 决策记录（来自 docs/decisions/INDEX.md）：\n\n"
    + content
    + "\n\n引用 ADR 时用编号（如「按 0002 ...」）。不要重复讨论已确定的决策。\n"
    + "决策落定即写：本会话中用户一旦拍板（「就这么定了」「选方案 X」「确认」等），立即用 adr-keeper skill 把该决策落盘为 ADR，不要等压缩提醒。\n"
    + "</system-reminder>"
)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": reminder}}, ensure_ascii=False))
' "$INDEX"
else
    echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<system-reminder>本项目存在 docs/decisions/INDEX.md，可通过 adr list 查看历史决策。</system-reminder>"}}'
fi
