# Tasks.ps1 - application state, task CRUD, reminders, history, statistics

$script:State = $null

# ------------------------------------------------------------------ State persistence

function Save-Settings { Save-JsonSafe 'settings.json' $script:State.Settings }

function Save-Tasks {
    $obj = [pscustomobject]@{ version = 1; tasks = $script:State.Tasks }
    Save-JsonSafe 'tasks.json' $obj
}

function Save-History {
    $h = $script:State.History
    if ($h.Count -gt 10000) { $h.RemoveRange(0, $h.Count - 10000) }
    Save-JsonSafe 'history.json' ([pscustomobject]@{ version = 1; entries = $h })
}

function Update-AllScoresAndSave {
    Update-AllScores -State $script:State
    Save-Tasks
}

function Test-TaskLink {
    param([string]$Link)
    if ([string]::IsNullOrWhiteSpace($Link)) { return $true }
    $value = $Link.Trim()
    if ($value.Length -gt 2048) { return $false }
    $uri = $null
    if (-not [uri]::TryCreate($value, [System.UriKind]::Absolute, [ref]$uri)) { return $false }
    return (($uri.Scheme -in @('http', 'https')) -and -not [string]::IsNullOrWhiteSpace($uri.Host))
}

function Repair-Tasks {
    param($Raw, $Settings)
    $list = New-Object 'System.Collections.Generic.List[psobject]'
    $ids = @{}; $codes = @{}
    $firstOpen = ($Settings.statuses | Where-Object { -not $_.isClosed } | Select-Object -First 1).id
    $midPrio = @($Settings.priorities | Sort-Object value)
    $defPrio = $midPrio[[int][math]::Floor(($midPrio.Count - 1) / 2)].id
    $now = Format-IsoDateTime (Get-Date)
    foreach ($r in @($Raw)) {
        if ($null -eq $r -or $r -isnot [System.Management.Automation.PSCustomObject]) { continue }
        $id = [string](Get-Prop $r 'id' ''); if ($id -eq '' -or $ids.ContainsKey($id)) { $id = New-Id }
        $ids[$id] = $true
        $title = ([string](Get-Prop $r 'title' '')).Trim(); if ($title -eq '') { $title = (T '(untitled)') }
        $code = ([string](Get-Prop $r 'code' '')).Trim()
        if ($code -eq '') { $code = "$($Settings.codePrefix)-$($Settings.nextCodeNumber)"; $Settings.nextCodeNumber++ }
        $base = $code; $k = 2
        while ($codes.ContainsKey($code.ToLower())) { $code = "$base-$k"; $k++ }
        $codes[$code.ToLower()] = $true
        $stId = [string](Get-Prop $r 'statusId' ''); if (-not ($Settings.statuses | Where-Object { $_.id -eq $stId })) { $stId = $firstOpen }
        $prId = [string](Get-Prop $r 'priorityId' ''); if (-not ($Settings.priorities | Where-Object { $_.id -eq $prId })) { $prId = $defPrio }
        $created = Format-IsoDateTime (Get-Prop $r 'createdAt' $null); if (-not $created) { $created = $now }
        $updated = Format-IsoDateTime (Get-Prop $r 'updatedAt' $null); if (-not $updated) { $updated = $created }
        $rem = 0; [void][int]::TryParse([string](Get-Prop $r 'reminders' 0), [ref]$rem); if ($rem -lt 0) { $rem = 0 }
        $link = ([string](Get-Prop $r 'link' '')).Trim()
        if (-not (Test-TaskLink $link)) { $link = '' }
        $list.Add([pscustomobject]@{
            id             = $id
            code           = $code
            title          = $title
            description    = [string](Get-Prop $r 'description' '')
            referent       = ([string](Get-Prop $r 'referent' '')).Trim()
            project        = ([string](Get-Prop $r 'project' '')).Trim()
            client         = ([string](Get-Prop $r 'client' '')).Trim()
            link           = $link
            statusId       = $stId
            priorityId     = $prId
            createdAt      = $created
            updatedAt      = $updated
            dueDate        = Format-IsoDate (Get-Prop $r 'dueDate' $null)
            reminders      = $rem
            lastReminderAt = Format-IsoDateTime (Get-Prop $r 'lastReminderAt' $null)
            completedAt    = Format-IsoDateTime (Get-Prop $r 'completedAt' $null)
            score          = $null
        })
    }
    return , $list
}

