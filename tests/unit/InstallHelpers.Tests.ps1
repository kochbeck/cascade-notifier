#Requires -Version 5.1
# InstallHelpers.Tests.ps1 - Unit tests for helper functions in install.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot "..\helpers\TestHelper.ps1")

    # Extract helper functions from install.ps1 by dot-sourcing just the function defs.
    # We parse the file and eval only the function blocks to avoid running install logic.
    $installScript = Join-Path (Get-ProjectRoot) "install.ps1"
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($installScript, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe "ConvertTo-JsonStringValue" {

    It "escapes backslashes" {
        ConvertTo-JsonStringValue 'C:\Users\test' | Should -Be 'C:\\Users\\test'
    }

    It "escapes double quotes" {
        ConvertTo-JsonStringValue 'say "hello"' | Should -Be 'say \"hello\"'
    }

    It "escapes tabs" {
        ConvertTo-JsonStringValue "col1`tcol2" | Should -Be 'col1\tcol2'
    }

    It "escapes newlines" {
        ConvertTo-JsonStringValue "line1`nline2" | Should -Be 'line1\nline2'
    }

    It "escapes carriage returns" {
        ConvertTo-JsonStringValue "line1`rline2" | Should -Be 'line1\rline2'
    }

    It "escapes backslashes before quotes (order matters)" {
        ConvertTo-JsonStringValue 'path \"quoted\"' | Should -Be 'path \\\"quoted\\\"'
    }

    It "returns empty string for empty input" {
        ConvertTo-JsonStringValue '' | Should -Be ''
    }

    It "passes through safe strings unchanged" {
        ConvertTo-JsonStringValue 'simple text 123' | Should -Be 'simple text 123'
    }
}

Describe "ConvertTo-HookEntryJson" {

    It "produces valid JSON with command and show_output" {
        $result = ConvertTo-HookEntryJson -Command 'echo hello'
        $obj = $result | ConvertFrom-Json

        $obj.command | Should -Be 'echo hello'
        $obj.show_output | Should -BeFalse
    }

    It "sets show_output to true when specified" {
        $result = ConvertTo-HookEntryJson -Command 'echo hello' -ShowOutput $true
        $obj = $result | ConvertFrom-Json

        $obj.show_output | Should -BeTrue
    }

    It "properly escapes paths with backslashes in command" {
        $result = ConvertTo-HookEntryJson -Command 'powershell.exe -File "C:\Users\test\.windsurf-notifier\hooks\script.ps1"'
        $obj = $result | ConvertFrom-Json

        $obj.command | Should -Be 'powershell.exe -File "C:\Users\test\.windsurf-notifier\hooks\script.ps1"'
    }

    It "produces parseable JSON (round-trip)" {
        $cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\script.ps1"'
        $result = ConvertTo-HookEntryJson -Command $cmd
        { $result | ConvertFrom-Json } | Should -Not -Throw
    }
}

Describe "Write-Utf8NoBom" {

    BeforeEach {
        $script:tempDir = New-TempTestDir
    }

    AfterEach {
        Remove-TempTestDir $script:tempDir
    }

    It "writes a file without UTF-8 BOM" {
        $testFile = Join-Path $script:tempDir "test.json"
        Write-Utf8NoBom -Path $testFile -Content '{"key": "value"}'

        $bytes = [System.IO.File]::ReadAllBytes($testFile)
        # Should NOT start with EF BB BF (UTF-8 BOM)
        if ($bytes.Length -ge 3) {
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        }
    }

    It "writes correct content" {
        $testFile = Join-Path $script:tempDir "test.json"
        $content = '{"hooks": {"post_run_command": []}}'
        Write-Utf8NoBom -Path $testFile -Content $content

        $readBack = [System.IO.File]::ReadAllText($testFile)
        $readBack | Should -Be $content
    }

    It "content is parseable by ConvertFrom-Json (no BOM interference)" {
        $testFile = Join-Path $script:tempDir "test.json"
        Write-Utf8NoBom -Path $testFile -Content '{"key": "value"}'

        $json = Get-Content -Path $testFile -Raw | ConvertFrom-Json
        $json.key | Should -Be "value"
    }
}
