#!/bin/bash
# PreCompact hook for adr-keeper.
# Instructs Claude to scan the current conversation for design decisions
# and write any new ones as ADR files before the context is compacted.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_common.sh"

cat >/dev/null 2>&1 || true

ROOT=$(adr_find_project_root "$PWD") || exit 0
if adr_is_blacklisted "$ROOT" || adr_is_blacklisted "$PWD"; then
    exit 0
fi

INSTR=$(cat <<'EOF'
<system-reminder>
PreCompact: 上下文即将被压缩。若本次对话中产生过设计决策（被采纳的方案、被否决的备选、达成的架构共识），请立即扫描并以 ADR 形式保存到 ./docs/decisions/。

__ADR_CRITERIA__

操作步骤（每个新决策一遍）：
1. 调用 `bash "__ADR_SCRIPTS__/new-adr.sh" "<short-slug>" "<完整标题>"`，记下返回的文件路径
2. 用 Edit 工具填充该文件的 Context / Decision / Alternatives Considered / Consequences 字段
3. 全部写完后执行 `bash "__ADR_SCRIPTS__/update-index.sh"` 重建 INDEX

若本次对话无明显决策，回复一句「无新决策」即可，不要硬凑。
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
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreCompact", "additionalContext": instr}}, ensure_ascii=False))
' <<< "$INSTR"
else
    ESCAPED=$(printf '%s' "$INSTR" | awk 'BEGIN{ORS="\\n"} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); print}')
    printf '{"hookSpecificOutput":{"hookEventName":"PreCompact","additionalContext":"%s"}}\n' "$ESCAPED"
fi
