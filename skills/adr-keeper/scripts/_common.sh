#!/bin/bash
# Shared helpers for adr-keeper scripts. Source, do not execute.

# Find the project root by walking up from cwd until a project marker is found.
# Echoes the absolute path on success, returns 1 if not in a project.
adr_find_project_root() {
    local dir="${1:-$PWD}"
    while [ "$dir" != "/" ] && [ -n "$dir" ]; do
        if [ -d "$dir/.git" ] \
            || [ -d "$dir/docs/decisions" ] \
            || [ -f "$dir/package.json" ] \
            || [ -f "$dir/pom.xml" ] \
            || [ -f "$dir/go.mod" ] \
            || [ -f "$dir/Cargo.toml" ] \
            || [ -f "$dir/pyproject.toml" ] \
            || [ -f "$dir/build.gradle" ] \
            || [ -f "$dir/build.gradle.kts" ] \
            || [ -f "$dir/Makefile" ] \
            || [ -f "$dir/CMakeLists.txt" ]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

# Check whether a path is on the blacklist (unsafe to write ADRs into).
# Returns 0 if blacklisted, 1 if safe.
adr_is_blacklisted() {
    local path="$1"
    case "$path" in
        "$HOME") return 0 ;;
        "$HOME/Desktop"|"$HOME/Desktop/"*) return 0 ;;
        "$HOME/Downloads"|"$HOME/Downloads/"*) return 0 ;;
        "$HOME/Documents"|"$HOME/Documents/"*) return 0 ;;
        "$HOME/.claude"|"$HOME/.claude/"*) return 0 ;;
        /tmp) return 0 ;;
        /var/log|/var/log/*) return 0 ;;
        /var/lib|/var/lib/*) return 0 ;;
        /var/cache|/var/cache/*) return 0 ;;
        /etc|/etc/*) return 0 ;;
        /usr|/usr/*) return 0 ;;
    esac
    return 1
}

# Per-project prompt-counter file, stored OUTSIDE the project so we never
# pollute the user's working tree (untracked .claude/ in git status).
# Keyed by basename + path checksum to stay unique and human-recognizable.
# Usage: adr_counter_file <project-root>
adr_counter_file() {
    local root="$1"
    local sum
    sum=$(printf '%s' "$root" | cksum | awk '{print $1}')
    echo "$HOME/.claude/adr-keeper/counters/$(basename "$root")-$sum"
}

# Decision criteria shared verbatim by precompact.sh and prompt-counter.sh,
# so both reminders apply the same bar for "this is worth an ADR".
adr_decision_criteria() {
    cat <<'EOF'
判定标准（满足任一即写）：
1. 用户明确说「就这么定了」「选方案 X」「确认」「OK」等表达
2. 在多个方案中选择并给出理由
3. 引入或废弃了重要技术依赖
4. 数据模型或核心接口的关键定义
EOF
}

# Atomic mkdir-based lock. Caller is responsible for releasing.
# Usage: adr_acquire_lock <lockdir> [max_wait_seconds]
# Returns 0 on success, 1 on timeout.
adr_acquire_lock() {
    local lockdir="$1"
    local max_wait="${2:-5}"
    local i=0
    local max_iter=$((max_wait * 10))
    while ! mkdir "$lockdir" 2>/dev/null; do
        sleep 0.1
        i=$((i + 1))
        if [ "$i" -ge "$max_iter" ]; then
            return 1
        fi
    done
    return 0
}

adr_release_lock() {
    rmdir "$1" 2>/dev/null
}
