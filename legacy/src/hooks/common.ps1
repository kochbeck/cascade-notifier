# common.ps1 - Shared initialization for Cascade notification hooks
# Dot-sourced by hook scripts to load config and library functions
# NOTE: Do not set ErrorActionPreference or StrictMode here -- the calling hook controls those.

# Paths
$script:NotifierDir = Join-Path $env:USERPROFILE ".windsurf-notifier"
$script:ConfigFile = Join-Path $script:NotifierDir "config.json"
$script:LogFile = Join-Path $script:NotifierDir "notifications.log"
$script:DebounceDir = Join-Path $script:NotifierDir "debounce"
$script:SoundsDir = Join-Path $script:NotifierDir "sounds"

# Resolve library directory relative to this script
$script:ScriptRoot = Split-Path -Parent $PSScriptRoot
if (-not $script:ScriptRoot) {
    $script:ScriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
$script:LibDir = Join-Path $script:ScriptRoot "lib"
$script:DefaultConfigFile = Join-Path (Join-Path $script:ScriptRoot "config") "default-config.json"

# If LibDir doesn't exist at the src location, try the installed location
if (-not (Test-Path $script:LibDir)) {
    $script:LibDir = Join-Path $script:NotifierDir "lib"
    $script:DefaultConfigFile = Join-Path (Join-Path $script:NotifierDir "config") "default-config.json"
}

# Source library functions
. (Join-Path $script:LibDir "json-helpers.ps1")
. (Join-Path $script:LibDir "logger.ps1")
. (Join-Path $script:LibDir "debounce.ps1")
. (Join-Path $script:LibDir "notifier.ps1")

# Ensure directories exist
foreach ($dir in @($script:NotifierDir, $script:DebounceDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Initialize-HookConfig {
    <#
    .SYNOPSIS
        Loads user config (hot-reload on each hook invocation).
    .OUTPUTS
        Hashtable of config values.
    #>
    return Get-NotifierConfig -ConfigPath $script:ConfigFile -DefaultConfigPath $script:DefaultConfigFile
}

function Test-ShouldNotify {
    <#
    .SYNOPSIS
        Determines if a notification should be sent for the given event type.
        Checks: master switch, per-event toggle, focus suppression, debounce.
    .PARAMETER EventType
        The event type to check
    .PARAMETER Config
        Hashtable of config values
    .OUTPUTS
        $true if should notify, $false if should skip.
    #>
    param(
        [Parameter(Mandatory)][string]$EventType,
        [Parameter(Mandatory)][hashtable]$Config
    )

    # Master switch
    if (-not $Config.enabled) {
        return $false
    }

    # Per-event toggle
    $eventKey = $EventType -replace '-', '_'
    if ($Config.ContainsKey($eventKey) -and -not $Config[$eventKey]) {
        return $false
    }

    # Debounce
    if (-not (Test-Debounce -EventType $EventType -DebounceSeconds $Config.debounce_seconds -DebounceDir $script:DebounceDir)) {
        Write-NotifierLog -EventType $EventType -Status "SUPPRESSED" -Message "debounced" -LogFile $script:LogFile
        return $false
    }

    return $true
}
