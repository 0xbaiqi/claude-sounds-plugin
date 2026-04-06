#!/usr/bin/env bash
# Claude Sounds Plugin - Management CLI
# Called by /sounds command: manage.sh [args...]

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
USER_DIR="${HOME}/.claude/claude-sounds-xapipro"
CONFIG_FILE="${USER_DIR}/config.json"
THEMES_DIR="${USER_DIR}/themes"
CACHE_DIR="${USER_DIR}/cache"
PLAY_SH="${PLUGIN_ROOT}/scripts/play.sh"
CSTHEME_PY="${PLUGIN_ROOT}/scripts/cstheme.py"
VALID_HOOKS="stop notification error permission"

# ── Helpers ───────────────────────────────────────────────────────────────────

_die() { echo "Error: $*" >&2; exit 1; }

_init_config() {
    if [ ! -f "${CONFIG_FILE}" ]; then
        mkdir -p "${USER_DIR}/themes"
        cat > "${CONFIG_FILE}" << 'EOF'
{
  "theme": "default",
  "enabled": true,
  "store_url": "https://raw.githubusercontent.com/0xbaiqi/claude-sounds-themes/main",
  "hooks": {
    "stop": true,
    "notification": true,
    "error": true,
    "permission": false
  }
}
EOF
    fi
}

_read() {
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

_set() {
    local key="$1" value="$2"
    python3 - "${CONFIG_FILE}" "${key}" "${value}" << 'PYEOF'
import json, sys
path, key, raw = sys.argv[1], sys.argv[2], sys.argv[3]
value = True if raw == "true" else (False if raw == "false" else raw)
with open(path) as f:
    c = json.load(f)
c[key] = value
with open(path, "w") as f:
    json.dump(c, f, indent=2)
    f.write("\n")
PYEOF
}

_set_hook() {
    local hook="$1" value="$2"
    python3 - "${CONFIG_FILE}" "${hook}" "${value}" << 'PYEOF'
import json, sys
path, hook, raw = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    c = json.load(f)
if "hooks" not in c:
    c["hooks"] = {}
c["hooks"][hook] = (raw == "true")
with open(path, "w") as f:
    json.dump(c, f, indent=2)
    f.write("\n")
PYEOF
}

_hook_state() {
    python3 -c "
import json
try:
    with open('${CONFIG_FILE}') as f:
        c = json.load(f)
    v = c.get('hooks', {}).get('${1}', True)
    print('enabled' if v else 'disabled')
except Exception:
    print('enabled')
" 2>/dev/null || echo "enabled"
}

_valid_hook() {
    for v in ${VALID_HOOKS}; do [ "$1" = "${v}" ] && return 0; done
    return 1
}

# ── Commands ──────────────────────────────────────────────────────────────────

cmd_status() {
    _init_config
    echo "Claude Sounds Plugin"
    echo "  Status : $(_read enabled true)"
    echo "  Theme  : $(_read theme default)"
    echo "  Hooks  :"
    for h in ${VALID_HOOKS}; do
        printf "    %-14s %s\n" "${h}" "$(_hook_state "${h}")"
    done
}

cmd_enable()  { _init_config; _set enabled true;  echo "Plugin enabled."; }
cmd_disable() { _init_config; _set enabled false; echo "Plugin disabled."; }

cmd_hook() {
    _init_config
    local action="${1:-}"
    case "${action}" in
        status)
            echo "Hooks:"
            for h in ${VALID_HOOKS}; do
                printf "  %-14s %s\n" "${h}" "$(_hook_state "${h}")"
            done
            ;;
        enable|disable)
            local hook="${2:-}"
            [ -z "${hook}" ] && _die "Usage: hook ${action} <${VALID_HOOKS// /|}>"
            _valid_hook "${hook}" || _die "Unknown hook '${hook}'. Valid: ${VALID_HOOKS}"
            local val; val=$([ "${action}" = "enable" ] && echo "true" || echo "false")
            _set_hook "${hook}" "${val}"
            echo "Hook [${hook}] ${action}d."
            ;;
        *)
            _die "Usage: hook <enable|disable|status> [hook-name]"
            ;;
    esac
}

