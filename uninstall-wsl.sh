#!/usr/bin/env bash
#
# uninstall-wsl.sh - Removes Windsurf Cascade Notifier hooks from WSL
#
# Removes the notifier entries from ~/.codeium/windsurf/hooks.json.
# Does NOT touch the Windows-side install (use uninstall.ps1 for that).
#
# Usage:
#   bash uninstall-wsl.sh

set -euo pipefail

WSL_HOOKS_DIR="$HOME/.codeium/windsurf"
WSL_HOOKS_FILE="$WSL_HOOKS_DIR/hooks.json"
NOTIFIER_MARKER=".windsurf-notifier"

echo "Uninstalling Windsurf Cascade Notifier (WSL hooks)..."

if [[ ! -f "$WSL_HOOKS_FILE" ]]; then
    echo "  No hooks.json found at $WSL_HOOKS_FILE -- nothing to do."
    exit 0
fi

# Backup
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
cp "$WSL_HOOKS_FILE" "${WSL_HOOKS_FILE}.backup.${TIMESTAMP}"
echo "  Backup created: ${WSL_HOOKS_FILE}.backup.${TIMESTAMP}"

if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys

marker, path = sys.argv[1], sys.argv[2]

with open(path) as f:
    data = json.load(f)

if 'hooks' in data:
    for key, entries in data['hooks'].items():
        if isinstance(entries, list):
            data['hooks'][key] = [
                e for e in entries if marker not in str(e.get('command', ''))
            ]

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$NOTIFIER_MARKER" "$WSL_HOOKS_FILE"
    echo "  Removed notifier entries from hooks.json"
else
    # Fallback: remove lines containing the notifier marker.
    # This is a rough approach -- if the result looks wrong, restore the backup.
    TEMP_FILE="$(mktemp)"
    trap 'rm -f "$TEMP_FILE"' EXIT
    grep -v "$NOTIFIER_MARKER" "$WSL_HOOKS_FILE" > "$TEMP_FILE" || true
    mv "$TEMP_FILE" "$WSL_HOOKS_FILE"
    trap - EXIT
    echo "  Removed notifier lines from hooks.json (grep fallback)"
    echo "  TIP: Review $WSL_HOOKS_FILE to verify it is still valid JSON."
fi

echo ""
echo "Uninstall complete!"
echo "Restart Windsurf to apply changes."
echo ""
echo "Note: Windows-side scripts are still installed."
echo "To remove those too, run on the Windows side:"
echo "  powershell.exe -ExecutionPolicy Bypass -File uninstall.ps1"
