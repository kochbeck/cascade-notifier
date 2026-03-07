# post_run_command.ps1 - Hook for detecting terminal blocking events
# Called by Windsurf Cascade after each terminal command execution

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# Source common initialization
$hookDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $hookDir "common.ps1")

# Regex patterns matched against the command line to detect commands that are
# likely to prompt for interactive input (passwords, confirmations, etc.).
# NOTE: The hook payload only provides the command text, not terminal output,
# so we detect commands by name rather than by output patterns.
$script:TerminalInputRegexes = @(
    '\bscp\b'
    '\bsftp\b'
    '\bssh-copy-id\b'
    '\bnpm\s+login\b'
    '\bnpm\s+adduser\b'
    '\baz\s+login\b'
    '\bgcloud\s+auth\s+login\b'
    '\baws\s+configure\b'
    '\bkinit\b'
    '\bpasswd\b'
    '\bRead-Host\b'
)

function Test-GitRemoteCommand {
    <#
    .SYNOPSIS
        Checks if the command is a git remote operation.
    #>
    param([string]$CommandLine)

    if ($CommandLine -match 'git\s+(push|pull|fetch|clone)\b') {
        return $true
    }
    return $false
}

function Test-TerminalBlocking {
    <#
    .SYNOPSIS
        Detects if a command is likely blocking for user input.
    .PARAMETER CommandLine
        The command that was executed
    .PARAMETER Config
        Config hashtable (to check git_commands preference)
    #>
    param(
        [string]$CommandLine,
        [hashtable]$Config
    )

    # Check git commands
    if (Test-GitRemoteCommand -CommandLine $CommandLine) {
        if (-not $Config.git_commands) {
            return $false
        }
        return $true
    }

    # Check if command is likely to prompt for password/input
    if ($CommandLine -match '^\s*sudo\s' -or
        $CommandLine -match '\bssh\b' -or
        $CommandLine -match '\bdocker\s+login\b' -or
        $CommandLine -match '\brunas\b') {
        return $true
    }

    # Check additional interactive command patterns
    foreach ($regex in $script:TerminalInputRegexes) {
        if ($CommandLine -match $regex) {
            return $true
        }
    }

    return $false
}

function Invoke-PostRunCommand {
    <#
    .SYNOPSIS
        Main hook logic: parse input, detect terminal blocking, send notification.
    #>

    # Load config (hot-reload)
    $config = Initialize-HookConfig

    # Read JSON input from stdin
    $inputJson = [Console]::In.ReadToEnd()

    if ([string]::IsNullOrWhiteSpace($inputJson)) {
        return
    }

    $hookInput = $null
    try {
        $hookInput = $inputJson | ConvertFrom-Json
    }
    catch {
        Write-NotifierLog -EventType "parse-error" -Status "FAILED" -Message "Could not parse hook input" -LogFile $script:LogFile
        return
    }

    # Extract command information (safe property access for StrictMode)
    $commandLine = ""
    if ($hookInput.PSObject.Properties['tool_info']) {
        $toolInfo = $hookInput.tool_info
        if ($toolInfo.PSObject.Properties['command_line']) {
            $commandLine = $toolInfo.command_line
        }
    }

    # Check if this might be a blocking command
    if (Test-TerminalBlocking -CommandLine $commandLine -Config $config) {
        if (Test-ShouldNotify -EventType "terminal-input" -Config $config) {
            $truncatedCmd = $commandLine
            if ($truncatedCmd.Length -gt 50) {
                $truncatedCmd = $truncatedCmd.Substring(0, 50) + "..."
            }
            Send-CascadeNotification `
                -EventType "terminal-input" `
                -Title "Cascade: Terminal waiting for input" `
                -Body "Command may require input: $truncatedCmd" `
                -Config $config `
                -SoundsDir $script:SoundsDir `
                -LogFile $script:LogFile `
                -DebounceDir $script:DebounceDir
        }
    }
}

# Run
try {
    Invoke-PostRunCommand
}
catch {
    # Hook failures must not break Cascade
    try {
        Write-NotifierLog -EventType "hook-error" -Status "FAILED" -Message $_.Exception.Message -LogFile $script:LogFile
    }
    catch { }
}
