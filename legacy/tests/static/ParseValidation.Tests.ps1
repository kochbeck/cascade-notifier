#Requires -Version 5.1
# ParseValidation.Tests.ps1 - Static analysis: parse errors and non-ASCII characters

# Collect files at script scope BEFORE Pester discovery
. (Join-Path $PSScriptRoot "..\helpers\TestHelper.ps1")
$script:Ps1TestCases = @(Get-ChildItem -Path (Get-ProjectRoot) -Filter "*.ps1" -Recurse |
    Where-Object { $_.FullName -notlike "*\tests\*" } |
    ForEach-Object { @{ File = $_; RelPath = $_.FullName.Replace((Get-ProjectRoot) + '\', '') } })

Describe "Static Analysis: All .ps1 files" {

    Context "Parse validation (Windows PowerShell 5.1 compatible)" {

        It "should parse without errors: <RelPath>" -TestCases $script:Ps1TestCases {
            param($File, $RelPath)
            $errors = $null
            $tokens = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $File.FullName, [ref]$tokens, [ref]$errors
            )
            $errors | Should -HaveCount 0 -Because (
                ($errors | ForEach-Object {
                    "Line $($_.Extent.StartLineNumber): $($_.Message)"
                }) -join "; "
            )
        }
    }

    Context "Non-ASCII character check" {

        It "should contain only ASCII characters: <RelPath>" -TestCases $script:Ps1TestCases {
            param($File, $RelPath)
            $bytes = [System.IO.File]::ReadAllBytes($File.FullName)
            $lineNum = 1
            $problems = @()

            for ($i = 0; $i -lt $bytes.Length; $i++) {
                if ($bytes[$i] -eq 10) { $lineNum++; continue }
                if ($bytes[$i] -gt 127) {
                    $start = [Math]::Max(0, $i - 15)
                    $len   = [Math]::Min(40, $bytes.Length - $start)
                    $ctx   = [System.Text.Encoding]::UTF8.GetString($bytes, $start, $len) -replace '[\r\n]', ' '
                    $problems += "Line ${lineNum}: byte 0x$("{0:X2}" -f $bytes[$i]) near: ...$ctx..."
                    while (($i + 1) -lt $bytes.Length -and $bytes[$i + 1] -gt 127 -and $bytes[$i + 1] -lt 192) {
                        $i++
                    }
                }
            }

            $problems | Should -HaveCount 0 -Because ($problems -join "`n")
        }
    }

    Context "BOM check" {

        It "should not have a UTF-8 BOM: <RelPath>" -TestCases $script:Ps1TestCases {
            param($File, $RelPath)
            $bytes = [System.IO.File]::ReadAllBytes($File.FullName)
            if ($bytes.Length -ge 3) {
                $hasBom = ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
                $hasBom | Should -BeFalse -Because "UTF-8 BOM can cause issues with PowerShell 5.1 and Node.js"
            }
        }
    }
}
