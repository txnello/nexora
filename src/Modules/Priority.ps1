# Priority.ps1 - prioritization engine (pure functions, no UI dependencies)
#
# Score = P*wP + S*wS + L*wL + A*wA   (weights in percentage, sum = 100)
# Each factor is normalized to 0..100:
#   P  manual priority   : (value - min) / (max - min) * 100 on configured levels
#   S  deadline          : overdue = 100; today = 95; then exponential decay 95*exp(-days/decay)
#                            no deadline = configurable neutral value (noDueScore)
#   L  reminders         : 100 * (1 - exp(-n / curve))  -> increasing but saturating (never above 100)
#   A  age               : min(days_open, ageCapDays) / ageCapDays * 100 -> max cap

function Get-PriorityFactor {
    param($PriorityId, $Priorities)
    $lv = @($Priorities)
    if ($lv.Count -le 1) { return 50.0 }
    $min = ($lv | Measure-Object -Property value -Minimum).Minimum
    $max = ($lv | Measure-Object -Property value -Maximum).Maximum
    $p = $lv | Where-Object { $_.id -eq $PriorityId } | Select-Object -First 1
    if ($null -eq $p -or $max -eq $min) { return 50.0 }
    return [math]::Max(0.0, [math]::Min(100.0, (([double]$p.value - $min) / ($max - $min)) * 100.0))
}

function Get-DeadlineFactor {
    param($DueDate, [datetime]$Today, $Scoring)
    $due = ConvertTo-DateTimeValue $DueDate
    if ($null -eq $due) { return [double]$Scoring.noDueScore }
    $days = ($due.Date - $Today.Date).Days
    if ($days -lt 0) { return 100.0 }
    $decay = [math]::Max(1.0, [double]$Scoring.deadlineDecayDays)
    return [math]::Min(95.0, 95.0 * [math]::Exp(-$days / $decay))
}

function Get-ReminderFactor {
    param([int]$Count, $Scoring)
    if ($Count -le 0) { return 0.0 }
    $curve = [math]::Max(0.5, [double]$Scoring.reminderCurve)
    return 100.0 * (1.0 - [math]::Exp(-$Count / $curve))
}

function Get-AgeFactor {
    param($CreatedAt, [datetime]$Today, $Scoring)
    $c = ConvertTo-DateTimeValue $CreatedAt
    if ($null -eq $c) { return 0.0 }
    $cap = [math]::Max(1.0, [double]$Scoring.ageCapDays)
    $days = [math]::Max(0.0, ($Today.Date - $c.Date).TotalDays)
    return [math]::Min(100.0, ($days / $cap) * 100.0)
}

function Get-ScoreBreakdown {
    param($Task, $Settings, [datetime]$Today = (Get-Date))
    $sc = $Settings.scoring
    $w = $sc.weights
    $p = Get-PriorityFactor -PriorityId $Task.priorityId -Priorities $Settings.priorities
    $s = Get-DeadlineFactor -DueDate $Task.dueDate -Today $Today -Scoring $sc
    $l = Get-ReminderFactor -Count ([int]$Task.reminders) -Scoring $sc
    $a = Get-AgeFactor -CreatedAt $Task.createdAt -Today $Today -Scoring $sc
    $total = ($p * $w.priority + $s * $w.deadline + $l * $w.reminders + $a * $w.age) / 100.0
    $total = [math]::Max(0.0, [math]::Min(100.0, $total))
    [pscustomobject]@{
        Priority  = [math]::Round($p, 1)
        Deadline  = [math]::Round($s, 1)
        Reminders = [math]::Round($l, 1)
        Age       = [math]::Round($a, 1)
        Total     = [math]::Round($total, 1)
    }
}

function Get-TaskScore {
    param($Task, $Settings, [datetime]$Today = (Get-Date))
    (Get-ScoreBreakdown -Task $Task -Settings $Settings -Today $Today).Total
}

function Test-StatusClosed {
    param($StatusId, $Statuses)
    $st = @($Statuses) | Where-Object { $_.id -eq $StatusId } | Select-Object -First 1
    if ($null -eq $st) { return $false }
    return [bool]$st.isClosed
}

function Test-TaskUrgent {
    # Urgent = open task with highest manual priority OR score above threshold
    param($Task, $Settings)
    if (Test-StatusClosed $Task.statusId $Settings.statuses) { return $false }
    $lv = @($Settings.priorities)
    if ($lv.Count -gt 1) {
        $max = ($lv | Measure-Object -Property value -Maximum).Maximum
        $p = $lv | Where-Object { $_.id -eq $Task.priorityId } | Select-Object -First 1
        if ($null -ne $p -and [double]$p.value -ge $max) { return $true }
    }
    return ($null -ne $Task.score -and [double]$Task.score -ge [double]$Settings.scoring.urgentThreshold)
}

function Test-TaskOverdue {
    param($Task, $Settings, [datetime]$Today = (Get-Date))
    if (Test-StatusClosed $Task.statusId $Settings.statuses) { return $false }
    $due = ConvertTo-DateTimeValue $Task.dueDate
    if ($null -eq $due) { return $false }
    return ($due.Date -lt $Today.Date)
}

function Update-AllScores {
    # Recomputes the score of all tasks; completed tasks are excluded from the ranking (score = null)
    param($State, [datetime]$Today = (Get-Date))
    foreach ($t in $State.Tasks) {
        if (Test-StatusClosed $t.statusId $State.Settings.statuses) { $t.score = $null }
        else { $t.score = Get-TaskScore -Task $t -Settings $State.Settings -Today $Today }
    }
    $State.LastScoreDay = $Today.Date
}