function Repair-History {
    param($Raw)
    $list = New-Object 'System.Collections.Generic.List[psobject]'
    foreach ($r in @($Raw)) {
        if ($null -eq $r -or $r -isnot [System.Management.Automation.PSCustomObject]) { continue }
        $at = Format-IsoDateTime (Get-Prop $r 'at' $null); if (-not $at) { continue }
        $list.Add([pscustomobject]@{
            id = [string](Get-Prop $r 'id' (New-Id)); taskId = [string](Get-Prop $r 'taskId' '')
            code = [string](Get-Prop $r 'code' ''); at = $at
            type = [string](Get-Prop $r 'type' 'modificato'); text = [string](Get-Prop $r 'text' '')
        })
    }
    return , $list
}

function Initialize-AppState {
    # Loads (or creates) the data. Returns the state; any warnings in $state.Warnings
    $warnings = New-Object 'System.Collections.Generic.List[string]'
    $rs = Read-JsonFile 'settings.json'
    $rt = Read-JsonFile 'tasks.json'
    $rh = Read-JsonFile 'history.json'
    foreach ($r in @($rs, $rt, $rh)) { if ($r.Warning) { $warnings.Add($r.Warning) } }

    $settings = Repair-Settings $rs.Data
    $tasks = Repair-Tasks (Get-Prop $rt.Data 'tasks' @()) $settings
    $hist = Repair-History (Get-Prop $rh.Data 'entries' @())

    $beforeReferentCount = $settings.referents.Count
    foreach ($name in @($tasks | ForEach-Object { ([string]$_.referent).Trim() } | Where-Object { $_ } | Sort-Object -Unique)) {
        if (-not ($settings.referents | Where-Object { $_.name -ieq $name })) {
            [void]$settings.referents.Add([pscustomobject]@{ id = 'rf' + (New-Id).Substring(0, 8); name = $name })
        }
    }

    # projects used by tasks but missing from the list are added (same as owners); tasks without 'project' = no project
    $beforeProjectCount = $settings.projects.Count
    foreach ($name in @($tasks | ForEach-Object { ([string]$_.project).Trim() } | Where-Object { $_ } | Sort-Object -Unique)) {
        if (-not ($settings.projects | Where-Object { $_.name -ieq $name })) {
            [void]$settings.projects.Add([pscustomobject]@{ id = 'pj' + (New-Id).Substring(0, 8); name = $name })
        }
    }

    # clients used by tasks but missing from the list are added (same as projects); tasks without 'client' = no client
    $beforeClientCount = $settings.clients.Count
    foreach ($name in @($tasks | ForEach-Object { ([string]$_.client).Trim() } | Where-Object { $_ } | Sort-Object -Unique)) {
        if (-not ($settings.clients | Where-Object { $_.name -ieq $name })) {
            [void]$settings.clients.Add([pscustomobject]@{ id = 'cl' + (New-Id).Substring(0, 8); name = $name })
        }
    }

    $script:State = [pscustomobject]@{
        Settings = $settings; Tasks = $tasks; History = $hist
        Warnings = $warnings; LastScoreDay = (Get-Date).Date
    }
    Update-AllScores -State $script:State
    # on first launch (or after a restore) creates the missing files
    # saves missing files and preferences schema migrations
    if ($rs.Source -ne 'main' -or $null -eq (Get-Prop $rs.Data 'language') -or
        $null -eq (Get-Prop $rs.Data 'openOnStartup') -or $null -eq (Get-Prop $rs.Data 'hideOnClose') -or
        (Get-BoundedNumber (Get-Prop $rs.Data 'preferencesVersion' 1) 1 1 2) -lt 2 -or
        $settings.referents.Count -ne $beforeReferentCount -or $settings.projects.Count -ne $beforeProjectCount -or $settings.clients.Count -ne $beforeClientCount) { Save-Settings }
    if ($rt.Source -ne 'main' -or $tasks.Count -ne @(Get-Prop $rt.Data 'tasks' @()).Count) { Save-Tasks }
    if ($rh.Source -ne 'main') { Save-History }
    return $script:State
}

