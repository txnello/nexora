# Storage.ps1 - safe JSON persistence (atomic write, backup, import/export)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:DataFiles = @('tasks.json', 'settings.json', 'history.json')

function Initialize-Storage {
    param([Parameter(Mandatory)][string]$DataPath)
    $script:DataPath = $DataPath
    $script:BackupPath = Join-Path $DataPath 'Backups'
    foreach ($d in @($DataPath, $script:BackupPath)) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    Initialize-Logging -LogDir (Join-Path $DataPath 'Logs')
}

function Get-DataFilePath { param([string]$Name) Join-Path $script:DataPath $Name }

function Write-JsonFile {
    # Atomic write: temp file -> replace, with .bak copy of previous file.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Object)
    $json = ConvertTo-Json -InputObject $Object -Depth 10
    $tmp = "$Path.tmp"
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmp, $json, $enc)
    if (Test-Path -LiteralPath $Path) {
        [System.IO.File]::Replace($tmp, $Path, "$Path.bak")
    } else {
        [System.IO.File]::Move($tmp, $Path)
    }
}

function Read-JsonStrict {
    # Reads and validates a JSON file; throws if missing, empty, or invalid.
    param([Parameter(Mandatory)][string]$Path)
    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($raw)) { throw (T 'Empty file: {0}' $Path) }
    $obj = ConvertFrom-Json -InputObject $raw
    if ($null -eq $obj) { throw (T 'Invalid JSON: {0}' $Path) }
    return $obj
}

function Read-JsonFile {
    # Returns @{ Data; Source = main|backup|missing; Warning }
    param([Parameter(Mandatory)][string]$Name)
    $path = Get-DataFilePath $Name
    $result = @{ Data = $null; Source = 'missing'; Warning = $null }
    if (Test-Path -LiteralPath $path) {
        try {
            $result.Data = Read-JsonStrict -Path $path
            $result.Source = 'main'
            return $result
        } catch {
            Write-Log "Corrupt file $Name : $($_.Exception.Message)" 'ERROR'
            # preserve corrupt file for analysis
            try {
                $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
                Copy-Item -LiteralPath $path -Destination (Join-Path $script:BackupPath "corrotto-$stamp-$Name") -Force
            } catch { }
            $bak = "$path.bak"
            if (Test-Path -LiteralPath $bak) {
                try {
                    $result.Data = Read-JsonStrict -Path $bak
                    $result.Source = 'backup'
                    $result.Warning = (T '{0} was not valid: the last safety copy (.bak) was restored.' $Name)
                    return $result
                } catch { }
            }
            $result.Source = 'missing'
            $result.Warning = (T '{0} was not valid and no usable safety copy exists: starting from scratch (the original file is kept in Data\Backups).' $Name)
            return $result
        }
    }
    return $result
}

function Save-JsonSafe {
    param([string]$Name, $Object)
    Write-JsonFile -Path (Get-DataFilePath $Name) -Object $Object
}

function Test-DataDirectoryHasData {
    param([Parameter(Mandatory)][string]$Path)
    foreach ($name in $script:DataFiles) {
        if ((Test-Path -LiteralPath (Join-Path $Path $name)) -or (Test-Path -LiteralPath (Join-Path $Path "$name.bak"))) { return $true }
    }
    $backups = Join-Path $Path 'Backups'
    if (Test-Path -LiteralPath $backups) {
        $file = Get-ChildItem -LiteralPath $backups -File -Force -Recurse | Select-Object -First 1
        if ($file) { return $true }
    }
    return $false
}

function Backup-ExistingDataDirectory {
    param([Parameter(Mandatory)][string]$Path)
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
    $backup = Join-Path $Path "Nexora-data-backup-$stamp"
    while (Test-Path -LiteralPath $backup) { $backup = Join-Path $Path "Nexora-data-backup-$stamp-$([guid]::NewGuid().ToString('N'))" }
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    foreach ($name in $script:DataFiles) {
        foreach ($file in $name, "$name.bak") {
            $source = Join-Path $Path $file
            if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $backup }
        }
    }
    $backups = Join-Path $Path 'Backups'
    if (Test-Path -LiteralPath $backups) { Copy-Item -LiteralPath $backups -Destination (Join-Path $backup 'Backups') -Recurse -Force }
    return $backup
}

