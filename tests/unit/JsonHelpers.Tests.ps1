#Requires -Version 5.1
# JsonHelpers.Tests.ps1 - Unit tests for src/lib/json-helpers.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot "..\helpers\TestHelper.ps1")
    . (Join-Path (Get-LibDir) "json-helpers.ps1")
}

Describe "Get-NotifierConfig" {

    BeforeEach {
        $script:tempDir = New-TempTestDir
    }

    AfterEach {
        Remove-TempTestDir $script:tempDir
    }

    It "returns all default values when no config file exists" {
        $config = Get-NotifierConfig -ConfigPath "C:\nonexistent\config.json" -DefaultConfigPath "C:\nonexistent\defaults.json"

        $config.enabled           | Should -BeTrue
        $config.terminal_input    | Should -BeTrue
        $config.git_commands      | Should -BeFalse
        $config.task_complete     | Should -BeTrue
        $config.task_error        | Should -BeTrue
        $config.approval_required | Should -BeTrue
        $config.sound_enabled     | Should -BeTrue
        $config.toast_enabled     | Should -BeTrue
        $config.debounce_seconds  | Should -Be 5
    }

    It "loads values from user config file" {
        $configFile = Join-Path $script:tempDir "config.json"
        Set-Content -Path $configFile -Value '{ "enabled": false, "debounce_seconds": 30 }'

        $config = Get-NotifierConfig -ConfigPath $configFile

        $config.enabled          | Should -BeFalse
        $config.debounce_seconds | Should -Be 30
        # Unspecified keys should keep defaults
        $config.task_complete    | Should -BeTrue
    }

    It "falls back to default config when user config is missing" {
        $defaultFile = Join-Path $script:tempDir "defaults.json"
        Set-Content -Path $defaultFile -Value '{ "sound_enabled": false }'

        $config = Get-NotifierConfig -ConfigPath "C:\nonexistent\config.json" -DefaultConfigPath $defaultFile

        $config.sound_enabled | Should -BeFalse
        $config.enabled       | Should -BeTrue
    }

    It "prefers user config over default config" {
        $userFile = Join-Path $script:tempDir "user.json"
        $defaultFile = Join-Path $script:tempDir "defaults.json"
        Set-Content -Path $userFile -Value '{ "debounce_seconds": 10 }'
        Set-Content -Path $defaultFile -Value '{ "debounce_seconds": 99 }'

        $config = Get-NotifierConfig -ConfigPath $userFile -DefaultConfigPath $defaultFile

        $config.debounce_seconds | Should -Be 10
    }

    It "returns defaults when config file contains malformed JSON" {
        $configFile = Join-Path $script:tempDir "bad.json"
        Set-Content -Path $configFile -Value '{ not valid json !!!'

        $config = Get-NotifierConfig -ConfigPath $configFile

        $config.enabled          | Should -BeTrue
        $config.debounce_seconds | Should -Be 5
    }

    It "returns defaults when config file is empty" {
        $configFile = Join-Path $script:tempDir "empty.json"
        Set-Content -Path $configFile -Value ''

        $config = Get-NotifierConfig -ConfigPath $configFile

        $config.enabled | Should -BeTrue
    }

    It "handles config with all keys overridden" {
        $configFile = Join-Path $script:tempDir "full.json"
        $json = @'
{
    "enabled": false,
    "terminal_input": false,
    "git_commands": true,
    "task_complete": false,
    "task_error": false,
    "approval_required": false,
    "sound_enabled": false,
    "toast_enabled": false,
    "debounce_seconds": 120
}
'@
        Set-Content -Path $configFile -Value $json

        $config = Get-NotifierConfig -ConfigPath $configFile

        $config.enabled           | Should -BeFalse
        $config.terminal_input    | Should -BeFalse
        $config.git_commands      | Should -BeTrue
        $config.task_complete     | Should -BeFalse
        $config.task_error        | Should -BeFalse
        $config.approval_required | Should -BeFalse
        $config.sound_enabled     | Should -BeFalse
        $config.toast_enabled     | Should -BeFalse
        $config.debounce_seconds  | Should -Be 120
    }

    It "ignores unknown keys in the config file" {
        $configFile = Join-Path $script:tempDir "extra.json"
        Set-Content -Path $configFile -Value '{ "enabled": true, "unknown_key": "ignored" }'

        $config = Get-NotifierConfig -ConfigPath $configFile

        $config.enabled | Should -BeTrue
        $config.ContainsKey("unknown_key") | Should -BeFalse
    }
}
