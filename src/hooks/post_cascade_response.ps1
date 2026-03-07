# post_cascade_response.ps1 - Hook for detecting task completion, errors, and approval events
# Called by Windsurf Cascade after each response

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# Source common initialization
$hookDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $hookDir "common.ps1")

# Patterns that indicate errors (use specific phrases to avoid false positives
# on normal Cascade responses that mention errors in passing)
$script:ErrorPatterns = @(
    "Error:"
    "error occurred"
    "error encountered"
    "build failed"
    "command failed"
    "task failed"
    "compilation failed"
    "install failed"
    "deploy failed"
    "unhandled exception"
    "threw an exception"
    "Cannot find "
    "Could not find "
    "Could not connect"
    "Could not resolve"
    "fatal error"
    "stack trace"
    "Traceback "
)

# Patterns that indicate waiting for approval (use specific phrases to avoid
# false positives when Cascade casually mentions "confirm" or "permission")
$script:ApprovalPatterns = @(
    "waiting for approval"
    "waiting for your approval"
    "requires approval"
    "needs your approval"
    "approve this"
    "approve the "
    "Do you want to proceed"
    "Would you like to continue"
    "Would you like me to"
    "Should I proceed"
    "Please confirm"
    "need your permission"
    "requires your permission"
)

function Test-TaskError {
    <#
    .SYNOPSIS
        Detects error patterns in the Cascade response.
    #>
    param([string]$Response)

    foreach ($pattern in $script:ErrorPatterns) {
        if ($Response -like "*$pattern*") {
            return $true
        }
    }
    return $false
}

function Test-ApprovalWaiting {
    <#
    .SYNOPSIS
        Detects approval-waiting patterns in the Cascade response.
    #>
    param([string]$Response)

    foreach ($pattern in $script:ApprovalPatterns) {
        if ($Response -like "*$pattern*") {
            return $true
        }
    }
    return $false
}

function Invoke-PostCascadeResponse {
    <#
    .SYNOPSIS
        Main hook logic: parse input, detect event type, send notification.
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

    # Extract response text (safe property access for StrictMode)
    $response = ""
    if ($hookInput.PSObject.Properties['tool_info']) {
        $toolInfo = $hookInput.tool_info
        if ($toolInfo.PSObject.Properties['response']) {
            $response = $toolInfo.response
        }
    }

    # Check for approval waiting (highest priority)
    if (Test-ApprovalWaiting -Response $response) {
        if (Test-ShouldNotify -EventType "approval-required" -Config $config) {
            Send-CascadeNotification `
                -EventType "approval-required" `
                -Title "Cascade: Waiting for your approval" `
                -Body "Cascade needs your approval to proceed" `
                -Config $config `
                -SoundsDir $script:SoundsDir `
                -LogFile $script:LogFile `
                -DebounceDir $script:DebounceDir
        }
        return
    }

    # Check for errors
    if (Test-TaskError -Response $response) {
        if (Test-ShouldNotify -EventType "task-error" -Config $config) {
            Send-CascadeNotification `
                -EventType "task-error" `
                -Title "Cascade: Error encountered" `
                -Body "An error occurred during task execution" `
                -Config $config `
                -SoundsDir $script:SoundsDir `
                -LogFile $script:LogFile `
                -DebounceDir $script:DebounceDir
        }
        return
    }

    # Default: task completed
    if (-not [string]::IsNullOrWhiteSpace($response)) {
        if (Test-ShouldNotify -EventType "task-complete" -Config $config) {
            Send-CascadeNotification `
                -EventType "task-complete" `
                -Title "Cascade: Task completed" `
                -Body "Cascade has finished the current task" `
                -Config $config `
                -SoundsDir $script:SoundsDir `
                -LogFile $script:LogFile `
                -DebounceDir $script:DebounceDir
        }
    }
}

# Run
try {
    Invoke-PostCascadeResponse
}
catch {
    # Hook failures must not break Cascade
    try {
        Write-NotifierLog -EventType "hook-error" -Status "FAILED" -Message $_.Exception.Message -LogFile $script:LogFile
    }
    catch { }
}
