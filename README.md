# Windsurf Cascade Notifier for Windows 

Desktop notifications and audible alerts for Windsurf's Cascade AI assistant on Windows 10/11.

Get notified when Cascade finishes a task, encounters an error, needs your approval, or is blocked waiting for terminal input -- so you can context-switch freely without missing a beat.

## Features

- **Task Completion Alerts** -- Know when Cascade finishes
- **Error Notifications** -- Get alerted when something goes wrong
- **Approval Prompts** -- Never miss when Cascade needs your approval
- **Terminal Blocking Detection** -- Notified when a command waits for password/input
- **Distinct Sounds** -- Different `.wav` sounds per event type (customizable)
- **Windows Toast Notifications** -- Popup notifications in the Windows notification center
- **Smart Suppression** -- Notifications only appear when Windsurf isn't focused
- **Debounce** -- Prevents notification spam (configurable interval)
- **Hot-Reload Config** -- Change settings without restarting Windsurf

## Requirements

- **Windows 10 or 11**
- **Windows PowerShell 5.1** (pre-installed on all Windows 10/11 systems)
- **Windsurf IDE** with Cascade Hooks support

## Installation

Open PowerShell and run from the project directory:

```powershell
powershell.exe -ExecutionPolicy Bypass -File install.ps1
```

This will:

1. Copy scripts to `%USERPROFILE%\.windsurf-notifier\`
2. Create default configuration
3. Configure user-level Windsurf hooks at `%USERPROFILE%\.codeium\windsurf\hooks.json`
4. Install default notification sounds

Then **restart Windsurf** to load the hooks.

## Configuration

Edit `%USERPROFILE%\.windsurf-notifier\config.json`:

```json
{
  "enabled": true,
  "terminal_input": true,
  "git_commands": false,
  "task_complete": true,
  "task_error": true,
  "approval_required": true,
  "sound_enabled": true,
  "toast_enabled": true,
  "debounce_seconds": 5
}
```

Changes take effect immediately (no restart needed).

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `enabled` | `true` | Master switch for all notifications |
| `terminal_input` | `true` | Notify on terminal blocking (password prompts, etc.) |
| `git_commands` | `false` | Notify on git push/pull/fetch/clone operations |
| `task_complete` | `true` | Notify when Cascade completes a task |
| `task_error` | `true` | Notify when Cascade encounters an error |
| `approval_required` | `true` | Notify when Cascade needs approval |
| `sound_enabled` | `true` | Play audible notification sounds |
| `toast_enabled` | `true` | Show Windows toast popup notifications |
| `debounce_seconds` | `5` | Minimum seconds between repeated notifications |

## Custom Sounds

Replace the `.wav` files in `%USERPROFILE%\.windsurf-notifier\sounds\`:

| File | Event |
|------|-------|
| `task-complete.wav` | Cascade finished a task |
| `task-error.wav` | Cascade encountered an error |
| `approval-required.wav` | Cascade waiting for approval |
| `terminal-input.wav` | Terminal waiting for input |

If a `.wav` file is missing, the system falls back to built-in Windows system sounds.

## Usage

Once installed, notifications appear automatically when:

- Cascade completes a task
- Cascade encounters an error
- Cascade needs your approval to proceed
- A terminal command is blocked waiting for input (e.g., password)

Notifications are **suppressed** when Windsurf is the active (focused) window.

## Logs

View notification history:

```powershell
Get-Content -Tail 20 -Wait "$env:USERPROFILE\.windsurf-notifier\notifications.log"
```

## Uninstall

```powershell
powershell.exe -ExecutionPolicy Bypass -File uninstall.ps1
```

This removes the hooks from `hooks.json` and optionally deletes the installation directory.

## How It Works

This project uses [Windsurf Cascade Hooks](https://docs.windsurf.com/windsurf/cascade/hooks) -- a built-in mechanism that executes custom commands at key points during Cascade's execution lifecycle.

Two hook events are registered:

- **`post_cascade_response`** -- Fires after Cascade finishes a response. The hook script analyzes the response to classify it as task completion, error, or approval request.
- **`post_run_command`** -- Fires after a terminal command. The hook script checks if the command is likely waiting for user input (passwords, confirmations, etc.).

Each hook script:
1. Reads JSON context from stdin
2. Loads user config (hot-reload)
3. Checks focus suppression and debounce
4. Plays the appropriate sound and shows a toast notification

## Project Structure

```
cascade-notifier/
├── install.ps1                        # Installer
├── uninstall.ps1                      # Uninstaller
├── src/
│   ├── config/
│   │   └── default-config.json        # Default preferences
│   ├── hooks/
│   │   ├── common.ps1                 # Shared initialization
│   │   ├── post_cascade_response.ps1  # Task/error/approval detection
│   │   └── post_run_command.ps1       # Terminal blocking detection
│   └── lib/
│       ├── notifier.ps1               # Sound + toast delivery
│       ├── focus.ps1                  # Win32 foreground window detection
│       ├── debounce.ps1               # Timestamp-based debounce
│       ├── logger.ps1                 # Event logging
│       └── json-helpers.ps1           # Config loading
├── sounds/
│   ├── task-complete.wav              # Bundled defaults (replaceable)
│   ├── task-error.wav
│   ├── approval-required.wav
│   └── terminal-input.wav
└── tests/
    ├── run-tests.ps1                  # Pester 5 test runner
    ├── helpers/
    │   └── TestHelper.ps1             # Shared test utilities
    ├── static/
    │   └── ParseValidation.Tests.ps1  # Parse errors, non-ASCII, BOM checks
    └── unit/
        ├── Debounce.Tests.ps1         # Debounce logic tests
        ├── HookLogic.Tests.ps1        # Pattern matching + decision tests
        ├── InstallHelpers.Tests.ps1   # Install script helper tests
        ├── JsonHelpers.Tests.ps1      # Config loading tests
        └── Logger.Tests.ps1           # Logging tests
```

## Manual Uninstall

If `uninstall.ps1` fails to run (e.g., the script files are missing or corrupted), you can disconnect the notifier from Windsurf by hand:

1. **Open the hooks config file** in any text editor:

   ```
   %USERPROFILE%\.codeium\windsurf\hooks.json
   ```

2. **Remove the notifier entries.** Look for entries in `post_run_command` and `post_cascade_response` whose `"command"` value contains `.windsurf-notifier` and delete them. For example, if the file looks like this:

   ```json
   {
     "hooks": {
       "post_run_command": [
         { "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\you\\.windsurf-notifier\\hooks\\post_run_command.ps1\"", "show_output": false }
       ],
       "post_cascade_response": [
         { "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\you\\.windsurf-notifier\\hooks\\post_cascade_response.ps1\"", "show_output": false }
       ]
     }
   }
   ```

   Change it to:

   ```json
   {
     "hooks": {
       "post_run_command": [],
       "post_cascade_response": []
     }
   }
   ```

   If there are other (non-notifier) entries in those arrays, keep them -- only remove lines that reference `.windsurf-notifier`.

3. **Restart Windsurf** to pick up the change.

4. **Optionally delete the installation directory:**

   ```powershell
   Remove-Item -Path "$env:USERPROFILE\.windsurf-notifier" -Recurse -Force
   ```

After step 3, Windsurf will stop invoking the notifier hooks and return to normal operation.

## Inspired By

[superlee/windsurf_cascade_notifier](https://github.com/superlee/windsurf_cascade_notifier) -- the macOS version using native `osascript` notifications.

## License

MIT
