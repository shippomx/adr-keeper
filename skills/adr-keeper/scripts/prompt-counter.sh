#!/bin/bash
# UserPromptSubmit hook for adr-keeper.
# Maintains a per-project counter; every 10 prompts, reminds Claude
# to scan the recent conversation for unsaved design decisions.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_common.sh"

cat >/dev/null 2>&1 || true

ROOT=$(adr_find_project_root "$PWD") || exit 0
if adr_is_blacklisted "$ROOT" || adr_is_blacklisted "$PWD"; then
    exit 0
fi

# Counter lives under $HOME/.claude/adr-keeper/, never inside the project
# (an untracked .claude/ would show up in every project's git status).
COUNTER_FILE=$(adr_counter_file "$ROOT")
mkdir -p "$(dirname "$COUNTER_FILE")"

N=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
N=$((N + 1))
echo "$N" > "$COUNTER_FILE"

# Threshold: every 10 prompts.
if [ $((N % 10)) -ne 0 ]; then
    exit 0
fi

INSTR=$(cat <<'EOF'
<system-reminder>
adr-keeper: 已过 10 条用户消息。若近期对话中产生过设计决策但尚未保存，请用 `bash "__ADR_SCRIPTS__/new-adr.sh" "<slug>" "<标题>"` 创建 ADR 并填充内容，然后调用 `update-index.sh` 重建索引。若无未保存决策，忽略此提示即可。

__ADR_CRITERIA__
</system-reminder>
EOF
)
# Substitute the real scripts dir / shared criteria at runtime.
INSTR=${INSTR//__ADR_SCRIPTS__/$HERE}
INSTR=${INSTR//__ADR_CRITERIA__/$(adr_decision_criteria)}

if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
instr = sys.stdin.read()
print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": instr}}, ensure_ascii=False))
' <<< "$INSTR"
else
    ESCAPED=$(printf '%s' "$INSTR" | awk 'BEGIN{ORS="\\n"} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); print}')
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$ESCAPED"
fi