function Copy-DataBackups {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    $sourceBackups = Join-Path $Source 'Backups'
    if (-not (Test-Path -LiteralPath $sourceBackups)) { return }
    $destinationBackups = Join-Path $Destination 'Backups'
    if (-not (Test-Path -LiteralPath $destinationBackups)) { New-Item -ItemType Directory -Path $destinationBackups -Force | Out-Null }
    foreach ($item in Get-ChildItem -LiteralPath $sourceBackups -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $destinationBackups -Recurse -Force
    }
}

function Read-DataDirectoryJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    $file = Join-Path $Path $Name
    if (Test-Path -LiteralPath $file) { return Read-JsonStrict -Path $file }
    $backup = "$file.bak"
    if (Test-Path -LiteralPath $backup) { return Read-JsonStrict -Path $backup }
    return $null
}

function Get-MergeUniqueId {
    param([hashtable]$UsedIds)
    do { $id = New-Id } while ($UsedIds.ContainsKey($id))
    $UsedIds[$id] = $true
    return $id
}

function Test-MergeDefaultSettingName {
    param([string]$Id, [string]$Name)
    if (-not $script:DefaultNames) { return $false }
    foreach ($language in 'en', 'it') {
        $names = $script:DefaultNames[$language]
        if ($names -and $names.ContainsKey($Id) -and $Name -ieq [string]$names[$Id]) { return $true }
    }
    return $false
}

