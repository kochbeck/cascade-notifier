#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the Windsurf Cascade Notifier.
.DESCRIPTION
    Copies hook scripts, libraries, sounds, and config to %USERPROFILE%\.windsurf-notifier,
    then merges hook entries into the user-level Windsurf hooks.json.
.NOTES
    Run from the project root: powershell.exe -ExecutionPolicy Bypass -File install.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Helper: write string to file as BOM-free UTF-8 ---
# PS 5.1's Set-Content -Encoding UTF8 writes a BOM, which breaks Node.js JSON.parse().
function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

# --- Helper: escape a string for safe embedding in a JSON string value ---
function ConvertTo-JsonStringValue {
    param([string]$Value)
    # Order matters: backslashes first, then quotes, then control chars
    $Value = $Value -replace '\\', '\\'
    $Value = $Value -replace '"', '\"'
    $Value = $Value -replace "`t", '\t'
    $Value = $Value -replace "`n", '\n'
    $Value = $Value -replace "`r", '\r'
    return $Value
}

# --- Helper: serialize a single hook entry object to a JSON string ---
# Using manual construction avoids PS 5.1's ConvertTo-Json single-element array bug.
function ConvertTo-HookEntryJson {
    param([Parameter(Mandatory)][string]$Command, [bool]$ShowOutput = $false)
    $escapedCmd = ConvertTo-JsonStringValue $Command
    $showStr = if ($ShowOutput) { "true" } else { "false" }
    return '{ "command": "' + $escapedCmd + '", "show_output": ' + $showStr + ' }'
}

# --- Validate environment ---
if (-not $PSScriptRoot -or -not (Test-Path $PSScriptRoot)) {
    Write-Host "ERROR: Cannot determine script directory. Run with: powershell.exe -ExecutionPolicy Bypass -File install.ps1" -ForegroundColor Red
    exit 1
}

# Configuration
$InstallDir = Join-Path $env:USERPROFILE ".windsurf-notifier"
$ScriptDir = $PSScriptRoot
$WindsurfHooksDir = Join-Path (Join-Path $env:USERPROFILE ".codeium") "windsurf"
$WindsurfHooksFile = Join-Path $WindsurfHooksDir "hooks.json"

# Validate source directories exist
$hooksSource  = Join-Path (Join-Path $ScriptDir "src") "hooks"
$libSource    = Join-Path (Join-Path $ScriptDir "src") "lib"
$configSource = Join-Path (Join-Path $ScriptDir "src") "config"

foreach ($srcDir in @($hooksSource, $libSource, $configSource)) {
    if (-not (Test-Path $srcDir)) {
        Write-Host "ERROR: Source directory missing: $srcDir" -ForegroundColor Red
        Write-Host "Please run install.ps1 from the project root directory." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Installing Windsurf Cascade Notifier..." -ForegroundColor Cyan

# --- Step 1: Create installation directories ---
$dirs = @(
    (Join-Path $InstallDir "hooks"),
    (Join-Path $InstallDir "lib"),
    (Join-Path $InstallDir "config"),
    (Join-Path $InstallDir "sounds"),
    (Join-Path $InstallDir "debounce")
)
foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}
Write-Host "  Created directory structure at: $InstallDir"

# --- Step 2: Copy source files ---
Copy-Item -Path (Join-Path $hooksSource "*.ps1") -Destination (Join-Path $InstallDir "hooks") -Force
Write-Host "  Installed hook scripts"

Copy-Item -Path (Join-Path $libSource "*.ps1") -Destination (Join-Path $InstallDir "lib") -Force
Write-Host "  Installed library scripts"

Copy-Item -Path (Join-Path $configSource "*.json") -Destination (Join-Path $InstallDir "config") -Force

# Copy user config (preserve existing)
$userConfig = Join-Path $InstallDir "config.json"
if (-not (Test-Path $userConfig)) {
    Copy-Item -Path (Join-Path $configSource "default-config.json") -Destination $userConfig -Force
    Write-Host "  Created default configuration"
}
else {
    Write-Host "  Preserving existing configuration"
}

# Copy sounds (preserve user customizations)
$soundsSource = Join-Path $ScriptDir "sounds"
if (Test-Path $soundsSource) {
    $soundsDest = Join-Path $InstallDir "sounds"
    Get-ChildItem -Path $soundsSource -Filter "*.wav" | ForEach-Object {
        $destFile = Join-Path $soundsDest $_.Name
        if (-not (Test-Path $destFile)) {
            Copy-Item -Path $_.FullName -Destination $destFile -Force
        }
    }
    Write-Host "  Installed default sounds (preserved existing)"
}

# --- Step 3: Configure Windsurf hooks ---
Write-Host "  Configuring Windsurf hooks..."

$postRunHookCmd      = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $InstallDir 'hooks\post_run_command.ps1') + '"'
$postResponseHookCmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $InstallDir 'hooks\post_cascade_response.ps1') + '"'
$notifierMarker      = ".windsurf-notifier"

# Create hooks directory if needed
if (-not (Test-Path $WindsurfHooksDir)) {
    New-Item -ItemType Directory -Path $WindsurfHooksDir -Force | Out-Null
}

# Backup existing hooks.json
if (Test-Path $WindsurfHooksFile) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    # Use ${var} syntax to prevent StrictMode from parsing "var.backup" as property access
    $backupFile = "${WindsurfHooksFile}.backup.${timestamp}"
    Copy-Item -Path $WindsurfHooksFile -Destination $backupFile -Force
    Write-Host "  Backup created: $backupFile"
}

