#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the Cascade Notifier test suite using Pester 5.
.DESCRIPTION
    Bootstraps Pester 5 (user-scope install if needed) and invokes all *.Tests.ps1
    files under the tests/ directory.
.NOTES
    Run from the project root:
      powershell.exe -ExecutionPolicy Bypass -File tests\run-tests.ps1
#>

param(
    [string]$Filter,
    [switch]$SkipInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# --- Ensure Pester 5+ is available ---
$pester = Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 } | Sort-Object Version -Descending | Select-Object -First 1

if (-not $pester) {
    if ($SkipInstall) {
        Write-Host "ERROR: Pester 5+ not found. Run without -SkipInstall to auto-install." -ForegroundColor Red
        exit 1
    }
    Write-Host "Pester 5 not found. Installing to CurrentUser scope..." -ForegroundColor Yellow
    Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
    $pester = Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 } | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $pester) {
        Write-Host "ERROR: Failed to install Pester 5." -ForegroundColor Red
        exit 1
    }
}

# Force-import Pester 5 (override the built-in 3.x)
Get-Module Pester | Remove-Module -Force
Import-Module $pester.Path -Force

Write-Host "Using Pester $((Get-Module Pester).Version)" -ForegroundColor Cyan
Write-Host "Project root: $projectRoot" -ForegroundColor Cyan
Write-Host ""

# --- Run tests ---
$config = New-PesterConfiguration
$config.Run.Path = Join-Path $projectRoot "tests"
$config.Run.Exit = $true
$config.Output.Verbosity = "Detailed"
$config.TestResult.Enabled = $false

if ($Filter) {
    $config.Filter.FullName = "*$Filter*"
}

Invoke-Pester -Configuration $config