cmd_theme() {
    _init_config
    local action="${1:-}"
    case "${action}" in
        list)
            echo "Installed themes:"
            # Plugin bundled themes
            for f in "${PLUGIN_ROOT}/themes/"*.cstheme; do
                [ -f "${f}" ] || continue
                _print_theme_row "${f}" "(built-in)"
            done
            # User installed themes
            mkdir -p "${THEMES_DIR}"
            for f in "${THEMES_DIR}/"*.cstheme; do
                [ -f "${f}" ] || continue
                _print_theme_row "${f}" ""
            done
            ;;
        pack)
            local src="${2:-}" out="${3:-}"
            [ -z "${src}" ] && _die "Usage: theme pack <source-dir> [output.cstheme]"
            [ -z "${out}" ] && out="$(basename "${src}").cstheme"
            python3 "${CSTHEME_PY}" pack "${src}" "${out}"
            ;;
        install)
            local file="${2:-}"
            [ -z "${file}" ] && _die "Usage: theme install <file.cstheme>"
            [ -f "${file}" ] || _die "File not found: ${file}"
            mkdir -p "${THEMES_DIR}"
            python3 "${CSTHEME_PY}" install "${file}" "${THEMES_DIR}"
            ;;
        remove)
            local name="${2:-}"
            [ -z "${name}" ] && _die "Usage: theme remove <name>"
            python3 "${CSTHEME_PY}" remove "${name}" "${THEMES_DIR}" "${CACHE_DIR}"
            ;;
        store)
            shift || true
            cmd_theme_store "$@"
            ;;
        cache-clear)
            local name="${2:-}"
            if [ -n "${name}" ]; then
                rm -rf "${CACHE_DIR:?}/${name}"
                echo "Cache cleared for theme: ${name}"
            else
                rm -rf "${CACHE_DIR:?}"
                echo "All theme caches cleared."
            fi
            ;;
        ""|use)
            local name="${2:-${1:-}}"
            [ "${action}" = "use" ] && name="${2:-}" || name="${1:-}"
            # Handle: theme <name> (no subcommand)
            if [ -z "${name}" ] || [ "${name}" = "list" ] || [ "${name}" = "use" ]; then
                _die "Usage: theme <name>"
            fi
            _set theme "${name}"
            echo "Global theme set to: ${name}"
            ;;
        *)
            # treat action as theme name
            _set theme "${action}"
            echo "Global theme set to: ${action}"
            ;;
    esac
}

_print_theme_row() {
    local file="$1" tag="$2"
    local info
    info=$(python3 -c "
import json, sys
try:
    import importlib.util, os
    spec = importlib.util.spec_from_file_location('cstheme', '${CSTHEME_PY}')
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    manifest, _ = m._parse('${file}')
    name    = manifest.get('name', '?')
    display = manifest.get('display_name', name)
    version = manifest.get('version', '')
    size    = os.path.getsize('${file}')
    print(f'{name}|{display}|{version}|{size}')
except Exception as e:
    print('?|?|?|0')
" 2>/dev/null || echo "?|?|?|0")
    local name display version size
    IFS='|' read -r name display version size <<< "${info}"
    printf "  %-16s %-20s v%-8s %s bytes %s\n" \
        "${name}" "${display}" "${version}" "${size}" "${tag}"
}

cmd_theme_store() {
    _init_config
    local action="${1:-list}"; shift || true
    local store_url; store_url=$(_read store_url "https://raw.githubusercontent.com/0xbaiqi/claude-sounds-themes/main")

    case "${action}" in
        list)
            echo "Fetching theme store..."
            local themes
            themes=$(python3 "${CSTHEME_PY}" fetch-index "${store_url}" 2>&1) || _die "${themes}"
            if [ -z "${themes}" ]; then
                echo "No themes available in store yet."
                return
            fi
            echo ""
            echo "Available themes:"
            local current; current=$(_read theme default)
            echo "${themes}" | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    t = json.loads(line)
    name    = t.get('name','?')
    display = t.get('display_name', name)
    version = t.get('version','?')
    desc    = t.get('description','')
    author  = t.get('author','')
    size    = t.get('size', 0)
    marker  = ' ←current' if name == '${current}' else ''
    print(f'  {name:<16} {display:<20} v{version:<8} {desc}')
    print(f'  {\"\":<16} by {author}  ({size:,} bytes){marker}')
    print()
"
            ;;
        install)
            local name="${1:-}"; [ -z "${name}" ] && _die "Usage: theme store install <name>"
            echo "Fetching index..."
            local themes; themes=$(python3 "${CSTHEME_PY}" fetch-index "${store_url}") || _die "Cannot fetch index"
            local file_path
            file_path=$(echo "${themes}" | python3 -c "
import json, sys
for line in sys.stdin:
    t = json.loads(line.strip())
    if t.get('name') == '${name}':
        print(t.get('file',''))
        break
")
            [ -z "${file_path}" ] && _die "Theme '${name}' not found in store"
            local url="${store_url}/${file_path}"
            local tmp; tmp=$(mktemp /tmp/claude-sounds-XXXXX.cstheme)
            echo "Downloading: ${url}"
            python3 "${CSTHEME_PY}" download "${url}" "${tmp}"
            echo "Validating..."
            python3 "${CSTHEME_PY}" validate "${tmp}" >/dev/null
            mkdir -p "${THEMES_DIR}"
            python3 "${CSTHEME_PY}" install "${tmp}" "${THEMES_DIR}"
            rm -f "${tmp}"
            echo "Done. Switch with: theme ${name}"
            ;;
        preview)
            local name="${1:-}"; [ -z "${name}" ] && _die "Usage: theme store preview <name>"
            echo "Fetching index..."
            local themes; themes=$(python3 "${CSTHEME_PY}" fetch-index "${store_url}") || _die "Cannot fetch index"
            local file_path preview_sound
            read -r file_path preview_sound <<< "$(echo "${themes}" | python3 -c "
