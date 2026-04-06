#!/usr/bin/env bash
set -euo pipefail

PLUGINS_DIR="${HOME}/.claude/plugins"
INSTALL_LINK="${PLUGINS_DIR}/claude-sounds"
INSTALLED_JSON="${PLUGINS_DIR}/installed_plugins.json"
PLUGIN_KEY="claude-sounds@local"
USER_DIR="${HOME}/.claude/claude-sounds-xapipro"

echo "Claude Sounds Plugin - Uninstaller"
echo ""

# ── 1. Remove from installed_plugins.json ────────────────────────────────────

if [ -f "${INSTALLED_JSON}" ]; then
    python3 - "${INSTALLED_JSON}" "${PLUGIN_KEY}" << 'PYEOF'
import json, sys
path, key = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
if key in data.get("plugins", {}):
    del data["plugins"][key]
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"Removed: {key}")
else:
    print(f"Not found: {key}")
PYEOF
else
    echo "installed_plugins.json not found, skipping"
fi

# ── 2. Remove symlink ─────────────────────────────────────────────────────────

if [ -L "${INSTALL_LINK}" ]; then
    rm "${INSTALL_LINK}"
    echo "Removed symlink: ${INSTALL_LINK}"
fi

# ── 3. Optionally remove user config ─────────────────────────────────────────

echo ""
if [ -d "${USER_DIR}" ]; then
    read -r -p "Remove user config & themes at ${USER_DIR}? [y/N]: " confirm
    if [[ "${confirm}" =~ ^[Yy]$ ]]; then
        rm -rf "${USER_DIR}"
        echo "Removed: ${USER_DIR}"
    else
        echo "Kept: ${USER_DIR}"
    fi
fi

echo ""
echo "Done. Restart Claude Code to deactivate the plugin."
