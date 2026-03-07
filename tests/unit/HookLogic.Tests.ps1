#Requires -Version 5.1
# HookLogic.Tests.ps1 - Unit tests for pattern matching and decision logic in hook scripts

BeforeAll {
    . (Join-Path $PSScriptRoot "..\helpers\TestHelper.ps1")

    # Source the library files that the hook functions depend on
    . (Join-Path (Get-LibDir) "json-helpers.ps1")
    . (Join-Path (Get-LibDir) "logger.ps1")
    . (Join-Path (Get-LibDir) "debounce.ps1")

    . (Join-Path (Get-LibDir) "notifier.ps1")

    # Define script-scope variables that common.ps1's functions expect
    $script:NotifierDir = "C:\fake\notifier"
    $script:LogFile = "C:\fake\notifications.log"
    $script:DebounceDir = "C:\fake\debounce"
    $script:SoundsDir = "C:\fake\sounds"
    $script:ConfigFile = "C:\fake\config.json"
    $script:DefaultConfigFile = "C:\fake\default-config.json"

    # Source the common.ps1 functions (Initialize-HookConfig, Test-ShouldNotify)
    # We need the functions but not the side effects, so we define them manually
    # by extracting just the function definitions.
    function Initialize-HookConfig {
        return Get-NotifierConfig -ConfigPath $script:ConfigFile -DefaultConfigPath $script:DefaultConfigFile
    }

    # Source pattern arrays and detection functions from hook scripts
    # post_cascade_response.ps1 patterns
    $script:ErrorPatterns = @(
        "Error:", "error occurred", "error encountered",
        "build failed", "command failed", "task failed",
        "compilation failed", "install failed", "deploy failed",
        "unhandled exception", "threw an exception",
        "Cannot find ", "Could not find ", "Could not connect", "Could not resolve",
        "fatal error", "stack trace", "Traceback "
    )
    $script:ApprovalPatterns = @(
        "waiting for approval", "waiting for your approval",
        "requires approval", "needs your approval",
        "approve this", "approve the ",
        "Do you want to proceed", "Would you like to continue",
        "Would you like me to", "Should I proceed",
        "Please confirm", "need your permission", "requires your permission"
    )

    function Test-TaskError {
        param([string]$Response)
        foreach ($pattern in $script:ErrorPatterns) {
            if ($Response -like "*$pattern*") { return $true }
        }
        return $false
    }

    function Test-ApprovalWaiting {
        param([string]$Response)
        foreach ($pattern in $script:ApprovalPatterns) {
            if ($Response -like "*$pattern*") { return $true }
        }
        return $false
    }

    # post_run_command.ps1 patterns
    $script:TerminalInputRegexes = @(
        '\bscp\b', '\bsftp\b', '\bssh-copy-id\b',
        '\bnpm\s+login\b', '\bnpm\s+adduser\b',
        '\baz\s+login\b', '\bgcloud\s+auth\s+login\b',
        '\baws\s+configure\b', '\bkinit\b', '\bpasswd\b', '\bRead-Host\b'
    )

    function Test-GitRemoteCommand {
        param([string]$CommandLine)
        if ($CommandLine -match 'git\s+(push|pull|fetch|clone)\b') { return $true }
        return $false
    }

    function Test-TerminalBlocking {
        param([string]$CommandLine, [hashtable]$Config)
        if (Test-GitRemoteCommand -CommandLine $CommandLine) {
            if (-not $Config.git_commands) { return $false }
            return $true
        }
        if ($CommandLine -match '^\s*sudo\s' -or
            $CommandLine -match '\bssh\b' -or
            $CommandLine -match '\bdocker\s+login\b' -or
            $CommandLine -match '\brunas\b') {
            return $true
        }
        foreach ($regex in $script:TerminalInputRegexes) {
            if ($CommandLine -match $regex) { return $true }
        }
        return $false
    }
}

# ---- post_cascade_response.ps1 pattern tests ----