function Reload-AppState {
    # Reloads everything from disk (after restore/import)
    return Initialize-AppState
}

# ------------------------------------------------------------------ History

function Add-HistoryEntry {
    param($Task, [string]$Type, [string]$Text)
    $script:State.History.Add([pscustomobject]@{
        id = New-Id; taskId = $Task.id; code = $Task.code
        at = Format-IsoDateTime (Get-Date); type = $Type; text = $Text
    })
}

function Get-TaskHistory {
    param([string]$TaskId)
    @($script:State.History | Where-Object { $_.taskId -eq $TaskId } | Sort-Object at -Descending)
}

# ------------------------------------------------------------------ Reading

function Get-TaskById { param([string]$Id) $script:State.Tasks | Where-Object { $_.id -eq $Id } | Select-Object -First 1 }

function Get-Referents {
    $names = New-Object 'System.Collections.Generic.List[string]'
    foreach ($r in @($script:State.Settings.referents)) { [void]$names.Add([string]$r.name) }
    foreach ($name in @($script:State.Tasks | ForEach-Object { $_.referent } | Where-Object { $_ })) {
        if (-not ($names | Where-Object { $_ -ieq $name })) { [void]$names.Add([string]$name) }
    }
    @($names | Sort-Object -Unique)
}

function Get-Projects {
    $names = New-Object 'System.Collections.Generic.List[string]'
    foreach ($p in @($script:State.Settings.projects)) { [void]$names.Add([string]$p.name) }
    foreach ($name in @($script:State.Tasks | ForEach-Object { $_.project } | Where-Object { $_ })) {
        if (-not ($names | Where-Object { $_ -ieq $name })) { [void]$names.Add([string]$name) }
    }
    @($names | Sort-Object -Unique)
}

function Get-Clients {
    $names = New-Object 'System.Collections.Generic.List[string]'
    foreach ($c in @($script:State.Settings.clients)) { [void]$names.Add([string]$c.name) }
    foreach ($name in @($script:State.Tasks | ForEach-Object { $_.client } | Where-Object { $_ })) {
        if (-not ($names | Where-Object { $_ -ieq $name })) { [void]$names.Add([string]$name) }
    }
    @($names | Sort-Object -Unique)
}

function Get-DashboardStats {
    $s = $script:State.Settings; $today = Get-Date
    $open = 0; $urgent = 0; $overdue = 0; $done = 0
    foreach ($t in $script:State.Tasks) {
        if (Test-StatusClosed $t.statusId $s.statuses) { $done++; continue }
        $open++
        if (Test-TaskUrgent $t $s) { $urgent++ }
        if (Test-TaskOverdue $t $s $today) { $overdue++ }
    }
    [pscustomobject]@{ Open = $open; Urgent = $urgent; Overdue = $overdue; Completed = $done; Total = $script:State.Tasks.Count }
}

# ------------------------------------------------------------------ Codes

function Get-NextTaskCode {
    $s = $script:State.Settings
    $pre = $s.codePrefix
    $max = [int]$s.nextCodeNumber - 1
    foreach ($t in $script:State.Tasks) {
        if ($t.code -match ('^' + [regex]::Escape($pre) + '-(\d+)$')) { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } }
    }
    $n = $max + 1
    while ($script:State.Tasks | Where-Object { $_.code -ieq "$pre-$n" }) { $n++ }
    return "$pre-$n"
}

# ------------------------------------------------------------------ Validation

