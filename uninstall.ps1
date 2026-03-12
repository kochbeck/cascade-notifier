# uninstall.ps1 - Remove cascade-notifier from Windsurf Cascade
# Run from Windows PowerShell (not WSL):
#   .\uninstall.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$BinName     = "cascade-notifier-win.exe"
$NotifierDir = Join-Path $env:USERPROFILE ".windsurf-notifier"
$BinDir      = Join-Path $NotifierDir "bin"
$BinPath     = Join-Path $BinDir $BinName
$HooksFile   = Join-Path $env:USERPROFILE ".codeium\windsurf\hooks.json"

# -- Stop daemon if running --
$proc = Get-Process -Name "cascade-notifier-win" -ErrorAction SilentlyContinue
if ($null -ne $proc) {
    Write-Host "Stopping daemon..."
    $proc | Stop-Process -Force
    Start-Sleep -Milliseconds 500
}

# -- Remove binary --
if (Test-Path $BinPath) {
    Remove-Item -Path $BinPath -Force
    Write-Host "Removed binary: $BinPath"
}

# -- Remove hooks.json entries --
if (Test-Path $HooksFile) {
    Set-Content -Path $HooksFile -Value '{"hooks":{}}' -Encoding ASCII
    Write-Host "Cleared hooks: $HooksFile"
}

Write-Host ""
Write-Host "Uninstall complete."
Write-Host "Note: config, sounds, and logs in $NotifierDir were not removed."
Write-Host "To remove them: Remove-Item -Recurse -Force $NotifierDir"
