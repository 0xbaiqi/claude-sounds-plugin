#!/usr/bin/env bash
# Claude Sounds Plugin - Audio Player
# Called by hooks: play.sh <event>
# Events: stop, notification, error, permission, permission_request
# Hook mapping: Stop→stop, Notification→notification, PermissionRequest→permission_request

EVENT="${1:-}"
[ -z "${EVENT}" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSTHEME_PY="${SCRIPT_DIR}/cstheme.py"
USER_DIR="${HOME}/.claude/claude-sounds-xapipro"
CONFIG_FILE="${USER_DIR}/config.json"
PROJECT_CONFIG="${PWD}/.claude/sounds.json"

# ── Config readers ────────────────────────────────────────────────────────────

_cfg_global() {
    local key="$1" default="$2"
    python3 -c "
import json
try:
    with open('${CONFIG_FILE}') as f:
        c = json.load(f)
    v = c.get('${key}', '${default}')
    print(str(v).lower() if isinstance(v, bool) else str(v))
except Exception:
    print('${default}')
" 2>/dev/null || echo "${default}"
}

# ── Guards ────────────────────────────────────────────────────────────────────

if [ "${CLAUDE_SOUNDS_FORCE:-0}" != "1" ]; then
    [ "$(_cfg_global enabled true)" = "false" ] && exit 0

    _hook_enabled=$(python3 -c "
import json
try:
    with open('${PROJECT_CONFIG}') as f:
        p = json.load(f)
    hooks = p.get('hooks', {})
    if '${EVENT}' in hooks:
        print(str(hooks['${EVENT}']).lower()); exit()
except Exception:
    pass
try:
    with open('${CONFIG_FILE}') as f:
        c = json.load(f)
    v = c.get('hooks', {}).get('${EVENT}', True)
    print(str(v).lower())
except Exception:
    print('true')
" 2>/dev/null || echo "true")
    [ "${_hook_enabled}" = "false" ] && exit 0
fi

# ── Resolve theme ─────────────────────────────────────────────────────────────
# Priority: project config → global config → default

THEME=""
if [ -f "${PROJECT_CONFIG}" ]; then
    THEME=$(python3 -c "
import json
try:
    with open('${PROJECT_CONFIG}') as f:
        print(json.load(f).get('theme', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")
fi
[ -z "${THEME}" ] && THEME="$(_cfg_global theme default)"

# ── Resolve .cstheme file ─────────────────────────────────────────────────────
# Priority: user themes → plugin bundled themes → plugin default

THEME_FILE="${USER_DIR}/themes/${THEME}.cstheme"
[ ! -f "${THEME_FILE}" ] && THEME_FILE="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/..}/themes/${THEME}.cstheme"
if [ ! -f "${THEME_FILE}" ]; then
    THEME_FILE="${USER_DIR}/themes/default.cstheme"
    [ ! -f "${THEME_FILE}" ] && THEME_FILE="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/..}/themes/default.cstheme"
fi
[ ! -f "${THEME_FILE}" ] && exit 0

# ── Cache management ──────────────────────────────────────────────────────────

CACHE_DIR="${USER_DIR}/cache/${THEME}"
CACHE_MARKER="${CACHE_DIR}/.cached"

_need_refresh() {
    [ ! -f "${CACHE_MARKER}" ] && return 0
    [ "${THEME_FILE}" -nt "${CACHE_MARKER}" ] && return 0
    return 1
}

if _need_refresh; then
    python3 "${CSTHEME_PY}" extract "${THEME_FILE}" "${CACHE_DIR}" 2>/dev/null && touch "${CACHE_MARKER}" || exit 0
fi

# ── Play asynchronously ───────────────────────────────────────────────────────

SOUND_FILE="${CACHE_DIR}/${EVENT}.mp3"
[ ! -f "${SOUND_FILE}" ] && exit 0

case "$(uname -s 2>/dev/null)" in
    Darwin)
        afplay "${SOUND_FILE}" >/dev/null 2>&1 & disown
        ;;
    Linux)
        if command -v paplay >/dev/null 2>&1; then
            paplay "${SOUND_FILE}" >/dev/null 2>&1 & disown
        elif command -v aplay >/dev/null 2>&1; then
            aplay "${SOUND_FILE}" >/dev/null 2>&1 & disown
        fi
        ;;
    MINGW*|CYGWIN*|MSYS*)
        _winpath="$(cygpath -w "${SOUND_FILE}" 2>/dev/null || echo "${SOUND_FILE}")"
        powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -Command \
            "Add-Type -AssemblyName PresentationCore; \
             \$m = [System.Windows.Media.MediaPlayer]::new(); \
             \$m.Open([Uri]::new('file:///${_winpath//\\/\/}')); \
             \$m.Play(); \
             Start-Sleep -Seconds 5" \
            >/dev/null 2>&1 & disown
        ;;
esac

exit 0