function Test-TaskInput {
    # $In: hashtable with Code, Title, Description, Referent, Link, StatusId, PriorityId, DueDate. Returns a list of errors
    param($In, [string]$ExceptId = '')
    $err = New-Object 'System.Collections.Generic.List[string]'
    $code = ([string]$In.Code).Trim()
    if ($code -eq '') { $err.Add((T 'The code is required.')) }
    elseif ($code -notmatch '^[A-Za-z0-9][A-Za-z0-9_\-\./]{0,24}$') { $err.Add((T 'The code may contain letters, numbers and - _ . / (max 25 characters).')) }
    elseif ($script:State.Tasks | Where-Object { $_.id -ne $ExceptId -and $_.code -ieq $code }) { $err.Add((T 'The code "{0}" is already used by another task.' $code)) }
    $title = ([string]$In.Title).Trim()
    if ($title -eq '') { $err.Add((T 'The title is required.')) }
    elseif ($title.Length -gt 200) { $err.Add((T 'The title cannot exceed 200 characters.')) }
    if (([string]$In.Referent).Trim().Length -gt 80) { $err.Add((T 'The owner cannot exceed 80 characters.')) }
    if (([string]$In.Project).Trim().Length -gt 80) { $err.Add((T 'The project cannot exceed 80 characters.')) }
    if (([string]$In.Client).Trim().Length -gt 80) { $err.Add((T 'The client cannot exceed 80 characters.')) }
    if (([string]$In.Description).Length -gt 10000) { $err.Add((T 'The description is too long (max 10000 characters).')) }
    if (-not (Test-TaskLink ([string]$In.Link))) { $err.Add((T 'The link must be an absolute HTTP or HTTPS URL no longer than 2048 characters.')) }
    if (-not (Get-StatusById $In.StatusId)) { $err.Add((T 'Select a valid status.')) }
    if (-not (Get-PriorityById $In.PriorityId)) { $err.Add((T 'Select a valid priority level.')) }
    return , $err
}

function Get-DefaultTaskInput {
    $s = $script:State.Settings
    $pr = @($s.priorities | Sort-Object value)
    @{
        Code = Get-NextTaskCode; Title = ''; Description = ''; Referent = $s.userName; Project = ''; Client = ''; Link = ''
        StatusId = ($s.statuses | Where-Object { -not $_.isClosed } | Select-Object -First 1).id
        PriorityId = $pr[[int][math]::Floor(($pr.Count - 1) / 2)].id
        DueDate = $null
    }
}

# ------------------------------------------------------------------ CRUD

function Add-AppTask {
    param($In)
    $errs = Test-TaskInput $In
    if ($errs.Count -gt 0) { throw ($errs -join "`n") }
    $now = Format-IsoDateTime (Get-Date)
    $closed = Test-StatusClosed $In.StatusId $script:State.Settings.statuses
    $t = [pscustomobject]@{
        id = New-Id; code = ([string]$In.Code).Trim(); title = ([string]$In.Title).Trim()
        description = [string]$In.Description; referent = ([string]$In.Referent).Trim()
        project = ([string]$In.Project).Trim()
        client = ([string]$In.Client).Trim()
        link = ([string]$In.Link).Trim()
        statusId = $In.StatusId; priorityId = $In.PriorityId
        createdAt = $now; updatedAt = $now; dueDate = (Format-IsoDate $In.DueDate)
        reminders = 0; lastReminderAt = $null
        completedAt = $(if ($closed) { $now } else { $null }); score = $null
    }
    $script:State.Tasks.Add($t)
    if ($t.code -match ('^' + [regex]::Escape($script:State.Settings.codePrefix) + '-(\d+)$')) {
        $n = [int]$Matches[1] + 1
        if ($n -gt $script:State.Settings.nextCodeNumber) { $script:State.Settings.nextCodeNumber = $n; Save-Settings }
    }
    Add-HistoryEntry $t 'creato' (T 'Task created')
    Update-AllScores -State $script:State
    Save-Tasks; Save-History
    return $t
}

