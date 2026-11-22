<#
.SYNOPSIS
    Launches NEXORA from sources (development) or inside Nexora.exe (installed product).
.DESCRIPTION
    In the installed product this script is executed by Nexora.exe inside its own process (Windows
    PowerShell 5.1 engine built into Windows): no console, no technical window.
    From sources it works with PowerShell 7 or Windows PowerShell 5.1 (it relaunches itself in STA mode).
.PARAMETER DataPath
    Personal data folder. If omitted, uses the folder chosen in NEXORA or %LOCALAPPDATA%\Nexora.
#>
[CmdletBinding()]
param(
    [string]$DataPath = '',
    [switch]$NoRelaunch
)

$ErrorActionPreference = 'Stop'

# WPF requires an STA thread: from sources, if needed, it relaunches with -STA (does not happen inside Nexora.exe)
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA -and -not $NoRelaunch) {
    $exe = (Get-Process -Id $PID).Path
    $argList = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-NoRelaunch')
    if ($DataPath) { $argList += @('-DataPath', $DataPath) }
    & $exe @argList
    exit $LASTEXITCODE
}

if ($PSVersionTable.PSVersion.Major -lt 5) { throw 'PowerShell 5.1 or later is required.' }

$src = Join-Path $PSScriptRoot 'src'
foreach ($f in 'Modules\Utils.ps1', 'Modules\Strings.ps1', 'Modules\AppInfo.ps1', 'Modules\Storage.ps1', 'Modules\Priority.ps1',
               'Modules\Config.ps1', 'Modules\Tasks.ps1', 'UI\Theme.ps1', 'UI\Dialogs.ps1', 'UI\Ui.ps1') {
    . (Join-Path $src $f)
}

# process identity for taskbar/Start menu (groups windows under NEXORA)
[Stm.Native]::SetAppId($script:AppId)

if (-not $DataPath) { $DataPath = Get-DefaultDataPath }
$script:LegacyImported = $false
try { $script:LegacyImported = Import-LegacyData -Target $DataPath } catch { }

# single instance per data folder (avoids concurrent writes to the same files)
$script:DataMutex = Enter-DataPathMutex $DataPath
if ($null -eq $script:DataMutex) {
    Close-Splash
    Request-ExistingInstanceActivation | Out-Null
    exit 0
}

try {
    Start-Nexora -DataPath $DataPath
} catch {
    try { Write-Log "FATAL ERROR: $($_.Exception.Message)`n$($_.ScriptStackTrace)" 'ERROR' } catch { }
    Close-Splash
    Add-Type -AssemblyName PresentationFramework
    [void][System.Windows.MessageBox]::Show("NEXORA could not start:`n`n$($_.Exception.Message)`n`nDetails: $DataPath\Logs\app.log", 'NEXORA', 'OK', 'Error')
    exit 1
} finally {
    Exit-DataPathMutex $script:DataMutex
    $script:DataMutex = $null
}