#!/usr/bin/env bash
# Integration tests for manage.sh
# Usage: bash tests/test_manage.sh
#
# Runs all tests in an isolated temp directory so real user config is untouched.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANAGE="${PLUGIN_ROOT}/scripts/manage.sh"

# ── Test harness ─────────────────────────────────────────────────────────────

PASS=0
FAIL=0
ERRORS=()

_setup() {
    TEST_HOME=$(mktemp -d /tmp/cs-test-XXXXX)
    TEST_PROJECT=$(mktemp -d /tmp/cs-proj-XXXXX)
    export HOME="${TEST_HOME}"
    export CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}"
    export PWD="${TEST_PROJECT}"
    cd "${TEST_PROJECT}"
}

_teardown() {
    rm -rf "${TEST_HOME}" "${TEST_PROJECT}" 2>/dev/null || true
}

_run() {
    # Run manage.sh with args, capture stdout+stderr
    bash "${MANAGE}" "$@" 2>&1
}

assert_contains() {
    local output="$1" expected="$2" msg="${3:-}"
    if echo "${output}" | grep -qF "${expected}"; then
        return 0
    else
        echo "  ASSERT FAIL: expected '${expected}' in output${msg:+ ($msg)}"
        echo "  Got: ${output:0:200}"
        return 1
    fi
}

assert_not_contains() {
    local output="$1" expected="$2" msg="${3:-}"
    if echo "${output}" | grep -qF "${expected}"; then
        echo "  ASSERT FAIL: did NOT expect '${expected}' in output${msg:+ ($msg)}"
        return 1
    fi
    return 0
}

assert_exit_0() {
    local desc="$1"; shift
    if bash "${MANAGE}" "$@" >/dev/null 2>&1; then
        return 0
    else
        echo "  ASSERT FAIL: expected exit 0 for: $desc"
        return 1
    fi
}

assert_exit_nonzero() {
    local desc="$1"; shift
    if bash "${MANAGE}" "$@" >/dev/null 2>&1; then
        echo "  ASSERT FAIL: expected non-zero exit for: $desc"
        return 1
    fi
    return 0
}

run_test() {
    local name="$1"
    _setup
    local ok=true
    if "${name}" 2>&1; then
        PASS=$((PASS + 1))
        printf "  ✓ %s\n" "${name}"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("${name}")
        printf "  ✗ %s\n" "${name}"
    fi
    _teardown
}

# ── Tests: status ────────────────────────────────────────────────────────────

test_status_default() {
    local out; out=$(_run status)
    assert_contains "${out}" "Claude Sounds Plugin"
    assert_contains "${out}" "Status : true"
    assert_contains "${out}" "Theme  : default"
    assert_contains "${out}" "stop"
    assert_contains "${out}" "notification"
    assert_contains "${out}" "error"
    assert_contains "${out}" "permission"
}

test_status_no_args() {
    # default command is status
    local out; out=$(_run)
    assert_contains "${out}" "Claude Sounds Plugin"
}

# ── Tests: enable / disable ──────────────────────────────────────────────────

test_enable() {
    local out; out=$(_run enable)
    assert_contains "${out}" "Plugin enabled"
    out=$(_run status)
    assert_contains "${out}" "Status : true"
}

test_disable() {
    local out; out=$(_run disable)
    assert_contains "${out}" "Plugin disabled"
    out=$(_run status)
    assert_contains "${out}" "Status : false"
}

test_disable_then_enable() {
    _run disable >/dev/null
    _run enable >/dev/null
    local out; out=$(_run status)
    assert_contains "${out}" "Status : true"
}

# ── Tests: hook ──────────────────────────────────────────────────────────────

test_hook_status() {
    local out; out=$(_run hook status)
    assert_contains "${out}" "Hooks:"
    assert_contains "${out}" "stop"
    assert_contains "${out}" "permission"
}

test_hook_enable_disable() {
    _run hook disable stop >/dev/null
    local out; out=$(_run hook status)
    assert_contains "${out}" "stop" "stop should appear"
    # Check config file directly
    local val; val=$(python3 -c "import json; print(json.load(open('${TEST_HOME}/.claude/claude-sounds-xapipro/config.json'))['hooks']['stop'])")
    [ "${val}" = "False" ] || { echo "  ASSERT FAIL: stop should be False, got ${val}"; return 1; }

    _run hook enable stop >/dev/null
    val=$(python3 -c "import json; print(json.load(open('${TEST_HOME}/.claude/claude-sounds-xapipro/config.json'))['hooks']['stop'])")
    [ "${val}" = "True" ] || { echo "  ASSERT FAIL: stop should be True, got ${val}"; return 1; }
}