function Get-MergedAppDataState {
    param([Parameter(Mandatory)][string]$Path)

    $targetSettings = Repair-Settings (Read-DataDirectoryJson -Path $Path -Name 'settings.json')
    $sourceSettings = Repair-Settings $script:State.Settings
    $targetRawTasks = Read-DataDirectoryJson -Path $Path -Name 'tasks.json'
    $targetTasks = Repair-Tasks (Get-Prop $targetRawTasks 'tasks' @()) $targetSettings
    $targetRawHistory = Read-DataDirectoryJson -Path $Path -Name 'history.json'
    $targetHistory = Repair-History (Get-Prop $targetRawHistory 'entries' @())
    $mergeWarnings = New-Object 'System.Collections.Generic.List[string]'
    foreach ($warning in $script:State.Warnings) { $mergeWarnings.Add($warning) }

    $statusIds = @{}
    $usedStatusIds = @{}
    foreach ($item in $targetSettings.statuses) { $usedStatusIds[[string]$item.id] = $true }
    foreach ($item in $sourceSettings.statuses) {
        $existing = $targetSettings.statuses | Where-Object { $_.name -ieq $item.name } | Select-Object -First 1
        if (-not $existing -and (Test-MergeDefaultSettingName $item.id $item.name)) {
            $default = $targetSettings.statuses | Where-Object {
                $_.id -eq $item.id -and (Test-MergeDefaultSettingName $_.id $_.name)
            } | Select-Object -First 1
            if ($default) { $existing = $default }
        }
        if ($existing) {
            $statusIds[[string]$item.id] = [string]$existing.id
            continue
        }
        $id = [string]$item.id
        if ($usedStatusIds.ContainsKey($id)) { $id = Get-MergeUniqueId $usedStatusIds }
        else { $usedStatusIds[$id] = $true }
        $statusIds[[string]$item.id] = $id
        $targetSettings.statuses.Add([pscustomobject]@{
            id = $id; name = $item.name; color = $item.color; isClosed = [bool]$item.isClosed
        })
    }

    $priorityIds = @{}
    $usedPriorityIds = @{}
    foreach ($item in $targetSettings.priorities) { $usedPriorityIds[[string]$item.id] = $true }
    foreach ($item in $sourceSettings.priorities) {
        $existing = $targetSettings.priorities | Where-Object { $_.name -ieq $item.name } | Select-Object -First 1
        if (-not $existing -and (Test-MergeDefaultSettingName $item.id $item.name)) {
            $default = $targetSettings.priorities | Where-Object {
                $_.id -eq $item.id -and (Test-MergeDefaultSettingName $_.id $_.name)
            } | Select-Object -First 1
            if ($default) { $existing = $default }
        }
        if ($existing) {
            $priorityIds[[string]$item.id] = [string]$existing.id
            continue
        }
        $id = [string]$item.id
        if ($usedPriorityIds.ContainsKey($id)) { $id = Get-MergeUniqueId $usedPriorityIds }
        else { $usedPriorityIds[$id] = $true }
        $priorityIds[[string]$item.id] = $id
        $targetSettings.priorities.Add([pscustomobject]@{
            id = $id; name = $item.name; color = $item.color; value = [double]$item.value
        })
    }

    $usedReferentIds = @{}
    foreach ($item in $targetSettings.referents) { $usedReferentIds[[string]$item.id] = $true }
    foreach ($item in $sourceSettings.referents) {
        if ($targetSettings.referents | Where-Object { $_.name -ieq $item.name }) { continue }
        $id = [string]$item.id
        if ($usedReferentIds.ContainsKey($id)) { $id = Get-MergeUniqueId $usedReferentIds }
        else { $usedReferentIds[$id] = $true }
        $targetSettings.referents.Add([pscustomobject]@{ id = $id; name = $item.name })
    }

    $usedProjectIds = @{}
    foreach ($item in $targetSettings.projects) { $usedProjectIds[[string]$item.id] = $true }
    foreach ($item in $sourceSettings.projects) {
        if ($targetSettings.projects | Where-Object { $_.name -ieq $item.name }) { continue }
        $id = [string]$item.id
        if ($usedProjectIds.ContainsKey($id)) { $id = Get-MergeUniqueId $usedProjectIds }
        else { $usedProjectIds[$id] = $true }
        $targetSettings.projects.Add([pscustomobject]@{ id = $id; name = $item.name })
    }

    $usedClientIds = @{}
    foreach ($item in $targetSettings.clients) { $usedClientIds[[string]$item.id] = $true }
    foreach ($item in $sourceSettings.clients) {
        if ($targetSettings.clients | Where-Object { $_.name -ieq $item.name }) { continue }
        $id = [string]$item.id
        if ($usedClientIds.ContainsKey($id)) { $id = Get-MergeUniqueId $usedClientIds }
        else { $usedClientIds[$id] = $true }
        $targetSettings.clients.Add([pscustomobject]@{ id = $id; name = $item.name })
    }

    $sourceRawTasks = New-Object 'System.Collections.Generic.List[psobject]'
    foreach ($task in $script:State.Tasks) {
        $sourceRawTasks.Add([pscustomobject]@{
            id = $task.id; code = $task.code; title = $task.title; description = $task.description
            referent = $task.referent; project = $task.project; client = $task.client; link = $task.link; statusId = $statusIds[[string]$task.statusId]
            priorityId = $priorityIds[[string]$task.priorityId]; createdAt = $task.createdAt
            updatedAt = $task.updatedAt; dueDate = $task.dueDate; reminders = $task.reminders
            lastReminderAt = $task.lastReminderAt; completedAt = $task.completedAt
        })
    }
    $sourceTasks = Repair-Tasks $sourceRawTasks $targetSettings

    foreach ($task in @($targetTasks) + @($sourceTasks)) {
        $ownerName = ([string]$task.referent).Trim()
        if (-not $ownerName -or ($targetSettings.referents | Where-Object { $_.name -ieq $ownerName })) { continue }
        $targetSettings.referents.Add([pscustomobject]@{ id = (Get-MergeUniqueId $usedReferentIds); name = $ownerName })
    }
    foreach ($task in @($targetTasks) + @($sourceTasks)) {
        $projectName = ([string]$task.project).Trim()
        if (-not $projectName -or ($targetSettings.projects | Where-Object { $_.name -ieq $projectName })) { continue }
        $targetSettings.projects.Add([pscustomobject]@{ id = (Get-MergeUniqueId $usedProjectIds); name = $projectName })
    }
    foreach ($task in @($targetTasks) + @($sourceTasks)) {
        $clientName = ([string]$task.client).Trim()
        if (-not $clientName -or ($targetSettings.clients | Where-Object { $_.name -ieq $clientName })) { continue }
        $targetSettings.clients.Add([pscustomobject]@{ id = (Get-MergeUniqueId $usedClientIds); name = $clientName })
    }

    $usedTaskIds = @{}
    $usedTaskCodes = @{}
    foreach ($task in $targetTasks) {
        $usedTaskIds[[string]$task.id] = $true
        $usedTaskCodes[[string]$task.code] = $true
    }
    $taskIdMap = @{}
    foreach ($task in $sourceTasks) {
        $oldId = [string]$task.id
        if ($usedTaskIds.ContainsKey($oldId)) { $task.id = Get-MergeUniqueId $usedTaskIds }
        else { $usedTaskIds[$oldId] = $true }
        $taskIdMap[$oldId] = [string]$task.id
        if ($usedTaskCodes.ContainsKey([string]$task.code)) {
            $originalCode = [string]$task.code
            do {
                if ($targetSettings.nextCodeNumber -gt 99999999) { throw (T 'No task codes remain for merging data.') }
                $task.code = '{0}-{1}' -f $targetSettings.codePrefix, $targetSettings.nextCodeNumber
                $targetSettings.nextCodeNumber++
            } while ($usedTaskCodes.ContainsKey([string]$task.code))
            $mergeWarnings.Add((T 'Task code "{0}" was changed to "{1}" because the destination already uses it.' $originalCode $task.code))
        }
        $usedTaskCodes[[string]$task.code] = $true
    }

    $tasks = New-Object 'System.Collections.Generic.List[psobject]'
    foreach ($task in $targetTasks) { $tasks.Add($task) }
    foreach ($task in $sourceTasks) { $tasks.Add($task) }

    $history = New-Object 'System.Collections.Generic.List[psobject]'
    $usedHistoryIds = @{}
    foreach ($entry in $targetHistory) {
        if ($usedHistoryIds.ContainsKey([string]$entry.id)) { $entry.id = Get-MergeUniqueId $usedHistoryIds }
        else { $usedHistoryIds[[string]$entry.id] = $true }
        $history.Add($entry)
    }
    foreach ($entry in (Repair-History $script:State.History)) {
        if ($usedHistoryIds.ContainsKey([string]$entry.id)) { $entry.id = Get-MergeUniqueId $usedHistoryIds }
        else { $usedHistoryIds[[string]$entry.id] = $true }
        if ($taskIdMap.ContainsKey([string]$entry.taskId)) { $entry.taskId = $taskIdMap[[string]$entry.taskId] }
        $history.Add($entry)
    }
    $sortedHistory = New-Object 'System.Collections.Generic.List[psobject]'
    foreach ($entry in @($history | Sort-Object at)) { $sortedHistory.Add($entry) }

    return [pscustomobject]@{
        Settings = $targetSettings; Tasks = $tasks; History = $sortedHistory
        Warnings = $mergeWarnings; LastScoreDay = (Get-Date).Date
    }
}

