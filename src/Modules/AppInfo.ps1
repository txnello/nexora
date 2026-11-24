# AppInfo.ps1 - product identity, version, paths (application and user data)
#
# Installed layout:   <install folder>\Nexora.exe + app\ (scripts, src, Assets, VERSION)
# Default personal data path: %LOCALAPPDATA%\Nexora\ (never inside the application folder)

$script:AppName = 'NEXORA'
$script:AppId = 'Nexora.App'                       # AppUserModelID (taskbar / menu Start)
$script:AppCopyright = "Copyright (c) $((Get-Date).Year) Manuel Tonello. All rights reserved."
$script:StartupRunKey = 'Software\Microsoft\Windows\CurrentVersion\Run'
$script:StartupApprovedRunKey = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$script:StartupValueName = 'NEXORA'
$script:StartupTaskId = 'NexoraStartup'
$script:ActivationEventName = 'Local\NEXORA.ActivateExisting'
# The data folder chosen by the user is remembered in the registry (HKCU\Software\Nexora, value DataPath), NOT in a file
# inside the default data folder: otherwise deleting the old folder would also delete the pointer and the app would
# silently fall back to (and recreate) %LOCALAPPDATA%\Nexora. Tests override the key name to stay isolated.
$script:DataPathRegistryKey = 'Software\Nexora'
$script:DataPathRegistryValue = 'DataPath'
# application root: the folder containing src\ (both in sources and in the installed package)
$script:AppRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:AssetsPath = Join-Path $script:AppRoot 'Assets'

function Get-InstalledLauncherPath {
    $launcher = Join-Path (Split-Path -Parent $script:AppRoot) 'Nexora.exe'
    if (Test-Path -LiteralPath $launcher -PathType Leaf) { return [System.IO.Path]::GetFullPath($launcher) }
    return $null
}

function Get-StartupCommand {
    $launcher = Get-InstalledLauncherPath
    if ($launcher) { return '"{0}"' -f $launcher }

    $hostPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $scriptPath = Join-Path $script:AppRoot 'Start-Nexora.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw (T 'The NEXORA startup script could not be found.') }
    return '"{0}" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" -NoRelaunch' -f $hostPath, $scriptPath
}

function Get-StartupRunValue {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:StartupRunKey, $false)
    if ($null -eq $key) { return $null }
    try { return [string]$key.GetValue($script:StartupValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
    finally { $key.Dispose() }
}

function Test-PackagedApp {
    if (-not ('Nexora.PackageIdentity' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
using System.Text;
namespace Nexora {
    public static class PackageIdentity {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetCurrentPackageFullName(ref uint length, StringBuilder fullName);
    }
}
'@
    }
    [uint32]$length = 0
    $result = [Nexora.PackageIdentity]::GetCurrentPackageFullName([ref]$length, $null)
    if ($result -eq 15700) { return $false }
    if ($result -eq 0 -or $result -eq 122) { return $true }
    throw "Unable to determine NEXORA package identity (Windows error $result)."
}

function Wait-WinRtOperation {
    param([Parameter(Mandatory)]$Operation, [Parameter(Mandatory)][type]$ResultType)
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $asTaskMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and
            $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        } |
        Select-Object -First 1
    if ($null -eq $asTaskMethod) { throw 'The Windows startup operation could not be awaited.' }

    $task = $asTaskMethod.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    return $task.GetAwaiter().GetResult()
}

function Get-PackagedStartupTask {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $operation = [Windows.ApplicationModel.StartupTask, Windows.ApplicationModel, ContentType=WindowsRuntime]::GetAsync($script:StartupTaskId)
    $task = Wait-WinRtOperation -Operation $operation -ResultType ([Windows.ApplicationModel.StartupTask, Windows.ApplicationModel, ContentType=WindowsRuntime])
    if ($null -eq $task) { throw 'The NEXORA startup task is missing from the MSIX manifest.' }
    return $task
}

function Set-PackagedStartupRegistration {
    param([bool]$Enabled)
    $task = Get-PackagedStartupTask
    if (-not $Enabled) {
        $task.Disable()
        return
    }

    if ([string]$task.State -in @('Enabled', 'EnabledByPolicy')) { return }
    $state = Wait-WinRtOperation -Operation ($task.RequestEnableAsync()) -ResultType ([Windows.ApplicationModel.StartupTaskState, Windows.ApplicationModel, ContentType=WindowsRuntime])
    if ([string]$state -notin @('Enabled', 'EnabledByPolicy')) {
        throw (T 'Windows did not enable NEXORA at startup. Check the Windows Startup apps settings.')
    }
}

function Ensure-StartupRegistration {
    param([bool]$Enabled)
    if ($script:TestMode) { return }
    if (-not $Enabled) { Set-StartupRegistration -Enabled $false; return }
    if (Test-PackagedApp) {
        $task = Get-PackagedStartupTask
        if ([string]$task.State -eq 'Disabled') {
            $state = Wait-WinRtOperation -Operation ($task.RequestEnableAsync()) -ResultType ([Windows.ApplicationModel.StartupTaskState, Windows.ApplicationModel, ContentType=WindowsRuntime])
            if ([string]$state -notin @('Enabled', 'EnabledByPolicy')) {
                throw (T 'Windows did not enable NEXORA at startup. Check the Windows Startup apps settings.')
            }
        }
        return
    }

    $command = Get-StartupCommand
    $current = Get-StartupRunValue
    if ([string]::Equals($current, $command, [System.StringComparison]::OrdinalIgnoreCase)) { return }

    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:StartupRunKey)
    try { $key.SetValue($script:StartupValueName, $command, [Microsoft.Win32.RegistryValueKind]::String) }
    finally { $key.Dispose() }
}