# --- Merge strategy ---
# To completely avoid PS 5.1's ConvertTo-Json single-element array unwrapping,
# we always assemble the final hooks.json as a hand-built JSON string.
# Existing non-notifier hook entries are serialized individually (no array issue
# for a single object), then placed inside explicit [...] brackets.

# Collect existing non-notifier entries per hook type
$existingPostRun      = @()  # array of JSON strings, one per entry
$existingPostResponse = @()
$otherHookSections    = @()  # JSON fragments for hook types we don't manage

$notifierHookNames = @("post_run_command", "post_cascade_response")

if (Test-Path $WindsurfHooksFile) {
    try {
        $hooksObj = Get-Content -Path $WindsurfHooksFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

        if ($null -ne $hooksObj.PSObject.Properties['hooks']) {
            $hooksNode = $hooksObj.hooks

            foreach ($pair in @(
                @{ Name = "post_run_command";      Var = "existingPostRun" },
                @{ Name = "post_cascade_response"; Var = "existingPostResponse" }
            )) {
                $hookName = $pair.Name
                if ($null -ne $hooksNode.PSObject.Properties[$hookName]) {
                    $entries = $hooksNode.$hookName
                    # Normalize: might be array, single object, or null
                    if ($null -ne $entries) {
                        if ($entries -isnot [System.Array]) { $entries = @($entries) }
                        foreach ($entry in $entries) {
                            # Skip our own entries (idempotent reinstall)
                            $isOurs = $false
                            if ($null -ne $entry.PSObject.Properties['command']) {
                                if ($entry.command -like "*${notifierMarker}*") {
                                    $isOurs = $true
                                }
                            }
                            if (-not $isOurs) {
                                # Serialize this single entry to JSON (safe -- single objects serialize fine)
                                $entryJson = $entry | ConvertTo-Json -Depth 5 -Compress
                                Set-Variable -Name $pair.Var -Value (@((Get-Variable -Name $pair.Var -ValueOnly) + $entryJson))
                            }
                        }
                    }
                }
            }

            # Preserve any hook types we don't manage (e.g. pre_run_command)
            foreach ($prop in $hooksNode.PSObject.Properties) {
                if ($notifierHookNames -contains $prop.Name) { continue }
                $otherEntries = $prop.Value
                if ($null -eq $otherEntries) {
                    $otherHookSections += '    "' + $prop.Name + '": null'
                }
                elseif ($otherEntries -is [System.Array] -or $otherEntries -is [System.Collections.IEnumerable] -and $otherEntries -isnot [string]) {
                    if ($otherEntries -isnot [System.Array]) { $otherEntries = @($otherEntries) }
                    $serialized = @()
                    foreach ($e in $otherEntries) {
                        $serialized += "      " + ($e | ConvertTo-Json -Depth 5 -Compress)
                    }
                    $otherHookSections += '    "' + $prop.Name + '": [' + "`r`n" + ($serialized -join ",`r`n") + "`r`n" + '    ]'
                }
                else {
                    # Scalar or single object
                    $otherHookSections += '    "' + $prop.Name + '": ' + ($otherEntries | ConvertTo-Json -Depth 5 -Compress)
                }
            }
        }
        Write-Host "  Parsed existing hooks.json"
    }
    catch {
        Write-Host "  WARNING: Could not parse existing hooks.json -- overwriting it." -ForegroundColor Yellow
        Write-Host "  (Backup was saved above)" -ForegroundColor DarkGray
        $existingPostRun = @()
        $existingPostResponse = @()
        $otherHookSections = @()
    }
}

# Build final entry lists: existing entries first, then our notifier entries
$postRunEntries      = $existingPostRun + @(ConvertTo-HookEntryJson $postRunHookCmd)
$postResponseEntries = $existingPostResponse + @(ConvertTo-HookEntryJson $postResponseHookCmd)

# Join entries with newline + indent for readability
$nl = "`r`n"
$indent = "      "
$postRunArrayBody      = ($postRunEntries | ForEach-Object { "${indent}$_" }) -join ",${nl}"
$postResponseArrayBody = ($postResponseEntries | ForEach-Object { "${indent}$_" }) -join ",${nl}"

# Assemble all hook sections: our two managed types + any preserved types
$allHookSections = @(
    ('    "post_run_command": [' + $nl + $postRunArrayBody + $nl + '    ]'),
    ('    "post_cascade_response": [' + $nl + $postResponseArrayBody + $nl + '    ]')
) + $otherHookSections

$hooksJsonText = @(
    '{',
    '  "hooks": {',
    ($allHookSections -join ",${nl}"),
    '  }',
    '}'
) -join $nl

Write-Utf8NoBom -Path $WindsurfHooksFile -Content $hooksJsonText
Write-Host "  Configured hooks.json"

# Check for workspace-level hooks
$wsHooksFile = Join-Path ".windsurf" "hooks.json"
if (Test-Path $wsHooksFile) {
    Write-Host ""
    Write-Host "  NOTE: Workspace-level .windsurf\hooks.json also exists." -ForegroundColor Yellow
    Write-Host "  User-level hooks take precedence. Consider removing project-level hooks if not needed."
}

Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Installed to:  $InstallDir"
Write-Host "  Hooks config:  $WindsurfHooksFile"
Write-Host "  User config:   $userConfig"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Restart Windsurf to load the hooks"
Write-Host "  2. Replace .wav files in ${InstallDir}\sounds\ with your preferred sounds"
Write-Host "  3. Edit $userConfig to customize notification preferences"
Write-Host "  4. View logs: Get-Content -Tail 20 -Wait '${InstallDir}\notifications.log'"
