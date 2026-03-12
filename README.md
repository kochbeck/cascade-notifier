# Windsurf Cascade Notifier for Windows

Desktop notifications and audible alerts for Windsurf's Cascade AI assistant on Windows 10/11.

Get notified when Cascade finishes a task, encounters an error, needs your approval, or is blocked waiting for terminal input -- so you can context-switch freely without missing a beat.

## Features

- **Task Completion Alerts** -- Know when Cascade finishes
- **Error Notifications** -- Get alerted when something goes wrong
- **Approval Prompts** -- Never miss when Cascade needs your approval
- **Terminal Blocking Detection** -- Notified when a command waits for password/input (opt-in)
- **Distinct Sounds** -- Different `.wav` sounds per event type (customizable)
- **Windows Toast Notifications** -- Popup notifications in the Windows notification center
- **Debounce** -- Prevents notification spam (configurable interval)
- **Hot-Reload Config** -- Change settings without restarting Windsurf
- **Native Performance** -- ~10ms hook overhead (single Go binary, persistent daemon)

## Requirements

- **Windows 10 or 11**
- **Windsurf IDE** with Cascade Hooks support
- **WSL2** (only if using Remote-WSL -- Windows interop must be enabled)

No PowerShell, no .NET runtime, no interpreter required at runtime.

## Installation

### Windows (native or Remote-WSL)

Open PowerShell in the project directory and run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File install.ps1
```

This will:

1. Copy `cascade-notifier-win.exe` to `%USERPROFILE%\.windsurf-notifier\bin\`
2. Copy notification sounds to `%USERPROFILE%\.windsurf-notifier\sounds\`
3. Create a default config at `%USERPROFILE%\.windsurf-notifier\config.json`
4. Configure Windsurf hooks at `%USERPROFILE%\.codeium\windsurf\hooks.json`

Then **restart Windsurf** to load the hooks.

### Remote-WSL (WSL2 folders)

If you use Windsurf's **Remote-WSL** feature to work in WSL2 folders, you need an additional step. Windsurf's WSL-side server reads hooks from `~/.codeium/windsurf/hooks.json` inside the distro, not from the Windows path.

1. **Run the Windows installer first** (`install.ps1`, as described above).

2. **Open your WSL distro** (e.g., Ubuntu) and navigate to the project directory:

   ```bash
   cd /mnt/c/path/to/cascade-notifier
   bash install-wsl.sh
   ```

   The script detects your Windows profile automatically, verifies the binary exists, and writes `~/.codeium/windsurf/hooks.json` to call the Windows binary via WSL interop.

3. **Restart Windsurf** to load the hooks.

> **Note:** If you use multiple WSL distros with Remote-WSL, run `install-wsl.sh` inside each one.

## Pre-Install Testing

You can verify the binary works before running the installer.

**From WSL:**

```bash
# Start the daemon (runs as a Windows process via WSL interop)
./dist/cascade-notifier-win.exe --daemon &
sleep 0.3

# Fire all four test notifications
./dist/cascade-notifier-win.exe --test all
```

**From Windows PowerShell (in the `dist\` folder):**

```powershell
# Terminal 1: start the daemon
.\cascade-notifier-win.exe --daemon

