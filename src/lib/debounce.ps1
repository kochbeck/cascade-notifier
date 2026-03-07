# debounce.ps1 - Notification debouncing to prevent spam

function Test-Debounce {
    <#
    .SYNOPSIS
        Checks if enough time has passed since the last notification of this type.
    .PARAMETER EventType
        The notification event type
    .PARAMETER DebounceSeconds
        Minimum seconds between notifications of the same type
    .PARAMETER DebounceDir
        Directory for debounce timestamp files
    .OUTPUTS
        $true if notification should proceed, $false if within debounce window.
    #>
    param(
        [Parameter(Mandatory)][string]$EventType,
        [int]$DebounceSeconds = 5,
        [Parameter(Mandatory)][string]$DebounceDir
    )

    if (-not (Test-Path $DebounceDir)) {
        New-Item -ItemType Directory -Path $DebounceDir -Force | Out-Null
    }

    $debounceFile = Join-Path $DebounceDir $EventType
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    if (Test-Path $debounceFile) {
        try {
            $lastTime = [long](Get-Content -Path $debounceFile -Raw -ErrorAction Stop).Trim()
            $elapsed = $now - $lastTime
            if ($elapsed -lt $DebounceSeconds) {
                return $false
            }
        }
        catch {
            # Corrupted file -- allow notification
        }
    }

    return $true
}

function Update-Debounce {
    <#
    .SYNOPSIS
        Records the current timestamp for debounce tracking.
    #>
    param(
        [Parameter(Mandatory)][string]$EventType,
        [Parameter(Mandatory)][string]$DebounceDir
    )

    if (-not (Test-Path $DebounceDir)) {
        New-Item -ItemType Directory -Path $DebounceDir -Force | Out-Null
    }

    $debounceFile = Join-Path $DebounceDir $EventType
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Set-Content -Path $debounceFile -Value $now -NoNewline
}