function Set-StartupRegistration {
    param([bool]$Enabled)
    if ($script:TestMode) { return }
    if (Test-PackagedApp) {
        Set-PackagedStartupRegistration -Enabled $Enabled
        return
    }
    if ($Enabled) {
        Ensure-StartupRegistration -Enabled $true
        $approvedKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:StartupApprovedRunKey, $true)
        if ($null -ne $approvedKey) {
            try { $approvedKey.DeleteValue($script:StartupValueName, $false) }
            finally { $approvedKey.Dispose() }
        }
        return
    }

    $runKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:StartupRunKey, $true)
    if ($null -ne $runKey) {
        try { $runKey.DeleteValue($script:StartupValueName, $false) }
        finally { $runKey.Dispose() }
    }

    $approvedKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:StartupApprovedRunKey, $true)
    if ($null -ne $approvedKey) {
        try { $approvedKey.DeleteValue($script:StartupValueName, $false) }
        finally { $approvedKey.Dispose() }
    }
}

function Get-AppVersion {
    # Major.Minor.Patch version read from the VERSION file (single source: also used by exe and installer)
    $f = Join-Path $script:AppRoot 'VERSION'
    try {
        $v = ([System.IO.File]::ReadAllText($f)).Trim()
        if ($v -match '^\d+\.\d+\.\d+$') { return $v }
    } catch { }
    return '0.0.0'
}

function Get-DefaultDataPath {
    # Order: test/IT override > user-chosen folder > portable mode > %LOCALAPPDATA%\Nexora
    if ($env:NEXORA_DATA) { return $env:NEXORA_DATA }
    $saved = Get-SavedDataPath
    if ($saved) { return $saved }
    if (Test-Path -LiteralPath (Join-Path $script:AppRoot 'portable.flag')) { return (Join-Path $script:AppRoot 'Data') }
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = [Environment]::GetFolderPath('LocalApplicationData') }
    return (Join-Path $base 'Nexora')
}

function Get-NormalizedDataPath {
    param([Parameter(Mandatory)][string]$Path)
    if (-not [System.IO.Path]::IsPathRooted($Path)) { throw (T 'The data folder path must be absolute.') }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.TrimEnd('\') -ieq $root.TrimEnd('\')) { return $root }
    return $fullPath.TrimEnd('\')
}

function Get-LegacyDataPathPreferenceFile {
    # Up to 1.0.4 the chosen folder was remembered in a file inside the default data folder. It is only READ now
    # (and migrated to the registry); nothing is ever written into the default folder any more.
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = [Environment]::GetFolderPath('LocalApplicationData') }
    return (Join-Path (Join-Path $base 'Nexora') 'data-path.txt')
}

function Get-DataPathRegistryValue {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:DataPathRegistryKey, $false)
    if ($null -eq $key) { return $null }
    try { return [string]$key.GetValue($script:DataPathRegistryValue, $null) }
    finally { $key.Dispose() }
}

