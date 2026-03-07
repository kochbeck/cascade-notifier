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
- **WSL2** (only if using Remote-WSL -- Windows interop must be enabled)

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

### Remote-WSL (WSL2 folders)

If you use Windsurf's **Remote-WSL** feature to work in WSL2 folders, you need an additional step. Windsurf's WSL-side server reads hooks from `~/.codeium/windsurf/hooks.json` inside the distro, not from the Windows path.

1. **Run the Windows installer first** (`install.ps1`, as described above).

2. **Open your WSL distro** (e.g., Ubuntu) and navigate to the project directory. If the repo is cloned on the Windows filesystem:

   ```bash
   cd /mnt/c/Users/$USER/path/to/cascade-notifier
   ```

   Replace the path with wherever you cloned the repo.

3. **Run the WSL installer:**

   ```bash
   bash install-wsl.sh
   ```

   The script will:
   - Detect your Windows user profile automatically
   - Verify that the Windows-side install exists
   - Create `~/.codeium/windsurf/hooks.json` inside your WSL distro
   - Preserve any existing non-notifier hooks in that file

   The hook commands call `powershell.exe` via WSL interop, so sounds and toasts still appear on the Windows desktop.

4. **Restart Windsurf** to load the hooks.

> **Note:** If you use multiple WSL distros with Remote-WSL, run `install-wsl.sh` inside each one.

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

**Windows:**

```powershell
powershell.exe -ExecutionPolicy Bypass -File uninstall.ps1
```

This removes the hooks from `hooks.json` and optionally deletes the installation directory.

**WSL (if installed):**

Open your WSL distro and navigate to the project directory:

```bash
cd /mnt/c/Users/$USER/path/to/cascade-notifier
bash uninstall-wsl.sh
```

This removes the notifier entries from `~/.codeium/windsurf/hooks.json` inside the distro. It does not touch the Windows-side install -- run `uninstall.ps1` separately for that.

If you installed into multiple WSL distros, run `uninstall-wsl.sh` inside each one.

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
├── install.ps1                        # Windows installer
├── uninstall.ps1                      # Windows uninstaller
├── install-wsl.sh                     # WSL hooks installer
├── uninstall-wsl.sh                   # WSL hooks uninstaller
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

### Manual WSL Uninstall

If `uninstall-wsl.sh` fails (e.g., script missing, etc.), you can remove the WSL-side hooks by hand:

1. **Open the WSL hooks config file** in any editor:

   ```
   ~/.codeium/windsurf/hooks.json
   ```

2. **Remove the notifier entries.** Same as the Windows instructions above -- delete entries in `post_run_command` and `post_cascade_response` whose `"command"` value contains `.windsurf-notifier`, leaving empty arrays `[]` if no other entries remain.

3. **Restart Windsurf** to pick up the change.

The WSL-side hooks.json does not control the Windows-side scripts or sounds -- it only tells WSL-mode Windsurf which commands to run. Removing the entries is sufficient to fully disable the notifier in Remote-WSL sessions.

## Inspired By

[superlee/windsurf_cascade_notifier](https://github.com/superlee/windsurf_cascade_notifier) -- the macOS version using native `osascript` notifications.

## License

MIT
