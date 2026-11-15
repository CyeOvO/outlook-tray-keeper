# OlkTrayKeep.ps1 - Outlook (new) tray keeper: autostart + background receive + hide to tray
# ASCII-only source: PowerShell 5.1 reads BOM-less UTF-8 as ANSI, so keep it ASCII.

param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Status,
    [switch]$Show,
    [switch]$Hide,
    [switch]$Boot
)

$ErrorActionPreference = 'SilentlyContinue'
$RunKey    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunName   = 'OutlookTrayKeeper'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogPath   = Join-Path $ScriptDir 'traykpr.log'
$Self      = $MyInvocation.MyCommand.Path
$OlkAlias  = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\olk.exe'

function Log($m) {
    try { Add-Content -Path $LogPath -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $m) -Encoding UTF8 } catch {}
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
public delegate bool EnumProc(IntPtr h, IntPtr l);
public const int SW_HIDE = 0;
public const int SW_SHOW = 5;
public const int SW_RESTORE = 9;
'@

$script:OlkClass = 'Outlook Host'
$script:Hidden   = $false

function Get-OlkProc {
    Get-Process -Name olk -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Find-OlkWindow([int]$ProcId) {
    $script:found = [IntPtr]::Zero
    $cb = [W.U+EnumProc]{
        param($h, $l)
        $p = 0
        [void][W.U]::GetWindowThreadProcessId($h, [ref]$p)
        if ($p -eq $ProcId) {
            $sb = New-Object System.Text.StringBuilder 512
            [void][W.U]::GetClassName($h, $sb, 512)
            if ($sb.ToString() -eq $script:OlkClass) { $script:found = $h; return $false }
        }
        return $true
    }
    [void][W.U]::EnumWindows($cb, [IntPtr]::Zero)
    return $script:found
}

function Start-Olk {
    if (-not (Test-Path $OlkAlias)) { Log 'olk.exe alias missing'; return $false }
    Start-Process -FilePath $OlkAlias
    Log 'launched olk'
    return $true
}

function Show-Olk {
    $p = Get-OlkProc
    if (-not $p) { Start-Olk; return }
    $h = Find-OlkWindow $p.Id
    if ($h -eq [IntPtr]::Zero) { return }
    [void][W.U]::ShowWindow($h, [W.U]::SW_SHOW)
    [void][W.U]::ShowWindow($h, [W.U]::SW_RESTORE)
    [void][W.U]::SetForegroundWindow($h)
    $script:Hidden = $false
    Log 'show'
}

function Hide-Olk {
    $p = Get-OlkProc
    if (-not $p) { return }
    $h = Find-OlkWindow $p.Id
    if ($h -eq [IntPtr]::Zero) { return }
    [void][W.U]::ShowWindow($h, [W.U]::SW_HIDE)
    $script:Hidden = $true
    Log 'hide'
}

# ---------- CLI-only modes ----------
if ($Install) {
    $cmd = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $Self + '"'
    Set-ItemProperty -Path $RunKey -Name $RunName -Value $cmd
    Log 'install autostart'
    Write-Output ('autostart installed: ' + $cmd)
    return
}
if ($Uninstall) {
    Remove-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue
    Write-Output 'autostart removed'
    return
}
if ($Show)  { Show-Olk; Write-Output 'shown';  return }
if ($Hide)  { Hide-Olk; Write-Output 'hidden'; return }
if ($Status) {
    $p = Get-OlkProc
    if (-not $p) { Write-Output 'olk: not running' }
    else {
        $h = Find-OlkWindow $p.Id
        Write-Output ('olk pid=' + $p.Id + ' hwnd=' + $h + ' visible=' + [W.U]::IsWindowVisible($h) + ' iconic=' + [W.U]::IsIconic($h))
    }
    $k = (Get-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue).$RunName
    Write-Output ('autostart: ' + $(if ($k) { $k } else { 'off' }))
    $running = [bool](Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like '*OlkTrayKeep.ps1*' })
    Write-Output ('keeper running: ' + $running)
    return
}

# ---------- single instance ----------
$mutex = New-Object System.Threading.Mutex($false, 'Global\OlkTrayKeeperPS')
$owned = $mutex.WaitOne(0)
if (-not $owned) { Log 'another instance already running'; return }

# ---------- tray host ----------
$tray = New-Object System.Windows.Forms.NotifyIcon
try {
    $ic = [System.Drawing.Icon]::ExtractAssociatedIcon($OlkAlias)
    if ($ic) { $tray.Icon = $ic } else { $tray.Icon = [System.Drawing.SystemIcons]::Application }
} catch { $tray.Icon = [System.Drawing.SystemIcons]::Application }
$tray.Text = 'Outlook Keeper'
$tray.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miOpen = $menu.Items.Add('Open Outlook')
$miHide = $menu.Items.Add('Hide to tray')
$miSep1 = $menu.Items.Add('-')
$miAuto = $menu.Items.Add('Start with Windows')
$miSep2 = $menu.Items.Add('-')
$miExit = $menu.Items.Add('Exit keeper')

$miAuto.Checked = [bool]((Get-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue).$RunName)

$miOpen.add_Click({ Show-Olk })
$miHide.add_Click({ Hide-Olk })
$miExit.add_Click({
    Log 'exit via menu'
    $tray.Visible = $false
    $tray.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
$miAuto.add_Click({
    if ($miAuto.Checked) {
        Remove-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue
    } else {
        $cmd = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $Self + '"'
        Set-ItemProperty -Path $RunKey -Name $RunName -Value $cmd
    }
    $miAuto.Checked = [bool]((Get-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue).$RunName)
})
$tray.add_DoubleClick({ Show-Olk })
$tray.ContextMenuStrip = $menu

# ---------- watcher ----------
$script:armed = $false
$script:lastLaunch = [DateTime]::MinValue
$script:pendingHide = $false

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 800
$timer.add_Tick({
    $p = Get-OlkProc
    if (-not $p) {
        $script:Hidden = $false
        if ($script:armed -and ((Get-Date) - $script:lastLaunch).TotalSeconds -gt 25) {
            Log 'olk gone -> relaunch'
            $script:lastLaunch = Get-Date
            $script:pendingHide = $true
            Start-Olk
        }
        return
    }
    $h = Find-OlkWindow $p.Id
    if ($h -eq [IntPtr]::Zero) { return }
    $script:armed = $true

    if ($script:pendingHide -and [W.U]::IsWindowVisible($h)) {
        [void][W.U]::ShowWindow($h, [W.U]::SW_HIDE)
        $script:Hidden = $true
        $script:pendingHide = $false
        Log 'relaunched -> hidden to tray'
        return
    }
    if ([W.U]::IsIconic($h) -and -not $script:Hidden) {
        [void][W.U]::ShowWindow($h, [W.U]::SW_HIDE)
        $script:Hidden = $true
        Log 'minimize -> tray'
    } elseif ($script:Hidden -and [W.U]::IsWindowVisible($h)) {
        $script:Hidden = $false
        Log 'window restored externally'
    }
})
$timer.Start()

Log ('keeper start boot=' + [bool]$Boot)
if ($Boot) {
    if (-not (Get-OlkProc)) { $script:lastLaunch = Get-Date; $script:pendingHide = $true; Start-Olk }
    $script:Hidden = $false
}

[System.Windows.Forms.Application]::Run()
$timer.Stop()
$tray.Visible = $false
$tray.Dispose()
try { $mutex.ReleaseMutex(); $mutex.Dispose() } catch {}
Log 'keeper stop'