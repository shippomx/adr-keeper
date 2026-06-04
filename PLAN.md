# ADR Keeper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a project-level ADR (Architecture Decision Record) tool that auto-saves design decisions before context loss, with three Claude Code hooks for automation plus a skill for manual operations.

**Architecture:** All scripts are pure bash (no Python/Node/db). Three hooks (SessionStart/PreCompact/UserPromptSubmit) wired in `~/.claude/settings.json` call scripts in `~/.claude/skills/adr-keeper/scripts/`. Each script outputs hook-protocol JSON (`{"additionalContext": "..."}`) on stdout to inject instructions to Claude. ADR files live in each project's `docs/decisions/` directory. A bash test suite verifies every script with TDD before wiring hooks live.

**Tech Stack:** bash 5+, `jq` (for settings.json merge), `mkdir`-based atomic locking (portable), `rg`/`grep` for search. No external dependencies beyond stock macOS/Linux toolchain.

**Plan file location:** This plan lives at `~/.claude/skills/adr-keeper/PLAN.md` (next to SPEC.md) because `~/.claude` is not a git repo. Default `docs/superpowers/plans/` does not apply.

**Reference spec:** `~/.claude/skills/adr-keeper/SPEC.md`

---

## File Structure

```
~/.claude/skills/adr-keeper/
├── SKILL.md                  ← skill metadata + user-facing command docs
├── SPEC.md                   ← exists, design doc
├── PLAN.md                   ← this file
├── templates/
│   └── adr.md                ← single-file ADR skeleton
├── scripts/
│   ├── _common.sh            ← shared helpers (lock, find_project_root)
│   ├── is-project-dir.sh     ← exit 0 if cwd is a project dir
│   ├── new-adr.sh            ← print path to new docs/decisions/NNNN-slug.md
│   ├── update-index.sh       ← regenerate docs/decisions/INDEX.md
│   ├── session-start.sh      ← SessionStart hook: inject INDEX to Claude
│   ├── precompact.sh         ← PreCompact hook: instruct Claude to scan & write
│   └── prompt-counter.sh     ← UserPromptSubmit hook: every-10 frequency gate
└── tests/
    ├── _test-helpers.sh      ← shared assertion/setup helpers
    ├── test-is-project-dir.sh
    ├── test-new-adr.sh
    ├── test-update-index.sh
    ├── test-session-start.sh
    ├── test-precompact.sh
    ├── test-prompt-counter.sh
    └── run-all.sh            ← runs every test, exits 1 on any failure

~/.claude/settings.json       ← modified to append our 3 hooks
```

**Boundaries (one responsibility per file):**

- `_common.sh`: pure utility, no I/O side effects beyond what callers ask for
- `is-project-dir.sh`: only decides yes/no; everything else short-circuits on this
- `new-adr.sh` / `update-index.sh`: pure data layer, no hook protocol concerns
- `*-hook` scripts: only translate environment → hook protocol; delegate to data layer
- `_test-helpers.sh`: assertion DSL only, no test cases

---

## Task 1: Scaffold directory + ADR template

**Files:**
- Create: `~/.claude/skills/adr-keeper/templates/adr.md`
- Create: `~/.claude/skills/adr-keeper/scripts/` (empty dir)
- Create: `~/.claude/skills/adr-keeper/tests/` (empty dir)

- [ ] **Step 1: Create directories**

Run:
```bash
mkdir -p ~/.claude/skills/adr-keeper/templates \
         ~/.claude/skills/adr-keeper/scripts \
         ~/.claude/skills/adr-keeper/tests
```

Expected: no output, exit 0.

- [ ] **Step 2: Write the ADR template**

Create `~/.claude/skills/adr-keeper/templates/adr.md` with exactly:

```markdown
# {{NUMBER}}. {{TITLE}}

- **Status**: Accepted
- **Date**: {{DATE}}
- **Tags**: {{TAGS}}

## Context（背景）

<!-- 为什么需要这个决策？面临什么约束、问题、外部要求？ -->
<!-- 这是未来你回看时最重要的字段——你那时候为什么这么定 -->

## Decision（结论）

<!-- 具体决定做什么。一句话能说清最好，复杂的展开。 -->

## Alternatives Considered（备选方案）

<!-- - **方案 X**：为什么没选（要写清「不是因为差，而是因为不符合 Y」） -->
<!-- - **方案 Y**：同上 -->

## Consequences（影响）

<!-- - 正面：... -->
<!-- - 负面 / 折中：... -->
<!-- - 后续待办：... -->

## References（可选）

<!-- - 相关 ADR：[[NNNN]] [[NNNN]] -->
<!-- - 外部链接：... -->
<!-- - 相关代码：`src/foo/bar.ts` -->
```

- [ ] **Step 3: Verify template renders correctly**

Run:
```bash
cat ~/.claude/skills/adr-keeper/templates/adr.md | head -5
```

Expected output (first 5 lines):
```
# {{NUMBER}}. {{TITLE}}

- **Status**: Accepted
- **Date**: {{DATE}}
- **Tags**: {{TAGS}}
```

No commit step (`~/.claude` is not a git repo).

---

## Task 2: Build `_common.sh` shared helpers

**Files:**
- Create: `~/.claude/skills/adr-keeper/scripts/_common.sh`

This file holds pure helper functions used by every other script. No CLI surface, only `source`-able functions.

- [ ] **Step 1: Write `_common.sh`**

Create `~/.claude/skills/adr-keeper/scripts/_common.sh` with exactly:

```bash
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
        /tmp|/tmp/*) return 0 ;;
        /var|/var/*) return 0 ;;
        /private|/private/*) return 0 ;;
        "$HOME/.claude"|"$HOME/.claude/"*) return 0 ;;
    esac
    return 1
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
```

- [ ] **Step 2: Make sourceable, no-exec smoke test**

