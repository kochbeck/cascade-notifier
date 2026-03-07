#Requires -Version 5.1
<#
.SYNOPSIS
    Uninstalls the Windsurf Cascade Notifier.
.DESCRIPTION
    Removes notifier hooks from hooks.json and optionally removes all notifier files.
.NOTES
    Run: powershell.exe -ExecutionPolicy Bypass -File uninstall.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Helper: write string to file as BOM-free UTF-8 ---
function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

# Configuration
$InstallDir = Join-Path $env:USERPROFILE ".windsurf-notifier"
$WindsurfHooksDir = Join-Path (Join-Path $env:USERPROFILE ".codeium") "windsurf"
$WindsurfHooksFile = Join-Path $WindsurfHooksDir "hooks.json"
$notifierMarker = ".windsurf-notifier"

Write-Host "Uninstalling Windsurf Cascade Notifier..." -ForegroundColor Cyan

# --- Remove hooks from hooks.json ---
if (Test-Path $WindsurfHooksFile) {
    # Backup before modifying
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupFile = "${WindsurfHooksFile}.backup.${timestamp}"
    Copy-Item -Path $WindsurfHooksFile -Destination $backupFile -Force
    Write-Host "  Backup created: $backupFile"

    try {
        $hooksObj = Get-Content -Path $WindsurfHooksFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

        # Safe check for hooks property
        if ($null -eq $hooksObj.PSObject.Properties['hooks']) {
            Write-Host "  No hooks section found in hooks.json"
        }
        else {
            $hooksNode = $hooksObj.hooks
            $modified = $false

            # Collect remaining entries per hook type, rebuild JSON by hand
            # (same strategy as install.ps1 to avoid PS 5.1 array serialization bugs)
            $remainingPerHook = @{}
            $notifierHookNames = @("post_run_command", "post_cascade_response")

            foreach ($hookName in $notifierHookNames) {
                $remainingPerHook[$hookName] = @()

                if ($null -eq $hooksNode.PSObject.Properties[$hookName]) {
                    continue
                }

                $entries = $hooksNode.$hookName
                # Normalize: might be single object, array, or null
                if ($null -eq $entries) { continue }
                if ($entries -isnot [System.Array]) { $entries = @($entries) }

                foreach ($entry in $entries) {
                    $isOurs = $false
                    if ($null -ne $entry.PSObject.Properties['command']) {
                        if ($entry.command -like "*${notifierMarker}*") {
                            $isOurs = $true
                            $modified = $true
                        }
                    }
                    if (-not $isOurs) {
                        # Serialize individual entry (single objects are fine in ConvertTo-Json)
                        $entryJson = $entry | ConvertTo-Json -Depth 5 -Compress
                        $remainingPerHook[$hookName] += $entryJson
                    }
                }
            }

            if ($modified) {
                # Rebuild hooks.json by hand to guarantee array syntax
                $nl = "`r`n"
                $indent = "      "
                $hookSections = @()
                foreach ($hookName in $notifierHookNames) {
                    $entries = $remainingPerHook[$hookName]
                    if ($entries.Count -gt 0) {
                        $body = ($entries | ForEach-Object { "${indent}$_" }) -join ",${nl}"
                        $hookSections += '    "' + $hookName + '": [' + $nl + $body + $nl + '    ]'
                    }
                    else {
                        $hookSections += '    "' + $hookName + '": []'
                    }
                }

                # Preserve any hook types we don't manage (e.g. pre_run_command)
                foreach ($prop in $hooksNode.PSObject.Properties) {
                    if ($notifierHookNames -contains $prop.Name) { continue }
                    $otherEntries = $prop.Value
                    if ($null -eq $otherEntries) {
                        $hookSections += '    "' + $prop.Name + '": null'
                    }
                    elseif ($otherEntries -is [System.Array] -or $otherEntries -is [System.Collections.IEnumerable] -and $otherEntries -isnot [string]) {
                        if ($otherEntries -isnot [System.Array]) { $otherEntries = @($otherEntries) }
                        $serialized = @()
                        foreach ($e in $otherEntries) {
                            $serialized += "      " + ($e | ConvertTo-Json -Depth 5 -Compress)
                        }
                        $hookSections += '    "' + $prop.Name + '": [' + $nl + ($serialized -join ",${nl}") + $nl + '    ]'
                    }
                    else {
                        $hookSections += '    "' + $prop.Name + '": ' + ($otherEntries | ConvertTo-Json -Depth 5 -Compress)
                    }
                }

                $hooksJsonText = '{' + $nl + '  "hooks": {' + $nl + ($hookSections -join (',' + $nl)) + $nl + '  }' + $nl + '}'
                Write-Utf8NoBom -Path $WindsurfHooksFile -Content $hooksJsonText
                Write-Host "  Removed notifier hooks from hooks.json"
            }
            else {
                Write-Host "  No notifier hooks found in hooks.json"
            }
        }
    }
    catch {
        Write-Host "  WARNING: Could not update hooks.json: $_" -ForegroundColor Yellow
        Write-Host "  (Backup was saved at: $backupFile)" -ForegroundColor DarkGray
    }
}
else {
    Write-Host "  No hooks.json found"
}

# --- Optionally remove installation directory ---
if (Test-Path $InstallDir) {
    Write-Host ""
    $response = Read-Host "Remove installation directory (${InstallDir})? This will delete config, logs, and custom sounds. [y/N]"
    if ($response -eq 'y' -or $response -eq 'Y') {
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Host "  Removed: $InstallDir"
    }
    else {
        Write-Host "  Kept: $InstallDir (config and logs preserved)"
    }
}

Write-Host ""
Write-Host "Uninstall complete!" -ForegroundColor Green
Write-Host "Restart Windsurf to apply changes."
