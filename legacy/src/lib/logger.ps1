# logger.ps1 - Notification event logging

function Write-NotifierLog {
    <#
    .SYNOPSIS
        Appends a structured log entry to the notifications log file.
    .PARAMETER EventType
        The type of event (e.g., task-complete, task-error, approval-required, terminal-input)
    .PARAMETER Status
        The outcome (SENT, SUPPRESSED, FAILED)
    .PARAMETER Message
        Human-readable description
    .PARAMETER LogFile
        Path to the log file
    #>
    param(
        [Parameter(Mandatory)][string]$EventType,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$LogFile
    )

    try {
        $logDir = Split-Path -Parent $LogFile
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
        $entry = $timestamp + ' | ' + $EventType + ' | ' + $Status + ' | "' + $Message + '"'
        Add-Content -Path $LogFile -Value $entry -ErrorAction Stop
    }
    catch {
        # Logging failure should not crash the hook
    }
}

function Get-RecentLogs {
    <#
    .SYNOPSIS
        Returns the last N log entries.
    #>
    param(
        [string]$LogFile,
        [int]$Count = 10
    )

    if (Test-Path $LogFile) {
        return Get-Content -Path $LogFile -Tail $Count
    }
    return @()
}