Run:
```bash
bash -c 'source ~/.claude/skills/adr-keeper/scripts/_common.sh && type adr_find_project_root'
```

Expected output:
```
adr_find_project_root is a function
adr_find_project_root ()
...
```

---

## Task 3: Build test helpers

**Files:**
- Create: `~/.claude/skills/adr-keeper/tests/_test-helpers.sh`

- [ ] **Step 1: Write `_test-helpers.sh`**

Create `~/.claude/skills/adr-keeper/tests/_test-helpers.sh` with exactly:

```bash
#!/bin/bash
# Test helpers for adr-keeper. Source, do not execute.

ADR_TEST_PASS=0
ADR_TEST_FAIL=0
ADR_TEST_CURRENT=""

adr_test_begin() {
    ADR_TEST_CURRENT="$1"
    echo "--- $1"
}

adr_assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-equality}"
    if [ "$expected" = "$actual" ]; then
        echo "  ✓ $msg"
        ADR_TEST_PASS=$((ADR_TEST_PASS + 1))
    else
        echo "  ✗ $msg"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        ADR_TEST_FAIL=$((ADR_TEST_FAIL + 1))
    fi
}

adr_assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-exit code}"
    if [ "$expected" -eq "$actual" ]; then
        echo "  ✓ $msg (exit $actual)"
        ADR_TEST_PASS=$((ADR_TEST_PASS + 1))
    else
        echo "  ✗ $msg: expected exit $expected, got $actual"
        ADR_TEST_FAIL=$((ADR_TEST_FAIL + 1))
    fi
}

adr_assert_file_exists() {
    local path="$1"
    local msg="${2:-file exists}"
    if [ -f "$path" ]; then
        echo "  ✓ $msg ($path)"
        ADR_TEST_PASS=$((ADR_TEST_PASS + 1))
    else
        echo "  ✗ $msg: $path not found"
        ADR_TEST_FAIL=$((ADR_TEST_FAIL + 1))
    fi
}

adr_assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-contains}"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  ✓ $msg"
        ADR_TEST_PASS=$((ADR_TEST_PASS + 1))
    else
        echo "  ✗ $msg: did not find '$needle' in output"
        echo "    output: $haystack"
        ADR_TEST_FAIL=$((ADR_TEST_FAIL + 1))
    fi
}

adr_test_summary() {
    echo ""
    echo "=================================="
    echo "  Passed: $ADR_TEST_PASS"
    echo "  Failed: $ADR_TEST_FAIL"
    echo "=================================="
    if [ "$ADR_TEST_FAIL" -gt 0 ]; then
        exit 1
    fi
}

# Make a temp dir that looks like a git project.
# Echoes the absolute path. Caller cd's into it.
adr_make_tmp_project() {
    local dir
    dir=$(mktemp -d)
    (cd "$dir" && git init -q)
    echo "$dir"
}

# Make a temp dir with no project markers.
adr_make_tmp_nonproject() {
    mktemp -d
}

adr_cleanup_tmp() {
    [ -n "$1" ] && [ -d "$1" ] && rm -rf "$1"
}
```

- [ ] **Step 2: Smoke-test the helpers**

Run:
```bash
bash -c 'source ~/.claude/skills/adr-keeper/tests/_test-helpers.sh && adr_test_begin "smoke" && adr_assert_eq "a" "a" "trivial" && adr_test_summary'
```

Expected output:
```
--- smoke
  ✓ trivial

==================================
  Passed: 1
  Failed: 0
==================================
```

---

## Task 4: TDD — `is-project-dir.sh`

**Files:**
- Create: `~/.claude/skills/adr-keeper/tests/test-is-project-dir.sh`
- Create: `~/.claude/skills/adr-keeper/scripts/is-project-dir.sh`

- [ ] **Step 1: Write the failing test**

Create `~/.claude/skills/adr-keeper/tests/test-is-project-dir.sh` with exactly:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/skills/adr-keeper/tests/test-is-project-dir.sh`

Expected: FAIL (script doesn't exist yet — bash error or all tests fail).

- [ ] **Step 3: Implement `is-project-dir.sh`**

Create `~/.claude/skills/adr-keeper/scripts/is-project-dir.sh` with exactly:

```bash
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
```

Make it executable:
```bash
chmod +x ~/.claude/skills/adr-keeper/scripts/is-project-dir.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/skills/adr-keeper/tests/test-is-project-dir.sh`

Expected output ends with:
```
==================================
  Passed: 8
  Failed: 0
==================================
```

---

## Task 5: TDD — `new-adr.sh`

**Files:**
- Create: `~/.claude/skills/adr-keeper/tests/test-new-adr.sh`
- Create: `~/.claude/skills/adr-keeper/scripts/new-adr.sh`

- [ ] **Step 1: Write the failing test**

Create `~/.claude/skills/adr-keeper/tests/test-new-adr.sh` with exactly:

```bash
#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_test-helpers.sh"

SCRIPT="$HERE/../scripts/new-adr.sh"

adr_test_begin "creates 0001 in empty project"
PROJ=$(adr_make_tmp_project)
OUT=$( cd "$PROJ" && bash "$SCRIPT" "test-decision" )
adr_assert_eq "$PROJ/docs/decisions/0001-test-decision.md" "$OUT" "returns full path"
adr_assert_file_exists "$PROJ/docs/decisions/0001-test-decision.md" "file was created"
adr_assert_contains "$(cat "$PROJ/docs/decisions/0001-test-decision.md")" "# 0001." "number substituted"
adr_assert_contains "$(cat "$PROJ/docs/decisions/0001-test-decision.md")" "$(date +%Y-%m-%d)" "date substituted"
adr_cleanup_tmp "$PROJ"

adr_test_begin "increments from existing max"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/docs/decisions"
touch "$PROJ/docs/decisions/0001-foo.md" \
      "$PROJ/docs/decisions/0002-bar.md"
