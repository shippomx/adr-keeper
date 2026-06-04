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
