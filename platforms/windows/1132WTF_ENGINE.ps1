<#
    1132.WTF engine for Windows
    Implements the levels described in docs/ENGINE.md.

    Usage:
      powershell -NoProfile -ExecutionPolicy Bypass -File 1132WTF_ENGINE.ps1 [-Action <verb>]

    Verbs: status | fix | deep-fix | browser | restore | autostart-on | autostart-off | logs
#>

[CmdletBinding()]
param(
    [ValidateSet('status', 'fix', 'deep-fix', 'browser', 'restore', 'autostart-on', 'autostart-off', 'logs')]
    [string]$Action = 'fix',

    [string]$Url,

    # Skip launching Zoom after a reset. Used by the test harness.
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppName      = '1132.WTF'
$script:AppVersion   = '1.0.0'
$script:TaskName     = '1132.WTF_AutoRun'
$script:StateDir     = Join-Path $env:ProgramData '1132.WTF'
$script:LogDir       = Join-Path $script:StateDir 'logs'
$script:ProfilesDir  = Join-Path $script:StateDir 'profiles'
$script:BackupDir    = Join-Path $script:StateDir 'backups'
$script:StateFile    = Join-Path $script:StateDir 'slot.txt'
$script:LastRunFile  = Join-Path $script:StateDir 'lastrun.txt'
$script:LockDir      = Join-Path $script:StateDir 'run.lock'
$script:LogFile      = Join-Path $script:LogDir ("engine_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'))

# Throwaway rotation users. The prefix is reserved so rotation can never
# delete a real account.
$script:SlotPrefix   = 'wtf1132_'
$script:SlotNames    = @('wtf1132_a', 'wtf1132_b', 'wtf1132_c')

$script:ZoomProcessNames = @('Zoom', 'Zoom_launcher', 'CptHost', 'airhost', 'zCrashReport64')

function Write-Step {
    param([string]$Level, [string]$Message)
    $line = "[{0}] {1}" -f $Level.ToUpperInvariant(), $Message
    Write-Host $line
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding utf8 } catch {}
}

function Ensure-Dirs {
    foreach ($dir in @($script:StateDir, $script:LogDir, $script:ProfilesDir, $script:BackupDir)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Elevated {
    param([string]$ForAction)
    if (Test-IsAdmin) { return $true }
    $self = $PSCommandPath
    if (-not $self) { throw 'Could not determine script path for elevation.' }
    Write-Step INFO ("'{0}' needs Administrator rights. Relaunching..." -f $ForAction)
    $argList = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', ('"{0}"' -f $self)
        '-Action', $ForAction
    ) -join ' '
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList | Out-Null
    }
    catch {
        throw 'Administrator rights were refused, so this action cannot run.'
    }
    return $false
}

function Show-Dialog {
    param([string]$Message, [ValidateSet('Info', 'Error')][string]$Kind = 'Info')
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $icon = if ($Kind -eq 'Error') {
            [System.Windows.Forms.MessageBoxIcon]::Error
        } else {
            [System.Windows.Forms.MessageBoxIcon]::Information
        }
        [void][System.Windows.Forms.MessageBox]::Show(
            $Message, $script:AppName, [System.Windows.Forms.MessageBoxButtons]::OK, $icon)
    }
    catch {}
}

# ---------------------------------------------------------------- single run

function Enter-Lock {
    try {
        New-Item -ItemType Directory -Path $script:LockDir -ErrorAction Stop | Out-Null
        Set-Content -LiteralPath (Join-Path $script:LockDir 'pid') -Value $PID -Encoding ascii -Force
        return $true
    }
    catch {
        $pidFile = Join-Path $script:LockDir 'pid'
        if (Test-Path -LiteralPath $pidFile) {
            $existing = (Get-Content -LiteralPath $pidFile -Raw -ErrorAction SilentlyContinue).Trim()
            if ($existing -and (Get-Process -Id ([int]$existing) -ErrorAction SilentlyContinue)) {
                Write-Step INFO ("Another {0} run is already active (PID {1})." -f $script:AppName, $existing)
                return $false
            }
        }
        Write-Step WARN 'Clearing a stale lock from a previous run.'
        Remove-Item -LiteralPath $script:LockDir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $script:LockDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:LockDir 'pid') -Value $PID -Encoding ascii -Force
        return $true
    }
}

