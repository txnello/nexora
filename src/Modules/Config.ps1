# Config.ps1 - settings: defaults, repair, referents, statuses, priorities, weights, date format

$script:DefaultNames = @{
    en = @{ todo = 'To do'; doing = 'In progress'; waiting = 'Waiting'; blocked = 'Blocked'; done = 'Done'
            low = 'Low'; medium = 'Medium'; high = 'High'; urgent = 'Urgent' }
    it = @{ todo = 'Da fare'; doing = 'In lavorazione'; waiting = 'In attesa'; blocked = 'Bloccato'; done = 'Completato'
            low = 'Bassa'; medium = 'Media'; high = 'Alta'; urgent = 'Urgente' }
}

function Convert-DefaultNames {
    # Translates the default status/priority names (only if not customized by the user)
    param($Settings, [string]$Lang)
    $target = $script:DefaultNames[$Lang]
    foreach ($item in (@($Settings.statuses) + @($Settings.priorities))) {
        if ($target.ContainsKey($item.id)) {
            foreach ($l in @($script:DefaultNames.Keys)) {
                if ($l -ne $Lang -and $item.name -ieq $script:DefaultNames[$l][$item.id]) { $item.name = $target[$item.id] }
            }
        }
    }
}

function Get-DateFormats { @('dd/MM/yyyy', 'yyyy-MM-dd', 'MM/dd/yyyy', 'dd MMM yyyy', 'd MMMM yyyy') }

function Get-ColorPalette {
    @('#6B7280', '#3B82F6', '#06B6D4', '#10B981', '#84CC16', '#EAB308',
      '#F59E0B', '#F97316', '#EF4444', '#EC4899', '#8B5CF6', '#6366F1')
}

function Get-DefaultSettings {
    [pscustomobject]@{
        version        = 1
        referents      = ConvertTo-List @()
        projects       = ConvertTo-List @()
        statuses       = ConvertTo-List @(
            [pscustomobject]@{ id = 'todo';    name = 'To do';        color = '#6B7280'; isClosed = $false }
            [pscustomobject]@{ id = 'doing';   name = 'In progress'; color = '#3B82F6'; isClosed = $false }
            [pscustomobject]@{ id = 'waiting'; name = 'Waiting';      color = '#F59E0B'; isClosed = $false }
            [pscustomobject]@{ id = 'blocked'; name = 'Blocked';       color = '#EF4444'; isClosed = $false }
            [pscustomobject]@{ id = 'done';    name = 'Done';     color = '#10B981'; isClosed = $true }
        )
        priorities     = ConvertTo-List @(
            [pscustomobject]@{ id = 'low';    name = 'Low';   value = 1; color = '#6B7280' }
            [pscustomobject]@{ id = 'medium'; name = 'Medium';   value = 2; color = '#3B82F6' }
            [pscustomobject]@{ id = 'high';   name = 'High';    value = 3; color = '#F97316' }
            [pscustomobject]@{ id = 'urgent'; name = 'Urgent'; value = 4; color = '#EF4444' }
        )
        scoring        = [pscustomobject]@{
            weights           = [pscustomobject]@{ priority = 35; deadline = 35; reminders = 20; age = 10 }
            noDueScore        = 40
            ageCapDays        = 90
            urgentThreshold   = 70
            deadlineDecayDays = 9
            reminderCurve     = 3
        }
        language       = 'en'
        lastRunVersion = ''
        theme          = 'dark'
        dateFormat     = 'dd/MM/yyyy'
        codePrefix     = 'TSK'
        nextCodeNumber = 1001
        userName       = ''
        maxBackups     = 30
        openOnStartup  = $true
        hideOnClose    = $true
        preferencesVersion = 2
    }
}

function Get-BoundedNumber {
    param($Value, [double]$Default, [double]$Min, [double]$Max)
    $n = 0.0
    if ($null -ne $Value -and [double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, $script:Inv, [ref]$n)) {
        return [math]::Max($Min, [math]::Min($Max, $n))
    }
    return $Default
}