import json, sys
for line in sys.stdin:
    t = json.loads(line.strip())
    if t.get('name') == '${name}':
        print(t.get('file',''), t.get('preview_sound','notification'))
        break
")"
            [ -z "${file_path}" ] && _die "Theme '${name}' not found in store"
            local tmp_file; tmp_file=$(mktemp /tmp/claude-sounds-XXXXX.cstheme)
            local tmp_dir; tmp_dir=$(mktemp -d /tmp/claude-sounds-preview-XXXXX)
            echo "Downloading ${name} for preview..."
            python3 "${CSTHEME_PY}" download "${store_url}/${file_path}" "${tmp_file}"
            python3 "${CSTHEME_PY}" extract "${tmp_file}" "${tmp_dir}"
            echo "Playing: ${preview_sound}.mp3"
            export CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}"
            bash "${PLAY_SH}" "${preview_sound}" 2>/dev/null || true
            # play directly from tmp_dir for preview
            local sound_file="${tmp_dir}/${preview_sound}.mp3"
            [ -f "${sound_file}" ] && afplay "${sound_file}" 2>/dev/null || \
                paplay "${sound_file}" 2>/dev/null || \
                aplay  "${sound_file}" 2>/dev/null || true
            sleep 1
            echo ""
            read -r -p "Keep this theme? [Y/n]: " keep
            if [[ "${keep:-Y}" =~ ^[Yy]$ ]]; then
                mkdir -p "${THEMES_DIR}"
                python3 "${CSTHEME_PY}" install "${tmp_file}" "${THEMES_DIR}"
                echo "Installed. Switch with: theme ${name}"
            else
                echo "Discarded."
            fi
            rm -f "${tmp_file}"; rm -rf "${tmp_dir}"
            ;;
        update)
            local name="${1:-}"
            echo "Fetching index..."
            local themes; themes=$(python3 "${CSTHEME_PY}" fetch-index "${store_url}") || _die "Cannot fetch index"
            _update_one() {
                local tname="$1"
                local file_path remote_ver
                read -r file_path remote_ver <<< "$(echo "${themes}" | python3 -c "
import json, sys
for line in sys.stdin:
    t = json.loads(line.strip())
    if t.get('name') == '${tname}':
        print(t.get('file',''), t.get('version','0'))
        break
")"
                [ -z "${file_path}" ] && { echo "  ${tname}: not in store"; return; }
                local local_file="${THEMES_DIR}/${tname}.cstheme"
                local local_ver=""
                [ -f "${local_file}" ] && local_ver=$(python3 -c "
import sys; sys.path.insert(0,'$(dirname "${CSTHEME_PY}")')
import cstheme, json
m,_ = cstheme._parse('${local_file}')
print(m.get('version','0'))
" 2>/dev/null)
                if [ "${remote_ver}" = "${local_ver}" ]; then
                    echo "  ${tname}: already up to date (v${local_ver})"
                else
                    echo "  ${tname}: v${local_ver} → v${remote_ver}"
                    local tmp; tmp=$(mktemp /tmp/claude-sounds-XXXXX.cstheme)
                    python3 "${CSTHEME_PY}" download "${store_url}/${file_path}" "${tmp}"
                    python3 "${CSTHEME_PY}" install "${tmp}" "${THEMES_DIR}"
                    rm -f "${tmp}"; rm -rf "${CACHE_DIR:?}/${tname}"
                    echo "  ${tname}: updated"
                fi
            }
            if [ -n "${name}" ]; then
                _update_one "${name}"
            else
                # update all installed user themes
                for f in "${THEMES_DIR}/"*.cstheme; do
                    [ -f "${f}" ] || continue
                    _update_one "$(basename "${f}" .cstheme)"
                done
            fi
            ;;
        *)
            _die "Usage: theme store <list|install|preview|update> [name]"
            ;;
    esac
}