Describe "Test-TaskError" {

    It "detects 'Error:' in response" {
        Test-TaskError -Response "Error: something went wrong" | Should -BeTrue
    }

    It "detects 'error occurred' in response" {
        Test-TaskError -Response "An error occurred during compilation" | Should -BeTrue
    }

    It "detects 'build failed' in response" {
        Test-TaskError -Response "The build failed with 3 errors" | Should -BeTrue
    }

    It "detects 'Cannot find' in response" {
        Test-TaskError -Response "Cannot find module 'express'" | Should -BeTrue
    }

    It "detects 'Could not connect' in response" {
        Test-TaskError -Response "Could not connect to server" | Should -BeTrue
    }

    It "detects 'threw an exception' in response" {
        Test-TaskError -Response "The method threw an exception" | Should -BeTrue
    }

    It "detects 'fatal error' in response" {
        Test-TaskError -Response "fatal error: out of memory" | Should -BeTrue
    }

    It "detects 'stack trace' in response" {
        Test-TaskError -Response "Here is the stack trace:" | Should -BeTrue
    }

    It "detects 'Traceback' in response" {
        Test-TaskError -Response "Traceback (most recent call last):" | Should -BeTrue
    }

    It "returns false for casual mention of 'error' (no false positive)" {
        Test-TaskError -Response "I fixed the error in your code" | Should -BeFalse
    }

    It "returns false for casual mention of 'failed' (no false positive)" {
        Test-TaskError -Response "The test that previously failed now passes" | Should -BeFalse
    }

    It "returns false for normal response text" {
        Test-TaskError -Response "Successfully compiled 42 files" | Should -BeFalse
    }

    It "returns false for empty string" {
        Test-TaskError -Response "" | Should -BeFalse
    }
}

Describe "Test-ApprovalWaiting" {

    It "detects 'waiting for approval'" {
        Test-ApprovalWaiting -Response "I am waiting for approval to proceed" | Should -BeTrue
    }

    It "detects 'Do you want to proceed'" {
        Test-ApprovalWaiting -Response "Do you want to proceed with the changes?" | Should -BeTrue
    }

    It "detects 'Please confirm'" {
        Test-ApprovalWaiting -Response "Please confirm the deletion" | Should -BeTrue
    }

    It "detects 'needs your approval'" {
        Test-ApprovalWaiting -Response "This action needs your approval" | Should -BeTrue
    }

    It "detects 'Would you like me to'" {
        Test-ApprovalWaiting -Response "Would you like me to apply these changes?" | Should -BeTrue
    }

    It "detects 'Should I proceed'" {
        Test-ApprovalWaiting -Response "Should I proceed with the refactor?" | Should -BeTrue
    }

    It "returns false for casual mention of 'confirm' (no false positive)" {
        Test-ApprovalWaiting -Response "I can confirm the fix works" | Should -BeFalse
    }

    It "returns false for casual mention of 'permission' (no false positive)" {
        Test-ApprovalWaiting -Response "I updated the file permission bits" | Should -BeFalse
    }

    It "returns false for normal completion text" {
        Test-ApprovalWaiting -Response "Task completed successfully" | Should -BeFalse
    }

    It "returns false for empty string" {
        Test-ApprovalWaiting -Response "" | Should -BeFalse
    }
}

# ---- post_run_command.ps1 pattern tests ----

Describe "Test-GitRemoteCommand" {

    It "detects 'git push'" {
        Test-GitRemoteCommand -CommandLine "git push origin main" | Should -BeTrue
    }

    It "detects 'git pull'" {
        Test-GitRemoteCommand -CommandLine "git pull --rebase" | Should -BeTrue
    }

    It "detects 'git fetch'" {
        Test-GitRemoteCommand -CommandLine "git fetch --all" | Should -BeTrue
    }

    It "detects 'git clone'" {
        Test-GitRemoteCommand -CommandLine "git clone https://github.com/user/repo.git" | Should -BeTrue
    }

    It "returns false for local git commands" {
        Test-GitRemoteCommand -CommandLine "git status" | Should -BeFalse
        Test-GitRemoteCommand -CommandLine "git commit -m 'test'" | Should -BeFalse
        Test-GitRemoteCommand -CommandLine "git log --oneline" | Should -BeFalse
        Test-GitRemoteCommand -CommandLine "git diff" | Should -BeFalse
    }

    It "returns false for non-git commands" {
        Test-GitRemoteCommand -CommandLine "npm install" | Should -BeFalse
    }

    It "returns false for empty string" {
        Test-GitRemoteCommand -CommandLine "" | Should -BeFalse
    }
}