function Exit-Lock {
    Remove-Item -LiteralPath $script:LockDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --------------------------------------------------------------- zoom lookup

function Get-ZoomExePath {
    $candidates = [System.Collections.Generic.List[string]]::new()

    foreach ($key in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Zoom.exe',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\Zoom.exe'
    )) {
        try {
            $value = (Get-ItemProperty -Path $key -ErrorAction Stop).'(default)'
            if ($value) { [void]$candidates.Add($value.Trim('"')) }
        }
        catch {}
    }

    foreach ($base in @($env:APPDATA, $env:LOCALAPPDATA)) {
        if ($base) {
            [void]$candidates.Add((Join-Path $base 'Zoom\bin\Zoom.exe'))
            [void]$candidates.Add((Join-Path $base 'Programs\Zoom\bin\Zoom.exe'))
        }
    }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($base) { [void]$candidates.Add((Join-Path $base 'Zoom\bin\Zoom.exe')) }
    }
    foreach ($userDir in (Get-ChildItem (Join-Path $env:SystemDrive 'Users') -Directory -Force -ErrorAction SilentlyContinue)) {
        foreach ($relative in @(
            'AppData\Roaming\Zoom\bin\Zoom.exe',
            'AppData\Local\Programs\Zoom\bin\Zoom.exe'
        )) {
            [void]$candidates.Add((Join-Path $userDir.FullName $relative))
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    return $null
}

function Stop-Zoom {
    $stopped = 0
    foreach ($name in $script:ZoomProcessNames) {
        foreach ($proc in (Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            try {
                $proc | Stop-Process -Force -ErrorAction Stop
                $stopped++
            }
            catch {
                Write-Step WARN ("Could not stop {0} (PID {1}): {2}" -f $name, $proc.Id, $_.Exception.Message)
            }
        }
    }
    if ($stopped -gt 0) {
        Write-Step OK ("Stopped {0} Zoom process(es)." -f $stopped)
        Start-Sleep -Milliseconds 900
    }
    else {
        Write-Step INFO 'Zoom was not running.'
    }
}

# ------------------------------------------------------- level 1: local reset

function Get-IdentityTargets {
    # Each target carries an explicit label, because %APPDATA%\Zoom\data and
    # %LOCALAPPDATA%\Zoom\data would otherwise collide inside one backup.
    $targets = [System.Collections.Generic.List[object]]::new()
    if ($env:APPDATA) {
        [void]$targets.Add([pscustomobject]@{ Label = 'roaming_data'; Path = (Join-Path $env:APPDATA 'Zoom\data') })
        [void]$targets.Add([pscustomobject]@{ Label = 'roaming_logs'; Path = (Join-Path $env:APPDATA 'Zoom\logs') })
    }
    if ($env:LOCALAPPDATA) {
        [void]$targets.Add([pscustomobject]@{ Label = 'local_data'; Path = (Join-Path $env:LOCALAPPDATA 'Zoom\data') })
    }
    return $targets
}

function Move-Away {
    param([string]$Source, [string]$Destination)
    try {
        Move-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
    }
    catch {
        # Falls here when the backup lands on a different volume.
        Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force -ErrorAction Stop
        Remove-Item -LiteralPath $Source -Recurse -Force -ErrorAction Stop
    }
}

function Invoke-IdentityReset {
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $backup = Join-Path $script:BackupDir $stamp
    New-Item -ItemType Directory -Path $backup -Force | Out-Null

    $manifest = @{}
    $moved = 0
    foreach ($target in (Get-IdentityTargets)) {
        if (-not (Test-Path -LiteralPath $target.Path)) { continue }
        $destination = Join-Path $backup $target.Label
        try {
            Move-Away -Source $target.Path -Destination $destination
            $manifest[$target.Label] = $target.Path
            Write-Step OK ("Reset {0}" -f $target.Path)
            $moved++
        }
        catch {
            Write-Step WARN ("Could not reset {0}: {1}" -f $target.Path, $_.Exception.Message)
        }
    }

    # Zoom keeps a client device id under HKCU. Export it, then drop it.
    if (Test-Path -LiteralPath 'HKCU:\Software\Zoom') {
        $regFile = Join-Path $backup 'HKCU_Software_Zoom.reg'
        try {
            & reg.exe export 'HKCU\Software\Zoom' $regFile /y | Out-Null
            Remove-Item -LiteralPath 'HKCU:\Software\Zoom' -Recurse -Force -ErrorAction Stop
            Write-Step OK 'Reset HKCU\Software\Zoom'
            $moved++
        }
        catch {
            Write-Step WARN ("Could not reset HKCU\Software\Zoom: {0}" -f $_.Exception.Message)
        }
    }

    if ($moved -eq 0) {
        Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
        Write-Step INFO 'Zoom identity was already clean, nothing to back up.'
    }
    else {
        $manifest.GetEnumerator() |
            ForEach-Object { '{0}={1}' -f $_.Key, $_.Value } |
            Set-Content -LiteralPath (Join-Path $backup 'manifest.txt') -Encoding utf8 -Force
        Write-Step INFO ("Backup written to {0}" -f $backup)
    }
    return $moved
}

function Invoke-Restore {
    $backups = @(Get-ChildItem -LiteralPath $script:BackupDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending)
    if ($backups.Count -eq 0) {
        Write-Step WARN 'There is no backup to restore.'
        return 1
    }
    $latest = $backups[0]
    Write-Step INFO ("Restoring backup {0}" -f $latest.Name)
    Stop-Zoom

    $manifestFile = Join-Path $latest.FullName 'manifest.txt'
    if (Test-Path -LiteralPath $manifestFile) {
        foreach ($line in (Get-Content -LiteralPath $manifestFile)) {
            $parts = $line -split '=', 2
            if ($parts.Count -ne 2) { continue }
            $source = Join-Path $latest.FullName $parts[0]
            $destination = $parts[1]
            if (-not (Test-Path -LiteralPath $source)) { continue }
            try {
                if (Test-Path -LiteralPath $destination) {
                    Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction Stop
                }
                New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
                Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force -ErrorAction Stop
                Write-Step OK ("Restored {0}" -f $destination)
            }
            catch {
                Write-Step WARN ("Could not restore {0}: {1}" -f $destination, $_.Exception.Message)
            }
        }
    }
    else {
        Write-Step WARN 'Backup has no manifest, so its folders cannot be placed automatically.'
    }

    $regFile = Join-Path $latest.FullName 'HKCU_Software_Zoom.reg'
    if (Test-Path -LiteralPath $regFile) {
        try {
            & reg.exe import $regFile | Out-Null
            Write-Step OK 'Restored HKCU\Software\Zoom'
        }
        catch {
            Write-Step WARN ("Could not import {0}: {1}" -f $regFile, $_.Exception.Message)
        }
    }
    Write-Step DONE 'Restore finished.'
    return 0
}

# ---------------------------------------------------- level 2: user rotation

function New-RandomPassword {
    # Mixed classes so the generated password always satisfies a default
    # Windows complexity policy. Never logged, never written to disk.
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower = 'abcdefghijkmnopqrstuvwxyz'
    $digit = '23456789'
    $sym   = '!@#$%^&*()-_=+'
    $all   = $upper + $lower + $digit + $sym
    $bytes = [byte[]]::new(64)
    # RNGCryptoServiceProvider rather than RandomNumberGenerator.Fill, because
    # Windows PowerShell 5.1 runs on .NET Framework where Fill does not exist.
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $chars = @(
        $upper[$bytes[0] % $upper.Length]
        $lower[$bytes[1] % $lower.Length]
        $digit[$bytes[2] % $digit.Length]
        $sym[$bytes[3] % $sym.Length]
    )
    for ($i = 4; $i -lt 24; $i++) { $chars += $all[$bytes[$i] % $all.Length] }
    $shuffled = $chars | Sort-Object { Get-Random }
    return ConvertTo-SecureString -String ($shuffled -join '') -AsPlainText -Force
}

function Get-SlotToRemove {
    param([int]$SlotAboutToRun)
    switch ($SlotAboutToRun) {
        1 { return 2 }
        2 { return 3 }
        3 { return 1 }
        default { throw "Invalid slot $SlotAboutToRun" }
    }
}

function Remove-SlotUser {
    param([Parameter(Mandatory)][string]$UserName)

    if (-not $UserName.StartsWith($script:SlotPrefix)) {
        throw "Refusing to delete '$UserName': not a 1132.WTF rotation account."
    }

    if (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue) {
        try {
            Remove-LocalUser -Name $UserName -ErrorAction Stop
            Write-Step OK ("Removed throwaway user {0}" -f $UserName)
        }
        catch {
            Write-Step WARN ("Could not remove user {0}: {1}" -f $UserName, $_.Exception.Message)
        }
    }

    $profilePath = Join-Path $env:SystemDrive ("Users\{0}" -f $UserName)
    try {
        # A WMI filter needs each backslash doubled.
        $escaped = $profilePath.Replace('\', '\\')
        $profile = Get-CimInstance Win32_UserProfile -Filter ("LocalPath='{0}'" -f $escaped) -ErrorAction SilentlyContinue
        if ($profile) {
            $profile | Remove-CimInstance -ErrorAction Stop
            Write-Step OK ("Removed Windows profile {0}" -f $profilePath)
        }
        elseif (Test-Path -LiteralPath $profilePath) {
            Remove-Item -LiteralPath $profilePath -Recurse -Force -ErrorAction Stop
            Write-Step OK ("Removed profile folder {0}" -f $profilePath)
        }
    }
    catch {
        Write-Step WARN ("Profile cleanup failed for {0}: {1}" -f $profilePath, $_.Exception.Message)
    }

    $slotProfile = Join-Path $script:ProfilesDir $UserName
    if (Test-Path -LiteralPath $slotProfile) {
        Remove-Item -LiteralPath $slotProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-SlotUser {
    param(
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][securestring]$Password
    )

    $description = '1132.WTF throwaway account - safe to delete'
    $existing = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if ($existing) {
        $existing | Set-LocalUser -Password $Password -Description $description
        Write-Step OK ("Reused throwaway user {0}" -f $UserName)
    }
    else {
        New-LocalUser -Name $UserName -Password $Password -FullName '1132.WTF Guest' `
            -Description $description -PasswordNeverExpires -AccountNeverExpires -UserMayNotChangePassword |
            Out-Null
        Write-Step OK ("Created throwaway user {0}" -f $UserName)
    }

    # Deliberately a standard user: Zoom does not need administrator rights,
    # and a throwaway admin account would be a real hole.
    try {
        Add-LocalGroupMember -Group 'Users' -Member $UserName -ErrorAction Stop
    }
    catch {
        if ($_.Exception.Message -notmatch 'already a member') {
            Write-Step WARN ("Could not confirm Users group membership: {0}" -f $_.Exception.Message)
        }
    }
}

function Grant-SlotPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$UserName
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    # Use the local SAM qualifier so this also works on a domain-joined box.
    $grant = ('{0}:(OI)(CI)M' -f $UserName)
    & icacls.exe $Path /inheritance:e /grant:r $grant 'Administrators:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Step WARN ("icacls returned {0} for {1}" -f $LASTEXITCODE, $Path)
    }
}

function Get-NextSlot {
    if (-not (Test-Path -LiteralPath $script:StateFile)) {
        Set-Content -LiteralPath $script:StateFile -Value '1' -Encoding ascii -Force
        return 1
    }
    $raw = (Get-Content -LiteralPath $script:StateFile -Raw -ErrorAction SilentlyContinue)
    if ($null -ne $raw) { $raw = $raw.Trim() }
    if ($raw -match '^[123]$') { return [int]$raw }
    Write-Step WARN ("Slot file held '{0}'. Resetting to slot 1." -f $raw)
    return 1
}

function Invoke-DeepFix {
    param([string]$ZoomExe)

    $slot = Get-NextSlot
    $removeSlot = Get-SlotToRemove -SlotAboutToRun $slot
    $activeName = $script:SlotNames[$slot - 1]
    $removeName = $script:SlotNames[$removeSlot - 1]

    Write-Step INFO ("Rotation: running slot {0} ({1}), destroying slot {2} ({3})" -f
        $slot, $activeName, $removeSlot, $removeName)

    Remove-SlotUser -UserName $removeName

    $password = New-RandomPassword
    New-SlotUser -UserName $activeName -Password $password

    $profileRoot = Join-Path $script:ProfilesDir $activeName
    $profileData = Join-Path $profileRoot 'data'
    Grant-SlotPath -Path $profileRoot -UserName $activeName
    Grant-SlotPath -Path $profileData -UserName $activeName

    $workDir = [System.IO.Path]::GetDirectoryName($ZoomExe)
    if (-not $workDir -or -not (Test-Path -LiteralPath $workDir)) { $workDir = $env:SystemRoot }

    $credential = [pscredential]::new($activeName, $password)
    Write-Step ACTION ("Launching Zoom as {0}" -f $activeName)
    try {
        $proc = Start-Process -FilePath $ZoomExe -ArgumentList @("--data=$profileData") `
            -WorkingDirectory $workDir -Credential $credential -PassThru -ErrorAction Stop
        Write-Step OK ("Zoom started, PID {0}" -f $proc.Id)
    }
    catch {
        throw ("Could not start Zoom as {0}: {1}" -f $activeName, $_.Exception.Message)
    }

    $following = if ($slot -ge 3) { 1 } else { $slot + 1 }
    Set-Content -LiteralPath $script:StateFile -Value $following -Encoding ascii -Force
    Write-Step STATE ("Next deep-fix will use slot {0}" -f $following)
}

# ------------------------------------------------------ level 3: browser join

function Invoke-Browser {
    param([string]$JoinUrl)

    if (-not $JoinUrl) { $JoinUrl = 'https://zoom.us/join' }

    $browsers = @(
        @{ Exe = 'chrome.exe';  Arg = '--incognito --new-window' }
        @{ Exe = 'msedge.exe';  Arg = '--inprivate --new-window' }
        @{ Exe = 'brave.exe';   Arg = '--incognito --new-window' }
        @{ Exe = 'firefox.exe'; Arg = '-private-window' }
    )

    foreach ($browser in $browsers) {
        $path = $null
        foreach ($key in @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$($browser.Exe)",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\$($browser.Exe)"
        )) {
            try {
                $value = (Get-ItemProperty -Path $key -ErrorAction Stop).'(default)'
                if ($value) { $path = $value.Trim('"'); break }
            }
            catch {}
        }
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }

        Write-Step ACTION ("Opening a private window in {0}" -f $browser.Exe)
        $argLine = ('{0} "{1}"' -f $browser.Arg, $JoinUrl)
        Start-Process -FilePath $path -ArgumentList $argLine | Out-Null
        Write-Step OK 'Join the meeting in the private window, and pick "Join from your browser".'
        return 0
    }

    Write-Step WARN 'No supported browser found. Opening the default browser instead.'
    Start-Process $JoinUrl | Out-Null
    return 0
}

# ------------------------------------------------------------------ autostart

function Install-AutoStart {
    $engine = $PSCommandPath
    $command = ('powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "{0}" -Action fix' -f $engine)
    & schtasks.exe /Create /TN $script:TaskName /SC ONLOGON /RL LIMITED /TR $command /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "schtasks failed with code $LASTEXITCODE" }
    Write-Step OK ("Autostart task '{0}' installed for logon." -f $script:TaskName)
    return 0
}

function Remove-AutoStart {
    & schtasks.exe /Delete /TN $script:TaskName /F | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Step INFO 'No autostart task was installed.'
    }
    else {
        Write-Step OK 'Autostart task removed.'
    }
    return 0
}