cmd_project() {
    local action="${1:-}"; shift || true
    local project_config="${PWD}/.claude/sounds.json"

    _proj_read() {
        python3 -c "
import json
try:
    with open('${project_config}') as f:
        print(json.dumps(json.load(f)))
except Exception:
    print('{}')
" 2>/dev/null || echo "{}"
    }

    _proj_write() {
        local data="$1"
        mkdir -p "${PWD}/.claude"
        echo "${data}" | python3 -c "import json,sys; json.dump(json.load(sys.stdin), open('${project_config}','w'), indent=2)" 2>/dev/null
        python3 -c "open('${project_config}','a').write('\n')" 2>/dev/null
    }

    case "${action}" in
        theme)
            local name="${1:-}"
            [ -z "${name}" ] && _die "Usage: project theme <name>"
            local data; data=$(_proj_read)
            data=$(python3 -c "import json,sys; d=json.loads('${data}'); d['theme']='${name}'; print(json.dumps(d))")
            _proj_write "${data}"
            echo "Project theme set to: ${name}  (${project_config})"
            ;;
        hook)
            local op="${1:-}" hook="${2:-}"
            case "${op}" in
                enable|disable)
                    [ -z "${hook}" ] && _die "Usage: project hook ${op} <${VALID_HOOKS// /|}>"
                    _valid_hook "${hook}" || _die "Unknown hook: ${hook}"
                    local val; val=$([ "${op}" = "enable" ] && echo "true" || echo "false")
                    local data; data=$(_proj_read)
                    data=$(python3 -c "
import json
d = json.loads('${data}')
d.setdefault('hooks', {})['${hook}'] = ('${val}' == 'true')
print(json.dumps(d))
")
                    _proj_write "${data}"
                    echo "Project hook [${hook}] ${op}d.  (${project_config})"
                    ;;
                status)
                    local data; data=$(_proj_read)
                    echo "Project hooks (${PWD}):"
                    python3 -c "
import json
d = json.loads('${data}')
hooks = d.get('hooks', {})
valid = '${VALID_HOOKS}'.split()
for h in valid:
    if h in hooks:
        state = 'enabled' if hooks[h] else 'disabled'
        print(f'  {h:<14} {state}  (project override)')
    else:
        print(f'  {h:<14} (using global setting)')
"
                    ;;
                *)
                    _die "Usage: project hook <enable|disable|status> [hook-name]"
                    ;;
            esac
            ;;
        status)
            if [ -f "${project_config}" ]; then
                echo "Project config: ${project_config}"
                python3 -c "import json; print(json.dumps(json.load(open('${project_config}')), indent=2))"
            else
                echo "No project config (using global settings)."
            fi
            ;;
        clear)
            if [ -f "${project_config}" ]; then
                rm "${project_config}"
                echo "Project config cleared. Using global settings."
            else
                echo "No project config found."
            fi
            ;;
        *)
            _die "Usage: project <theme|hook|status|clear>"
            ;;
    esac
}

cmd_ui() {
    _init_config
    local port="${1:-52437}"
    export CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}"
    echo "启动 Web UI: http://localhost:${port}"
    python3 "${PLUGIN_ROOT}/scripts/server.py" "${port}" "${PLUGIN_ROOT}"
}

cmd_test() {
    _init_config
    local event="${1:-}"
    export CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}"
    export CLAUDE_SOUNDS_FORCE=1
    if [ -n "${event}" ]; then
        echo "Testing: ${event}"
        bash "${PLAY_SH}" "${event}"
    else
        for h in ${VALID_HOOKS}; do
            echo "Testing: ${h}"
            bash "${PLAY_SH}" "${h}"
            sleep 2
        done
    fi
}

