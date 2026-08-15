<#
    1132.WTF desktop app for Windows.

    A WinForms front end over 1132WTF_ENGINE.ps1. Every button runs an engine
    verb in a child process and tails the engine log into the output pane, so
    elevated actions stream their progress here too.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()

$AppName    = '1132.WTF'
$AppVersion = '1.0.0'
$Root       = Split-Path -Parent $PSCommandPath
$Engine     = Join-Path $Root '1132WTF_ENGINE.ps1'
$IconPath   = Join-Path $Root 'assets\1132.WTF.ico'
$LogDir     = Join-Path (Join-Path $env:ProgramData '1132.WTF') 'logs'

if (-not (Test-Path -LiteralPath $Engine)) {
    [void][System.Windows.Forms.MessageBox]::Show(
        "1132WTF_ENGINE.ps1 is missing from:`n$Root`n`nKeep the package files together.",
        $AppName, 'OK', 'Error')
    exit 1
}

# ------------------------------------------------------------------ palette

$Palette = @{
    Bg      = [System.Drawing.ColorTranslator]::FromHtml('#0B0E14')
    Panel   = [System.Drawing.ColorTranslator]::FromHtml('#141A26')
    Ink     = [System.Drawing.ColorTranslator]::FromHtml('#F5F7FA')
    Muted   = [System.Drawing.ColorTranslator]::FromHtml('#8A94A6')
    Accent  = [System.Drawing.ColorTranslator]::FromHtml('#00E5FF')
    Accent2 = [System.Drawing.ColorTranslator]::FromHtml('#FF2E88')
    Ok      = [System.Drawing.ColorTranslator]::FromHtml('#22C55E')
    Warn    = [System.Drawing.ColorTranslator]::FromHtml('#FFB020')
}