test_hook_enable_permission() {
    # permission defaults to false
    _run status >/dev/null  # init config
    local val; val=$(python3 -c "import json; print(json.load(open('${TEST_HOME}/.claude/claude-sounds-xapipro/config.json'))['hooks']['permission'])")
    [ "${val}" = "False" ] || { echo "  ASSERT FAIL: permission should default to False"; return 1; }

    _run hook enable permission >/dev/null
    val=$(python3 -c "import json; print(json.load(open('${TEST_HOME}/.claude/claude-sounds-xapipro/config.json'))['hooks']['permission'])")
    [ "${val}" = "True" ] || { echo "  ASSERT FAIL: permission should be True after enable"; return 1; }
}

test_hook_invalid_name() {
    assert_exit_nonzero "invalid hook" hook enable bogus
}

test_hook_missing_name() {
    assert_exit_nonzero "missing hook name" hook enable
}

test_hook_bad_action() {
    assert_exit_nonzero "bad action" hook foobar stop
}

# ── Tests: theme ─────────────────────────────────────────────────────────────

test_theme_switch() {
    _run status >/dev/null  # init
    local out; out=$(_run theme cyberpunk)
    assert_contains "${out}" "Global theme set to: cyberpunk"
    out=$(_run status)
    assert_contains "${out}" "Theme  : cyberpunk"
}

test_theme_list_builtin() {
    local out; out=$(_run theme list)
    assert_contains "${out}" "Installed themes:"
    assert_contains "${out}" "default"
    assert_contains "${out}" "(built-in)"
}

test_theme_pack_install_remove() {
    # Create a theme source dir
    local src="${TEST_HOME}/mytheme"
    mkdir -p "${src}"
    echo '{"name":"mytheme","display_name":"My Theme","version":"1.0.0","author":"test"}' > "${src}/manifest.json"
    for f in stop notification error permission; do
        # Create minimal "mp3" files (won't be valid audio but cstheme doesn't check)
        echo "fake-mp3-${f}" > "${src}/${f}.mp3"
    done

    # Pack
    local out; out=$(_run theme pack "${src}" "${TEST_HOME}/mytheme.cstheme")
    assert_contains "${out}" "Packed theme"
    [ -f "${TEST_HOME}/mytheme.cstheme" ] || { echo "  ASSERT FAIL: cstheme file not created"; return 1; }

    # Install
    out=$(_run theme install "${TEST_HOME}/mytheme.cstheme")
    assert_contains "${out}" "Installed theme"
    [ -f "${TEST_HOME}/.claude/claude-sounds-xapipro/themes/mytheme.cstheme" ] || { echo "  ASSERT FAIL: theme not installed"; return 1; }

    # List should show it
    out=$(_run theme list)
    assert_contains "${out}" "mytheme"

    # Remove
    out=$(_run theme remove mytheme)
    assert_contains "${out}" "Removed"
    [ ! -f "${TEST_HOME}/.claude/claude-sounds-xapipro/themes/mytheme.cstheme" ] || { echo "  ASSERT FAIL: theme not removed"; return 1; }
}

test_theme_install_nonexistent() {
    assert_exit_nonzero "install nonexistent" theme install /tmp/no-such-file.cstheme
}

test_theme_cache_clear() {
    _run status >/dev/null  # init
    local cache="${TEST_HOME}/.claude/claude-sounds-xapipro/cache/default"
    mkdir -p "${cache}"
    echo "cached" > "${cache}/stop.mp3"
    local out; out=$(_run theme cache-clear default)
    assert_contains "${out}" "Cache cleared"
    [ ! -d "${cache}" ] || { echo "  ASSERT FAIL: cache not cleared"; return 1; }
}

test_theme_cache_clear_all() {
    _run status >/dev/null  # init
    local cache="${TEST_HOME}/.claude/claude-sounds-xapipro/cache"
    mkdir -p "${cache}/a" "${cache}/b"
    local out; out=$(_run theme cache-clear)
    assert_contains "${out}" "All theme caches cleared"
    [ ! -d "${cache}" ] || { echo "  ASSERT FAIL: cache dir still exists"; return 1; }
}

# ── Tests: project ───────────────────────────────────────────────────────────

test_project_theme() {
    local out; out=$(_run project theme retro)
    assert_contains "${out}" "Project theme set to: retro"
    [ -f "${TEST_PROJECT}/.claude/sounds.json" ] || { echo "  ASSERT FAIL: project config not created"; return 1; }
    local val; val=$(python3 -c "import json; print(json.load(open('${TEST_PROJECT}/.claude/sounds.json'))['theme'])")
    [ "${val}" = "retro" ] || { echo "  ASSERT FAIL: theme should be retro, got ${val}"; return 1; }
}

test_project_hook_enable_disable() {
    _run project hook enable stop >/dev/null
    local val; val=$(python3 -c "import json; print(json.load(open('${TEST_PROJECT}/.claude/sounds.json'))['hooks']['stop'])")
    [ "${val}" = "True" ] || { echo "  ASSERT FAIL: project stop should be True"; return 1; }

    _run project hook disable stop >/dev/null
    val=$(python3 -c "import json; print(json.load(open('${TEST_PROJECT}/.claude/sounds.json'))['hooks']['stop'])")
    [ "${val}" = "False" ] || { echo "  ASSERT FAIL: project stop should be False"; return 1; }
}

