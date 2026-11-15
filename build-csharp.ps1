# build-csharp.ps1 - compile the C# variant with the in-box csc.exe (no SDK needed)

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Csc  = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'

if (-not (Test-Path $Csc)) { throw "csc.exe not found at $Csc" }

& $Csc /nologo /target:winexe /platform:anycpu /optimize+ `
    "/out:$Here\OlkTrayKeep.exe" `
    /r:System.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll `
    "$Here\csharp\OlkTrayKeep.cs"

if (Test-Path "$Here\OlkTrayKeep.exe") {
    Write-Host ("built: " + (Join-Path $Here 'OlkTrayKeep.exe'))
    Get-Item "$Here\OlkTrayKeep.exe" | Select-Object Name, Length | Format-Table -AutoSize
}
