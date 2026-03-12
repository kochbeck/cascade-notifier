#!/usr/bin/env bash
#
# uninstall-wsl.sh - Remove cascade-notifier hooks from WSL hooks.json
#
# Does NOT touch the Windows-side install. Use uninstall.ps1 for that.
#
# Usage:
#   bash uninstall-wsl.sh

set -euo pipefail

WSL_HOOKS_FILE="$HOME/.codeium/windsurf/hooks.json"
NOTIFIER_MARKER=".windsurf-notifier"

if [[ ! -f "$WSL_HOOKS_FILE" ]]; then
    echo "No hooks.json at $WSL_HOOKS_FILE -- nothing to do."
    exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp "$WSL_HOOKS_FILE" "${WSL_HOOKS_FILE}.backup.${TS}"
echo "Backup: ${WSL_HOOKS_FILE}.backup.${TS}"

if command -v python3 &>/dev/null; then
    python3 - "$NOTIFIER_MARKER" "$WSL_HOOKS_FILE" << 'PYEOF'
import json, sys

marker, path = sys.argv[1], sys.argv[2]

with open(path) as f:
    data = json.load(f)

if "hooks" in data:
    for key in list(data["hooks"].keys()):
        entries = data["hooks"][key]
        if isinstance(entries, list):
            data["hooks"][key] = [
                e for e in entries
                if not (isinstance(e, dict) and marker in e.get("command", ""))
            ]

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
    echo "Removed notifier entries from $WSL_HOOKS_FILE"
else
    # Rough fallback: grep out lines containing the marker.
    TMPF="$(mktemp)"
    grep -v "$NOTIFIER_MARKER" "$WSL_HOOKS_FILE" > "$TMPF" || true
    mv "$TMPF" "$WSL_HOOKS_FILE"
    echo "Removed notifier lines (grep fallback -- verify JSON is still valid)"
fi

echo "Done. Restart Windsurf to apply."
echo "To also remove the Windows binary, run uninstall.ps1 on the Windows side."