function Update-AppTask {
    param([string]$Id, $In)
    $t = Get-TaskById $Id
    if ($null -eq $t) { throw (T 'Task not found (it may have been deleted).') }
    $errs = Test-TaskInput $In $Id
    if ($errs.Count -gt 0) { throw ($errs -join "`n") }
    $s = $script:State.Settings
    $changes = New-Object 'System.Collections.Generic.List[string]'
    $new = @{
        code = ([string]$In.Code).Trim(); title = ([string]$In.Title).Trim()
        description = [string]$In.Description; referent = ([string]$In.Referent).Trim()
        link = $(if ($In.ContainsKey('Link')) { ([string]$In.Link).Trim() } else { [string]$t.link })
        # an input without 'Project' (older callers) must NOT clear the task's project
        project = $(if ($In.ContainsKey('Project')) { ([string]$In.Project).Trim() } else { ([string]$t.project).Trim() })
        client = $(if ($In.ContainsKey('Client')) { ([string]$In.Client).Trim() } else { ([string]$t.client).Trim() })
        statusId = $In.StatusId; priorityId = $In.PriorityId; dueDate = (Format-IsoDate $In.DueDate)
    }
    if ($t.code -ne $new.code) { $changes.Add((T 'Code: {0} -> {1}' $t.code $new.code)) }
    if ($t.title -ne $new.title) { $changes.Add((T 'Title changed')) }
    if ($t.description -ne $new.description) { $changes.Add((T 'Description changed')) }
    if ($t.link -ne $new.link) { $changes.Add((T 'Link changed')) }
    if ($t.referent -ne $new.referent) { $changes.Add((T 'Owner: "{0}" -> "{1}"' $t.referent $new.referent)) }
    if (([string]$t.client) -ne $new.client) { $changes.Add((T 'Client: "{0}" -> "{1}"' ([string]$t.client) $new.client)) }
    if (([string]$t.project) -ne $new.project) { $changes.Add((T 'Project: "{0}" -> "{1}"' ([string]$t.project) $new.project)) }
    $statusChanged = ($t.statusId -ne $new.statusId)
    if ($statusChanged) { $changes.Add((T 'Status: {0} -> {1}' (Get-StatusById $t.statusId).name (Get-StatusById $new.statusId).name)) }
    if ($t.priorityId -ne $new.priorityId) { $changes.Add((T 'Priority: {0} -> {1}' (Get-PriorityById $t.priorityId).name (Get-PriorityById $new.priorityId).name)) }
    if ([string]$t.dueDate -ne [string]$new.dueDate) {
        $o = $(if ($t.dueDate) { Format-AppDate $t.dueDate $s } else { (T 'none') })
        $n = $(if ($new.dueDate) { Format-AppDate $new.dueDate $s } else { (T 'none') })
        $changes.Add((T 'Due date: {0} -> {1}' $o $n))
    }
    if ($changes.Count -eq 0) { return $t }

    $wasClosed = Test-StatusClosed $t.statusId $s.statuses
    $t.code = $new.code; $t.title = $new.title; $t.description = $new.description; $t.referent = $new.referent; $t.link = $new.link
    # tasks loaded through Repair-Tasks always have 'project'; Add-Member only guards objects built by hand
    if ($null -eq $t.PSObject.Properties['project']) { $t | Add-Member -NotePropertyName project -NotePropertyValue $new.project } else { $t.project = $new.project }
    if ($null -eq $t.PSObject.Properties['client']) { $t | Add-Member -NotePropertyName client -NotePropertyValue $new.client } else { $t.client = $new.client }
    $t.statusId = $new.statusId; $t.priorityId = $new.priorityId; $t.dueDate = $new.dueDate
    $now = Format-IsoDateTime (Get-Date)
    $t.updatedAt = $now
    $isClosed = Test-StatusClosed $t.statusId $s.statuses
    if ($isClosed -and -not $wasClosed) { $t.completedAt = $now }
    if (-not $isClosed) { $t.completedAt = $null }
    Add-HistoryEntry $t $(if ($statusChanged) { 'stato' } else { 'modificato' }) ($changes -join '; ')
    Update-AllScores -State $script:State
    Save-Tasks; Save-History
    return $t
}

function Set-AppTaskStatus {
    param([string]$Id, [string]$StatusId)
    $t = Get-TaskById $Id
    if ($null -eq $t) { throw (T 'Task not found.') }
    $in = @{ Code = $t.code; Title = $t.title; Description = $t.description; Referent = $t.referent; Project = [string]$t.project; Client = [string]$t.client; Link = $t.link
             StatusId = $StatusId; PriorityId = $t.priorityId; DueDate = (ConvertTo-DateTimeValue $t.dueDate) }
    return Update-AppTask $Id $in
}

