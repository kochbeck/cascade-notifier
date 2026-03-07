#Requires -Version 5.1
# Debounce.Tests.ps1 - Unit tests for src/lib/debounce.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot "..\helpers\TestHelper.ps1")
    . (Join-Path (Get-LibDir) "debounce.ps1")
}

Describe "Test-Debounce" {

    BeforeEach {
        $script:tempDir = New-TempTestDir
        $script:debounceDir = Join-Path $script:tempDir "debounce"
    }

    AfterEach {
        Remove-TempTestDir $script:tempDir
    }

    It "returns true when no previous debounce file exists" {
        $result = Test-Debounce -EventType "task-complete" -DebounceSeconds 5 -DebounceDir $script:debounceDir
        $result | Should -BeTrue
    }

    It "returns true when debounce file exists but window has expired" {
        New-Item -ItemType Directory -Path $script:debounceDir -Force | Out-Null
        $oldTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 60
        Set-Content -Path (Join-Path $script:debounceDir "task-complete") -Value $oldTime -NoNewline

        $result = Test-Debounce -EventType "task-complete" -DebounceSeconds 5 -DebounceDir $script:debounceDir
        $result | Should -BeTrue
    }

    It "returns false when within the debounce window" {
        New-Item -ItemType Directory -Path $script:debounceDir -Force | Out-Null
        $recentTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        Set-Content -Path (Join-Path $script:debounceDir "task-complete") -Value $recentTime -NoNewline

        $result = Test-Debounce -EventType "task-complete" -DebounceSeconds 60 -DebounceDir $script:debounceDir
        $result | Should -BeFalse
    }

    It "returns true when debounce file is corrupted" {
        New-Item -ItemType Directory -Path $script:debounceDir -Force | Out-Null
        Set-Content -Path (Join-Path $script:debounceDir "task-complete") -Value "not-a-number"

        $result = Test-Debounce -EventType "task-complete" -DebounceSeconds 5 -DebounceDir $script:debounceDir
        $result | Should -BeTrue
    }

    It "creates the debounce directory if it does not exist" {
        Test-Path $script:debounceDir | Should -BeFalse
        Test-Debounce -EventType "task-complete" -DebounceSeconds 5 -DebounceDir $script:debounceDir
        Test-Path $script:debounceDir | Should -BeTrue
    }

    It "tracks separate debounce windows per event type" {
        New-Item -ItemType Directory -Path $script:debounceDir -Force | Out-Null
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        Set-Content -Path (Join-Path $script:debounceDir "task-complete") -Value $now -NoNewline

        # task-complete should be debounced, but task-error should not
        Test-Debounce -EventType "task-complete" -DebounceSeconds 60 -DebounceDir $script:debounceDir | Should -BeFalse
        Test-Debounce -EventType "task-error" -DebounceSeconds 60 -DebounceDir $script:debounceDir | Should -BeTrue
    }
}

Describe "Update-Debounce" {

    BeforeEach {
        $script:tempDir = New-TempTestDir
        $script:debounceDir = Join-Path $script:tempDir "debounce"
    }

    AfterEach {
        Remove-TempTestDir $script:tempDir
    }

    It "creates a debounce file with a Unix timestamp" {
        Update-Debounce -EventType "task-complete" -DebounceDir $script:debounceDir

        $file = Join-Path $script:debounceDir "task-complete"
        Test-Path $file | Should -BeTrue

        $content = (Get-Content -Path $file -Raw).Trim()
        $ts = [long]$content
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        [Math]::Abs($now - $ts) | Should -BeLessOrEqual 2
    }

    It "creates the debounce directory if it does not exist" {
        Test-Path $script:debounceDir | Should -BeFalse
        Update-Debounce -EventType "task-complete" -DebounceDir $script:debounceDir
        Test-Path $script:debounceDir | Should -BeTrue
    }

    It "overwrites an existing debounce file" {
        New-Item -ItemType Directory -Path $script:debounceDir -Force | Out-Null
        Set-Content -Path (Join-Path $script:debounceDir "task-complete") -Value "1000" -NoNewline

        Update-Debounce -EventType "task-complete" -DebounceDir $script:debounceDir

        $content = (Get-Content -Path (Join-Path $script:debounceDir "task-complete") -Raw).Trim()
        [long]$content | Should -BeGreaterThan 1000
    }
}
