# TestHelper.ps1 - Shared utilities for Pester tests

$script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:SrcDir = Join-Path $script:ProjectRoot "src"
$script:LibDir = Join-Path $script:SrcDir "lib"
$script:HooksDir = Join-Path $script:SrcDir "hooks"
$script:ConfigDir = Join-Path $script:SrcDir "config"

function Get-ProjectRoot { return $script:ProjectRoot }
function Get-SrcDir { return $script:SrcDir }
function Get-LibDir { return $script:LibDir }
function Get-HooksDir { return $script:HooksDir }
function Get-ConfigDir { return $script:ConfigDir }

function New-TempTestDir {
    <#
    .SYNOPSIS
        Creates an isolated temp directory for a test run.
    #>
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("CascadeNotifierTests_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Remove-TempTestDir {
    param([string]$Path)
    if ($Path -and (Test-Path $Path)) {
        Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-AllPs1Files {
    <#
    .SYNOPSIS
        Returns all .ps1 files in the project (excluding tests/).
    #>
    return Get-ChildItem -Path (Get-ProjectRoot) -Filter "*.ps1" -Recurse |
        Where-Object { $_.FullName -notlike "*\tests\*" }
}