OUT=$( cd "$PROJ" && bash "$SCRIPT" "third" )
adr_assert_eq "$PROJ/docs/decisions/0003-third.md" "$OUT" "next is 0003"
adr_cleanup_tmp "$PROJ"

adr_test_begin "uses max+1 even with gaps"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/docs/decisions"
touch "$PROJ/docs/decisions/0001-foo.md" \
      "$PROJ/docs/decisions/0005-baz.md"
OUT=$( cd "$PROJ" && bash "$SCRIPT" "next" )
adr_assert_eq "$PROJ/docs/decisions/0006-next.md" "$OUT" "next is max+1 = 0006"
adr_cleanup_tmp "$PROJ"

adr_test_begin "fails on non-project dir"
NONPROJ=$(adr_make_tmp_nonproject)
( cd "$NONPROJ" && bash "$SCRIPT" "foo" >/dev/null 2>&1 )
adr_assert_exit_code 1 $? "exits 1 when not in project"
adr_cleanup_tmp "$NONPROJ"

adr_test_begin "rejects empty slug"
PROJ=$(adr_make_tmp_project)
( cd "$PROJ" && bash "$SCRIPT" "" >/dev/null 2>&1 )
adr_assert_exit_code 1 $? "exits 1 on empty slug"
adr_cleanup_tmp "$PROJ"

adr_test_begin "concurrent invocations get different numbers"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/docs/decisions"
(
    cd "$PROJ"
    bash "$SCRIPT" "a" > /tmp/adr-a.out &
    bash "$SCRIPT" "b" > /tmp/adr-b.out &
    wait
)
A=$(cat /tmp/adr-a.out)
B=$(cat /tmp/adr-b.out)
if [ "$A" != "$B" ] && [ -f "$A" ] && [ -f "$B" ]; then
    echo "  ✓ both files exist with distinct numbers"
    ADR_TEST_PASS=$((ADR_TEST_PASS + 1))
else
    echo "  ✗ concurrent run produced collision or missing file"
    echo "    A=$A B=$B"
    ADR_TEST_FAIL=$((ADR_TEST_FAIL + 1))
fi
rm -f /tmp/adr-a.out /tmp/adr-b.out
adr_cleanup_tmp "$PROJ"

adr_test_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/skills/adr-keeper/tests/test-new-adr.sh`

Expected: FAIL (script does not exist).

- [ ] **Step 3: Implement `new-adr.sh`**

Create `~/.claude/skills/adr-keeper/scripts/new-adr.sh` with exactly:

```bash
#!/bin/bash
# Usage: new-adr.sh <slug> [title]
# Creates docs/decisions/NNNN-<slug>.md from template, prints the absolute path.
# Exits 1 if not in a project dir or slug missing.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_common.sh"

SLUG="${1:-}"
TITLE="${2:-}"

if [ -z "$SLUG" ]; then
    echo "error: slug required" >&2
    exit 1
fi

ROOT=$(adr_find_project_root "$PWD") || { echo "error: not in project dir" >&2; exit 1; }
if adr_is_blacklisted "$ROOT" || adr_is_blacklisted "$PWD"; then
    echo "error: blacklisted dir" >&2
    exit 1
fi

DIR="$ROOT/docs/decisions"
mkdir -p "$DIR"

LOCK="$DIR/.lock"
if ! adr_acquire_lock "$LOCK" 5; then
    echo "error: could not acquire lock" >&2
    exit 1
fi
trap 'adr_release_lock "$LOCK"' EXIT

LAST=$(ls "$DIR" 2>/dev/null | grep -oE '^[0-9]{4}' | sort -n | tail -1)
if [ -z "$LAST" ]; then
    NEXT="0001"
