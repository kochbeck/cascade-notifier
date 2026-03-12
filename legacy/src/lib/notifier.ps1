# notifier.ps1 - Sound playback and Windows toast notification delivery

function Send-Sound {
    <#
    .SYNOPSIS
        Plays a .wav file for the given event type. Falls back to system sounds if WAV is missing.
    .PARAMETER EventType
        One of: task-complete, task-error, approval-required, terminal-input
    .PARAMETER SoundsDir
        Path to the directory containing .wav files
    .PARAMETER Enabled
        Whether sound is enabled
    #>
    param(
        [Parameter(Mandatory)][string]$EventType,
        [Parameter(Mandatory)][string]$SoundsDir,
        [bool]$Enabled = $true
    )

    if (-not $Enabled) { return }

    $wavFile = Join-Path $SoundsDir "$EventType.wav"

    if (Test-Path $wavFile) {
        try {
            $player = New-Object System.Media.SoundPlayer $wavFile
            $player.PlaySync()
            return
        }
        catch {
            # Fall through to system sound
        }
    }

    # Fallback to system sounds
    switch ($EventType) {
        "task-error"         { [System.Media.SystemSounds]::Hand.Play() }
        "approval-required"  { [System.Media.SystemSounds]::Exclamation.Play() }
        "terminal-input"     { [System.Media.SystemSounds]::Asterisk.Play() }
        default              { [System.Media.SystemSounds]::Exclamation.Play() }
    }
}

function Send-Toast {
    <#
    .SYNOPSIS
        Shows a Windows 10/11 toast notification.
    .PARAMETER Title
        Notification title
    .PARAMETER Body
        Notification body text
    .PARAMETER Enabled
        Whether toast notifications are enabled
    #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Body,
        [bool]$Enabled = $true
    )

    if (-not $Enabled) { return $true }

    # Try WinRT toast (Windows 10+)
    $sent = Send-ToastWinRT -Title $Title -Body $Body
    if ($sent) { return $true }

    # Fallback: BalloonTip via NotifyIcon
    $sent = Send-BalloonTip -Title $Title -Body $Body
    return $sent
}

function Send-ToastWinRT {
    <#
    .SYNOPSIS
        Sends a toast notification using WinRT APIs (Windows 10/11).
    #>
    param(
        [string]$Title,
        [string]$Body
    )

    try {
        # Load WinRT assemblies
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]

        # Use PowerShell as the AppId since Windsurf may not have a registered AUMID
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

        # Build toast XML
        $toastXml = @(
            '<toast>',
            '  <visual>',
            '    <binding template="ToastGeneric">',
            "      <text>$([System.Security.SecurityElement]::Escape($Title))</text>",
            "      <text>$([System.Security.SecurityElement]::Escape($Body))</text>",
            '    </binding>',
            '  </visual>',
            '</toast>'
        ) -join "`n"

        $xmlDoc = [Windows.Data.Xml.Dom.XmlDocument]::new()
        $xmlDoc.LoadXml($toastXml)

        $toast = [Windows.UI.Notifications.ToastNotification]::new($xmlDoc)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId)
        $notifier.Show($toast)
        return $true
    }
    catch {
        return $false
    }
}

function Send-BalloonTip {
    <#
    .SYNOPSIS
        Fallback notification using System.Windows.Forms NotifyIcon balloon tip.
    #>
    param(
        [string]$Title,
        [string]$Body
    )

    $notifyIcon = $null
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
        $notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
        $notifyIcon.BalloonTipTitle = $Title
        $notifyIcon.BalloonTipText = $Body
        $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $notifyIcon.Visible = $true
        $notifyIcon.ShowBalloonTip(5000)

        # Brief pause so the balloon registers with the OS before we exit
        Start-Sleep -Milliseconds 500
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $notifyIcon) {
            $notifyIcon.Visible = $false
            $notifyIcon.Dispose()
        }
    }
}

function Send-CascadeNotification {
    <#
    .SYNOPSIS
        Full notification lifecycle: send sound + toast, log result, update debounce.
    .PARAMETER EventType
        Event type identifier
    .PARAMETER Title
        Notification title
    .PARAMETER Body
        Notification body
    .PARAMETER Config
        Hashtable of user preferences
    .PARAMETER SoundsDir
        Path to sounds directory
    .PARAMETER LogFile
        Path to log file
    .PARAMETER DebounceDir
        Path to debounce directory
    #>
    param(
        [Parameter(Mandatory)][string]$EventType,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Body,
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$SoundsDir,
        [Parameter(Mandatory)][string]$LogFile,
        [Parameter(Mandatory)][string]$DebounceDir
    )

    # Play sound
    Send-Sound -EventType $EventType -SoundsDir $SoundsDir -Enabled ([bool]$Config.sound_enabled)

    # Show toast
    $toastSent = Send-Toast -Title $Title -Body $Body -Enabled ([bool]$Config.toast_enabled)

    # Log
    if ($toastSent) {
        Write-NotifierLog -EventType $EventType -Status "SENT" -Message $Title -LogFile $LogFile
    }
    else {
        Write-NotifierLog -EventType $EventType -Status "PARTIAL" -Message "$Title (sound only, toast failed)" -LogFile $LogFile
    }

    # Update debounce
    Update-Debounce -EventType $EventType -DebounceDir $DebounceDir
}
