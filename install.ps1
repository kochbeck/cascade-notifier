# install.ps1 - Install cascade-notifier-win.exe for Windsurf Cascade
# Requires: Windows 10/11, PowerShell 5.1+
# Run from Windows PowerShell (not WSL):
#   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#   .\install.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BinName    = "cascade-notifier-win.exe"
$NotifierDir = Join-Path $env:USERPROFILE ".windsurf-notifier"
$BinDir      = Join-Path $NotifierDir "bin"
$SoundsDir   = Join-Path $NotifierDir "sounds"
$ConfigFile  = Join-Path $NotifierDir "config.json"
$HooksFile   = Join-Path $env:USERPROFILE ".codeium\windsurf\hooks.json"

# -- Locate source files --
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$SrcBin     = Join-Path $ScriptDir "dist\$BinName"
$SrcSounds  = Join-Path $ScriptDir "sounds"
$SrcConfig  = Join-Path $ScriptDir "src\config\default-config.json"

if (-not (Test-Path $SrcBin)) {
    Write-Error "Binary not found: $SrcBin"
    Write-Error "Download a release or build: GOOS=windows GOARCH=amd64 go build -o dist\$BinName .\cmd\win"
    exit 1
}

# -- Create directories --
foreach ($dir in @($BinDir, $SoundsDir, (Split-Path -Parent $HooksFile))) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# -- Copy binary --
Copy-Item -Path $SrcBin -Destination (Join-Path $BinDir $BinName) -Force
Write-Host "Installed binary: $BinDir\$BinName"

# -- Copy sounds --
if (Test-Path $SrcSounds) {
    Copy-Item -Path "$SrcSounds\*.wav" -Destination $SoundsDir -Force
    Write-Host "Installed sounds: $SoundsDir"
}

# -- Write default config (do not overwrite existing user config) --
if (-not (Test-Path $ConfigFile)) {
    if (Test-Path $SrcConfig) {
        Copy-Item -Path $SrcConfig -Destination $ConfigFile -Force
        Write-Host "Created config: $ConfigFile"
    }
}

# -- Update hooks.json --
$BinPath = Join-Path $BinDir $BinName

$HooksContent = @"
{
  "hooks": {
    "post_cascade_response": [
      { "command": "$($BinPath.Replace('\','\\')) pcr", "show_output": false }
    ],
    "post_run_command": [
      { "command": "$($BinPath.Replace('\','\\')) prc", "show_output": false }
    ]
  }
}
"@

Set-Content -Path $HooksFile -Value $HooksContent -Encoding ASCII
Write-Host "Updated hooks: $HooksFile"

Write-Host ""
Write-Host "Installation complete."
Write-Host "Run the smoke test:"
Write-Host "  $BinPath --test all"
