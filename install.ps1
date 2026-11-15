# install.ps1 - deploy OlkTrayKeep and register logon autostart
# usage: powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 [-Uninstall] [-Status]

param([switch]$Uninstall, [switch]$Status)

$ErrorActionPreference = 'Stop'
$Here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$SrcKeeper = Join-Path $Here 'OlkTrayKeep.ps1'
$TargetDir = Join-Path $env:LOCALAPPDATA 'OlkTrayKeep'
$Target    = Join-Path $TargetDir 'OlkTrayKeeper.ps1'
$RunKey    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunName   = 'OutlookTrayKeeper'
$CmdLine   = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $Target + '"'

function Get-KeeperProcs {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like '*OlkTrayKeep*' -or $_.CommandLine -like '*OlkTrayKeeper*' }
}

if ($Status) {
    $reg = (Get-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue).$RunName
    Write-Host ('autostart : ' + $(if ($reg) { $reg } else { 'OFF' }))
    Write-Host ('deployed  : ' + $(if (Test-Path $Target) { $Target } else { 'NOT DEPLOYED' }))
    $p = @(Get-KeeperProcs)
    Write-Host ('keeper    : ' + $(if ($p.Count -gt 0) { 'running pid=' + ($p.ProcessId -join ',') } else { 'not running' }))
    $olk = @(Get-Process olk -ErrorAction SilentlyContinue)
    Write-Host ('outlook   : ' + $(if ($olk.Count -gt 0) { 'olk.exe pid=' + $olk[0].Id } else { 'not running' }))
    return
}

if ($Uninstall) {
    Get-KeeperProcs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Remove-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $RunKey -Name 'OutlookTrayKeep' -ErrorAction SilentlyContinue
    Write-Host 'autostart removed, keeper stopped.'
    Write-Host ('files kept at: ' + $TargetDir)
    return
}

# stop any running instance (old path or new)
Get-KeeperProcs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 800

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
Copy-Item -Path $SrcKeeper -Destination $Target -Force

Set-ItemProperty -Path $RunKey -Name $RunName -Value $CmdLine
Remove-ItemProperty -Path $RunKey -Name 'OutlookTrayKeep' -ErrorAction SilentlyContinue

Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',$Target) -WindowStyle Hidden
Start-Sleep -Seconds 4

Write-Host 'installed.'
Write-Host ('  keeper   : ' + $Target)
Write-Host ('  autostart: ' + $CmdLine)
$p = @(Get-KeeperProcs)
Write-Host ('  running  : ' + $(if ($p.Count -gt 0) { 'yes pid=' + ($p.ProcessId -join ',') } else { 'NO - check ' + (Join-Path $TargetDir 'traykpr.log') }))