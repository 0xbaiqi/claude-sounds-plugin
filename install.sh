#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="${HOME}/.claude/plugins"
INSTALL_LINK="${PLUGINS_DIR}/claude-sounds"
INSTALLED_JSON="${PLUGINS_DIR}/installed_plugins.json"
PLUGIN_KEY="claude-sounds@local"

echo "Claude Sounds Plugin - Installer"
echo ""

# ── 1. Choose scope ───────────────────────────────────────────────────────────

echo "Install scope:"
echo "  1) user    - all projects (current user)"
echo "  2) project - current directory only"
echo ""
read -r -p "Choose [1/2] (default: 1): " scope_choice
scope_choice="${scope_choice:-1}"

SCOPE=""
PROJECT_PATH=""

case "${scope_choice}" in
    1)
        SCOPE="user"
        ;;
    2)
        SCOPE="project"
        PROJECT_PATH="$(pwd)"
        echo ""
        echo "Project path: ${PROJECT_PATH}"
        read -r -p "Use this path? [Y/n]: " confirm
        confirm="${confirm:-Y}"
        if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
            read -r -p "Enter project path: " PROJECT_PATH
        fi
        ;;
    *)
        echo "Invalid choice. Aborting." >&2
        exit 1
        ;;
esac

echo ""
echo "Scope: ${SCOPE}${PROJECT_PATH:+ → ${PROJECT_PATH}}"

# ── 2. Create symlink ─────────────────────────────────────────────────────────

mkdir -p "${PLUGINS_DIR}"
ln -sfn "${PLUGIN_DIR}" "${INSTALL_LINK}"
echo "Linked: ${INSTALL_LINK} → ${PLUGIN_DIR}"

# ── 3. Register in installed_plugins.json ─────────────────────────────────────

python3 - "${INSTALLED_JSON}" "${PLUGIN_KEY}" "${SCOPE}" "${PROJECT_PATH}" "${INSTALL_LINK}" << 'PYEOF'
import json, os, sys
from datetime import datetime, timezone

path, key, scope, project_path, install_path = sys.argv[1:6]
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")

# Load or init
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
else:
    data = {"version": 2, "plugins": {}}

# Remove existing entry for this key
data["plugins"].pop(key, None)

entry = {
    "scope": scope,
    "installPath": install_path,
    "version": "1.0.0",
    "installedAt": now,
    "lastUpdated": now
}
if project_path:
    entry["projectPath"] = project_path

data["plugins"][key] = [entry]

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

echo "Registered: ${PLUGIN_KEY} (scope: ${SCOPE})"

# ── 4. Init user config ───────────────────────────────────────────────────────

USER_DIR="${HOME}/.claude/claude-sounds-xapipro"
CONFIG_FILE="${USER_DIR}/config.json"

if [ ! -f "${CONFIG_FILE}" ]; then
    mkdir -p "${USER_DIR}/themes"
    cat > "${CONFIG_FILE}" << 'EOF'
{
  "theme": "default",
  "enabled": true,
  "hooks": {
    "stop": true,
    "notification": true,
    "error": true,
    "permission": false
  }
}
EOF
    echo "Created: ${CONFIG_FILE}"
else
    echo "Kept existing: ${CONFIG_FILE}"
fi

echo ""
echo "Done. Restart Claude Code to activate the plugin."
echo "Then use /sounds to manage it."