# --------------------------------------------------------------------- status

function Show-Status {
    Write-Step INFO ("{0} v{1}" -f $script:AppName, $script:AppVersion)
    Write-Step INFO ("User={0} Computer={1} Admin={2}" -f $env:USERNAME, $env:COMPUTERNAME, (Test-IsAdmin))

    $zoom = Get-ZoomExePath
    if ($zoom) { Write-Step OK ("Zoom found: {0}" -f $zoom) }
    else { Write-Step WARN 'Zoom was not found. Level 1 and 2 need the Zoom client installed.' }

    $running = @($script:ZoomProcessNames | ForEach-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue })
    Write-Step INFO ("Zoom running: {0}" -f ([bool]$running))
    Write-Step INFO ("Next deep-fix slot: {0}" -f (Get-NextSlot))

    $existing = @()
    foreach ($name in $script:SlotNames) {
        if (Get-LocalUser -Name $name -ErrorAction SilentlyContinue) { $existing += $name }
    }
    $existingText = 'none'
    if ($existing.Count -gt 0) { $existingText = $existing -join ', ' }
    Write-Step INFO ("Throwaway users present: {0}" -f $existingText)

    $backups = @(Get-ChildItem -LiteralPath $script:BackupDir -Directory -ErrorAction SilentlyContinue)
    Write-Step INFO ("Identity backups: {0}" -f $backups.Count)

    if (Test-Path -LiteralPath $script:LastRunFile) {
        Write-Step INFO ("Last run: {0}" -f (Get-Content -LiteralPath $script:LastRunFile -Raw).Trim())
    }

    [void](& schtasks.exe /Query /TN $script:TaskName 2>$null)
    Write-Step INFO ("Autostart installed: {0}" -f ($LASTEXITCODE -eq 0))
    Write-Step INFO ("Logs: {0}" -f $script:LogDir)
    return 0
}