cmd_help() {
    echo "╔══════════════════════════════════════════════════╗"
    echo "║         Claude Sounds Plugin - Help              ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    echo "── 查看状态 ────────────────────────────────────────"
    echo "  /sounds:cs               查看当前配置（主题、开关、hooks）"
    echo "  /sounds:cs hook status   查看每个 hook 的启用状态"
    echo ""
    echo "── 启用 / 禁用插件 ─────────────────────────────────"
    echo "  /sounds:cs enable        启用插件（恢复所有声音）"
    echo "  /sounds:cs disable       禁用插件（静音所有事件）"
    echo ""
    echo "── 管理 Hooks ──────────────────────────────────────"
    echo "  每个事件独立控制，hook 名称："
    echo "    stop         任务完成时播放"
    echo "    notification 需要你输入时播放"
    echo "    error        出错时播放"
    echo "    permission   每次工具调用前播放（默认关闭）"
    echo ""
    echo "  /sounds:cs hook enable stop        开启 stop 声音"
    echo "  /sounds:cs hook disable stop       关闭 stop 声音"
    echo "  /sounds:cs hook enable permission  开启工具调用提示音"
    echo ""
    echo "── 主题商店 ────────────────────────────────────────"
    echo "  /sounds:cs theme store list             查看商店可用主题"
    echo "  /sounds:cs theme store install <name>   下载并安装主题"
    echo "  /sounds:cs theme store preview <name>   试听后决定是否安装"
    echo "  /sounds:cs theme store update [name]    更新已安装主题"
    echo ""
    echo "── 主题管理 ────────────────────────────────────────"
    echo "  /sounds:cs theme <name>              切换全局主题"
    echo "  /sounds:cs theme list                查看所有已安装主题"
    echo "  /sounds:cs theme install <file>      安装 .cstheme 主题包"
    echo "  /sounds:cs theme remove  <name>      删除已安装主题"
    echo "  /sounds:cs theme cache-clear         清除缓存（下次播放自动重建）"
    echo ""
    echo "── 制作本地主题 ────────────────────────────────────"
    echo "  1. 新建文件夹，放入 4 个 MP3 + manifest.json："
    echo "     mytheme/"
    echo "       stop.mp3          任务完成"
    echo "       notification.mp3  需要输入"
    echo "       error.mp3         出错"
    echo "       permission.mp3    工具调用前"
    echo '       manifest.json     {"name":"mytheme","display_name":"My Theme","version":"1.0.0"}'
    echo "  2. 打包成 .cstheme："
    echo "     /sounds:cs theme pack ./mytheme"
    echo "  3. 安装并切换："
    echo "     /sounds:cs theme install ./mytheme.cstheme"
    echo "     /sounds:cs theme mytheme"
    echo ""
    echo "── 按项目配置（主题 + Hooks）───────────────────────"
    echo "  在项目根目录运行，只影响当前项目："
    echo "  /sounds:cs project theme cyberpunk      设置项目主题"
    echo "  /sounds:cs project hook enable  stop    项目内开启 stop"
    echo "  /sounds:cs project hook disable stop    项目内关闭 stop"
    echo "  /sounds:cs project hook status          查看项目 hook 配置"
    echo "  /sounds:cs project status               查看完整项目配置"
    echo "  /sounds:cs project clear                清除项目配置（回退到全局）"
    echo ""
    echo "  配置文件：<项目根>/.claude/sounds.json"
    echo "  优先级：项目配置 > 全局配置 > 内置默认"
    echo ""
    echo "── 图形界面 ────────────────────────────────────────"
    echo "  /sounds:cs ui            打开 Web UI（自动启动浏览器）"
    echo "  /sounds:cs ui 8080       指定端口"
    echo ""
    echo "── 测试声音 ────────────────────────────────────────"
    echo "  /sounds:cs test              依次测试所有声音"
    echo "  /sounds:cs test stop         只测试 stop 声音"
    echo "  /sounds:cs test notification 只测试 notification 声音"
    echo "  /sounds:cs test error        只测试 error 声音"
    echo "  /sounds:cs test permission   只测试 permission 声音"
}

# ── Entry point ───────────────────────────────────────────────────────────────

CMD="${1:-status}"
shift || true

case "${CMD}" in
    status)          cmd_status ;;
    help|-h|--help)  cmd_help ;;
    enable)          cmd_enable ;;
    disable)         cmd_disable ;;
    hook)            cmd_hook "$@" ;;
    theme)           cmd_theme "$@" ;;
    project)         cmd_project "$@" ;;
    ui)              cmd_ui "$@" ;;
    test)            cmd_test "$@" ;;
    *)               echo "Unknown command: ${CMD}"; echo ""; cmd_help; exit 1 ;;
esac
