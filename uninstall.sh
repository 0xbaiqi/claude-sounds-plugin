#!/usr/bin/env bash
# Claude Sounds Plugin - Uninstaller
set -euo pipefail

USER_DIR="${HOME}/.claude/claude-sounds-xapipro"

echo "Claude Sounds Plugin - Uninstaller"
echo ""

# ── 1. Uninstall plugin ───────────────────────────────────────────────────────

echo "Uninstalling plugin..."
claude plugin uninstall sounds 2>/dev/null && echo "Plugin removed." || echo "Plugin not found (already uninstalled?)."

# ── 2. Remove marketplace ─────────────────────────────────────────────────────

echo "Removing marketplace..."
claude plugin marketplace remove sounds 2>/dev/null && echo "Marketplace removed." || echo "Marketplace not found."

# ── 3. Optionally remove user config ─────────────────────────────────────────

if [ -d "${USER_DIR}" ]; then
    echo ""
    read -r -p "Remove user config and installed themes? [y/N]: " confirm
    if [[ "${confirm:-N}" =~ ^[Yy]$ ]]; then
        rm -rf "${USER_DIR}"
        echo "Removed: ${USER_DIR}"
    else
        echo "Kept: ${USER_DIR}"
    fi
fi

echo ""
echo "Done. Restart Claude Code to apply changes."
