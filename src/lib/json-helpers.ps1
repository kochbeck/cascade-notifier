# json-helpers.ps1 - JSON parsing utilities for Windows PowerShell 5.1

function Get-NotifierConfig {
    <#
    .SYNOPSIS
        Loads notification config from JSON file with defaults fallback.
    .PARAMETER ConfigPath
        Path to the user's config.json
    .PARAMETER DefaultConfigPath
        Path to the default config.json (bundled)
    #>
    param(
        [string]$ConfigPath,
        [string]$DefaultConfigPath
    )

    $defaults = @{
        enabled           = $true
        terminal_input    = $true
        git_commands      = $false
        task_complete     = $true
        task_error        = $true
        approval_required = $true
        sound_enabled     = $true
        toast_enabled     = $true
        debounce_seconds  = 5
    }

    # Try user config first, then default config
    $configFile = $null
    if ($ConfigPath -and (Test-Path $ConfigPath)) {
        $configFile = $ConfigPath
    }
    elseif ($DefaultConfigPath -and (Test-Path $DefaultConfigPath)) {
        $configFile = $DefaultConfigPath
    }

    if ($configFile) {
        try {
            $json = Get-Content -Path $configFile -Raw -ErrorAction Stop | ConvertFrom-Json
            # Merge loaded values over defaults
            foreach ($key in @($defaults.Keys)) {
                $value = $json.PSObject.Properties[$key]
                if ($null -ne $value) {
                    $defaults[$key] = $value.Value
                }
            }
        }
        catch {
            # If config is malformed, fall back to defaults silently
        }
    }

    return $defaults
}