# ----------------------------------------------------------------------- main

$exitCode = 0
$locked = $false
try {
    Ensure-Dirs
    Write-Step START ("{0} action={1}" -f $script:AppName, $Action)

    switch ($Action) {
        'logs' {
            Write-Step INFO $script:LogDir
            Start-Process explorer.exe $script:LogDir | Out-Null
        }

        'status' { $exitCode = Show-Status }

        'browser' { $exitCode = Invoke-Browser -JoinUrl $Url }

        'autostart-on' {
            if (Ensure-Elevated -ForAction 'autostart-on') { $exitCode = Install-AutoStart }
        }

        'autostart-off' {
            if (Ensure-Elevated -ForAction 'autostart-off') { $exitCode = Remove-AutoStart }
        }

        'restore' {
            $locked = Enter-Lock
            if (-not $locked) { break }
            $exitCode = Invoke-Restore
        }

        'fix' {
            $locked = Enter-Lock
            if (-not $locked) { break }

            $zoom = Get-ZoomExePath
            if (-not $zoom) {
                throw 'Zoom is not installed on this PC. Install Zoom first, or use the browser bypass.'
            }
            Write-Step OK ("Zoom: {0}" -f $zoom)

            Stop-Zoom
            [void](Invoke-IdentityReset)

            if (-not $NoLaunch) {
                $profileData = Join-Path $script:ProfilesDir ('self_{0}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
                New-Item -ItemType Directory -Path $profileData -Force | Out-Null
                Write-Step ACTION 'Launching Zoom with a fresh profile'
                $proc = Start-Process -FilePath $zoom -ArgumentList @("--data=$profileData") -PassThru
                Write-Step OK ("Zoom started, PID {0}" -f $proc.Id)
            }
            Write-Step DONE 'Level 1 reset complete. Rejoin the meeting now.'
        }

        'deep-fix' {
            if (-not (Ensure-Elevated -ForAction 'deep-fix')) { break }
            $locked = Enter-Lock
            if (-not $locked) { break }

            $zoom = Get-ZoomExePath
            if (-not $zoom) {
                throw 'Zoom is not installed on this PC. Install Zoom first, or use the browser bypass.'
            }
            Write-Step OK ("Zoom: {0}" -f $zoom)

            Stop-Zoom
            Invoke-DeepFix -ZoomExe $zoom
            Write-Step DONE 'Level 2 rotation complete. Rejoin the meeting now.'
        }
    }

    Set-Content -LiteralPath $script:LastRunFile -Encoding utf8 -Force `
        -Value ("{0} action={1} exit={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Action, $exitCode)
}
catch {
    $exitCode = 1
    Write-Step FATAL $_.Exception.Message
    Write-Step FATAL ("Log: {0}" -f $script:LogFile)
    if ($Action -in @('fix', 'deep-fix', 'restore')) {
        Show-Dialog -Kind Error -Message ("{0}`n`nLog:`n{1}" -f $_.Exception.Message, $script:LogFile)
    }
}
finally {
    if ($locked) { Exit-Lock }
}

exit $exitCode