$FontUi    = [System.Drawing.Font]::new('Segoe UI', 9.5)
$FontTitle = [System.Drawing.Font]::new('Segoe UI', 20, [System.Drawing.FontStyle]::Bold)
$FontSub   = [System.Drawing.Font]::new('Segoe UI', 8.5)
$FontBtn   = [System.Drawing.Font]::new('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$FontMono  = [System.Drawing.Font]::new('Consolas', 8.75)

# --------------------------------------------------------------------- form

$form = [System.Windows.Forms.Form]::new()
$form.Text = "$AppName - Zoom error 1132 fixer"
$form.Size = [System.Drawing.Size]::new(620, 700)
$form.MinimumSize = [System.Drawing.Size]::new(560, 600)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $Palette.Bg
$form.ForeColor = $Palette.Ink
$form.Font = $FontUi
if (Test-Path -LiteralPath $IconPath) {
    try { $form.Icon = [System.Drawing.Icon]::new($IconPath) } catch {}
}

# Controls are added to the form in one ordered pass further down, because
# Top-docked controls stack in reverse order of addition.
$header = [System.Windows.Forms.Panel]::new()
$header.Dock = 'Top'
$header.Height = 92
$header.BackColor = $Palette.Panel

$logo = [System.Windows.Forms.PictureBox]::new()
$logo.Size = [System.Drawing.Size]::new(60, 60)
$logo.Location = [System.Drawing.Point]::new(18, 16)
$logo.SizeMode = 'Zoom'
if (Test-Path -LiteralPath $IconPath) {
    try { $logo.Image = [System.Drawing.Icon]::new($IconPath, 256, 256).ToBitmap() } catch {}
}
$header.Controls.Add($logo)

$title = [System.Windows.Forms.Label]::new()
$title.Text = $AppName
$title.Font = $FontTitle
$title.ForeColor = $Palette.Accent
$title.AutoSize = $true
$title.Location = [System.Drawing.Point]::new(90, 18)
$header.Controls.Add($title)

$subtitle = [System.Windows.Forms.Label]::new()
$subtitle.Text = "STEP 1  then  STEP 2  then  LAUNCH     v$AppVersion"
$subtitle.Font = $FontSub
$subtitle.ForeColor = $Palette.Accent2
$subtitle.AutoSize = $true
$subtitle.Location = [System.Drawing.Point]::new(93, 58)
$header.Controls.Add($subtitle)

$statusLabel = [System.Windows.Forms.Label]::new()
$statusLabel.Dock = 'Top'
$statusLabel.Height = 30
$statusLabel.TextAlign = 'MiddleLeft'
$statusLabel.Padding = [System.Windows.Forms.Padding]::new(20, 0, 0, 0)
$statusLabel.ForeColor = $Palette.Muted
$statusLabel.Text = 'Checking this PC...'

# ------------------------------------------------------------------ buttons

function New-ActionButton {
    param(
        [string]$Text,
        [string]$Detail,
        [System.Drawing.Color]$Accent,
        [scriptblock]$OnClick
    )
    $panel = [System.Windows.Forms.Panel]::new()
    $panel.Dock = 'Top'
    $panel.Height = 62
    $panel.Padding = [System.Windows.Forms.Padding]::new(20, 6, 20, 6)

    $button = [System.Windows.Forms.Button]::new()
    $button.Dock = 'Fill'
    $button.Text = "$Text`n$Detail"
    $button.Font = $FontBtn
    $button.TextAlign = 'MiddleLeft'
    $button.Padding = [System.Windows.Forms.Padding]::new(14, 0, 0, 0)
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 1
    $button.FlatAppearance.BorderColor = $Accent
    $button.FlatAppearance.MouseOverBackColor = $Palette.Panel
    $button.BackColor = $Palette.Bg
    $button.ForeColor = $Accent
    $button.Cursor = 'Hand'
    $button.Add_Click($OnClick)
    $panel.Controls.Add($button)
    return @{ Panel = $panel; Button = $button }
}

# --------------------------------------------------------------- output pane

$outputBox = [System.Windows.Forms.TextBox]::new()
$outputBox.Multiline = $true
$outputBox.ReadOnly = $true
$outputBox.ScrollBars = 'Vertical'
$outputBox.Font = $FontMono
$outputBox.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#06080D')
$outputBox.ForeColor = $Palette.Muted
$outputBox.BorderStyle = 'FixedSingle'
$outputBox.WordWrap = $false

$outputHost = [System.Windows.Forms.Panel]::new()
$outputHost.Dock = 'Fill'
$outputHost.Padding = [System.Windows.Forms.Padding]::new(20, 6, 20, 14)
$outputHost.Controls.Add($outputBox)
$outputBox.Dock = 'Fill'

function Add-LogLine {
    param([string]$Text)
    $outputBox.AppendText($Text + "`r`n")
}

# ----------------------------------------------------------- engine plumbing

$script:Tail = @{
    Process  = $null
    LogFile  = $null
    Offset   = 0
    Action   = $null
    Previous = $null
}

$timer = [System.Windows.Forms.Timer]::new()
$timer.Interval = 300

function Get-NewestEngineLog {
    if (-not (Test-Path -LiteralPath $LogDir)) { return $null }
    $newest = Get-ChildItem -LiteralPath $LogDir -Filter 'engine_*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($newest) { return $newest.FullName }
    return $null
}

function Set-Busy {
    param([bool]$Busy)
    foreach ($entry in $script:Buttons) { $entry.Button.Enabled = -not $Busy }
    $form.Cursor = if ($Busy) { 'WaitCursor' } else { 'Default' }
}

function Start-EngineAction {
    param([string]$EngineAction, [string]$Header, [string[]]$Extra = @())

    if ($script:Tail.Process -and -not $script:Tail.Process.HasExited) {
        Add-LogLine '[busy] An action is still running.'
        return
    }

    $outputBox.Clear()
    Add-LogLine "=== $Header ==="
    Set-Busy -Busy $true

    # Remember which log existed before, so the tail latches onto the new one.
    $before = Get-NewestEngineLog
    $script:Tail.LogFile = $null
    $script:Tail.Offset = 0
    $script:Tail.Action = $EngineAction
    $script:Tail.Previous = $before

    $argList = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', ('"{0}"' -f $Engine)
        '-Action', $EngineAction
    ) + $Extra

    try {
        $script:Tail.Process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList `
            -WindowStyle Hidden -PassThru -ErrorAction Stop
        $timer.Start()
    }
    catch {
        Set-Busy -Busy $false
        Add-LogLine "[fatal] Could not start the engine: $($_.Exception.Message)"
    }
}

$timer.Add_Tick({
    # Latch onto the engine's log file once it appears.
    if (-not $script:Tail.LogFile) {
        $newest = Get-NewestEngineLog
        if ($newest -and $newest -ne $script:Tail.Previous) {
            $script:Tail.LogFile = $newest
            $script:Tail.Offset = 0
        }
    }

    if ($script:Tail.LogFile -and (Test-Path -LiteralPath $script:Tail.LogFile)) {
        try {
            $stream = [System.IO.FileStream]::new(
                $script:Tail.LogFile, [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                if ($stream.Length -gt $script:Tail.Offset) {
                    [void]$stream.Seek($script:Tail.Offset, [System.IO.SeekOrigin]::Begin)
                    $reader = [System.IO.StreamReader]::new($stream)
                    $chunk = $reader.ReadToEnd()
                    $script:Tail.Offset = $stream.Length
                    foreach ($line in ($chunk -split "`r?`n")) {
                        if ($line.Trim()) { Add-LogLine $line }
                    }
                }
            }
            finally { $stream.Dispose() }
        }
        catch {}
    }

    if ($script:Tail.Process -and $script:Tail.Process.HasExited) {
        $timer.Stop()
        $code = $script:Tail.Process.ExitCode
        if ($code -eq 0) {
            Add-LogLine ''
            Add-LogLine '[done] Finished cleanly.'
        }
        else {
            Add-LogLine ''
            Add-LogLine "[failed] Engine exit code $code. Full log: $LogDir"
        }
        $script:Tail.Process = $null
        Set-Busy -Busy $false
        Update-StatusLine
    }
})

# --------------------------------------------------------------- status line

function Update-StatusLine {
    $parts = [System.Collections.Generic.List[string]]::new()

    $zoomFound = $false
    foreach ($candidate in @(
        (Join-Path $env:APPDATA 'Zoom\bin\Zoom.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Zoom\bin\Zoom.exe'),
        (Join-Path $env:ProgramFiles 'Zoom\bin\Zoom.exe')
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { $zoomFound = $true; break }
    }
    if (-not $zoomFound) {
        try {
            $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Zoom.exe'
            if ((Get-ItemProperty -Path $key -ErrorAction Stop).'(default)') { $zoomFound = $true }
        }
        catch {}
    }

    if ($zoomFound) {
        [void]$parts.Add('Zoom: installed')
        $statusLabel.ForeColor = $Palette.Ok
    }
    else {
        [void]$parts.Add('Zoom: not found (browser bypass still works)')
        $statusLabel.ForeColor = $Palette.Warn
    }

    $running = @(Get-Process -Name 'Zoom' -ErrorAction SilentlyContinue)
    [void]$parts.Add("running: $([bool]$running)")

    $slotFile = Join-Path (Join-Path $env:ProgramData '1132.WTF') 'slot.txt'
    if (Test-Path -LiteralPath $slotFile) {
        $slot = (Get-Content -LiteralPath $slotFile -Raw -ErrorAction SilentlyContinue)
        if ($slot) { [void]$parts.Add("next deep-fix slot: $($slot.Trim())") }
    }

    $statusLabel.Text = '   ' + ($parts -join '     |     ')
}

# ------------------------------------------------------------- compose panels

$script:Buttons = @()

$fix = New-ActionButton -Text 'STEP 1 - Fix Zoom' -Detail 'Wipe the old name and rooms, then open Zoom empty' `
    -Accent $Palette.Accent -OnClick {
        Start-EngineAction -EngineAction 'fix' -Header 'STEP 1 - Fix Zoom'
    }

$deep = New-ActionButton -Text 'STEP 2 - Deep fix' -Detail 'Only if STEP 1 still fails. Asks for admin.' `
    -Accent $Palette.Accent2 -OnClick {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "STEP 1 - Click Yes. Allow admin when Windows asks.`n`n" +
            "STEP 2 - Wait. A temporary Windows user is created.`n`n" +
            "LAUNCH - Zoom opens as that user. Join. Do not sign in as the old account.",
            $AppName, 'YesNo', 'Question')
        if ($answer -eq 'Yes') {
            Start-EngineAction -EngineAction 'deep-fix' -Header 'STEP 2 - Deep fix'
        }
    }

$browser = New-ActionButton -Text 'STEP 3 - Join in browser' -Detail 'Only if STEP 1 and STEP 2 still fail' `
    -Accent $Palette.Ok -OnClick {
        $url = [Microsoft.VisualBasic.Interaction]::InputBox(
            "STEP 1 - Paste the meeting link`r`nSTEP 2 - Or leave blank`r`nLAUNCH", $AppName, '')
        $extra = @()
        if ($url) { $extra = @('-Url', ('"{0}"' -f $url)) }
        Start-EngineAction -EngineAction 'browser' -Header 'STEP 3 - Join in browser' -Extra $extra
    }

$script:Buttons = @($fix, $deep, $browser)

# Secondary row.
$secondary = [System.Windows.Forms.Panel]::new()
$secondary.Dock = 'Top'
$secondary.Height = 46
$secondary.Padding = [System.Windows.Forms.Padding]::new(20, 6, 20, 6)

$secondaryLayout = [System.Windows.Forms.TableLayoutPanel]::new()
$secondaryLayout.Dock = 'Fill'
$secondaryLayout.ColumnCount = 4
$secondaryLayout.RowCount = 1
foreach ($i in 1..4) {
    [void]$secondaryLayout.ColumnStyles.Add(
        [System.Windows.Forms.ColumnStyle]::new('Percent', 25))
}
$secondary.Controls.Add($secondaryLayout)

function New-SmallButton {
    param([string]$Text, [scriptblock]$OnClick)
    $b = [System.Windows.Forms.Button]::new()
    $b.Text = $Text
    $b.Dock = 'Fill'
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = $Palette.Muted
    $b.BackColor = $Palette.Bg
    $b.ForeColor = $Palette.Ink
    $b.Cursor = 'Hand'
    $b.Margin = [System.Windows.Forms.Padding]::new(3, 0, 3, 0)
    $b.Add_Click($OnClick)
    return $b
}

$statusButton = New-SmallButton -Text 'Status' -OnClick {
    Start-EngineAction -EngineAction 'status' -Header 'Status report'
}
$restoreButton = New-SmallButton -Text 'Undo last fix' -OnClick {
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Put back the Zoom identity saved by the most recent fix?", $AppName, 'YesNo', 'Question')
    if ($answer -eq 'Yes') {
        Start-EngineAction -EngineAction 'restore' -Header 'Restore previous Zoom identity'
    }
}
$autostartButton = New-SmallButton -Text 'Autostart on' -OnClick {
    Start-EngineAction -EngineAction 'autostart-on' -Header 'Install logon autostart'
}
$logsButton = New-SmallButton -Text 'Open logs' -OnClick {
    if (Test-Path -LiteralPath $LogDir) { Start-Process explorer.exe $LogDir | Out-Null }
    else { Add-LogLine "[info] No logs yet: $LogDir" }
}

$secondaryLayout.Controls.Add($statusButton, 0, 0)
$secondaryLayout.Controls.Add($restoreButton, 1, 0)
$secondaryLayout.Controls.Add($autostartButton, 2, 0)
$secondaryLayout.Controls.Add($logsButton, 3, 0)

$script:Buttons += @(
    @{ Button = $statusButton }, @{ Button = $restoreButton },
    @{ Button = $autostartButton }, @{ Button = $logsButton }
)

$outputCaption = [System.Windows.Forms.Label]::new()
$outputCaption.Dock = 'Top'
$outputCaption.Height = 24
$outputCaption.Text = '   Engine output'
$outputCaption.TextAlign = 'MiddleLeft'
$outputCaption.ForeColor = $Palette.Muted
$outputCaption.Padding = [System.Windows.Forms.Padding]::new(17, 0, 0, 0)

# Dock order is bottom-up for Top-docked controls, so add in reverse.
$form.Controls.Add($outputHost)
$form.Controls.Add($outputCaption)
$form.Controls.Add($secondary)
$form.Controls.Add($browser.Panel)
$form.Controls.Add($deep.Panel)
$form.Controls.Add($fix.Panel)
$form.Controls.Add($statusLabel)
$form.Controls.Add($header)

$form.Add_Shown({
    Update-StatusLine
    Add-LogLine "$AppName v$AppVersion ready."
    Add-LogLine 'STEP 1 - click Fix Zoom'
    Add-LogLine 'STEP 2 - if that fails, click Deep fix'
    Add-LogLine 'LAUNCH - or Join in browser'
    Add-LogLine ''
})

$form.Add_FormClosing({
    $timer.Stop()
})

[void]$form.ShowDialog()