# Terminal 2: fire test notifications
.\cascade-notifier-win.exe --test all
```

You should hear four Windows system sounds and see four toast notifications.
Without the installer, custom `.wav` files are not yet in place, so system sounds play as fallback.

To test with the bundled sounds before installing:

```powershell
$sounds = "$env:USERPROFILE\.windsurf-notifier\sounds"
New-Item -ItemType Directory -Path $sounds -Force | Out-Null
Copy-Item .\sounds\*.wav $sounds
.\dist\cascade-notifier-win.exe --daemon
# in another terminal:
.\dist\cascade-notifier-win.exe --test all
```

## Configuration

Edit `%USERPROFILE%\.windsurf-notifier\config.json`:

```json
{
  "enabled": true,
  "terminal_input": false,
  "git_commands": false,
  "task_complete": true,
  "task_error": true,
  "approval_required": true,
  "sound_enabled": true,
  "toast_enabled": true,
  "debounce_seconds": 5
}
```

Changes take effect immediately on the next hook event (no restart needed).

### Configuration Options

| Option              | Default | Description                                                     |
| ------------------- | ------- | --------------------------------------------------------------- |
| `enabled`           | `true`  | Master switch for all notifications                             |
| `terminal_input`    | `false` | Notify on terminal blocking (password prompts, etc.) -- opt-in  |
| `git_commands`      | `false` | Notify on git push/pull/fetch/clone                             |
| `task_complete`     | `true`  | Notify when Cascade completes a task                            |
| `task_error`        | `true`  | Notify when Cascade encounters an error                         |
| `approval_required` | `true`  | Notify when Cascade needs approval                              |
| `sound_enabled`     | `true`  | Play audible notification sounds                                |
| `toast_enabled`     | `true`  | Show Windows toast popup notifications                          |
| `debounce_seconds`  | `5`     | Minimum seconds between repeated notifications of the same type |

`terminal_input` is off by default because `post_run_command` fires on every terminal command (including routine ones like `ls`). Enable it if you want to be alerted when commands wait for interactive input.

## Custom Sounds

Replace the `.wav` files in `%USERPROFILE%\.windsurf-notifier\sounds\`:

| File                    | Event                        |
| ----------------------- | ---------------------------- |
| `task-complete.wav`     | Cascade finished a task      |
| `task-error.wav`        | Cascade encountered an error |
| `approval-required.wav` | Cascade waiting for approval |
| `terminal-input.wav`    | Terminal waiting for input   |

If a `.wav` file is missing, the notifier falls back to built-in Windows system sounds.

## Logs

View notification history:

```powershell
Get-Content -Tail 20 -Wait "$env:USERPROFILE\.windsurf-notifier\notifications.log"
```

Log entries look like:

```powershell
2026-03-12T14:23:01Z [SENT] task-complete: Cascade: Task completed
2026-03-12T14:23:06Z [SUPPRESSED] task-complete: debounced
2026-03-12T14:25:00Z [SENT] approval-required: Cascade: Waiting for your approval
```

## Uninstall

**Windows:**

```powershell
powershell.exe -ExecutionPolicy Bypass -File uninstall.ps1
```

This stops the daemon, removes the binary from `hooks.json`, and removes the binary file.
Config, sounds, and logs in `%USERPROFILE%\.windsurf-notifier\` are left intact.
To remove them too:

```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\.windsurf-notifier"
```

**WSL (if installed):**

```bash
bash uninstall-wsl.sh
```

Removes notifier entries from `~/.codeium/windsurf/hooks.json`. Does not touch the Windows-side install -- run `uninstall.ps1` separately for that. Run in each WSL distro where you installed.

## How It Works

This project uses [Windsurf Cascade Hooks](https://docs.windsurf.com/windsurf/cascade/hooks) -- a built-in mechanism that runs commands at key points in Cascade's execution lifecycle.

Two hook events are registered:

- **`post_cascade_response`** -- Fires after Cascade finishes a response. The notifier classifies the response as task completion, error, or approval request.
- **`post_run_command`** -- Fires after every terminal command. The notifier checks whether the command is likely waiting for interactive input.

### Architecture

Every hook event calls `cascade-notifier-win.exe` as a **shim** (~10ms lifetime):

```markdown
hooks.json --> cascade-notifier-win.exe pcr (reads stdin, sends to pipe, exits)
|
\\.\pipe\cascade-notifier
|
cascade-notifier-win.exe --daemon (persistent Windows process)
|-- pattern matching
|-- in-memory debounce
|-- hot-reload config
|-- Win32 PlaySound
|-- WinRT toast notification
|-- log append
exits after 30 min idle
```

The daemon starts automatically on the first hook event and exits after 30 minutes of inactivity. It is transparently relaunched on the next event. The named pipe (`\\.\pipe\cascade-notifier`) is local IPC only -- no network ports, no firewall exposure.

WSL hooks call the same Windows binary at its `/mnt/c/...` path via WSL interop. The binary runs as a native Windows process with full pipe access -- no separate Linux binary is needed.

### Production Pipeline Testing

The daemon recognizes magic strings in hook payloads that trigger test notifications immediately, bypassing pattern matching and debounce. Useful for verifying the full hook chain without needing Cascade to generate a real response.

Ask Cascade to include one of these strings in its reply:

| Magic string                              | Effect                                           |
| ----------------------------------------- | ------------------------------------------------ |
| `cascade-notifier:test:task-complete`     | Fires task-complete sound + toast                |
| `cascade-notifier:test:task-error`        | Fires task-error sound + toast                   |
| `cascade-notifier:test:approval-required` | Fires approval-required sound + toast            |
| `cascade-notifier:test:terminal-input`    | Fires terminal-input sound + toast               |
| `cascade-notifier:test:ping`              | Logs "pong" to notifications.log; no sound/toast |
| `cascade-notifier:test:all`               | Fires all four in sequence, 500ms apart          |

Or invoke directly without Windsurf:

```powershell
cascade-notifier-win.exe --test task-complete
cascade-notifier-win.exe --test all
```

## Project Structure

```markdown
cascade-notifier/
├── install.ps1 # Windows installer (pure ASCII)
├── uninstall.ps1 # Windows uninstaller (pure ASCII)
├── install-wsl.sh # WSL hooks installer
├── uninstall-wsl.sh # WSL hooks uninstaller
├── cmd/win/ # Go source -- single binary
│ ├── main.go # Entry point: --daemon / --test / pcr / prc
│ ├── daemon.go # Named pipe server, Dispatcher, debounce
│ ├── notify.go # Windows: Win32 PlaySound + WinRT toast
│ ├── notify_stub.go # Non-Windows: RecordingNotifier for tests
│ ├── autostart.go # Windows: CreateProcess daemon self-launch
│ ├── pipe_windows.go # Named pipe listen/dial (go-winio)
│ ├── pipe_stub.go # Non-Windows stub
│ └── dispatcher_test.go # Unit tests for dispatch logic
├── internal/
│ ├── config/ # JSON config loading, hot-reload
│ ├── patterns/ # Event classification (pcr/prc)
│ └── protocol/ # Length-prefix framing, BOM stripping
├── testdata/
│ ├── payloads/ # Sample hook JSON payloads
│ └── configs/ # Test config variants
├── tests/
│ ├── integration/ # Named pipe pipeline tests (Windows only)
│ └── live/ # Real audio/toast tests (manual, Windows)
├── dist/
│ └── cascade-notifier-win.exe # Pre-built Windows AMD64 binary
├── config/
│ └── default-config.json # Default user config
├── sounds/
│ ├── task-complete.wav
│ ├── task-error.wav
│ ├── approval-required.wav
│ └── terminal-input.wav
├── legacy/ # Deprecated PowerShell implementation
│ ├── src/hooks/ # post_cascade_response.ps1, etc.
│ ├── src/lib/ # notifier.ps1, debounce.ps1, etc.
│ └── tests/ # Pester test suite
├── go.mod
└── go.sum
```

## Building from Source

Requires Go 1.23+.

```bash
# Cross-compile from WSL (or build natively on Windows)
GOOS=windows GOARCH=amd64 go build -ldflags="-s -w" -o dist/cascade-notifier-win.exe ./cmd/win