function Set-DataPathRegistryValue {
    param([Parameter(Mandatory)][string]$Path)
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:DataPathRegistryKey)
    try { $key.SetValue($script:DataPathRegistryValue, $Path, [Microsoft.Win32.RegistryValueKind]::String) }
    finally { $key.Dispose() }
}

function Get-SavedDataPath {
    # 1) registry (current); 2) pointer file of versions <= 1.0.4, migrated to the registry the first time it is read
    $value = Get-DataPathRegistryValue
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        $value = $value.Trim()
        if (-not [System.IO.Path]::IsPathRooted($value)) { throw (T 'The saved data folder path is invalid: {0}' ('HKCU\' + $script:DataPathRegistryKey)) }
        return Get-NormalizedDataPath $value
    }
    $file = Get-LegacyDataPathPreferenceFile
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $legacy = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8).Trim()
    if ([string]::IsNullOrWhiteSpace($legacy) -or -not [System.IO.Path]::IsPathRooted($legacy)) {
        throw (T 'The saved data folder path is invalid: {0}' $file)
    }
    $path = Get-NormalizedDataPath $legacy
    try { Set-DataPathRegistryValue -Path $path } catch { }   # best effort: the file is still used if the registry is not writable
    return $path
}

function Set-DataPathPreference {
    param([Parameter(Mandatory)][string]$Path)
    Set-DataPathRegistryValue -Path (Get-NormalizedDataPath $Path)
}

function Get-DataPathMutexName {
    param([Parameter(Mandatory)][string]$Path)
    $fullPath = Get-NormalizedDataPath $Path
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($fullPath.ToLowerInvariant())
    $hash = [BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash($bytes)).Replace('-', '')
    return "Local\NEXORA-$hash"
}

function Enter-DataPathMutex {
    param([Parameter(Mandatory)][string]$Path)
    $created = $false
    $mutex = New-Object System.Threading.Mutex($true, (Get-DataPathMutexName $Path), [ref]$created)
    if (-not $created) { $mutex.Dispose(); return $null }
    return $mutex
}

function Exit-DataPathMutex {
    param($Mutex)
    if ($null -eq $Mutex) { return }
    try { $Mutex.ReleaseMutex() } finally { $Mutex.Dispose() }
}

function Request-ExistingInstanceActivation {
    try {
        $event = [System.Threading.EventWaitHandle]::OpenExisting($script:ActivationEventName)
    } catch [System.Threading.WaitHandleCannotBeOpenedException] {
        return $false
    }
    try {
        return $event.Set()
    } finally {
        $event.Dispose()
    }
}

function Import-LegacyData {
    # First launch with the new data folder: if data from the old location (<app>\Data) exists, it COPIES it
    # (does not move or delete them). Returns $true if it copied anything.
    param([Parameter(Mandatory)][string]$Target)
    $legacy = Join-Path $script:AppRoot 'Data'
    if (-not (Test-Path -LiteralPath $legacy)) { return $false }
    if ([System.IO.Path]::GetFullPath($legacy).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($Target).TrimEnd('\')) { return $false }
    foreach ($f in 'tasks.json', 'settings.json', 'history.json') {
        if (Test-Path -LiteralPath (Join-Path $Target $f)) { return $false }   # new folder already in use: do not touch anything
    }
    $files = @('tasks.json', 'settings.json', 'history.json') | Where-Object { Test-Path -LiteralPath (Join-Path $legacy $_) }
    if (@($files).Count -eq 0) { return $false }
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    foreach ($f in $files) { Copy-Item -LiteralPath (Join-Path $legacy $f) -Destination (Join-Path $Target $f) -Force }
    $bk = Join-Path $legacy 'Backups'
    if (Test-Path -LiteralPath $bk) { Copy-Item -LiteralPath $bk -Destination (Join-Path $Target 'Backups') -Recurse -Force }
    return $true
}
