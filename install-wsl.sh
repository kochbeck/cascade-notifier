#!/usr/bin/env bash
#
# install-wsl.sh - Sets up Windsurf Cascade Notifier hooks for Remote-WSL sessions
#
# When Windsurf runs in Remote-WSL mode, it reads hooks.json from the WSL
# filesystem (~/.codeium/windsurf/hooks.json) instead of the Windows side.
# This script creates that hooks.json so the notifier works in WSL folders.
#
# Prerequisites:
#   1. Run install.ps1 on the Windows side first (installs scripts + sounds).
#   2. Run this script inside your WSL distro.
#
# Usage:
#   bash install-wsl.sh

set -euo pipefail

# --- Helpers ---
die() { echo "ERROR: $*" >&2; exit 1; }

# --- Detect Windows user profile ---
# powershell.exe is available in WSL via Windows interop
if ! command -v powershell.exe &>/dev/null; then
    die "powershell.exe not found. Ensure WSL has Windows interop enabled (see /etc/wsl.conf)."
fi

WIN_USERPROFILE="$(powershell.exe -NoProfile -Command 'Write-Host -NoNewline $env:USERPROFILE' 2>/dev/null)" \
    || die "Could not determine Windows USERPROFILE."

# Trim trailing carriage return that powershell.exe may add
WIN_USERPROFILE="${WIN_USERPROFILE%$'\r'}"

if [[ -z "$WIN_USERPROFILE" ]]; then
    die "Windows USERPROFILE is empty."
fi

echo "Windows profile: $WIN_USERPROFILE"

# --- Verify Windows-side install exists ---
# Convert Windows path to WSL mount path for validation
WIN_NOTIFIER_DIR="${WIN_USERPROFILE}\\.windsurf-notifier"
WSL_MOUNT="$(wslpath "$WIN_USERPROFILE" 2>/dev/null)" \
    || die "Could not convert Windows path with wslpath. Is this running inside WSL?"

if [[ ! -d "$WSL_MOUNT/.windsurf-notifier" ]]; then
    die "Windows-side install not found at ${WIN_NOTIFIER_DIR}.
    Run install.ps1 on the Windows side first:
      powershell.exe -ExecutionPolicy Bypass -File install.ps1"
fi

echo "Windows-side install verified: $WIN_NOTIFIER_DIR"

# --- Build hook commands (same as install.ps1 generates) ---
# These call powershell.exe via WSL interop with the Windows-side script paths.
HOOKS_DIR="${WIN_USERPROFILE}\\.windsurf-notifier\\hooks"
POST_RUN_CMD="powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"${HOOKS_DIR}\\post_run_command.ps1\""
POST_RESPONSE_CMD="powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"${HOOKS_DIR}\\post_cascade_response.ps1\""

# --- Prepare WSL hooks.json directory ---
WSL_HOOKS_DIR="$HOME/.codeium/windsurf"
WSL_HOOKS_FILE="$WSL_HOOKS_DIR/hooks.json"

mkdir -p "$WSL_HOOKS_DIR"

# --- Backup existing hooks.json ---
NOTIFIER_MARKER=".windsurf-notifier"

if [[ -f "$WSL_HOOKS_FILE" ]]; then
    TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    cp "$WSL_HOOKS_FILE" "${WSL_HOOKS_FILE}.backup.${TIMESTAMP}"
    echo "  Backup created: ${WSL_HOOKS_FILE}.backup.${TIMESTAMP}"
fi

# --- Merge with existing hooks.json ---
# If jq is available, do a proper merge. Otherwise, warn and overwrite.
write_fresh_hooks() {
    cat > "$WSL_HOOKS_FILE" <<HOOKSJSON
{
  "hooks": {
    "post_run_command": [
      { "command": "${POST_RUN_CMD}", "show_output": false }
    ],
    "post_cascade_response": [
      { "command": "${POST_RESPONSE_CMD}", "show_output": false }
    ]
  }
}
HOOKSJSON
}

if [[ -f "$WSL_HOOKS_FILE" ]] && command -v jq &>/dev/null; then
    echo "  Merging with existing hooks.json (jq detected)..."

    # Remove any existing notifier entries, then append ours
    TEMP_FILE="$(mktemp)"
    trap 'rm -f "$TEMP_FILE"' EXIT

    jq --arg marker "$NOTIFIER_MARKER" \
       --arg postRunCmd "$POST_RUN_CMD" \
       --arg postResponseCmd "$POST_RESPONSE_CMD" '
        # Ensure structure exists
        .hooks //= {} |
        .hooks.post_run_command //= [] |
        .hooks.post_cascade_response //= [] |

        # Remove old notifier entries
        .hooks.post_run_command = [.hooks.post_run_command[] | select(.command | contains($marker) | not)] |
        .hooks.post_cascade_response = [.hooks.post_cascade_response[] | select(.command | contains($marker) | not)] |

        # Append new notifier entries
        .hooks.post_run_command += [{"command": $postRunCmd, "show_output": false}] |
        .hooks.post_cascade_response += [{"command": $postResponseCmd, "show_output": false}]
    ' "$WSL_HOOKS_FILE" > "$TEMP_FILE"

    mv "$TEMP_FILE" "$WSL_HOOKS_FILE"
    trap - EXIT
elif [[ -f "$WSL_HOOKS_FILE" ]]; then
    echo "  WARNING: jq not installed -- overwriting existing hooks.json" >&2
    echo "  (Backup was saved above)"
    write_fresh_hooks
else
    write_fresh_hooks
fi

echo "  Configured hooks at: $WSL_HOOKS_FILE"

echo ""
echo "Installation complete!"
echo ""
echo "  WSL hooks:    $WSL_HOOKS_FILE"
echo "  Win scripts:  $WIN_NOTIFIER_DIR"
echo ""
echo "Next steps:"
echo "  1. Restart Windsurf to load the hooks"
echo "  2. Open a folder in WSL via Remote-WSL and test"