# Run unit tests (any platform)
go test ./...

# Run integration tests (Windows only -- requires named pipe)
go test -tags integration ./tests/integration/
```

## Manual Uninstall

If `uninstall.ps1` fails, disconnect the notifier from Windsurf by hand:

1. Open `%USERPROFILE%\.codeium\windsurf\hooks.json` in any text editor.

2. Remove entries whose `"command"` value contains `.windsurf-notifier`. For example, change:

   ```json
   {
     "hooks": {
       "post_cascade_response": [
         {
           "command": "C:\\Users\\you\\.windsurf-notifier\\bin\\cascade-notifier-win.exe pcr",
           "show_output": false
         }
       ],
       "post_run_command": [
         {
           "command": "C:\\Users\\you\\.windsurf-notifier\\bin\\cascade-notifier-win.exe prc",
           "show_output": false
         }
       ]
     }
   }
   ```

   to:

   ```json
   { "hooks": {} }
   ```

3. Restart Windsurf.

4. Optionally stop the daemon and remove files:

   ```powershell
   Stop-Process -Name cascade-notifier-win -ErrorAction SilentlyContinue
   Remove-Item -Recurse -Force "$env:USERPROFILE\.windsurf-notifier"
   ```

### Manual WSL Uninstall

Open `~/.codeium/windsurf/hooks.json` and remove any entries whose `"command"` contains `.windsurf-notifier`. Restart Windsurf.

## Inspired By

[superlee/windsurf_cascade_notifier](https://github.com/superlee/windsurf_cascade_notifier) -- the macOS version using native `osascript` notifications.

## License

MIT
