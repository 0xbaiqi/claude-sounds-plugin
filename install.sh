#!/usr/bin/env bash
# Claude Sounds Plugin - Installer
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Claude Sounds Plugin - Installer"
echo ""

# ── 1. Choose scope ───────────────────────────────────────────────────────────

echo "Install scope:"
echo "  1) user    - all projects (current user)"
echo "  2) project - current directory only"
echo ""
read -r -p "Choose [1/2] (default: 1): " scope_choice
scope_choice="${scope_choice:-1}"

case "${scope_choice}" in
    1) SCOPE="user" ;;
    2) SCOPE="project" ;;
    *)
        echo "Invalid choice. Aborting." >&2
        exit 1
        ;;
esac

echo ""
echo "Scope: ${SCOPE}"

# ── 2. Register marketplace and install plugin ────────────────────────────────

echo ""
echo "Adding local marketplace..."
claude plugin marketplace add --scope "${SCOPE}" "${PLUGIN_DIR}"

echo ""
echo "Installing plugin..."
claude plugin install --scope "${SCOPE}" "sounds@sounds"

# ── 3. Init user config ───────────────────────────────────────────────────────

USER_DIR="${HOME}/.claude/claude-sounds-xapipro"
CONFIG_FILE="${USER_DIR}/config.json"

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
    echo "Created: ${CONFIG_FILE}"
else
    echo "Kept existing: ${CONFIG_FILE}"
fi

echo ""
echo "Done. Restart Claude Code to activate the plugin."
echo "Then use: /sounds:cs help"
