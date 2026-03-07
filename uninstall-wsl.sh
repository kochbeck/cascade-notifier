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

if command -v jq &>/dev/null; then
    TEMP_FILE="$(mktemp)"
    trap 'rm -f "$TEMP_FILE"' EXIT

    jq --arg marker "$NOTIFIER_MARKER" '
        if .hooks then
            .hooks |= with_entries(
                if (.value | type) == "array" then
                    .value |= [.[] | select(.command | tostring | contains($marker) | not)]
                else .
                end
            )
        else .
        end
    ' "$WSL_HOOKS_FILE" > "$TEMP_FILE"

    mv "$TEMP_FILE" "$WSL_HOOKS_FILE"
    trap - EXIT
    echo "  Removed notifier entries from hooks.json"
else
    echo "  WARNING: jq not installed -- cannot surgically remove entries." >&2
    echo "  To finish manually, edit $WSL_HOOKS_FILE and remove entries containing '$NOTIFIER_MARKER'."
    exit 1
fi

echo ""
echo "Uninstall complete!"
echo "Restart Windsurf to apply changes."
echo ""
echo "Note: Windows-side scripts are still installed."
echo "To remove those too, run on the Windows side:"
echo "  powershell.exe -ExecutionPolicy Bypass -File uninstall.ps1"