Describe "Test-TerminalBlocking" {

    BeforeAll {
        $script:configGitOn  = @{ git_commands = $true }
        $script:configGitOff = @{ git_commands = $false }
    }

    It "detects sudo commands" {
        Test-TerminalBlocking -CommandLine "sudo apt install foo" -Config $script:configGitOff | Should -BeTrue
    }

    It "detects ssh commands" {
        Test-TerminalBlocking -CommandLine "ssh user@host" -Config $script:configGitOff | Should -BeTrue
    }

    It "detects docker login" {
        Test-TerminalBlocking -CommandLine "docker login registry.example.com" -Config $script:configGitOff | Should -BeTrue
    }

    It "detects runas" {
        Test-TerminalBlocking -CommandLine "runas /user:admin cmd" -Config $script:configGitOff | Should -BeTrue
    }

    It "detects scp commands" {
        Test-TerminalBlocking -CommandLine "scp file.txt user@host:/tmp/" -Config $script:configGitOff | Should -BeTrue
    }

    It "detects npm login" {
        Test-TerminalBlocking -CommandLine "npm login --registry https://registry.example.com" -Config $script:configGitOff | Should -BeTrue
    }

    It "detects passwd command" {
        Test-TerminalBlocking -CommandLine "passwd" -Config $script:configGitOff | Should -BeTrue
    }

    It "allows git push when git_commands is enabled" {
        Test-TerminalBlocking -CommandLine "git push origin main" -Config $script:configGitOn | Should -BeTrue
    }

    It "suppresses git push when git_commands is disabled" {
        Test-TerminalBlocking -CommandLine "git push origin main" -Config $script:configGitOff | Should -BeFalse
    }

    It "returns false for benign commands" {
        Test-TerminalBlocking -CommandLine "ls -la" -Config $script:configGitOff | Should -BeFalse
        Test-TerminalBlocking -CommandLine "npm test" -Config $script:configGitOff | Should -BeFalse
        Test-TerminalBlocking -CommandLine "clear" -Config $script:configGitOff | Should -BeFalse
    }

    It "returns false for dotnet build (no false positives)" {
        Test-TerminalBlocking -CommandLine "dotnet build" -Config $script:configGitOff | Should -BeFalse
    }
}

# ---- Test-ShouldNotify decision logic ----

Describe "Test-ShouldNotify" {

    BeforeEach {
        $script:tempDir = New-TempTestDir
        $script:DebounceDir = Join-Path $script:tempDir "debounce"
        $script:LogFile = Join-Path $script:tempDir "notifications.log"
    }

    AfterEach {
        Remove-TempTestDir $script:tempDir
    }

    BeforeAll {
        function Test-ShouldNotify {
            param(
                [Parameter(Mandatory)][string]$EventType,
                [Parameter(Mandatory)][hashtable]$Config
            )
            if (-not $Config.enabled) { return $false }
            $eventKey = $EventType -replace '-', '_'
            if ($Config.ContainsKey($eventKey) -and -not $Config[$eventKey]) { return $false }
            if (-not (Test-Debounce -EventType $EventType -DebounceSeconds $Config.debounce_seconds -DebounceDir $script:DebounceDir)) {
                Write-NotifierLog -EventType $EventType -Status "SUPPRESSED" -Message "debounced" -LogFile $script:LogFile
                return $false
            }
            return $true
        }
    }

    It "returns false when master switch is disabled" {
        $config = @{ enabled = $false; task_complete = $true; debounce_seconds = 0 }

        Test-ShouldNotify -EventType "task-complete" -Config $config | Should -BeFalse
    }

    It "returns false when per-event toggle is disabled" {
        $config = @{ enabled = $true; task_complete = $false; debounce_seconds = 0 }

        Test-ShouldNotify -EventType "task-complete" -Config $config | Should -BeFalse
    }

    It "returns true when all conditions pass" {
        $config = @{ enabled = $true; task_complete = $true; debounce_seconds = 0 }

        Test-ShouldNotify -EventType "task-complete" -Config $config | Should -BeTrue
    }

    It "returns false when within debounce window" {
        $config = @{ enabled = $true; task_complete = $true; debounce_seconds = 300 }

        # Seed a recent debounce timestamp
        New-Item -ItemType Directory -Path $script:DebounceDir -Force | Out-Null
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        Set-Content -Path (Join-Path $script:DebounceDir "task-complete") -Value $now -NoNewline

        Test-ShouldNotify -EventType "task-complete" -Config $config | Should -BeFalse
    }

    It "handles hyphenated event types mapping to underscore config keys" {
        $config = @{ enabled = $true; approval_required = $false; debounce_seconds = 0 }

        Test-ShouldNotify -EventType "approval-required" -Config $config | Should -BeFalse
    }

    It "allows notification when event key is not in config (unknown event)" {
        $config = @{ enabled = $true; debounce_seconds = 0 }

        Test-ShouldNotify -EventType "custom-event" -Config $config | Should -BeTrue
    }
}
