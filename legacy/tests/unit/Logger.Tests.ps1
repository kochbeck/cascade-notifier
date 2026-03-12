#Requires -Version 5.1
# Logger.Tests.ps1 - Unit tests for src/lib/logger.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot "..\helpers\TestHelper.ps1")
    . (Join-Path (Get-LibDir) "logger.ps1")
}

Describe "Write-NotifierLog" {

    BeforeEach {
        $script:tempDir = New-TempTestDir
        $script:logFile = Join-Path $script:tempDir "notifications.log"
    }

    AfterEach {
        Remove-TempTestDir $script:tempDir
    }

    It "creates a log file and writes a structured entry" {
        Write-NotifierLog -EventType "task-complete" -Status "SENT" -Message "Test message" -LogFile $script:logFile

        Test-Path $script:logFile | Should -BeTrue
        $content = Get-Content -Path $script:logFile -Raw
        $content | Should -Match "task-complete"
        $content | Should -Match "SENT"
        $content | Should -Match "Test message"
    }

    It "writes entries in the expected format: timestamp | event | status | message" {
        Write-NotifierLog -EventType "task-error" -Status "FAILED" -Message "Something broke" -LogFile $script:logFile

        # @() forces array context — without it, single-line Get-Content returns
        # a bare string, and [0] would give the first *character* in PS 5.1.
        $line = @(Get-Content -Path $script:logFile)[0]
        $parts = @($line -split ' \| ')
        $parts.Count | Should -Be 4

        # Timestamp should be ISO 8601
        $parts[0] | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
        $parts[1] | Should -Be "task-error"
        $parts[2] | Should -Be "FAILED"
        $parts[3] | Should -Match "Something broke"
    }

    It "appends multiple entries to the same log file" {
        Write-NotifierLog -EventType "task-complete" -Status "SENT" -Message "First" -LogFile $script:logFile
        Write-NotifierLog -EventType "task-error" -Status "SENT" -Message "Second" -LogFile $script:logFile

        $lines = @(Get-Content -Path $script:logFile)
        $lines.Count | Should -Be 2
    }

    It "creates parent directories if they do not exist" {
        $nestedLog = Join-Path $script:tempDir "sub\dir\test.log"
        Write-NotifierLog -EventType "test" -Status "SENT" -Message "Nested" -LogFile $nestedLog

        Test-Path $nestedLog | Should -BeTrue
    }

    It "does not throw when logging fails (silent failure)" {
        # Use an invalid path that can't be created
        { Write-NotifierLog -EventType "test" -Status "SENT" -Message "Test" -LogFile "\\?\invalid\path\<>:.log" } |
            Should -Not -Throw
    }
}

Describe "Get-RecentLogs" {

    BeforeEach {
        $script:tempDir = New-TempTestDir
        $script:logFile = Join-Path $script:tempDir "notifications.log"
    }

    AfterEach {
        Remove-TempTestDir $script:tempDir
    }

    It "returns empty array when log file does not exist" {
        $result = @(Get-RecentLogs -LogFile $script:logFile -Count 10)
        $result.Count | Should -Be 0
    }

    It "returns the last N entries" {
        for ($i = 1; $i -le 20; $i++) {
            Add-Content -Path $script:logFile -Value "Entry $i"
        }

        $result = @(Get-RecentLogs -LogFile $script:logFile -Count 5)
        $result.Count | Should -Be 5
        $result[0] | Should -Be "Entry 16"
        $result[-1] | Should -Be "Entry 20"
    }

    It "returns all entries when fewer than N exist" {
        Add-Content -Path $script:logFile -Value "Only entry"

        $result = @(Get-RecentLogs -LogFile $script:logFile -Count 10)
        $result.Count | Should -Be 1
        $result[0] | Should -Be "Only entry"
    }
}
