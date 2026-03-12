#!/usr/bin/env bash
#
# install-wsl.sh - Configure Windsurf Cascade Notifier hooks for Remote-WSL
#
# When Windsurf runs in Remote-WSL mode it reads hooks.json from the WSL
# filesystem (~/.codeium/windsurf/hooks.json). This script writes that file
# so that Windsurf invokes the Windows binary directly via WSL interop.
#
# Prerequisites:
#   1. Run install.ps1 on the Windows side first.
#   2. Run this script inside your WSL distro.
#
# Usage:
#   bash install-wsl.sh

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

# -- Locate Windows user profile --
if ! command -v powershell.exe &>/dev/null; then
    die "powershell.exe not found. Ensure WSL interop is enabled."
fi

WIN_USERPROFILE="$(powershell.exe -NoProfile -Command 'Write-Host -NoNewline $env:USERPROFILE' 2>/dev/null)"
WIN_USERPROFILE="${WIN_USERPROFILE%$'\r'}"
[[ -n "$WIN_USERPROFILE" ]] || die "Could not determine Windows USERPROFILE."

echo "Windows profile: $WIN_USERPROFILE"

# -- Verify Windows-side binary exists --
WSL_WIN_HOME="$(wslpath "$WIN_USERPROFILE" 2>/dev/null)" \
    || die "Could not convert Windows path with wslpath."

BINARY_WSL="$WSL_WIN_HOME/.windsurf-notifier/bin/cascade-notifier-win.exe"
if [[ ! -f "$BINARY_WSL" ]]; then
    die "Binary not found: $BINARY_WSL
Run install.ps1 on the Windows side first:
  powershell.exe -ExecutionPolicy Bypass -File install.ps1"
fi

echo "Binary found: $BINARY_WSL"

# Build the WSL-style /mnt/c/... path that Windsurf will pass to WSL interop.
# This is the path as seen from inside WSL when invoking the Windows binary.
PCR_CMD="${BINARY_WSL} pcr"
PRC_CMD="${BINARY_WSL} prc"

# -- Prepare hooks.json location --
WSL_HOOKS_DIR="$HOME/.codeium/windsurf"
WSL_HOOKS_FILE="$WSL_HOOKS_DIR/hooks.json"
NOTIFIER_MARKER=".windsurf-notifier"

mkdir -p "$WSL_HOOKS_DIR"

# -- Backup existing hooks.json if present --
if [[ -f "$WSL_HOOKS_FILE" ]]; then
    TS="$(date +%Y%m%d_%H%M%S)"
    cp "$WSL_HOOKS_FILE" "${WSL_HOOKS_FILE}.backup.${TS}"
    echo "Backup: ${WSL_HOOKS_FILE}.backup.${TS}"
fi

write_fresh_hooks() {
    cat > "$WSL_HOOKS_FILE" << HOOKSJSON
{
  "hooks": {
    "post_cascade_response": [
      { "command": "${PCR_CMD}", "show_output": false }
    ],
    "post_run_command": [
      { "command": "${PRC_CMD}", "show_output": false }
    ]
  }
}
HOOKSJSON
}

merge_hooks() {
    python3 - "$NOTIFIER_MARKER" "$PCR_CMD" "$PRC_CMD" "$WSL_HOOKS_FILE" << 'PYEOF'
import json, sys

marker, pcr, prc, path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}

hooks = data.setdefault("hooks", {})
for key in ("post_cascade_response", "post_run_command"):
    hooks[key] = [e for e in hooks.get(key, [])
                  if isinstance(e, dict) and marker not in e.get("command", "")]

hooks["post_cascade_response"].append({"command": pcr, "show_output": False})
hooks["post_run_command"].append({"command": prc, "show_output": False})

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
}

if [[ -f "$WSL_HOOKS_FILE" ]] && command -v python3 &>/dev/null; then
    merge_hooks || { echo "WARNING: merge failed, overwriting" >&2; write_fresh_hooks; }
else
    write_fresh_hooks
fi

echo "Hooks written: $WSL_HOOKS_FILE"
echo ""
echo "Installation complete. Restart Windsurf to apply."
echo "Smoke test (from Windows): cascade-notifier-win.exe --test all"