test_project_hook_status() {
    _run project hook enable error >/dev/null
    local out; out=$(_run project hook status)
    assert_contains "${out}" "error"
    assert_contains "${out}" "project override"
}

test_project_status_no_config() {
    local out; out=$(_run project status)
    assert_contains "${out}" "No project config"
}

test_project_status_with_config() {
    _run project theme jazz >/dev/null
    local out; out=$(_run project status)
    assert_contains "${out}" "jazz"
}

test_project_clear() {
    _run project theme temp >/dev/null
    [ -f "${TEST_PROJECT}/.claude/sounds.json" ] || { echo "  ASSERT FAIL: config should exist before clear"; return 1; }
    local out; out=$(_run project clear)
    assert_contains "${out}" "Project config cleared"
    [ ! -f "${TEST_PROJECT}/.claude/sounds.json" ] || { echo "  ASSERT FAIL: config should be gone after clear"; return 1; }
}

test_project_clear_no_config() {
    local out; out=$(_run project clear)
    assert_contains "${out}" "No project config"
}

test_project_hook_invalid() {
    assert_exit_nonzero "project invalid hook" project hook enable bogus
}

test_project_bad_action() {
    assert_exit_nonzero "project bad action" project foobar
}

# ── Tests: help ──────────────────────────────────────────────────────────────

test_help() {
    local out; out=$(_run help)
    assert_contains "${out}" "Claude Sounds Plugin"
    assert_contains "${out}" "theme store"
    assert_contains "${out}" "project"
    assert_contains "${out}" "hook enable"
    assert_contains "${out}" "theme pack"
}

test_help_flags() {
    local out; out=$(_run -h)
    assert_contains "${out}" "Claude Sounds Plugin"
    out=$(_run --help)
    assert_contains "${out}" "Claude Sounds Plugin"
}

# ── Tests: unknown command ───────────────────────────────────────────────────

test_unknown_command() {
    local out; out=$(_run xyzzy 2>&1) || true
    assert_contains "${out}" "Unknown command: xyzzy"
}

# ── Tests: config persistence ────────────────────────────────────────────────

test_config_created_on_first_run() {
    _run status >/dev/null
    [ -f "${TEST_HOME}/.claude/claude-sounds-xapipro/config.json" ] || { echo "  ASSERT FAIL: config not created"; return 1; }
}

test_config_valid_json() {
    _run status >/dev/null
    python3 -c "import json; json.load(open('${TEST_HOME}/.claude/claude-sounds-xapipro/config.json'))" || { echo "  ASSERT FAIL: config is not valid JSON"; return 1; }
}

test_themes_dir_created() {
    _run status >/dev/null
    [ -d "${TEST_HOME}/.claude/claude-sounds-xapipro/themes" ] || { echo "  ASSERT FAIL: themes dir not created"; return 1; }
}

# ── Run all tests ────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════"
echo "  manage.sh Integration Tests"
echo "═══════════════════════════════════════════════════"
echo ""

# Save real HOME
REAL_HOME="${HOME}"

echo "Status:"
run_test test_status_default
run_test test_status_no_args

echo ""
echo "Enable / Disable:"
run_test test_enable
run_test test_disable
run_test test_disable_then_enable

echo ""
echo "Hook:"
run_test test_hook_status
run_test test_hook_enable_disable
run_test test_hook_enable_permission
run_test test_hook_invalid_name
run_test test_hook_missing_name
run_test test_hook_bad_action

echo ""
echo "Theme:"
run_test test_theme_switch
run_test test_theme_list_builtin
run_test test_theme_pack_install_remove
run_test test_theme_install_nonexistent
run_test test_theme_cache_clear
run_test test_theme_cache_clear_all

echo ""
echo "Project:"
run_test test_project_theme
run_test test_project_hook_enable_disable
run_test test_project_hook_status
run_test test_project_status_no_config
run_test test_project_status_with_config
run_test test_project_clear
run_test test_project_clear_no_config
run_test test_project_hook_invalid
run_test test_project_bad_action

echo ""
echo "Help:"
run_test test_help
run_test test_help_flags

echo ""
echo "Other:"
run_test test_unknown_command
run_test test_config_created_on_first_run
run_test test_config_valid_json
run_test test_themes_dir_created

# Restore HOME
export HOME="${REAL_HOME}"

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "═══════════════════════════════════════════════════"

if [ ${FAIL} -gt 0 ]; then
    echo ""
    echo "Failed tests:"
    for e in "${ERRORS[@]}"; do
        echo "  - ${e}"
    done
    exit 1
fi