function Get-NormalizedWeights {
    # Rounds 4 weights to integers summing exactly to 100 (largest remainder method)
    param([double[]]$Weights)
    $w = @($Weights | ForEach-Object { [math]::Max(0.0, $_) })
    $sum = ($w | Measure-Object -Sum).Sum
    if ($sum -le 0) { return @(35, 35, 20, 10) }
    $scaled = @($w | ForEach-Object { $_ * 100.0 / $sum })
    $floor = @($scaled | ForEach-Object { [int][math]::Floor($_) })
    $rest = 100 - ($floor | Measure-Object -Sum).Sum
    $order = 0..3 | Sort-Object { -($scaled[$_] - $floor[$_]) }
    for ($i = 0; $i -lt $rest; $i++) { $floor[$order[$i]]++ }
    return $floor
}

function Repair-Settings {
    # Merges the data read from disk with the defaults, discarding invalid values
    param($Raw)
    $d = Get-DefaultSettings
    if ($null -eq $Raw) { return $d }

    # configurable referents
    $refs = New-Object 'System.Collections.Generic.List[psobject]'
    $seenRefs = @{}
    foreach ($r in @(Get-Prop $Raw 'referents' @())) {
        $name = ([string](Get-Prop $r 'name' '')).Trim()
        if ($name -eq '' -or $seenRefs.ContainsKey($name.ToLowerInvariant())) { continue }
        $seenRefs[$name.ToLowerInvariant()] = $true
        $id = [string](Get-Prop $r 'id' '')
        if ($id -eq '') { $id = 'rf' + (New-Id).Substring(0, 8) }
        $refs.Add([pscustomobject]@{ id = $id; name = $name })
    }
    $d.referents = $refs

    # configurable projects (optional: settings written by versions before 1.0.5 have no 'projects' key -> empty list)
    $projs = New-Object 'System.Collections.Generic.List[psobject]'
    $seenProjs = @{}
    foreach ($p in @(Get-Prop $Raw 'projects' @())) {
        $name = ([string](Get-Prop $p 'name' '')).Trim()
        if ($name -eq '' -or $seenProjs.ContainsKey($name.ToLowerInvariant())) { continue }
        $seenProjs[$name.ToLowerInvariant()] = $true
        $id = [string](Get-Prop $p 'id' '')
        if ($id -eq '') { $id = 'pj' + (New-Id).Substring(0, 8) }
        $projs.Add([pscustomobject]@{ id = $id; name = $name })
    }
    $d.projects = $projs

    # statuses
    $st = New-Object 'System.Collections.Generic.List[psobject]'
    $seen = @{}
    foreach ($s in @(Get-Prop $Raw 'statuses' @())) {
        $id = [string](Get-Prop $s 'id' ''); $name = ([string](Get-Prop $s 'name' '')).Trim()
        if ($id -eq '' -or $name -eq '' -or $seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        $col = [string](Get-Prop $s 'color' '#6B7280'); if (-not (Test-HexColor $col)) { $col = '#6B7280' }
        $st.Add([pscustomobject]@{ id = $id; name = $name; color = $col.ToUpper(); isClosed = [bool](Get-Prop $s 'isClosed' $false) })
    }
    if ($st.Count -eq 0) { $st = $d.statuses }
    if (-not ($st | Where-Object { -not $_.isClosed })) { $st[0].isClosed = $false }
    $d.statuses = $st

    # priorities
    $pr = New-Object 'System.Collections.Generic.List[psobject]'
    $seen = @{}
    foreach ($p in @(Get-Prop $Raw 'priorities' @())) {
        $id = [string](Get-Prop $p 'id' ''); $name = ([string](Get-Prop $p 'name' '')).Trim()
        if ($id -eq '' -or $name -eq '' -or $seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        $col = [string](Get-Prop $p 'color' '#6B7280'); if (-not (Test-HexColor $col)) { $col = '#6B7280' }
        $pr.Add([pscustomobject]@{ id = $id; name = $name; value = (Get-BoundedNumber (Get-Prop $p 'value' 1) 1 -1000 1000); color = $col.ToUpper() })
    }
    if ($pr.Count -eq 0) { $pr = $d.priorities }
    $d.priorities = $pr

    # scoring
    $rs = Get-Prop $Raw 'scoring' $null
    if ($null -ne $rs) {
        $rw = Get-Prop $rs 'weights' $null
        if ($null -ne $rw) {
            $arr = @(
                (Get-BoundedNumber (Get-Prop $rw 'priority' 35) 35 0 100),
                (Get-BoundedNumber (Get-Prop $rw 'deadline' 35) 35 0 100),
                (Get-BoundedNumber (Get-Prop $rw 'reminders' 20) 20 0 100),
                (Get-BoundedNumber (Get-Prop $rw 'age' 10) 10 0 100))
            $n = Get-NormalizedWeights $arr
            $d.scoring.weights = [pscustomobject]@{ priority = $n[0]; deadline = $n[1]; reminders = $n[2]; age = $n[3] }
        }
        $d.scoring.noDueScore = Get-BoundedNumber (Get-Prop $rs 'noDueScore' 40) 40 0 100
        $d.scoring.ageCapDays = Get-BoundedNumber (Get-Prop $rs 'ageCapDays' 90) 90 1 3650
        $d.scoring.urgentThreshold = Get-BoundedNumber (Get-Prop $rs 'urgentThreshold' 70) 70 1 100
        $d.scoring.deadlineDecayDays = Get-BoundedNumber (Get-Prop $rs 'deadlineDecayDays' 9) 9 1 365
        $d.scoring.reminderCurve = Get-BoundedNumber (Get-Prop $rs 'reminderCurve' 3) 3 0.5 50
    }

    $d.lastRunVersion = [string](Get-Prop $Raw 'lastRunVersion' '')
    $lang = [string](Get-Prop $Raw 'language' 'en'); if ($lang -in @('en', 'it')) { $d.language = $lang }
    Convert-DefaultNames $d $d.language
    $theme = [string](Get-Prop $Raw 'theme' 'dark'); if ($theme -in @('dark', 'light')) { $d.theme = $theme }
    $fmt = [string](Get-Prop $Raw 'dateFormat' 'dd/MM/yyyy'); if ((Get-DateFormats) -contains $fmt) { $d.dateFormat = $fmt }
    $pre = ([string](Get-Prop $Raw 'codePrefix' 'TSK')).Trim().ToUpper()
    if ($pre -match '^[A-Z0-9]{1,10}$') { $d.codePrefix = $pre }
    $d.nextCodeNumber = [int](Get-BoundedNumber (Get-Prop $Raw 'nextCodeNumber' 1001) 1001 1 99999999)
    $d.userName = ([string](Get-Prop $Raw 'userName' '')).Trim()
    $d.maxBackups = [int](Get-BoundedNumber (Get-Prop $Raw 'maxBackups' 30) 30 5 500)
    $d.openOnStartup = [bool](Get-Prop $Raw 'openOnStartup' $true)
    $preferencesVersion = Get-BoundedNumber (Get-Prop $Raw 'preferencesVersion' 1) 1 1 2
    $d.hideOnClose = if ($preferencesVersion -lt 2) { $true } else { [bool](Get-Prop $Raw 'hideOnClose' $true) }
    $d.preferencesVersion = 2
    return $d
}

# ------------------------------------------------------------------ Date

function Format-AppDate {
    param($Value, $Settings)
    $d = ConvertTo-DateTimeValue $Value
    if ($null -eq $d) { return '' }
    $fmt = 'dd/MM/yyyy'
    if ($null -ne $Settings) { $fmt = $Settings.dateFormat }
    return $d.ToString($fmt, $script:UiCulture)
}

function ConvertFrom-AppDate {
    # Parses the text entered by the user; $null if invalid
    param([string]$Text, $Settings)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $formats = @()
    if ($null -ne $Settings) { $formats += $Settings.dateFormat }
    $formats += @('dd/MM/yyyy', 'd/M/yyyy', 'yyyy-MM-dd', 'dd-MM-yyyy', 'dd.MM.yyyy', 'd MMMM yyyy', 'dd MMM yyyy')
    $d = [datetime]::MinValue
    if ([datetime]::TryParseExact($Text.Trim(), [string[]]$formats, $script:UiCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { return $d.Date }
    return $null
}

function Format-DueHint {
    # Relative text: today, tomorrow, in 5 days, overdue by 3 days
    param($DueDate, [datetime]$Today = (Get-Date))
    $due = ConvertTo-DateTimeValue $DueDate
    if ($null -eq $due) { return '' }
    $n = ($due.Date - $Today.Date).Days
    if ($n -eq 0) { return (T 'today') }
    if ($n -eq 1) { return (T 'tomorrow') }
    if ($n -eq -1) { return (T 'overdue by 1 day') }
    if ($n -lt 0) { return (T 'overdue by {0} days' (-$n)) }
    return (T 'in {0} days' $n)
}

# ------------------------------------------------------------------ Statuses

function Get-StatusById { param($Id) $script:State.Settings.statuses | Where-Object { $_.id -eq $Id } | Select-Object -First 1 }
function Get-PriorityById { param($Id) $script:State.Settings.priorities | Where-Object { $_.id -eq $Id } | Select-Object -First 1 }
function Get-ReferentById { param($Id) $script:State.Settings.referents | Where-Object { $_.id -eq $Id } | Select-Object -First 1 }
function Get-ProjectById { param($Id) $script:State.Settings.projects | Where-Object { $_.id -eq $Id } | Select-Object -First 1 }

function Assert-ValidName {
    param([string]$Name, $List, [string]$ExceptId, [string]$Kind)
    $n = $Name.Trim()
    if ($n.Length -eq 0) { throw (T 'The name is required.') }
    if ($n.Length -gt 40) { throw (T 'The name cannot exceed 40 characters.') }
    if ($List | Where-Object { $_.id -ne $ExceptId -and $_.name -ieq $n }) {
        if ($Kind -eq 'status') { throw (T 'A status named "{0}" already exists.' $n) }
        throw (T 'A priority level named "{0}" already exists.' $n)
    }
}

function Add-Status {
    param([string]$Name, [string]$Color = '#6B7280', [bool]$IsClosed = $false)
    $sts = $script:State.Settings.statuses
    Assert-ValidName $Name $sts '' 'status'
    if (-not (Test-HexColor $Color)) { throw (T 'Invalid color (use the #RRGGBB format).') }
    $s = [pscustomobject]@{ id = 'st' + (New-Id).Substring(0, 8); name = $Name.Trim(); color = $Color.ToUpper(); isClosed = $IsClosed }
    $sts.Add($s)
    Save-Settings; Update-AllScoresAndSave
    return $s
}

function Update-Status {
    param([string]$Id, [string]$Name, [string]$Color, [bool]$IsClosed)
    $sts = $script:State.Settings.statuses
    $s = Get-StatusById $Id
    if ($null -eq $s) { throw (T 'Status not found.') }
    Assert-ValidName $Name $sts $Id 'status'
    if (-not (Test-HexColor $Color)) { throw (T 'Invalid color (use the #RRGGBB format).') }
    if (-not $s.isClosed -and $IsClosed) {
        if (-not ($sts | Where-Object { $_.id -ne $Id -and -not $_.isClosed })) { throw (T 'There must be at least one open status.') }
    }
    $wasClosed = [bool]$s.isClosed
    $s.name = $Name.Trim(); $s.color = $Color.ToUpper(); $s.isClosed = $IsClosed
    if ($wasClosed -ne $IsClosed) {
        # aligns the completion date of tasks in this status
        foreach ($t in $script:State.Tasks) {
            if ($t.statusId -eq $Id) {
                if ($IsClosed -and -not $t.completedAt) { $t.completedAt = Format-IsoDateTime (Get-Date) }
                if (-not $IsClosed) { $t.completedAt = $null }
            }
        }
    }
    Save-Settings; Update-AllScoresAndSave
}

function Remove-Status {
    # Returns the number of tasks moved to the replacement status
    param([string]$Id)
    $sts = $script:State.Settings.statuses
    $s = Get-StatusById $Id
    if ($null -eq $s) { throw (T 'Status not found.') }
    if ($sts.Count -le 1) { throw (T 'You cannot delete the last status.') }
    $others = @($sts | Where-Object { $_.id -ne $Id })
    if (-not ($others | Where-Object { -not $_.isClosed })) { throw (T 'There must be at least one open status.') }
    $target = $others | Where-Object { $_.isClosed -eq $s.isClosed } | Select-Object -First 1
    if ($null -eq $target) { $target = $others | Select-Object -First 1 }
    New-Snapshot -Reason 'pre-delete-status' | Out-Null
    $moved = 0
    foreach ($t in $script:State.Tasks) {
        if ($t.statusId -eq $Id) {
            $t.statusId = $target.id; $moved++
            if ($target.isClosed -and -not $t.completedAt) { $t.completedAt = Format-IsoDateTime (Get-Date) }
            if (-not $target.isClosed) { $t.completedAt = $null }
        }
    }
    [void]$sts.Remove($s)
    Save-Settings; Update-AllScoresAndSave
    return [pscustomobject]@{ Moved = $moved; TargetName = $target.name }
}

function Move-Status {
    param([string]$Id, [int]$Direction)
    $sts = $script:State.Settings.statuses
    $s = Get-StatusById $Id
    if ($null -eq $s) { return }
    $i = $sts.IndexOf($s); $j = $i + $Direction
    if ($j -lt 0 -or $j -ge $sts.Count) { return }
    $sts.RemoveAt($i); $sts.Insert($j, $s)
    Save-Settings
}

# ------------------------------------------------------------------ Owners

function Assert-ValidReferentName {
    param([string]$Name, [string]$ExceptId = '')
    $n = $Name.Trim()
    if ($n.Length -eq 0) { throw (T 'The name is required.') }
    if ($n.Length -gt 80) { throw (T 'The owner cannot exceed 80 characters.') }
    if ($script:State.Settings.referents | Where-Object { $_.id -ne $ExceptId -and $_.name -ieq $n }) {
        throw (T 'An owner named "{0}" already exists.' $n)
    }
}

function Add-Referent {
    param([string]$Name)
    Assert-ValidReferentName $Name
    $r = [pscustomobject]@{ id = 'rf' + (New-Id).Substring(0, 8); name = $Name.Trim() }
    $script:State.Settings.referents.Add($r)
    Save-Settings
    return $r
}

function Update-Referent {
    param([string]$Id, [string]$Name)
    $r = Get-ReferentById $Id
    if ($null -eq $r) { throw (T 'Owner not found.') }
    Assert-ValidReferentName $Name $Id
    $oldName = $r.name
    $r.name = $Name.Trim()
    foreach ($t in $script:State.Tasks) {
        if ($t.referent -ieq $oldName) { $t.referent = $r.name }
    }
    Save-Settings; Save-Tasks
}

function Remove-Referent {
    param([string]$Id)
    $refs = $script:State.Settings.referents
    $r = Get-ReferentById $Id
    if ($null -eq $r) { throw (T 'Owner not found.') }
    $others = @($refs | Where-Object { $_.id -ne $Id })
    $target = if ($others.Count -gt 0) { $others[0].name } else { '' }
    New-Snapshot -Reason 'pre-delete-owner' | Out-Null
    $moved = 0
    foreach ($t in $script:State.Tasks) {
        if ($t.referent -ieq $r.name) { $t.referent = $target; $moved++ }
    }
    [void]$refs.Remove($r)
    Save-Settings; Save-Tasks
    return [pscustomobject]@{ Moved = $moved; TargetName = $target }
}

function Move-Referent {
    param([string]$Id, [int]$Direction)
    $refs = $script:State.Settings.referents
    $r = Get-ReferentById $Id
    if ($null -eq $r) { return }
    $i = $refs.IndexOf($r); $j = $i + $Direction
    if ($j -lt 0 -or $j -ge $refs.Count) { return }
    $refs.RemoveAt($i); $refs.Insert($j, $r)
    Save-Settings
}

# ------------------------------------------------------------------ Projects
# Same model as the owners: the list lives in settings.projects, tasks store the project NAME in task.project
# (empty string = no project). Deleting a project never deletes tasks: they go back to "no project".

function Assert-ValidProjectName {
    param([string]$Name, [string]$ExceptId = '')
    $n = $Name.Trim()
    if ($n.Length -eq 0) { throw (T 'The name is required.') }
    if ($n.Length -gt 80) { throw (T 'The project cannot exceed 80 characters.') }
    if ($script:State.Settings.projects | Where-Object { $_.id -ne $ExceptId -and $_.name -ieq $n }) {
        throw (T 'A project named "{0}" already exists.' $n)
    }
}

function Add-Project {
    param([string]$Name)
    Assert-ValidProjectName $Name
    $p = [pscustomobject]@{ id = 'pj' + (New-Id).Substring(0, 8); name = $Name.Trim() }
    $script:State.Settings.projects.Add($p)
    Save-Settings
    return $p
}

function Update-Project {
    param([string]$Id, [string]$Name)
    $p = Get-ProjectById $Id
    if ($null -eq $p) { throw (T 'Project not found.') }
    Assert-ValidProjectName $Name $Id
    $oldName = $p.name
    $p.name = $Name.Trim()
    foreach ($t in $script:State.Tasks) {
        if ($t.project -ieq $oldName) { $t.project = $p.name }
    }
    Save-Settings; Save-Tasks
}

function Remove-Project {
    param([string]$Id)
    $projs = $script:State.Settings.projects
    $p = Get-ProjectById $Id
    if ($null -eq $p) { throw (T 'Project not found.') }
    New-Snapshot -Reason 'pre-delete-project' | Out-Null
    $moved = 0
    foreach ($t in $script:State.Tasks) {
        if ($t.project -ieq $p.name) { $t.project = ''; $moved++ }
    }
    [void]$projs.Remove($p)
    Save-Settings; Save-Tasks
    return [pscustomobject]@{ Moved = $moved }
}

function Move-Project {
    param([string]$Id, [int]$Direction)
    $projs = $script:State.Settings.projects
    $p = Get-ProjectById $Id
    if ($null -eq $p) { return }
    $i = $projs.IndexOf($p); $j = $i + $Direction
    if ($j -lt 0 -or $j -ge $projs.Count) { return }
    $projs.RemoveAt($i); $projs.Insert($j, $p)
    Save-Settings
}

# ------------------------------------------------------------------ Priorities

function Add-PriorityLevel {
    param([string]$Name, [double]$Value, [string]$Color = '#6B7280')
    $pr = $script:State.Settings.priorities
    Assert-ValidName $Name $pr '' 'priority'
    if (-not (Test-HexColor $Color)) { throw (T 'Invalid color (use the #RRGGBB format).') }
    $p = [pscustomobject]@{ id = 'pr' + (New-Id).Substring(0, 8); name = $Name.Trim(); value = $Value; color = $Color.ToUpper() }
    $pr.Add($p)
    Save-Settings; Update-AllScoresAndSave
    return $p
}

function Update-PriorityLevel {
    param([string]$Id, [string]$Name, [double]$Value, [string]$Color)
    $pr = $script:State.Settings.priorities
    $p = Get-PriorityById $Id
    if ($null -eq $p) { throw (T 'Priority level not found.') }
    Assert-ValidName $Name $pr $Id 'priority'
    if (-not (Test-HexColor $Color)) { throw (T 'Invalid color (use the #RRGGBB format).') }
    $p.name = $Name.Trim(); $p.value = $Value; $p.color = $Color.ToUpper()
    Save-Settings; Update-AllScoresAndSave
}

function Remove-PriorityLevel {
    param([string]$Id)
    $pr = $script:State.Settings.priorities
    $p = Get-PriorityById $Id
    if ($null -eq $p) { throw (T 'Priority level not found.') }
    if ($pr.Count -le 1) { throw (T 'You cannot delete the last priority level.') }
    # tasks are moved to the level with the nearest value
    $target = $pr | Where-Object { $_.id -ne $Id } | Sort-Object { [math]::Abs([double]$_.value - [double]$p.value) } | Select-Object -First 1
    New-Snapshot -Reason 'pre-delete-priority' | Out-Null
    $moved = 0
    foreach ($t in $script:State.Tasks) { if ($t.priorityId -eq $Id) { $t.priorityId = $target.id; $moved++ } }
    [void]$pr.Remove($p)
    Save-Settings; Update-AllScoresAndSave
    return [pscustomobject]@{ Moved = $moved; TargetName = $target.name }
}

# ------------------------------------------------------------------ Weights and other settings

function Set-ScoringWeights {
    # Accepts 4 values and normalizes them so the sum is always 100
    param([double]$Priority, [double]$Deadline, [double]$Reminders, [double]$Age)
    $n = Get-NormalizedWeights @($Priority, $Deadline, $Reminders, $Age)
    $script:State.Settings.scoring.weights = [pscustomobject]@{ priority = $n[0]; deadline = $n[1]; reminders = $n[2]; age = $n[3] }
    Save-Settings; Update-AllScoresAndSave
}

function Set-ScoringParameters {
    param([double]$NoDueScore, [double]$AgeCapDays, [double]$UrgentThreshold)
    $sc = $script:State.Settings.scoring
    $sc.noDueScore = Get-BoundedNumber $NoDueScore 40 0 100
    $sc.ageCapDays = Get-BoundedNumber $AgeCapDays 90 1 3650
    $sc.urgentThreshold = Get-BoundedNumber $UrgentThreshold 70 1 100
    Save-Settings; Update-AllScoresAndSave
}

function Reset-ScoringDefaults {
    $script:State.Settings.scoring = (Get-DefaultSettings).scoring
    Save-Settings; Update-AllScoresAndSave
}

function Set-AppStartupPreferences {
    param(
        [bool]$OpenOnStartup = $script:State.Settings.openOnStartup,
        [bool]$HideOnClose = $script:State.Settings.hideOnClose
    )
    $s = $script:State.Settings
    $startupChanged = ($OpenOnStartup -ne [bool]$s.openOnStartup)
    $s.openOnStartup = $OpenOnStartup
    $s.hideOnClose = $HideOnClose
    $s.preferencesVersion = 2
    Save-Settings
    if ($startupChanged) { Set-StartupRegistration -Enabled $OpenOnStartup }
}

function Set-AppPreferences {
    param(
        [string]$Theme, [string]$DateFormat, [string]$CodePrefix, [string]$UserName, [int]$MaxBackups, [string]$Language = '',
        [bool]$OpenOnStartup = $script:State.Settings.openOnStartup,
        [bool]$HideOnClose = $script:State.Settings.hideOnClose
    )
    $s = $script:State.Settings
    if ($Theme -notin @('dark', 'light')) { throw (T 'Invalid theme.') }
    if ((Get-DateFormats) -notcontains $DateFormat) { throw (T 'Invalid date format.') }
    $pre = $CodePrefix.Trim().ToUpper()
    if ($pre -notmatch '^[A-Z0-9]{1,10}$') { throw (T 'The code prefix must be 1-10 alphanumeric characters (A-Z, 0-9).') }
    if ($Language -eq '') { $Language = $s.language }
    if ($Language -notin @('en', 'it')) { throw (T 'Invalid language.') }
    if ($Language -ne $s.language) { $s.language = $Language; Convert-DefaultNames $s $Language }
    $s.theme = $Theme; $s.dateFormat = $DateFormat; $s.codePrefix = $pre
    $s.userName = $UserName.Trim()
    $s.maxBackups = [math]::Max(5, [math]::Min(500, $MaxBackups))
    Set-AppStartupPreferences -OpenOnStartup $OpenOnStartup -HideOnClose $HideOnClose
}