function Remove-AppTask {
    param([string]$Id)
    $t = Get-TaskById $Id
    if ($null -eq $t) { throw (T 'Task not found.') }
    New-Snapshot -Reason 'pre-delete' | Out-Null
    [void]$script:State.Tasks.Remove($t)
    # history is kept as a trace of the deletion
    Add-HistoryEntry $t 'eliminato' (T 'Task deleted: {0}' $t.title)
    Update-AllScores -State $script:State
    Save-Tasks; Save-History
}

function Remove-AppTasks {
    param([Parameter(Mandatory)][string[]]$Ids)
    $uniqueIds = @($Ids | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($uniqueIds.Count -lt 2) { throw (T 'Select at least two tasks.') }
    $tasks = New-Object 'System.Collections.Generic.List[psobject]'
    foreach ($id in $uniqueIds) {
        $task = Get-TaskById $id
        if ($null -eq $task) { throw (T 'Task not found.') }
        $tasks.Add($task)
    }

    $null = New-Snapshot -Reason 'pre-delete'
    foreach ($task in $tasks) {
        [void]$script:State.Tasks.Remove($task)
        Add-HistoryEntry $task 'eliminato' (T 'Task deleted: {0}' $task.title)
    }
    Update-AllScores -State $script:State
    Save-Tasks; Save-History
    return $tasks.Count
}

function Copy-AppTask {
    param([string]$Id)
    $t = Get-TaskById $Id
    if ($null -eq $t) { throw (T 'Task not found.') }
    $in = @{
        Code = Get-NextTaskCode; Title = (T '{0} (copy)' $t.title); Description = $t.description; Referent = $t.referent; Project = [string]$t.project; Client = [string]$t.client; Link = $t.link
        StatusId = $t.statusId; PriorityId = $t.priorityId; DueDate = (ConvertTo-DateTimeValue $t.dueDate)
    }
    $copy = Add-AppTask $in
    Add-HistoryEntry $copy 'duplicato' (T 'Duplicated from {0}' $t.code)
    Save-History
    return $copy
}

function Copy-AppTasks {
    param([Parameter(Mandatory)][string[]]$Ids)
    $uniqueIds = @($Ids | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($uniqueIds.Count -lt 2) { throw (T 'Select at least two tasks.') }
    foreach ($id in $uniqueIds) {
        if ($null -eq (Get-TaskById $id)) { throw (T 'Task not found.') }
    }
    $copies = New-Object 'System.Collections.Generic.List[psobject]'
    foreach ($id in $uniqueIds) { $copies.Add((Copy-AppTask $id)) }
    return $copies.ToArray()
}

# ------------------------------------------------------------------ Reminders

function Add-TaskReminder {
    param([string]$Id)
    $t = Get-TaskById $Id
    if ($null -eq $t) { throw (T 'Task not found.') }
    if (Test-StatusClosed $t.statusId $script:State.Settings.statuses) { throw (T 'Reminders cannot be logged on a closed task.') }
    $now = Format-IsoDateTime (Get-Date)
    $t.reminders = [int]$t.reminders + 1
    $t.lastReminderAt = $now
    $t.updatedAt = $now
    Add-HistoryEntry $t 'sollecito' (T 'Reminder #{0} logged' $t.reminders)
    Update-AllScores -State $script:State
    Save-Tasks; Save-History
    return $t
}

function Undo-TaskReminder {
    # Undoes the last reminder (misclick)
    param([string]$Id)
    $t = Get-TaskById $Id
    if ($null -eq $t) { throw (T 'Task not found.') }
    if ([int]$t.reminders -le 0) { return $t }
    $rem = @($script:State.History | Where-Object { $_.taskId -eq $Id -and $_.type -eq 'sollecito' } | Sort-Object at)
    if ($rem.Count -gt 0) { [void]$script:State.History.Remove($rem[-1]) }
    $t.reminders = [int]$t.reminders - 1
    $t.lastReminderAt = $(if ($rem.Count -gt 1) { $rem[-2].at } else { $null })
    $t.updatedAt = Format-IsoDateTime (Get-Date)
    Add-HistoryEntry $t 'modificato' (T 'Last reminder undone')
    Update-AllScores -State $script:State
    Save-Tasks; Save-History
    return $t
}
