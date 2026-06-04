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

COUNTER_DIR="$ROOT/.claude"
COUNTER_FILE="$COUNTER_DIR/.adr-counter"
mkdir -p "$COUNTER_DIR"

N=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
N=$((N + 1))
echo "$N" > "$COUNTER_FILE"

# Threshold: every 10 prompts.
if [ $((N % 10)) -ne 0 ]; then
    exit 0
fi

INSTR=$(cat <<'EOF'
<system-reminder>
adr-keeper: 已过 10 条用户消息。若近期对话中产生过设计决策（已采纳/已否决/重要技术选型）但尚未保存，请用 `bash "__ADR_SCRIPTS__/new-adr.sh" "<slug>" "<标题>"` 创建 ADR 并填充内容，然后调用 `update-index.sh` 重建索引。若无未保存决策，忽略此提示即可。
</system-reminder>
EOF
)
# Substitute the real scripts dir at runtime so the plugin works wherever it is installed.
INSTR=${INSTR//__ADR_SCRIPTS__/$HERE}

if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
instr = sys.stdin.read()
print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": instr}}))
' <<< "$INSTR"
else
    ESCAPED=$(printf '%s' "$INSTR" | awk 'BEGIN{ORS="\\n"} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); print}')
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$ESCAPED"
fi