else
    NEXT=$(printf "%04d" $((10#$LAST + 1)))
fi

FILE="$DIR/${NEXT}-${SLUG}.md"
TEMPLATE="$HERE/../templates/adr.md"
cp "$TEMPLATE" "$FILE"

DATE=$(date +%Y-%m-%d)
TITLE_DISPLAY="${TITLE:-$SLUG}"

# In-place substitution. macOS sed needs '' after -i; we use a portable awk pass.
awk -v num="$NEXT" -v date="$DATE" -v title="$TITLE_DISPLAY" -v tags="" '
{
    gsub(/\{\{NUMBER\}\}/, num)
    gsub(/\{\{DATE\}\}/, date)
    gsub(/\{\{TITLE\}\}/, title)
    gsub(/\{\{TAGS\}\}/, tags)
    print
}' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"

echo "$FILE"
```

Make executable:
```bash
chmod +x ~/.claude/skills/adr-keeper/scripts/new-adr.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/skills/adr-keeper/tests/test-new-adr.sh`

Expected: all 6 test groups pass, summary shows `Failed: 0`.

---

## Task 6: TDD — `update-index.sh`

**Files:**
- Create: `~/.claude/skills/adr-keeper/tests/test-update-index.sh`
- Create: `~/.claude/skills/adr-keeper/scripts/update-index.sh`

- [ ] **Step 1: Write the failing test**

Create `~/.claude/skills/adr-keeper/tests/test-update-index.sh` with exactly:

```bash
#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_test-helpers.sh"

SCRIPT="$HERE/../scripts/update-index.sh"

write_adr() {
    local proj="$1" num="$2" title="$3" status="$4" date="$5" tags="$6"
    local file="$proj/docs/decisions/${num}-test.md"
    mkdir -p "$proj/docs/decisions"
    cat > "$file" <<EOF
# ${num}. ${title}

- **Status**: ${status}
- **Date**: ${date}
- **Tags**: ${tags}

## Context

x
EOF
}

adr_test_begin "creates header-only index when no ADRs"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/docs/decisions"
( cd "$PROJ" && bash "$SCRIPT" )
adr_assert_file_exists "$PROJ/docs/decisions/INDEX.md" "INDEX created"
INDEX=$(cat "$PROJ/docs/decisions/INDEX.md")
adr_assert_contains "$INDEX" "# ADR Index" "has header"
adr_cleanup_tmp "$PROJ"

adr_test_begin "lists multiple ADRs in order"
PROJ=$(adr_make_tmp_project)
write_adr "$PROJ" "0001" "First decision" "Accepted" "2026-01-01" "架构"
write_adr "$PROJ" "0002" "Second decision" "Accepted" "2026-02-01" "数据模型"
write_adr "$PROJ" "0003" "Third decision" "Superseded by 0007" "2026-03-01" "架构"
( cd "$PROJ" && bash "$SCRIPT" )
INDEX=$(cat "$PROJ/docs/decisions/INDEX.md")
adr_assert_contains "$INDEX" "0001" "lists 0001"
adr_assert_contains "$INDEX" "First decision" "lists title 1"
adr_assert_contains "$INDEX" "0002" "lists 0002"
adr_assert_contains "$INDEX" "Superseded by 0007" "lists status with reference"
adr_cleanup_tmp "$PROJ"

adr_test_begin "handles ADR with missing fields gracefully"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/docs/decisions"
cat > "$PROJ/docs/decisions/0001-malformed.md" <<EOF
# 0001. Malformed
EOF
( cd "$PROJ" && bash "$SCRIPT" )
adr_assert_file_exists "$PROJ/docs/decisions/INDEX.md" "INDEX created despite malformed file"
adr_cleanup_tmp "$PROJ"

adr_test_begin "fails outside project"
NONPROJ=$(adr_make_tmp_nonproject)
( cd "$NONPROJ" && bash "$SCRIPT" >/dev/null 2>&1 )
adr_assert_exit_code 1 $? "exits 1 when not in project"
adr_cleanup_tmp "$NONPROJ"

adr_test_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/skills/adr-keeper/tests/test-update-index.sh`

Expected: FAIL.

- [ ] **Step 3: Implement `update-index.sh`**

Create `~/.claude/skills/adr-keeper/scripts/update-index.sh` with exactly:

```bash
#!/bin/bash
# Regenerates docs/decisions/INDEX.md from all NNNN-*.md files.
# Exits 1 if not in project dir.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_common.sh"

ROOT=$(adr_find_project_root "$PWD") || { echo "error: not in project dir" >&2; exit 1; }
if adr_is_blacklisted "$ROOT" || adr_is_blacklisted "$PWD"; then
    echo "error: blacklisted dir" >&2
    exit 1
fi

DIR="$ROOT/docs/decisions"
INDEX="$DIR/INDEX.md"
mkdir -p "$DIR"

extract_field() {
    local file="$1"
    local field="$2"
    grep -m1 "^- \*\*${field}\*\*:" "$file" 2>/dev/null \
        | sed -E "s/^- \*\*${field}\*\*:[[:space:]]*//"
}

extract_title() {
    local file="$1"
    head -1 "$file" 2>/dev/null \
        | sed -E 's/^# [0-9]+\. *//'
}

{
    echo "# ADR Index"
    echo ""
    echo "> 本文件由 update-index.sh 自动生成，请勿手动编辑。"
    echo ""
    echo "| ID | 标题 | 状态 | 日期 | 标签 |"
    echo "|---|---|---|---|---|"

    for f in $(ls "$DIR"/[0-9]*.md 2>/dev/null | sort); do
        ID=$(basename "$f" | grep -oE '^[0-9]{4}')
        TITLE=$(extract_title "$f")
        STATUS=$(extract_field "$f" "Status")
        DATE=$(extract_field "$f" "Date")
        TAGS=$(extract_field "$f" "Tags")
        [ -z "$TITLE" ] && TITLE="(no title)"
        echo "| $ID | $TITLE | $STATUS | $DATE | $TAGS |"
    done
} > "$INDEX"

echo "$INDEX"
```

Make executable:
```bash
chmod +x ~/.claude/skills/adr-keeper/scripts/update-index.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/skills/adr-keeper/tests/test-update-index.sh`

Expected: all 4 test groups pass, summary `Failed: 0`.

---

## Task 7: TDD — `session-start.sh` hook

**Files:**
- Create: `~/.claude/skills/adr-keeper/tests/test-session-start.sh`
- Create: `~/.claude/skills/adr-keeper/scripts/session-start.sh`

This script reads a hook payload from stdin (we ignore it — SessionStart payload is minimal), checks project status, and outputs JSON.

- [ ] **Step 1: Write the failing test**

Create `~/.claude/skills/adr-keeper/tests/test-session-start.sh` with exactly:

```bash
#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_test-helpers.sh"

SCRIPT="$HERE/../scripts/session-start.sh"

adr_test_begin "silent in non-project dir"
NONPROJ=$(adr_make_tmp_nonproject)
OUT=$( cd "$NONPROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_eq "" "$OUT" "no output outside project"
adr_cleanup_tmp "$NONPROJ"

adr_test_begin "silent in project without INDEX"
PROJ=$(adr_make_tmp_project)
OUT=$( cd "$PROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_eq "" "$OUT" "no output when no INDEX.md"
adr_cleanup_tmp "$PROJ"

adr_test_begin "emits additionalContext when INDEX exists"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/docs/decisions"
cat > "$PROJ/docs/decisions/INDEX.md" <<EOF
# ADR Index

| ID | 标题 | 状态 | 日期 | 标签 |
|---|---|---|---|---|
| 0001 | use postgres | Accepted | 2026-05-01 | 架构 |
EOF
OUT=$( cd "$PROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_contains "$OUT" "additionalContext" "emits JSON with additionalContext"
adr_assert_contains "$OUT" "0001" "INDEX content included"
adr_assert_contains "$OUT" "use postgres" "INDEX content included"
adr_cleanup_tmp "$PROJ"

adr_test_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/skills/adr-keeper/tests/test-session-start.sh`

Expected: FAIL.

- [ ] **Step 3: Implement `session-start.sh`**

Create `~/.claude/skills/adr-keeper/scripts/session-start.sh` with exactly:

```bash
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

# Build the system-reminder payload. Use python -c only for JSON escaping
# of the file contents; fall back to a heredoc-based escape if python missing.
if command -v python3 >/dev/null 2>&1; then
    CONTEXT=$(python3 -c '
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    content = f.read()
reminder = "<system-reminder>\n本项目已有 ADR 决策记录（来自 docs/decisions/INDEX.md）：\n\n" + content + "\n引用 ADR 时用编号（如「按 0002 ...」）。不要重复讨论已确定的决策。\n</system-reminder>"
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": reminder}}))
' "$INDEX")
    echo "$CONTEXT"
else
    # Minimal fallback: emit a stripped version without full INDEX content.
    echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<system-reminder>本项目存在 docs/decisions/INDEX.md，可通过 adr list 查看历史决策。</system-reminder>"}}'
fi
```

Make executable:
```bash
chmod +x ~/.claude/skills/adr-keeper/scripts/session-start.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/skills/adr-keeper/tests/test-session-start.sh`

Expected: all 3 test groups pass.

---

## Task 8: TDD — `precompact.sh` hook

**Files:**
- Create: `~/.claude/skills/adr-keeper/tests/test-precompact.sh`
- Create: `~/.claude/skills/adr-keeper/scripts/precompact.sh`

- [ ] **Step 1: Write the failing test**

Create `~/.claude/skills/adr-keeper/tests/test-precompact.sh` with exactly:

```bash
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
adr_cleanup_tmp "$PROJ"

adr_test_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/skills/adr-keeper/tests/test-precompact.sh`

Expected: FAIL.

- [ ] **Step 3: Implement `precompact.sh`**

Create `~/.claude/skills/adr-keeper/scripts/precompact.sh` with exactly:

```bash
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

# We emit a static instruction string. No file content is interpolated,
# so we can build the JSON inline without python.

INSTR=$(cat <<'EOF'
<system-reminder>
PreCompact: 上下文即将被压缩。若本次对话中产生过设计决策（被采纳的方案、被否决的备选、达成的架构共识），请立即扫描并以 ADR 形式保存到 ./docs/decisions/。

判定标准（满足任一即写）：
1. 用户明确说「就这么定了」「选方案 X」「确认」「OK」等表达
2. 在多个方案中选择并给出理由
3. 引入或废弃了重要技术依赖
4. 数据模型或核心接口的关键定义

操作步骤（每个新决策一遍）：
1. 调用 `bash ~/.claude/skills/adr-keeper/scripts/new-adr.sh "<short-slug>" "<完整标题>"`，记下返回的文件路径
2. 用 Edit 工具填充该文件的 Context / Decision / Alternatives Considered / Consequences 字段
3. 全部写完后执行 `bash ~/.claude/skills/adr-keeper/scripts/update-index.sh` 重建 INDEX

若本次对话无明显决策，回复一句「无新决策」即可，不要硬凑。
</system-reminder>
EOF
)

# Use python3 if available for safe JSON encoding; fallback to printf.
if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
instr = sys.stdin.read()
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreCompact", "additionalContext": instr}}))
' <<< "$INSTR"
else
    # Minimal escaped fallback.
    ESCAPED=$(printf '%s' "$INSTR" | awk 'BEGIN{ORS="\\n"} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); print}')
    printf '{"hookSpecificOutput":{"hookEventName":"PreCompact","additionalContext":"%s"}}\n' "$ESCAPED"
fi
```

Make executable:
```bash
chmod +x ~/.claude/skills/adr-keeper/scripts/precompact.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/skills/adr-keeper/tests/test-precompact.sh`

Expected: all 2 test groups pass.

---

## Task 9: TDD — `prompt-counter.sh` hook

**Files:**
- Create: `~/.claude/skills/adr-keeper/tests/test-prompt-counter.sh`
- Create: `~/.claude/skills/adr-keeper/scripts/prompt-counter.sh`

- [ ] **Step 1: Write the failing test**

Create `~/.claude/skills/adr-keeper/tests/test-prompt-counter.sh` with exactly:

```bash
#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/_test-helpers.sh"

SCRIPT="$HERE/../scripts/prompt-counter.sh"

adr_test_begin "silent in non-project dir"
NONPROJ=$(adr_make_tmp_nonproject)
OUT=$( cd "$NONPROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_eq "" "$OUT" "no output outside project"
adr_cleanup_tmp "$NONPROJ"

adr_test_begin "first call creates counter at 1, no output"
PROJ=$(adr_make_tmp_project)
OUT=$( cd "$PROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_eq "" "$OUT" "no output at count=1"
adr_assert_file_exists "$PROJ/.claude/.adr-counter" "counter file created"
adr_assert_eq "1" "$(cat "$PROJ/.claude/.adr-counter")" "counter = 1"
adr_cleanup_tmp "$PROJ"

adr_test_begin "10th call emits reminder"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/.claude"
echo "9" > "$PROJ/.claude/.adr-counter"
OUT=$( cd "$PROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_contains "$OUT" "additionalContext" "emits reminder at 10"
adr_assert_eq "10" "$(cat "$PROJ/.claude/.adr-counter")" "counter incremented to 10"
adr_cleanup_tmp "$PROJ"

adr_test_begin "11th call silent again"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/.claude"
echo "10" > "$PROJ/.claude/.adr-counter"
OUT=$( cd "$PROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_eq "" "$OUT" "no output at count=11"
adr_assert_eq "11" "$(cat "$PROJ/.claude/.adr-counter")" "counter = 11"
adr_cleanup_tmp "$PROJ"

adr_test_begin "20th call emits reminder again"
PROJ=$(adr_make_tmp_project)
mkdir -p "$PROJ/.claude"
echo "19" > "$PROJ/.claude/.adr-counter"
OUT=$( cd "$PROJ" && echo '{}' | bash "$SCRIPT" )
adr_assert_contains "$OUT" "additionalContext" "emits reminder at 20"
adr_cleanup_tmp "$PROJ"

adr_test_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/skills/adr-keeper/tests/test-prompt-counter.sh`

Expected: FAIL.

- [ ] **Step 3: Implement `prompt-counter.sh`**

Create `~/.claude/skills/adr-keeper/scripts/prompt-counter.sh` with exactly:

```bash
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
adr-keeper: 已过 10 条用户消息。若近期对话中产生过设计决策（已采纳/已否决/重要技术选型）但尚未保存，请用 `bash ~/.claude/skills/adr-keeper/scripts/new-adr.sh "<slug>" "<标题>"` 创建 ADR 并填充内容，然后调用 `update-index.sh` 重建索引。若无未保存决策，忽略此提示即可。
</system-reminder>
EOF
)

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
```

Make executable:
```bash
chmod +x ~/.claude/skills/adr-keeper/scripts/prompt-counter.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/skills/adr-keeper/tests/test-prompt-counter.sh`

Expected: all 5 test groups pass.

---

## Task 10: Combined test runner

**Files:**
- Create: `~/.claude/skills/adr-keeper/tests/run-all.sh`

- [ ] **Step 1: Write the runner**

Create `~/.claude/skills/adr-keeper/tests/run-all.sh` with exactly:

```bash
#!/bin/bash
# Run every adr-keeper test. Exit 1 if any test exits non-zero.
HERE="$(cd "$(dirname "$0")" && pwd)"
FAILED=0
for t in "$HERE"/test-*.sh; do
    echo ""
    echo "######### $(basename "$t") #########"
    if ! bash "$t"; then
        FAILED=$((FAILED + 1))
    fi
done
echo ""
echo "Total failing test files: $FAILED"
[ "$FAILED" -eq 0 ]
```

Make executable:
```bash
chmod +x ~/.claude/skills/adr-keeper/tests/run-all.sh
```

- [ ] **Step 2: Run all tests in sequence**

Run: `bash ~/.claude/skills/adr-keeper/tests/run-all.sh`

Expected: every test file reports `Failed: 0`, and final line reads `Total failing test files: 0`.

If any fail, fix the corresponding script before proceeding to Task 11.

---

## Task 11: Write SKILL.md (user-facing skill manifest)

**Files:**
- Create: `~/.claude/skills/adr-keeper/SKILL.md`

This file is read by Claude when the user invokes the skill. It documents the manual commands.

- [ ] **Step 1: Write `SKILL.md`**

Create `~/.claude/skills/adr-keeper/SKILL.md` with exactly:

````markdown
---
name: adr-keeper
description: Manage per-project ADR (Architecture Decision Record) files in docs/decisions/. Use when the user mentions ADR, 决策记录, 查看历史决策, 新建决策, 搜决策, supersede, deprecate, or asks to see/edit content under docs/decisions.
---

# ADR Keeper

Per-project ADR tooling. Files live in `<project>/docs/decisions/`, indexed by `INDEX.md`.

Three hooks automate saving (SessionStart loads index, PreCompact dumps decisions before context loss, UserPromptSubmit nudges every 10 prompts). This skill is the manual escape hatch.

## Commands

When the user asks for one of these actions, execute the corresponding bash command.

### List all ADRs

User triggers: "list ADRs", "show decisions", "看看有哪些决策".

Run:
```bash
cat docs/decisions/INDEX.md 2>/dev/null || echo "(no ADRs yet)"
```

### View a specific ADR

User triggers: "show ADR 0003", "看一下 0003 决策", "ADR 7 是什么".

Resolve the number to 4 digits, then:
```bash
ls docs/decisions/<4-digit-id>-*.md 2>/dev/null | head -1 | xargs cat
```

### Search ADRs

User triggers: "search ADRs for X", "在决策记录里找 X".

Run (prefer `rg`, fall back to `grep -r`):
```bash
rg "<keyword>" docs/decisions/ 2>/dev/null || grep -rn "<keyword>" docs/decisions/
```

### Create a new ADR manually

User triggers: "create ADR for X", "记一下这个决策".

Steps:
1. Pick a kebab-case slug (e.g. `use-event-sourcing`)
2. Run: `bash ~/.claude/skills/adr-keeper/scripts/new-adr.sh "<slug>" "<title>"`
3. Edit the returned file path to fill in Context / Decision / Alternatives / Consequences
4. Run: `bash ~/.claude/skills/adr-keeper/scripts/update-index.sh`

### Mark an ADR as superseded

User triggers: "supersede 0003 with 0007", "0003 已经被 0007 替换".

```bash
sed -i.bak 's/^- \*\*Status\*\*:.*$/- **Status**: Superseded by 0007/' docs/decisions/0003-*.md
rm docs/decisions/0003-*.md.bak
bash ~/.claude/skills/adr-keeper/scripts/update-index.sh
```

(Substitute the actual old/new IDs each call.)

### Mark an ADR as deprecated

User triggers: "deprecate 0005", "0005 这个决策不用了".

```bash
sed -i.bak 's/^- \*\*Status\*\*:.*$/- **Status**: Deprecated/' docs/decisions/0005-*.md
rm docs/decisions/0005-*.md.bak
bash ~/.claude/skills/adr-keeper/scripts/update-index.sh
```

Optionally append a `## Reason for deprecation` section with the user's stated reason.

## File layout reference

```
<project>/docs/decisions/
├── INDEX.md            ← auto-maintained; do not edit by hand
├── 0001-<slug>.md
├── 0002-<slug>.md
├── ...
└── .lock               ← acquired by new-adr.sh; ignore
```

## ADR template

Each ADR file has the same structure. See `~/.claude/skills/adr-keeper/templates/adr.md` for the exact skeleton. Required fields: Status, Date, Tags, Context, Decision. Optional but recommended: Alternatives Considered, Consequences, References.

Cross-reference between ADRs using `[[NNNN]]` syntax.

## Status values

- `Accepted` — currently in effect (default)
- `Proposed` — under discussion
- `Deprecated` — obsolete, no replacement
- `Superseded by NNNN` — replaced by ADR NNNN

## Hook coordination

When the PreCompact hook fires, Claude will be instructed to scan the conversation and write ADRs. The user does not need to invoke this skill manually for normal use; this skill exists for queries and manual fixes.
````

- [ ] **Step 2: Smoke-test SKILL.md is readable**

Run:
```bash
head -5 ~/.claude/skills/adr-keeper/SKILL.md
```

Expected:
```
---
name: adr-keeper
description: Manage per-project ADR (Architecture Decision Record) files in docs/decisions/. Use when the user mentions ADR, 决策记录, 查看历史决策, 新建决策, 搜决策, supersede, deprecate, or asks to see/edit content under docs/decisions.
---
```

---

## Task 12: Wire hooks into `~/.claude/settings.json`

This is the riskiest task — settings.json already contains other hooks. We must **append**, never replace.

**Files:**
- Modify: `~/.claude/settings.json` (existing — has gsd-* hooks already in SessionStart, PostToolUse, PreToolUse)

- [ ] **Step 1: Verify `jq` is installed**

Run:
```bash
command -v jq
```

Expected: prints a path (e.g. `/opt/homebrew/bin/jq`). If not installed, stop and install via `brew install jq` before continuing.

- [ ] **Step 2: Back up the current settings**

Run:
```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak.adr-keeper.$(date +%Y%m%d_%H%M%S)
ls -la ~/.claude/settings.json.bak.adr-keeper.* | tail -1
```

Expected: prints the backup filename. Verify it matches today's date.

- [ ] **Step 3: Inspect existing hooks**

Run:
```bash
jq '.hooks | keys' ~/.claude/settings.json
```

Expected output:
```json
[
  "PostToolUse",
  "PreToolUse",
  "SessionStart"
]
```

Note: `PreCompact` and `UserPromptSubmit` keys do NOT exist yet. We will add them. The existing `SessionStart` array already has gsd entries — we will append our entry to that array.

- [ ] **Step 4: Apply the merge with `jq`**

Run this exact command:
```bash
jq '
.hooks.SessionStart += [{
  "hooks": [{
    "type": "command",
    "command": "bash /Users/bmtaka/.claude/skills/adr-keeper/scripts/session-start.sh"
  }]
}]
| .hooks.PreCompact = [{
  "matcher": "*",
  "hooks": [{
    "type": "command",
    "command": "bash /Users/bmtaka/.claude/skills/adr-keeper/scripts/precompact.sh"
  }]
}]
| .hooks.UserPromptSubmit = [{
  "hooks": [{
    "type": "command",
    "command": "bash /Users/bmtaka/.claude/skills/adr-keeper/scripts/prompt-counter.sh",
    "timeout": 5
  }]
}]
' ~/.claude/settings.json > ~/.claude/settings.json.new \
  && mv ~/.claude/settings.json.new ~/.claude/settings.json
```

- [ ] **Step 5: Verify the merge**

Run:
```bash
jq '.hooks.SessionStart | length' ~/.claude/settings.json
jq '.hooks.PreCompact[0].hooks[0].command' ~/.claude/settings.json
jq '.hooks.UserPromptSubmit[0].hooks[0].command' ~/.claude/settings.json
```

Expected:
```
3
"bash /Users/bmtaka/.claude/skills/adr-keeper/scripts/precompact.sh"
"bash /Users/bmtaka/.claude/skills/adr-keeper/scripts/prompt-counter.sh"
```

(SessionStart length grew from 2 to 3 — the two gsd entries plus our new one.)

- [ ] **Step 6: Validate settings.json is well-formed**

Run:
```bash
jq '.' ~/.claude/settings.json > /dev/null && echo "valid JSON"
```

Expected: `valid JSON`. If this fails, restore from the backup created in Step 2.

- [ ] **Step 7: Confirm existing gsd entries are intact**

Run:
```bash
jq '.hooks.PostToolUse | length' ~/.claude/settings.json
jq '.hooks.PreToolUse | length' ~/.claude/settings.json
jq '[.hooks.SessionStart[].hooks[0].command] | .[]' ~/.claude/settings.json
```

Expected:
```
2
4
"node \"/Users/bmtaka/.claude/hooks/gsd-check-update.js\""
"bash /Users/bmtaka/.claude/hooks/gsd-session-state.sh"
"bash /Users/bmtaka/.claude/skills/adr-keeper/scripts/session-start.sh"
```

If existing gsd commands are missing, **stop immediately** and restore from backup.

---

## Task 13: End-to-end smoke test in a real temp project

This task validates the wired hooks work by simulating what Claude Code does.

**Files:**
- No new files — uses already-built scripts.

- [ ] **Step 1: Create a throwaway project**

Run:
```bash
SMOKE_DIR=$(mktemp -d)
cd "$SMOKE_DIR" && git init -q
echo "SMOKE_DIR=$SMOKE_DIR"
```

Expected: prints `SMOKE_DIR=/var/folders/.../tmp.XXXXXX` (the temp path).

- [ ] **Step 2: Simulate SessionStart hook on an empty project (should be silent)**

Run:
```bash
cd "$SMOKE_DIR" && echo '{}' | bash ~/.claude/skills/adr-keeper/scripts/session-start.sh
echo "---exit=$?---"
```

Expected:
```
---exit=0---
```

No JSON output because no INDEX exists. Exit code 0.

- [ ] **Step 3: Create an ADR manually**

Run:
```bash
cd "$SMOKE_DIR"
NEW=$(bash ~/.claude/skills/adr-keeper/scripts/new-adr.sh "smoke-test" "Smoke test decision")
echo "Created: $NEW"
cat "$NEW"
```

Expected: prints the file path, then the ADR template content with `# 0001. Smoke test decision` as the title and today's date.

- [ ] **Step 4: Rebuild the index**

Run:
```bash
cd "$SMOKE_DIR" && bash ~/.claude/skills/adr-keeper/scripts/update-index.sh
cat docs/decisions/INDEX.md
```

Expected: INDEX.md contains a table row referencing `0001 | Smoke test decision | Accepted | <today> | `.

- [ ] **Step 5: Re-run SessionStart — should now emit additionalContext**

Run:
```bash
cd "$SMOKE_DIR" && echo '{}' | bash ~/.claude/skills/adr-keeper/scripts/session-start.sh
```

Expected: a single JSON line containing `"hookSpecificOutput"`, `"additionalContext"`, `"SessionStart"`, and the literal string `Smoke test decision`.

- [ ] **Step 6: Test PreCompact in project**

Run:
```bash
cd "$SMOKE_DIR" && echo '{}' | bash ~/.claude/skills/adr-keeper/scripts/precompact.sh
```

Expected: a single JSON line containing `"PreCompact"` in `hookEventName` and the literal phrase `new-adr.sh` in the additionalContext payload.

- [ ] **Step 7: Test PreCompact outside project (should be silent)**

Run:
```bash
cd "$HOME" && echo '{}' | bash ~/.claude/skills/adr-keeper/scripts/precompact.sh
echo "---exit=$?---"
```

Expected:
```
---exit=0---
```

No output, exit 0.

- [ ] **Step 8: Test UserPromptSubmit counter behavior**

Run:
```bash
cd "$SMOKE_DIR"
rm -f .claude/.adr-counter
for i in $(seq 1 11); do
    echo "--- run $i ---"
    echo '{}' | bash ~/.claude/skills/adr-keeper/scripts/prompt-counter.sh
done
echo "Final counter: $(cat .claude/.adr-counter)"
```

Expected:
- Runs 1–9: only the `--- run N ---` header line, no JSON
- Run 10: header line followed by a JSON line containing `"UserPromptSubmit"` in `hookEventName`
- Run 11: header line, no JSON
- Final counter: `11`

- [ ] **Step 9: Clean up**

Run:
```bash
rm -rf "$SMOKE_DIR"
unset SMOKE_DIR
echo "cleanup done"
```

Expected: `cleanup done`.

---

## Task 14: Live verification — restart Claude Code

This step requires user action and cannot be fully automated.

- [ ] **Step 1: User restarts Claude Code in a real project**

In a separate terminal, the user opens a project directory (e.g. one with a `.git`) and runs `claude code`. The SessionStart hook fires automatically.

- [ ] **Step 2: User verifies no errors at session start**

The session should start cleanly. If `is-project-dir` blacklisting or JSON formatting is wrong, errors may appear in the session log. If errors appear:
1. Run `jq '.' ~/.claude/settings.json` to confirm syntax is valid
2. Restore from the backup created in Task 12 Step 2
3. Re-debug the failing script with the matching test from Task 4–9

- [ ] **Step 3: User runs `adr list` via the skill**

In a Claude Code session, the user prompts "list all ADRs". Claude should match the `adr-keeper` skill and run `cat docs/decisions/INDEX.md`. If the project has no INDEX, it should say "(no ADRs yet)".

- [ ] **Step 4: User triggers a manual ADR creation**

The user prompts: "Create an ADR for: we will use Postgres over MySQL because of the JSONB support". Claude runs `new-adr.sh`, fills the file, runs `update-index.sh`, and shows the result.

- [ ] **Step 5: Sign-off**

If steps 1–4 succeed without errors, the implementation is complete.

---

## Self-Review Notes

After writing this plan, I checked it against the spec:

**Spec coverage check:**
- ✓ Section 2.1 file structure → Tasks 1–11 create every listed file
- ✓ Section 2.2 tech stack (bash + jq + mkdir lock) → Task 2 uses mkdir lock, Task 12 uses jq
- ✓ Section 3.1 status flow (Accepted/Proposed/Deprecated/Superseded) → Task 11 SKILL.md documents all four
- ✓ Section 3.2 flows A/B/C/D → Tasks 7/8/9/11 implement the four flow scripts; Task 13 smoke-tests them
- ✓ Section 4.1 hook interface → Tasks 7/8/9 produce `hookSpecificOutput.additionalContext`
- ✓ Section 4.1 skill subcommands → Task 11 documents list/view/search/new/supersede/deprecate
- ✓ Section 5.1 data model (ADR fields + INDEX format) → Tasks 1, 5, 6 produce/parse them
- ✓ Section 5.2 project dir rules + blacklist → Task 4 tests both inclusively
- ✓ Section 6.2 risks → Task 4 covers blacklist, Task 5 covers concurrency, Task 12 covers settings.json safety, Task 6 covers malformed-field handling
- ✓ Section 7 test scenarios — every "待验证" test maps to a Task 4–9 test case

**Placeholder scan:** No TBD/TODO/placeholder phrases. All code blocks are complete and copy-pastable.

**Type/name consistency:**
- `adr_find_project_root`, `adr_is_blacklisted`, `adr_acquire_lock`, `adr_release_lock` — defined in Task 2, used identically in Tasks 4/5/6/7/8/9
- ADR template fields (`Status`, `Date`, `Tags`) — written in Task 1 template, read in Task 6 `update-index.sh` via `extract_field`, displayed in Task 11 SKILL.md
- File path conventions (`<proj>/docs/decisions/NNNN-<slug>.md`, `<proj>/.claude/.adr-counter`) — consistent across all tasks
- Counter threshold `10` — appears only in Task 9 implementation and matches the test cases

No drift detected.