function Switch-AppDataDirectory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Overwrite', 'Keep', 'Merge')][string]$Mode = 'Overwrite'
    )
    $target = Get-NormalizedDataPath $Path
    $current = Get-NormalizedDataPath $script:DataPath
    if ($target -ieq $current) { return $false }
    $application = Get-NormalizedDataPath $script:AppRoot
    if ($target -ieq $application -or $target.StartsWith($application.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw (T 'The data folder must be outside the application folder.')
    }
    if ($target.StartsWith($current.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
        $current.StartsWith($target.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw (T 'The new data folder cannot be inside or above the current data folder.')
    }

    $destinationHasData = Test-DataDirectoryHasData $target
    $newMutex = Enter-DataPathMutex $target
    if ($null -eq $newMutex) { throw (T 'NEXORA is already using the selected data folder.') }

    $oldMutex = $script:DataMutex
    $storageChanged = $false
    $preferenceChanged = $false
    try {
        $mergedState = $null
        if ($Mode -eq 'Merge') { $mergedState = Get-MergedAppDataState -Path $target }
        if ($Mode -in @('Overwrite', 'Merge')) {
            Save-Tasks
            Save-Settings
            Save-History
            $null = New-Snapshot -Reason 'pre-location-change'
            if ($destinationHasData) { $null = Backup-ExistingDataDirectory $target }
        }

        $storageChanged = $true
        Initialize-Storage -DataPath $target
        if ($Mode -eq 'Overwrite') {
            Save-Tasks
            Save-Settings
            Save-History
            Copy-DataBackups -Source $current -Destination $target
        } elseif ($Mode -eq 'Merge') {
            $script:State = $mergedState
            Save-Tasks
            Save-Settings
            Save-History
            Copy-DataBackups -Source $current -Destination $target
        }
        $null = Initialize-AppState
        Set-DataPathPreference -Path $target
        $preferenceChanged = $true
        $script:DataPath = $target

        Exit-DataPathMutex $oldMutex
        $script:DataMutex = $newMutex
        $newMutex = $null
        return $true
    } catch {
        $failure = $_.Exception.Message
        if ($storageChanged) {
            try {
                Initialize-Storage -DataPath $current
                $null = Initialize-AppState
                $script:DataPath = $current
                if ($preferenceChanged) { Set-DataPathPreference -Path $current }
            } catch {
                Write-Log "Data folder rollback failed: $($_.Exception.Message)" 'ERROR'
                throw (T 'Changing the data folder failed and the previous folder could not be restored: {0}' $_.Exception.Message)
            }
        }
        throw $failure
    } finally {
        Exit-DataPathMutex $newMutex
    }
}

# ---------------------------------------------------------------- Snapshot / backup

function New-Snapshot {
    # Creates a zip with data files. Reason: manual | auto | pre-import | ...
    param([string]$Reason = 'auto', [string]$DestinationFile)
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
    $safeReason = ($Reason -replace '[^A-Za-z0-9\-]', '')
    if ([string]::IsNullOrEmpty($DestinationFile)) {
        $DestinationFile = Join-Path $script:BackupPath "snapshot-$stamp-$safeReason.zip"
    }
    $zip = [System.IO.Compression.ZipFile]::Open($DestinationFile, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $count = 0
        foreach ($f in $script:DataFiles) {
            $p = Get-DataFilePath $f
            if (Test-Path -LiteralPath $p) {
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $p, $f, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
                $count++
            }
        }
    } finally { $zip.Dispose() }
    if ($count -eq 0) { Remove-Item -LiteralPath $DestinationFile -Force; return $null }
    Write-Log "Snapshot created: $DestinationFile"
    return $DestinationFile
}

function Get-Snapshots {
    if (-not (Test-Path -LiteralPath $script:BackupPath)) { return @() }
    $items = Get-ChildItem -LiteralPath $script:BackupPath -Filter 'snapshot-*.zip' -File |
        Sort-Object LastWriteTime -Descending
    foreach ($i in $items) {
        $reason = ''
        if ($i.BaseName -match '^snapshot-\d{8}-\d{6}-\d{3}-(.*)$') { $reason = $Matches[1] }
        [pscustomobject]@{
            Path = $i.FullName; Name = $i.Name; Date = $i.LastWriteTime
            Reason = $reason; SizeKB = [math]::Round($i.Length / 1KB, 1)
        }
    }
}

function Remove-OldSnapshots {
    param([int]$Keep = 30)
    # manual backups are never deleted automatically
    $auto = @(Get-Snapshots | Where-Object { $_.Reason -ne 'manual' })
    if ($auto.Count -gt $Keep) {
        $auto | Select-Object -Skip $Keep | ForEach-Object {
            try { Remove-Item -LiteralPath $_.Path -Force } catch { Write-Log "Cannot delete $($_.Path)" 'WARN' }
        }
    }
}

function Invoke-DailySnapshot {
    param([int]$Keep = 30)
    $today = (Get-Date).Date
    $has = @(Get-Snapshots | Where-Object { $_.Reason -eq 'auto' -and $_.Date.Date -eq $today })
    if ($has.Count -eq 0) { New-Snapshot -Reason 'auto' | Out-Null; Remove-OldSnapshots -Keep $Keep }
}

function Test-BackupArchive {
    # Verifies the zip; returns @{ Ok; Error; Entries }
    param([Parameter(Mandatory)][string]$ZipPath)
    $res = @{ Ok = $false; Error = $null; Entries = @() }
    if (-not (Test-Path -LiteralPath $ZipPath)) { $res.Error = (T 'File not found.'); return $res }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('nexora-' + (New-Id))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        try {
            $names = @($zip.Entries | ForEach-Object { $_.FullName })
            if ($names -notcontains 'tasks.json') { $res.Error = (T 'The backup does not contain tasks.json.'); return $res }
            foreach ($f in $script:DataFiles) {
                $e = $zip.GetEntry($f)
                if ($null -ne $e) {
                    $dest = Join-Path $tmp $f   # only known names: no path traversal risk
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
                    $null = Read-JsonStrict -Path $dest
                    $res.Entries += $f
                }
            }
            $res.Ok = $true
            $res.TempDir = $tmp
            return $res
        } finally { $zip.Dispose() }
    } catch {
        $res.Error = (T 'Invalid archive: {0}' $_.Exception.Message)
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return $res
    }
}

function Restore-BackupArchive {
    # Imports a full backup. First creates a safety snapshot of current state.
    param([Parameter(Mandatory)][string]$ZipPath)
    $check = Test-BackupArchive -ZipPath $ZipPath
    if (-not $check.Ok) { throw $check.Error }
    try {
        New-Snapshot -Reason 'pre-import' | Out-Null
        foreach ($f in $check.Entries) {
            $src = Join-Path $check.TempDir $f
            $dst = Get-DataFilePath $f
            $tmp = "$dst.tmp"
            Copy-Item -LiteralPath $src -Destination $tmp -Force
            if (Test-Path -LiteralPath $dst) { [System.IO.File]::Replace($tmp, $dst, "$dst.bak") }
            else { [System.IO.File]::Move($tmp, $dst) }
        }
        Write-Log "Backup restored from $ZipPath"
    } finally {
        Remove-Item -LiteralPath $check.TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
