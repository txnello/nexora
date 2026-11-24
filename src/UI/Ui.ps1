# Ui.ps1 - main window logic (code-behind). Business logic is in src/Modules.

$script:Win = $null
$script:Ui = $null
$script:View = 'dashboard'
$script:Quick = ''
$script:ManualSort = $false
$script:Updating = $false
$script:WUpd = $false
$script:LoadingSettings = $false
$script:Tray = $null
$script:ActivationEvent = $null
$script:ActivationTimer = $null
$script:ExitRequested = $false
$script:ReplacingMainWindow = $false

$script:MainNames = @(
    'colSide', 'txtBrand', 'btnTheme', 'lblTheme', 'btnAbout', 'lblAbout', 'btnDonate', 'lblDonate', 'navDashboard', 'navAll', 'navMine', 'navByRef', 'navDone', 'navSettings',
    'lblDashboard', 'lblAll', 'lblMine', 'lblByRef', 'lblDone', 'lblSettings', 'btnNew', 'txtTitle', 'txtSubtitle', 'statsPanel',
    'cardOpen', 'cardUrgent', 'cardOverdue', 'cardDone', 'txtOpen', 'txtUrgent', 'txtOverdue', 'txtDone', 'filterPanel', 'txtSearch', 'searchHint',
    'cmbStatus', 'cmbPriority', 'cmbReferent', 'btnClear', 'btnEdit', 'btnReminder', 'btnDuplicate', 'btnDelete', 'tableCard', 'txtInfo', 'grid',
    'emptyState', 'emptyIcon', 'emptyTitle', 'emptyText', 'btnEmptyNew', 'settingsView', 'lstStatuses', 'btnStAdd', 'btnStEdit', 'btnStDel',
    'btnStUp', 'btnStDown', 'lstPriorities', 'btnPrAdd', 'btnPrEdit', 'btnPrDel', 'lstReferents', 'btnRfAdd', 'btnRfEdit', 'btnRfDel', 'btnRfUp', 'btnRfDown', 'sldPriority', 'sldDeadline', 'sldReminders', 'sldAge',
    'valPriority', 'valDeadline', 'valReminders', 'valAge', 'txtWeightSum', 'txtNoDue', 'txtAgeCap', 'txtUrgent2', 'txtParamsError', 'btnParamsSave', 'btnWeightsReset',
    'cmbLanguage', 'cmbTheme', 'cmbDateFormat', 'txtPrefix', 'txtUserName', 'txtMaxBackups', 'txtPrefError', 'btnPrefSave', 'btnWebsiteSettings', 'txtDataPath', 'chkMoveData',
    'chkOpenOnStartup', 'chkHideOnClose', 'lstBackups', 'btnBkNow', 'btnBkRestore', 'btnBkExport', 'btnBkImport', 'btnChangeDataFolder', 'btnBkOpen', 'toast', 'toastIcon', 'toastText'
)

# table columns (indices)
$script:ColBulk = 0; $script:ColCode = 1; $script:ColTitle = 2; $script:ColReferent = 3; $script:ColStatus = 4
$script:ColPriority = 5; $script:ColDue = 6; $script:ColReminders = 7; $script:ColScore = 8; $script:ColCompleted = 9; $script:ColLink = 10

# ------------------------------------------------------------------ Utilities

function Get-Ancestor {
    param($Element, [type]$Type)
    $e = $Element
    while ($null -ne $e) {
        if ($Type.IsInstanceOfType($e)) { return $e }
        if ($e -is [System.Windows.Media.Visual] -or $e -is [System.Windows.Media.Media3D.Visual3D]) { $e = [System.Windows.Media.VisualTreeHelper]::GetParent($e) }
        else { $e = [System.Windows.LogicalTreeHelper]::GetParent($e) }
    }
    return $null
}

function Show-Toast {
    param([string]$Text, [switch]$Error)
    $u = $script:Ui
    $u.toastText.Text = $Text
    if ($Error) { $u.toastIcon.Text = [string][char]0xE783; $u.toastIcon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'DangerBrush') }
    else { $u.toastIcon.Text = [string][char]0xE73E; $u.toastIcon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'OkBrush') }
    $u.toast.Visibility = 'Visible'
    $script:ToastTimer.Stop(); $script:ToastTimer.Start()
}

function Get-ScoreColorHex {
    param([double]$Score, [bool]$Closed)
    if ($Closed) { return '#6B7280' }
    if ($Score -ge 70) { return '#EF4444' }
    if ($Score -ge 50) { return '#F59E0B' }
    if ($Score -ge 30) { return '#6E7DFF' }
    return '#6B7280'
}

# ------------------------------------------------------------------ Table rows

function New-RowContext {
    $s = $script:State.Settings
    $ctx = @{ Settings = $s; Today = (Get-Date); Status = @{}; StatusIdx = @{}; Prio = @{} }
    $i = 0
    foreach ($x in $s.statuses) { $ctx.Status[$x.id] = $x; $ctx.StatusIdx[$x.id] = $i++ }
    foreach ($p in $s.priorities) { $ctx.Prio[$p.id] = $p }
    return $ctx
}

function New-TaskRow {
    param($t, $ctx)
    $s = $ctx.Settings
    $r = New-Object TaskRow
    $stt = $ctx.Status[$t.statusId]; $prr = $ctx.Prio[$t.priorityId]
    $closed = ($null -ne $stt -and [bool]$stt.isClosed)
    $r.Id = $t.id; $r.Code = $t.code; $r.Title = $t.title; $r.Description = $t.description; $r.Link = [string]$t.link
    $r.LinkCommand = $script:OpenTaskLinkCommand
    $first = ([string]$t.description -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if ($first -and $first.Length -gt 110) { $first = $first.Substring(0, 110) + '…' }
    $r.Snippet = [string]$first
    $r.Referent = $(if ($t.referent) { $t.referent } else { '—' })
    $r.Group = $(if ($t.referent) { $t.referent } else { (T '(no owner)') })
    $r.StatusName = $stt.name; $r.StatusColor = $stt.color; $r.StatusBg = ConvertTo-TintHex $stt.color; $r.StatusOrder = $ctx.StatusIdx[$t.statusId]
    $r.PriorityName = $prr.name; $r.PriorityColor = $prr.color; $r.PriorityBg = ConvertTo-TintHex $prr.color; $r.PriorityValue = [double]$prr.value
    $due = ConvertTo-DateTimeValue $t.dueDate
    if ($due) {
        $r.DueText = Format-AppDate $due $s
        $r.DueHint = $(if ($closed) { '' } else { Format-DueHint $due $ctx.Today })
        $r.DueSort = $due.Date
    } else { $r.DueText = '—'; $r.DueHint = ''; $r.DueSort = [datetime]::MaxValue }
    $r.IsClosed = $closed
    $r.IsOverdue = (Test-TaskOverdue $t $s $ctx.Today)
    $r.IsUrgent = (Test-TaskUrgent $t $s)
    $r.Reminders = [int]$t.reminders
    $r.ReminderText = $(if ($t.reminders -gt 0) { [string]$t.reminders } else { '—' })
    $last = ConvertTo-DateTimeValue $t.lastReminderAt
    $r.ReminderTip = $(if ($last) { (T 'Last reminder: ') + $last.ToString(($s.dateFormat + ' HH:mm'), $script:UiCulture) } else { (T 'No reminders') })
    if ($closed -or $null -eq $t.score) {
        $r.ScoreValue = -1; $r.ScoreBar = 0; $r.ScoreText = '—'; $r.ScoreColor = Get-ScoreColorHex 0 $true
    } else {
        $r.ScoreValue = [double]$t.score; $r.ScoreBar = [double]$t.score
        $r.ScoreText = ([double]$t.score).ToString('0.0', $script:UiCulture); $r.ScoreColor = Get-ScoreColorHex ([double]$t.score) $false
    }
    $r.ClosedRank = $(if ($closed) { 1 } else { 0 })
    $upd = ConvertTo-DateTimeValue $t.updatedAt
    $r.UpdatedSort = $(if ($upd) { $upd } else { [datetime]::MinValue })
    $cmp = ConvertTo-DateTimeValue $t.completedAt
    if ($closed -and $cmp) {
        $r.CompletedText = $cmp.ToString(($s.dateFormat + ' HH:mm'), $script:UiCulture); $r.CompletedSort = $cmp
    } else { $r.CompletedText = '—'; $r.CompletedSort = [datetime]::MinValue }
    $r.RowState = $(if ($closed) { 'closed' } elseif ($r.IsOverdue) { 'overdue' } elseif ($r.IsUrgent) { 'urgent' } else { 'normal' })
    return $r
}

function Get-FilterId {
    param($Combo)
    $it = $Combo.SelectedItem
    if ($null -eq $it) { return $null }
    return $it.id
}

function Get-VisibleRows {
    $ctx = New-RowContext; $s = $ctx.Settings; $u = $script:Ui
    $q = $u.txtSearch.Text.Trim()
    $fSt = Get-FilterId $u.cmbStatus; $fPr = Get-FilterId $u.cmbPriority; $fRef = Get-FilterId $u.cmbReferent
    $me = $s.userName
    $rows = New-Object 'System.Collections.Generic.List[TaskRow]'
    foreach ($t in $script:State.Tasks) {
        $closed = Test-StatusClosed $t.statusId $s.statuses
        # note: 'continue' inside a switch exits the switch, not the foreach -> a flag is used
        $skip = $false
        switch ($script:View) {
            'dashboard' {
                if ($closed) { $skip = $true }
                elseif ($script:Quick -eq 'urgent' -and -not (Test-TaskUrgent $t $s)) { $skip = $true }
                elseif ($script:Quick -eq 'overdue' -and -not (Test-TaskOverdue $t $s $ctx.Today)) { $skip = $true }
            }
            'mine' { if (-not $me -or $t.referent -ine $me) { $skip = $true } }
            'byref' { if ($closed) { $skip = $true } }
            'done' { if (-not $closed) { $skip = $true } }
        }
        if ($skip) { continue }
        if ($fSt -and $t.statusId -ne $fSt) { continue }
        if ($fPr -and $t.priorityId -ne $fPr) { continue }
        if ($fRef -and $t.referent -ine $fRef) { continue }
        if ($q) {
            $cmp = [System.StringComparison]::OrdinalIgnoreCase
            if ($t.code.IndexOf($q, $cmp) -lt 0 -and $t.title.IndexOf($q, $cmp) -lt 0 -and ([string]$t.referent).IndexOf($q, $cmp) -lt 0) { continue }
        }
        $rows.Add((New-TaskRow $t $ctx))
    }
    return , $rows
}

function Set-GridSort {
    param($Previous)
    $u = $script:Ui; $items = $u.grid.Items
    $items.SortDescriptions.Clear(); $items.GroupDescriptions.Clear()
    $asc = [System.ComponentModel.ListSortDirection]::Ascending; $desc = [System.ComponentModel.ListSortDirection]::Descending
    foreach ($c in $u.grid.Columns) { $c.SortDirection = $null }
    if ($script:View -eq 'byref') {
        [void]$items.GroupDescriptions.Add((New-Object System.Windows.Data.PropertyGroupDescription 'Group'))
    }
    if ($script:ManualSort -and $Previous -and @($Previous).Count -gt 0) {
        foreach ($p in $Previous) {
            if ($p.P -eq 'Group') { continue }
            $items.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription($p.P, $p.D)))
        }
        if ($script:View -eq 'byref') { $items.SortDescriptions.Insert(0, (New-Object System.ComponentModel.SortDescription('Group', $asc))) }
        foreach ($c in $u.grid.Columns) {
            foreach ($p in $Previous) { if ($c.SortMemberPath -eq $p.P) { $c.SortDirection = $p.D } }
        }
        return
    }
    if ($script:View -eq 'done') {
        $items.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('CompletedSort', $desc)))
        $items.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('UpdatedSort', $desc)))
        $u.grid.Columns[$script:ColCompleted].SortDirection = $desc
        return
    }
    if ($script:View -eq 'byref') { $items.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('Group', $asc))) }
    $items.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('ClosedRank', $asc)))
    $items.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('ScoreValue', $desc)))
    $items.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('DueSort', $asc)))
    $items.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('Code', $asc)))
    $u.grid.Columns[$script:ColScore].SortDirection = $desc
}

function Update-Stats {
    $u = $script:Ui
    $st = Get-DashboardStats
    $u.txtOpen.Text = [string]$st.Open; $u.txtUrgent.Text = [string]$st.Urgent
    $u.txtOverdue.Text = [string]$st.Overdue; $u.txtDone.Text = [string]$st.Completed
    $u.cardOpen.Tag = $(if ($script:Quick -eq '') { 'active' } else { '' })
    $u.cardUrgent.Tag = $(if ($script:Quick -eq 'urgent') { 'active' } else { '' })
    $u.cardOverdue.Tag = $(if ($script:Quick -eq 'overdue') { 'active' } else { '' })
    return $st
}

function Refresh-Tasks {
    if ($null -eq $script:Ui -or $script:View -eq 'settings') { return }
    $u = $script:Ui
    $st = Update-Stats
    $prevId = $(if ($u.grid.SelectedItem) { $u.grid.SelectedItem.Id } else { $null })
    $prevSort = @($u.grid.Items.SortDescriptions | ForEach-Object { @{ P = $_.PropertyName; D = $_.Direction } })
    $rows = Get-VisibleRows
    $coll = New-Object 'System.Collections.ObjectModel.ObservableCollection[TaskRow]'
    foreach ($r in $rows) { $coll.Add($r) }
    $u.grid.ItemsSource = $coll
    Set-GridSort $prevSort
    if ($prevId) {
        $sel = $coll | Where-Object { $_.Id -eq $prevId } | Select-Object -First 1
        if ($sel) { $u.grid.SelectedItem = $sel }
    }
    # subtitle and empty state
    $n = $rows.Count
    $s = $script:State.Settings
    switch ($script:View) {
        'dashboard' { $u.txtSubtitle.Text = $(if ($script:Quick -eq 'urgent') { (T '{0} urgent tasks' $n) } elseif ($script:Quick -eq 'overdue') { (T '{0} overdue tasks' $n) } else { (T '{0} open tasks · automatically sorted by urgency' $n) }) }
        'all' { $u.txtSubtitle.Text = (T '{0} tasks listed' $n) }
        'mine' { $u.txtSubtitle.Text = $(if ($s.userName) { (T '{0} tasks assigned to {1}' $n $s.userName) } else { '' }) }
        'byref' { $u.txtSubtitle.Text = (T '{0} open tasks grouped by owner' $n) }
        'done' { $u.txtSubtitle.Text = (T '{0} completed tasks' $n) }
    }
    $u.txtInfo.Visibility = 'Collapsed'
    if ($script:View -eq 'mine' -and -not $s.userName) {
        $u.txtInfo.Text = (T 'To use «My tasks», set your name in Settings → Appearance and preferences (it must match the task owner).')
        $u.txtInfo.Visibility = 'Visible'
    }
    if ($n -eq 0) {
        $u.emptyState.Visibility = 'Visible'
        $filtered = ($u.txtSearch.Text.Trim() -ne '' -or (Get-FilterId $u.cmbStatus) -or (Get-FilterId $u.cmbPriority) -or (Get-FilterId $u.cmbReferent) -or $script:Quick)
        $u.btnEmptyNew.Visibility = 'Collapsed'
        if ($script:State.Tasks.Count -eq 0) {
            $u.emptyTitle.Text = (T 'No tasks yet')
            $u.emptyText.Text = (T 'Create your first task: NEXORA will sort them for you based on priority, due date, reminders and age.')
            $u.btnEmptyNew.Visibility = 'Visible'
        } elseif ($filtered) {
            $u.emptyTitle.Text = (T 'No results'); $u.emptyText.Text = (T 'No task matches the active filters. Try clearing them.')
        } elseif ($script:View -eq 'done') {
            $u.emptyTitle.Text = (T 'No completed tasks'); $u.emptyText.Text = (T 'Tasks moved to a «closed» status will appear here.')
        } elseif ($script:View -eq 'mine') {
            $u.emptyTitle.Text = (T 'No tasks assigned to you'); $u.emptyText.Text = ''
        } else {
            $u.emptyTitle.Text = (T 'All done!'); $u.emptyText.Text = (T 'There are no open tasks.')
        }
    } else { $u.emptyState.Visibility = 'Collapsed' }
    Update-ActionButtons
}

function Update-ActionButtons {
    $u = $script:Ui
    $has = ($null -ne $u.grid.SelectedItem)
    $bulkCount = @(Get-BulkSelectedTaskIds).Count
    $multiple = ($bulkCount -ge 2)
    $u.btnEdit.IsEnabled = $has
    $u.btnReminder.IsEnabled = $has
    $u.btnDuplicate.IsEnabled = ($has -or $multiple)
    $u.btnDelete.IsEnabled = ($has -or $multiple)
    $u.btnDuplicate.ToolTip = $(if ($multiple) { (T 'Duplicate checked tasks') } else { (T 'Duplicate the selected task') })
    $u.btnDelete.ToolTip = $(if ($multiple) { (T 'Delete checked tasks (Del)') } else { (T 'Delete the selected task (Del)') })
    if ($has -and $u.grid.SelectedItem.IsClosed) { $u.btnReminder.IsEnabled = $false }
}

function Update-FilterCombos {
    # repopulates the filters keeping the selection
    $u = $script:Ui; $s = $script:State.Settings
    $script:Updating = $true
    try {
        $sets = @(
            @{ C = $u.cmbStatus; All = (T 'All statuses'); Items = @($s.statuses | ForEach-Object { [pscustomobject]@{ id = $_.id; name = $_.name } }) },
            @{ C = $u.cmbPriority; All = (T 'All priorities'); Items = @($s.priorities | Sort-Object { -[double]$_.value } | ForEach-Object { [pscustomobject]@{ id = $_.id; name = $_.name } }) },
            @{ C = $u.cmbReferent; All = (T 'All owners'); Items = @(Get-Referents | ForEach-Object { [pscustomobject]@{ id = $_; name = $_ } }) }
        )
        foreach ($set in $sets) {
            $prev = Get-FilterId $set.C
            $list = @([pscustomobject]@{ id = $null; name = $set.All }) + $set.Items
            $set.C.ItemsSource = $list
            $sel = $list | Where-Object { $_.id -and $_.id -eq $prev } | Select-Object -First 1
            $set.C.SelectedItem = $(if ($sel) { $sel } else { $list[0] })
        }
    } finally { $script:Updating = $false }
}

function Refresh-All {
    Update-FilterCombos
    Refresh-Tasks
}

# ------------------------------------------------------------------ Views

function Set-View {
    param([string]$Name)
    $u = $script:Ui
    $script:View = $Name; $script:Quick = ''; $script:ManualSort = $false
    $isSettings = ($Name -eq 'settings')
    $u.settingsView.Visibility = $(if ($isSettings) { 'Visible' } else { 'Collapsed' })
    foreach ($c in $u.statsPanel, $u.filterPanel, $u.tableCard) { $c.Visibility = $(if ($isSettings) { 'Collapsed' } else { 'Visible' }) }
    if (-not $isSettings -and $Name -ne 'dashboard') { $u.statsPanel.Visibility = 'Collapsed' }
    $u.btnNew.Visibility = $(if ($isSettings) { 'Collapsed' } else { 'Visible' })
    $titles = @{ dashboard = 'Dashboard'; all = (T 'All tasks'); mine = (T 'My tasks'); byref = (T 'By owner'); done = (T 'Completed'); settings = (T 'Settings') }
    $u.txtTitle.Text = $titles[$Name]
    $script:Updating = $true
    $u.cmbStatus.SelectedIndex = 0; $u.cmbPriority.SelectedIndex = 0; $u.cmbReferent.SelectedIndex = 0
    $script:Updating = $false
    Update-Layout
    if ($isSettings) {
        $u.txtSubtitle.Text = (T 'Customize statuses, priorities, calculation engine and backups')
        Load-SettingsView
    } else { Refresh-Tasks }
}

function Update-Layout {
    if ($null -eq $script:Win -or $null -eq $script:Ui) { return }
    $u = $script:Ui; $w = $script:Win.ActualWidth
    $compact = ($w -lt 1020)
    $u.colSide.Width = New-Object System.Windows.GridLength($(if ($compact) { 74 } else { 236 }))
    $vis = $(if ($compact) { 'Collapsed' } else { 'Visible' })
    foreach ($l in 'txtBrand', 'lblAbout', 'lblDonate', 'lblTheme', 'lblDashboard', 'lblAll', 'lblMine', 'lblByRef', 'lblDone', 'lblSettings') { $u[$l].Visibility = $vis }
    $cols = $u.grid.Columns
    $cols[$script:ColReferent].Visibility = $(if ($w -lt 1180 -or $script:View -eq 'byref') { 'Collapsed' } else { 'Visible' })
    $cols[$script:ColReminders].Visibility = $(if ($w -lt 1050) { 'Collapsed' } else { 'Visible' })
    $cols[$script:ColScore].Visibility = $(if ($script:View -eq 'done') { 'Collapsed' } else { 'Visible' })
    $cols[$script:ColCompleted].Visibility = $(if ($script:View -eq 'done') { 'Visible' } else { 'Collapsed' })
    $cols[$script:ColPriority].Visibility = $(if ($w -lt 880) { 'Collapsed' } else { 'Visible' })
}

# ------------------------------------------------------------------ Task actions

function Get-SelectedTaskId {
    $r = $script:Ui.grid.SelectedItem
    if ($r) { return $r.Id } else { return $null }
}

function Get-BulkSelectedTaskIds {
    @($script:Ui.grid.ItemsSource | Where-Object { $_.BulkSelected } | ForEach-Object { [string]$_.Id })
}

function Test-MultipleBulkSelection {
    return (@(Get-BulkSelectedTaskIds).Count -ge 2)
}

function Open-TaskLink {
    param([string]$Link)
    if ([string]::IsNullOrWhiteSpace($Link) -or -not (Test-TaskLink $Link)) { throw (T 'The link must be an absolute HTTP or HTTPS URL no longer than 2048 characters.') }
    $uri = $null
    [void][uri]::TryCreate($Link.Trim(), [System.UriKind]::Absolute, [ref]$uri)
    Start-Process -FilePath $uri.AbsoluteUri
}

function Invoke-NewTask {
    if (Show-TaskDialog) { Refresh-All; Show-Toast (T 'Task created') }
}

function Invoke-EditTask {
    param([string]$Id)
    if (-not $Id) { return }
    if (Show-TaskDialog -TaskId $Id) { Refresh-All }
}

function Invoke-DeleteTask {
    param([string]$Id)
    if (Test-MultipleBulkSelection) { Invoke-BulkDeleteTasks; return }
    if (-not $Id) { return }
    $t = Get-TaskById $Id
    if ($null -eq $t) { return }
    $ok = Show-Message -Title (T 'Delete task {0}?' $t.code) -Text (T '«{0}» will be permanently deleted. A safety backup is created first.' $t.title) -Yes (T 'Delete') -No (T 'Cancel') -Danger -Icon 'warn'
    if ($ok) { Remove-AppTask $Id; Refresh-All; Show-Toast (T 'Task {0} deleted' $t.code) }
}

function Invoke-DuplicateTask {
    param([string]$Id)
    if (Test-MultipleBulkSelection) { Invoke-BulkDuplicateTasks; return }
    if (-not $Id) { return }
    $c = Copy-AppTask $Id
    Refresh-All
    $row = $script:Ui.grid.Items | Where-Object { $_.Id -eq $c.id } | Select-Object -First 1
    if ($row) { $script:Ui.grid.SelectedItem = $row; $script:Ui.grid.ScrollIntoView($row) }
    Show-Toast (T 'Task duplicated as {0}' $c.code)
}

function Invoke-Reminder {
    param([string]$Id)
    if (-not $Id) { return }
    $t = Add-TaskReminder $Id
    Refresh-Tasks
    Show-Toast (T 'Reminder #{0} logged on {1}' $t.reminders $t.code)
}

function Invoke-SetStatus {
    param([string]$Id, [string]$StatusId)
    $t = Set-AppTaskStatus $Id $StatusId
    Refresh-All
    Show-Toast "$($t.code) → $((Get-StatusById $StatusId).name)"
}

function Invoke-BulkDeleteTasks {
    $ids = @(Get-BulkSelectedTaskIds)
    if ($ids.Count -lt 2) { return }
    if (-not (Show-Message -Title (T 'Delete {0} selected tasks?' $ids.Count) -Text (T 'These tasks will be permanently deleted. A safety backup is created first.') -Yes (T 'Delete') -No (T 'Cancel') -Danger -Icon 'warn')) { return }
    $count = Remove-AppTasks $ids
    Refresh-All
    Show-Toast (T '{0} tasks deleted' $count)
}

function Invoke-BulkDuplicateTasks {
    $ids = @(Get-BulkSelectedTaskIds)
    if ($ids.Count -lt 2) { return }
    $copies = @(Copy-AppTasks $ids)
    Refresh-All
    $last = $copies[-1]
    $row = $script:Ui.grid.Items | Where-Object { $_.Id -eq $last.id } | Select-Object -First 1
    if ($row) { $script:Ui.grid.SelectedItem = $row; $script:Ui.grid.ScrollIntoView($row) }
    Show-Toast (T '{0} tasks duplicated' $copies.Count)
}

function Show-RowMenu {
    $u = $script:Ui
    $r = $u.grid.SelectedItem
    $m = $u.grid.ContextMenu
    $m.Items.Clear()
    if ($null -eq $r) { return $false }
    $icon = $script:Win.FindResource('IconFont')
    $add = {
        param([string]$Header, [string]$Glyph, [string]$Cmd, [bool]$Enabled = $true)
        $mi = New-Object System.Windows.Controls.MenuItem
        $mi.Header = $Header; $mi.Tag = $Cmd; $mi.IsEnabled = $Enabled
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $Glyph; $tb.FontFamily = $icon; $tb.Foreground = $script:Win.FindResource('MutedBrush')
        $mi.Icon = $tb
        [void]$m.Items.Add($mi)
        return $mi
    }
    [void](& $add (T 'Open / edit') ([string][char]0xE70F) 'open')
    [void](& $add (T 'Log reminder') ([string][char]0xE7ED) 'remind' (-not $r.IsClosed))
    $sub = & $add (T 'Change status') ([string][char]0xE8AB) 'none'
    foreach ($s in $script:State.Settings.statuses) {
        $si = New-Object System.Windows.Controls.MenuItem
        $si.Header = $s.name; $si.Tag = "status:$($s.id)"
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = 9; $dot.Height = 9; $dot.Fill = New-FrozenBrush $s.color
        $si.Icon = $dot
        [void]$sub.Items.Add($si)
    }
    [void]$m.Items.Add((New-Object System.Windows.Controls.Separator))
    [void](& $add (T 'Duplicate') ([string][char]0xE8C8) 'dup')
    [void](& $add (T 'Delete') ([string][char]0xE74D) 'del')
    return $true
}

# ------------------------------------------------------------------ Settings

function Get-BackupReasonLabel {
    param([string]$Reason)
    switch ($Reason) {
        'auto' { (T 'Automatic (daily)') } 'manual' { (T 'Manual') } 'pre-delete' { (T 'Before deleting a task') } 'pre-upgrade' { (T 'Before an update') }
        'pre-import' { (T 'Before an import') } 'pre-deletestatus' { (T 'Before deleting a status') }
        'pre-deletepriority' { (T 'Before deleting a priority level') } default { $Reason }
    }
}

function Load-BackupList {
    $items = foreach ($b in (Get-Snapshots)) {
        [pscustomobject]@{ path = $b.Path; when = $b.Date.ToString('dd/MM/yyyy HH:mm:ss', $script:UiCulture); reason = (Get-BackupReasonLabel $b.Reason); size = "$($b.SizeKB) KB" }
    }
    $script:Ui.lstBackups.ItemsSource = @($items)
}

function Resolve-FolderPickerPath {
    param([Parameter(Mandatory)][string]$Selection, [Parameter(Mandatory)][string]$Placeholder, [string]$BasePath)
    if (-not [System.IO.Path]::IsPathRooted($Selection)) {
        if (-not $BasePath) { throw (T 'The selected path is not a folder.') }
        $Selection = Join-Path $BasePath $Selection
    }
    $selected = [System.IO.Path]::GetFullPath($Selection)
    if ([System.IO.Directory]::Exists($selected)) { return Get-NormalizedDataPath $selected }
    if ([System.IO.File]::Exists($selected)) { throw (T 'Choose a folder, not a file.') }
    if ([System.IO.Path]::GetFileName($selected) -ieq $Placeholder) {
        $parent = [System.IO.Path]::GetDirectoryName($selected)
        if ([System.IO.Directory]::Exists($parent)) { return Get-NormalizedDataPath $parent }
    }
    throw (T 'The selected path is not a folder.')
}

function Invoke-ChooseDataFolder {
    param($Owner = $script:Win)
    $placeholder = (T 'Select this folder')
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title = (T 'Choose a folder for NEXORA data')
    $dialog.InitialDirectory = $script:DataPath
    $dialog.FileName = $placeholder
    $dialog.Filter = (T 'All files (*.*)|*.*')
    $dialog.CheckFileExists = $false
    $dialog.CheckPathExists = $true
    $dialog.ValidateNames = $false
    $dialog.AddExtension = $false
    $dialog.RestoreDirectory = $true
    if ($dialog.ShowDialog($Owner) -ne $true) { return }

    $target = Resolve-FolderPickerPath -Selection $dialog.FileName -Placeholder $placeholder -BasePath $dialog.InitialDirectory
    if ($target -ieq (Get-NormalizedDataPath $script:DataPath)) { return }
    $hasData = Test-DataDirectoryHasData $target
    if ($hasData) {
        $mode = Show-DataFolderChoice -Path $target -Owner $Owner
        if ($mode -eq 'Cancel') { return }
    } else {
        $mode = $(if ([bool]$script:Ui.chkMoveData.IsChecked) { 'Overwrite' } else { 'Keep' })
    }

    $previousLanguage = $script:Lang
    $null = Switch-AppDataDirectory -Path $target -Mode $mode
    Set-Language $script:State.Settings.language
    Set-Theme $script:State.Settings.theme
    if ($previousLanguage -ne $script:Lang) { Switch-MainWindowLanguage }
    else { Update-ThemeButton }
    Update-FilterCombos
    Load-SettingsView
    Refresh-Tasks
    if ($script:State.Warnings.Count -gt 0) { Show-Message -Title (T 'Data warning') -Text ($script:State.Warnings -join "`n`n") -Icon 'warn' | Out-Null }
    Show-Toast (T 'Data folder changed to: {0}' $script:DataPath)
}

function Save-StartupPreferences {
    if ($script:LoadingSettings) { return }
    try {
        Set-AppStartupPreferences -OpenOnStartup ([bool]$script:Ui.chkOpenOnStartup.IsChecked) -HideOnClose ([bool]$script:Ui.chkHideOnClose.IsChecked)
    } finally {
        Update-TrayIcon -Enabled ([bool]$script:State.Settings.hideOnClose)
    }
    Show-Toast (T 'Startup and background preferences saved')
}

function Load-SettingsView {
    $u = $script:Ui; $s = $script:State.Settings
    $selS = $(if ($u.lstStatuses.SelectedItem) { $u.lstStatuses.SelectedItem.id } else { $null })
    $selP = $(if ($u.lstPriorities.SelectedItem) { $u.lstPriorities.SelectedItem.id } else { $null })
    $selR = $(if ($u.lstReferents.SelectedItem) { $u.lstReferents.SelectedItem.id } else { $null })
    $sl = @($s.statuses | ForEach-Object { [pscustomobject]@{ id = $_.id; name = $_.name; color = $_.color; kind = $(if ($_.isClosed) { (T 'closed') } else { (T 'open') }) } })
    $u.lstStatuses.ItemsSource = $sl
    if ($selS) { $u.lstStatuses.SelectedItem = ($sl | Where-Object { $_.id -eq $selS } | Select-Object -First 1) }
    $pl = @($s.priorities | Sort-Object { [double]$_.value } | ForEach-Object { [pscustomobject]@{ id = $_.id; name = $_.name; color = $_.color; kind = (T 'value {0}' $_.value) } })
    $u.lstPriorities.ItemsSource = $pl
    if ($selP) { $u.lstPriorities.SelectedItem = ($pl | Where-Object { $_.id -eq $selP } | Select-Object -First 1) }
    $rl = @($s.referents | ForEach-Object { [pscustomobject]@{ id = $_.id; name = $_.name } })
    $u.lstReferents.ItemsSource = $rl
    if ($selR) { $u.lstReferents.SelectedItem = ($rl | Where-Object { $_.id -eq $selR } | Select-Object -First 1) }

    $script:WUpd = $true
    try {
        $w = $s.scoring.weights
        $u.sldPriority.Value = $w.priority; $u.sldDeadline.Value = $w.deadline; $u.sldReminders.Value = $w.reminders; $u.sldAge.Value = $w.age
    } finally { $script:WUpd = $false }
    Update-WeightLabels
    $u.txtNoDue.Text = ([double]$s.scoring.noDueScore).ToString($script:UiCulture)
    $u.txtAgeCap.Text = ([double]$s.scoring.ageCapDays).ToString($script:UiCulture)
    $u.txtUrgent2.Text = ([double]$s.scoring.urgentThreshold).ToString($script:UiCulture)
    $script:LoadingSettings = $true
    try {
        $u.chkOpenOnStartup.IsChecked = [bool]$s.openOnStartup
        $u.chkHideOnClose.IsChecked = [bool]$s.hideOnClose
    } finally { $script:LoadingSettings = $false }

    $langs = @([pscustomobject]@{ id = 'en'; name = 'English' }, [pscustomobject]@{ id = 'it'; name = 'Italiano' })
    $u.cmbLanguage.ItemsSource = $langs
    $u.cmbLanguage.SelectedItem = ($langs | Where-Object { $_.id -eq $s.language } | Select-Object -First 1)
    $themes = @([pscustomobject]@{ id = 'dark'; name = (T 'Dark') }, [pscustomobject]@{ id = 'light'; name = (T 'Light') })
    $u.cmbTheme.ItemsSource = $themes
    $u.cmbTheme.SelectedItem = ($themes | Where-Object { $_.id -eq $s.theme } | Select-Object -First 1)
    $now = Get-Date
    $fmts = @(Get-DateFormats | ForEach-Object { [pscustomobject]@{ id = $_; name = "$($_)   ($($now.ToString($_, $script:UiCulture)))" } })
    $u.cmbDateFormat.ItemsSource = $fmts
    $u.cmbDateFormat.SelectedItem = ($fmts | Where-Object { $_.id -eq $s.dateFormat } | Select-Object -First 1)
    $u.txtPrefix.Text = $s.codePrefix; $u.txtUserName.Text = $s.userName; $u.txtMaxBackups.Text = [string]$s.maxBackups
    $u.txtDataPath.Text = (T 'Data folder: {0}   ·   tasks.json · settings.json · history.json' $script:DataPath)
    Load-BackupList
}

function Update-WeightLabels {
    $u = $script:Ui
    $u.valPriority.Text = "$([int]$u.sldPriority.Value)%"; $u.valDeadline.Text = "$([int]$u.sldDeadline.Value)%"
    $u.valReminders.Text = "$([int]$u.sldReminders.Value)%"; $u.valAge.Text = "$([int]$u.sldAge.Value)%"
    $sum = [int]$u.sldPriority.Value + [int]$u.sldDeadline.Value + [int]$u.sldReminders.Value + [int]$u.sldAge.Value
    $u.txtWeightSum.Text = (T 'Total: {0}%' $sum)
}

function Update-WeightsFromSlider {
    # When a slider moves, the others are redistributed proportionally: sum is always 100
    param($Moved)
    $u = $script:Ui
    $sl = @($u.sldPriority, $u.sldDeadline, $u.sldReminders, $u.sldAge)
    $idx = [array]::IndexOf($sl, $Moved)
    if ($idx -lt 0) { return }
    $v = [int][math]::Round($Moved.Value)
    $rem = 100 - $v
    $oth = @(0..3 | Where-Object { $_ -ne $idx })
    $osum = 0; foreach ($i in $oth) { $osum += [int]$sl[$i].Value }
    $new = @{}
    if ($osum -le 0) {
        $each = [int][math]::Floor($rem / 3); $left = $rem - 3 * $each
        foreach ($i in $oth) { $new[$i] = $each }
        $new[$oth[0]] += $left
    } else {
        $tot = 0
        foreach ($i in $oth) { $new[$i] = [int][math]::Round([double]$sl[$i].Value * $rem / $osum); $tot += $new[$i] }
        $diff = $rem - $tot
        $big = $oth | Sort-Object { $new[$_] } -Descending | Select-Object -First 1
        $new[$big] = [math]::Max(0, $new[$big] + $diff)
    }
    foreach ($i in $oth) { $sl[$i].Value = $new[$i] }
    $sl[$idx].Value = $v
}

function Get-ListSelectionId {
    param($List, [string]$What)
    $it = $List.SelectedItem
    if ($null -eq $it) { Show-Toast (T 'First select {0} from the list' $What) -Error; return $null }
    return $it.id
}

function Invoke-ReloadAfterRestore {
    $null = Reload-AppState
    $prev = $script:Lang
    Set-Language $script:State.Settings.language
    Set-Theme $script:State.Settings.theme
    if ($prev -ne $script:Lang) { Switch-MainWindowLanguage; return }
    Update-ThemeButton
    Update-FilterCombos
    Load-SettingsView
}

function Switch-MainWindowLanguage {
    # Rebuilds the main window in the current language, keeping position, size and view
    $old = $script:Win
    $script:ToastTimer.Stop(); $script:ClockTimer.Stop(); $script:WeightTimer.Stop()
    $bounds = $(if ($old.WindowState -eq 'Normal') { New-Object System.Windows.Rect($old.Left, $old.Top, $old.Width, $old.Height) } else { $old.RestoreBounds })
    $state = $old.WindowState
    $new = New-MainWindow
    $new.WindowStartupLocation = 'Manual'
    $new.Left = $bounds.Left; $new.Top = $bounds.Top; $new.Width = $bounds.Width; $new.Height = $bounds.Height
    $new.WindowState = $state
    $new.Show()
    [System.Windows.Application]::Current.MainWindow = $new
    $script:ReplacingMainWindow = $true
    try { $old.Close() } finally { $script:ReplacingMainWindow = $false }
    $script:Ui.navSettings.IsChecked = $true
    Show-Toast (T 'Preferences saved')
}

function Get-ScoringParameterValidation {
    param($Controls)
    $errors = New-Object 'System.Collections.Generic.List[string]'
    $values = New-Object 'System.Collections.Generic.List[double]'
    $fields = @(
        [pscustomobject]@{ Control = $Controls.txtNoDue; Label = (T 'Due date score when missing'); Min = 0; Max = 100 }
        [pscustomobject]@{ Control = $Controls.txtAgeCap; Label = (T 'Age cap'); Min = 1; Max = 3650 }
        [pscustomobject]@{ Control = $Controls.txtUrgent2; Label = (T 'Urgent threshold'); Min = 1; Max = 100 }
    )
    foreach ($field in $fields) {
        $value = 0.0
        $valid = [double]::TryParse($field.Control.Text.Trim().Replace(',', '.'), [System.Globalization.NumberStyles]::Float, $script:Inv, [ref]$value) -and $value -ge $field.Min -and $value -le $field.Max
        Set-FieldInvalid $field.Control (-not $valid)
        if ($valid) {
            $values.Add($value)
        } else {
            $errors.Add((T '{0}: enter a number between {1} and {2}.' $field.Label $field.Min $field.Max))
        }
    }
    return [pscustomobject]@{ Errors = @($errors.ToArray()); Values = @($values.ToArray()) }
}

function Update-ScoringParameterError {
    param($Controls)
    $validation = Get-ScoringParameterValidation $Controls
    if ($validation.Errors.Count -gt 0) {
        $Controls.txtParamsError.Text = $validation.Errors -join "`n"
        $Controls.txtParamsError.Visibility = 'Visible'
    } else {
        $Controls.txtParamsError.Text = ''
        $Controls.txtParamsError.Visibility = 'Collapsed'
    }
}

function Get-PreferenceValidation {
    param($Controls)
    $errors = New-Object 'System.Collections.Generic.List[string]'
    $maxBackups = 0
    $maxBackupsValid = [int]::TryParse($Controls.txtMaxBackups.Text.Trim(), [ref]$maxBackups) -and $maxBackups -ge 5 -and $maxBackups -le 500
    Set-FieldInvalid $Controls.txtMaxBackups (-not $maxBackupsValid)
    if (-not $maxBackupsValid) { $errors.Add((T 'Backups to keep must be a number between 5 and 500.')) }

    $prefix = $Controls.txtPrefix.Text.Trim()
    $prefixValid = $prefix -match '^[A-Za-z0-9]{1,10}$'
    Set-FieldInvalid $Controls.txtPrefix (-not $prefixValid)
    if (-not $prefixValid) { $errors.Add((T 'The code prefix must be 1-10 alphanumeric characters (A-Z, 0-9).')) }

    $language = $(if ($Controls.cmbLanguage.SelectedItem) { $Controls.cmbLanguage.SelectedItem.id } else { '' })
    $theme = $(if ($Controls.cmbTheme.SelectedItem) { $Controls.cmbTheme.SelectedItem.id } else { '' })
    $dateFormat = $(if ($Controls.cmbDateFormat.SelectedItem) { $Controls.cmbDateFormat.SelectedItem.id } else { '' })
    $languageValid = $language -in @('en', 'it')
    $themeValid = $theme -in @('dark', 'light')
    $dateFormatValid = (Get-DateFormats) -contains $dateFormat
    Set-FieldInvalid $Controls.cmbLanguage (-not $languageValid)
    Set-FieldInvalid $Controls.cmbTheme (-not $themeValid)
    Set-FieldInvalid $Controls.cmbDateFormat (-not $dateFormatValid)
    if (-not $languageValid) { $errors.Add((T 'Invalid language.')) }
    if (-not $themeValid) { $errors.Add((T 'Invalid theme.')) }
    if (-not $dateFormatValid) { $errors.Add((T 'Invalid date format.')) }

    return [pscustomobject]@{
        Errors = @($errors.ToArray())
        MaxBackups = $maxBackups
        Prefix = $prefix
        Language = $language
        Theme = $theme
        DateFormat = $dateFormat
        OpenOnStartup = [bool]$Controls.chkOpenOnStartup.IsChecked
        HideOnClose = [bool]$Controls.chkHideOnClose.IsChecked
    }
}

function Update-PreferenceError {
    param($Controls)
    $validation = Get-PreferenceValidation $Controls
    if ($validation.Errors.Count -gt 0) {
        $Controls.txtPrefError.Text = $validation.Errors -join "`n"
        $Controls.txtPrefError.Visibility = 'Visible'
    } else {
        $Controls.txtPrefError.Text = ''
        $Controls.txtPrefError.Visibility = 'Collapsed'
    }
}

function Register-SettingsHandlers {
    $u = $script:Ui

    On $u.btnWebsiteSettings 'Click' { param($s, $e) Open-PublisherWebsite }
    On $u.btnChangeDataFolder 'Click' { param($s, $e) Invoke-ChooseDataFolder }
    foreach ($checkbox in $u.chkOpenOnStartup, $u.chkHideOnClose) {
        On $checkbox 'Checked' { param($s, $e) Save-StartupPreferences }
        On $checkbox 'Unchecked' { param($s, $e) Save-StartupPreferences }
    }

    foreach ($field in $u.txtNoDue, $u.txtAgeCap, $u.txtUrgent2, $u.txtPrefix, $u.txtMaxBackups) {
        On $field 'TextChanged' { param($s, $e)
            switch ($s.Name) {
                'txtNoDue' {
                    $v = 0.0
                    if ([double]::TryParse($s.Text.Trim().Replace(',', '.'), [System.Globalization.NumberStyles]::Float, $script:Inv, [ref]$v) -and $v -ge 0 -and $v -le 100) { Set-FieldInvalid $s $false }
                }
                'txtAgeCap' {
                    $v = 0.0
                    if ([double]::TryParse($s.Text.Trim().Replace(',', '.'), [System.Globalization.NumberStyles]::Float, $script:Inv, [ref]$v) -and $v -ge 1 -and $v -le 3650) { Set-FieldInvalid $s $false }
                }
                'txtUrgent2' {
                    $v = 0.0
                    if ([double]::TryParse($s.Text.Trim().Replace(',', '.'), [System.Globalization.NumberStyles]::Float, $script:Inv, [ref]$v) -and $v -ge 1 -and $v -le 100) { Set-FieldInvalid $s $false }
                }
                'txtPrefix' { if ($s.Text.Trim() -match '^[A-Za-z0-9]{1,10}$') { Set-FieldInvalid $s $false } }
                'txtMaxBackups' {
                    $v = 0
                    if ([int]::TryParse($s.Text.Trim(), [ref]$v) -and $v -ge 5 -and $v -le 500) { Set-FieldInvalid $s $false }
                }
            }
            if ($script:Ui.txtParamsError.Visibility -eq 'Visible' -and $s.Name -in @('txtNoDue', 'txtAgeCap', 'txtUrgent2')) { Update-ScoringParameterError $script:Ui }
            if ($script:Ui.txtPrefError.Visibility -eq 'Visible' -and $s.Name -in @('txtPrefix', 'txtMaxBackups')) { Update-PreferenceError $script:Ui }
        }
    }
    On $u.cmbLanguage 'SelectionChanged' { param($s, $e)
        if ($script:Ui.txtPrefError.Visibility -eq 'Visible') { Update-PreferenceError $script:Ui }
        elseif ($s.SelectedItem -and $s.SelectedItem.id -in @('en', 'it')) { Set-FieldInvalid $s $false }
    }
    On $u.cmbTheme 'SelectionChanged' { param($s, $e)
        if ($script:Ui.txtPrefError.Visibility -eq 'Visible') { Update-PreferenceError $script:Ui }
        elseif ($s.SelectedItem -and $s.SelectedItem.id -in @('dark', 'light')) { Set-FieldInvalid $s $false }
    }
    On $u.cmbDateFormat 'SelectionChanged' { param($s, $e)
        if ($script:Ui.txtPrefError.Visibility -eq 'Visible') { Update-PreferenceError $script:Ui }
        elseif ($s.SelectedItem -and (Get-DateFormats) -contains $s.SelectedItem.id) { Set-FieldInvalid $s $false }
    }

    # ---- statuses
    On $u.btnStAdd 'Click' { param($s, $e)
        $saved = Show-ItemDialog -Title (T 'New status') -Initial @{ Name = ''; Color = '#3B82F6'; IsClosed = $false } -ShowValue $false -ShowClosed $true -OnSave {
            param($d) $null = Add-Status $d.Name $d.Color $d.IsClosed }
        if ($saved) { Load-SettingsView; Update-FilterCombos; Show-Toast (T 'Status created') }
    }
    On $u.btnStEdit 'Click' { param($s, $e)
        $id = Get-ListSelectionId $script:Ui.lstStatuses (T 'a status'); if (-not $id) { return }
        $st = Get-StatusById $id
        $script:EditId = $id
        $saved = Show-ItemDialog -Title (T 'Edit status') -Initial @{ Name = $st.name; Color = $st.color; IsClosed = $st.isClosed } -ShowValue $false -ShowClosed $true -OnSave {
            param($d) Update-Status $script:EditId $d.Name $d.Color $d.IsClosed }
        if ($saved) { Load-SettingsView; Refresh-All; Show-Toast (T 'Status updated') }
    }
    On $u.btnStDel 'Click' { param($s, $e)
        $id = Get-ListSelectionId $script:Ui.lstStatuses (T 'a status'); if (-not $id) { return }
        $st = Get-StatusById $id
        $n = @($script:State.Tasks | Where-Object { $_.statusId -eq $id }).Count
        $txt = $(if ($n -gt 0) { (T '{0} tasks use this status: they will be moved automatically to another status.' $n) } else { (T 'No task uses this status.') })
        if (Show-Message -Title (T 'Delete status «{0}»?' $st.name) -Text $txt -Yes (T 'Delete') -No (T 'Cancel') -Danger -Icon 'warn') {
            $r = Remove-Status $id
            Load-SettingsView; Refresh-All
            Show-Toast $(if ($r.Moved -gt 0) { (T 'Status deleted · {0} tasks moved to «{1}»' $r.Moved $r.TargetName) } else { (T 'Status deleted') })
        }
    }
    On $u.btnStUp 'Click' { param($s, $e) $id = Get-ListSelectionId $script:Ui.lstStatuses (T 'a status'); if ($id) { Move-Status $id -1; Load-SettingsView; Update-FilterCombos } }
    On $u.btnStDown 'Click' { param($s, $e) $id = Get-ListSelectionId $script:Ui.lstStatuses (T 'a status'); if ($id) { Move-Status $id 1; Load-SettingsView; Update-FilterCombos } }

    # ---- priorities
    On $u.btnPrAdd 'Click' { param($s, $e)
        $max = ($script:State.Settings.priorities | Measure-Object -Property value -Maximum).Maximum
        $saved = Show-ItemDialog -Title (T 'New priority level') -Initial @{ Name = ''; Value = ([double]$max + 1); Color = '#F97316' } -ShowValue $true -ShowClosed $false -OnSave {
            param($d) $null = Add-PriorityLevel $d.Name $d.Value $d.Color }
        if ($saved) { Load-SettingsView; Refresh-All; Show-Toast (T 'Level created') }
    }
    On $u.btnPrEdit 'Click' { param($s, $e)
        $id = Get-ListSelectionId $script:Ui.lstPriorities (T 'a level'); if (-not $id) { return }
        $p = Get-PriorityById $id
        $script:EditId = $id
        $saved = Show-ItemDialog -Title (T 'Edit priority level') -Initial @{ Name = $p.name; Value = $p.value; Color = $p.color } -ShowValue $true -ShowClosed $false -OnSave {
            param($d) Update-PriorityLevel $script:EditId $d.Name $d.Value $d.Color }
        if ($saved) { Load-SettingsView; Refresh-All; Show-Toast (T 'Level updated') }
    }
    On $u.btnPrDel 'Click' { param($s, $e)
        $id = Get-ListSelectionId $script:Ui.lstPriorities (T 'a level'); if (-not $id) { return }
        $p = Get-PriorityById $id
        $n = @($script:State.Tasks | Where-Object { $_.priorityId -eq $id }).Count
        $txt = $(if ($n -gt 0) { (T '{0} tasks use this level: they will be moved to the nearest level.' $n) } else { (T 'No task uses this level.') })
        if (Show-Message -Title (T 'Delete level «{0}»?' $p.name) -Text $txt -Yes (T 'Delete') -No (T 'Cancel') -Danger -Icon 'warn') {
            $r = Remove-PriorityLevel $id
            Load-SettingsView; Refresh-All
            Show-Toast $(if ($r.Moved -gt 0) { (T 'Level deleted · {0} tasks moved to «{1}»' $r.Moved $r.TargetName) } else { (T 'Level deleted') })
        }
    }

    # ---- owners
    On $u.btnRfAdd 'Click' { param($s, $e)
        $saved = Show-ItemDialog -Title (T 'New owner') -Initial @{ Name = ''; Color = '#6B7280'; IsClosed = $false } -ShowValue $false -ShowClosed $false -ShowColor $false -MaxNameLength 80 -OnSave {
            param($d) $null = Add-Referent $d.Name }
        if ($saved) { Load-SettingsView; Update-FilterCombos; Show-Toast (T 'Owner created') }
    }
    On $u.btnRfEdit 'Click' { param($s, $e)
        $id = Get-ListSelectionId $script:Ui.lstReferents (T 'an owner'); if (-not $id) { return }
        $r = Get-ReferentById $id
        $script:EditId = $id
        $saved = Show-ItemDialog -Title (T 'Edit owner') -Initial @{ Name = $r.name; Color = '#6B7280'; IsClosed = $false } -ShowValue $false -ShowClosed $false -ShowColor $false -MaxNameLength 80 -OnSave {
            param($d) Update-Referent $script:EditId $d.Name }
        if ($saved) { Load-SettingsView; Refresh-All; Show-Toast (T 'Owner updated') }
    }
    On $u.btnRfDel 'Click' { param($s, $e)
        $id = Get-ListSelectionId $script:Ui.lstReferents (T 'an owner'); if (-not $id) { return }
        $r = Get-ReferentById $id
        $n = @($script:State.Tasks | Where-Object { $_.referent -ieq $r.name }).Count
        $txt = $(if ($n -gt 0) { (T '{0} tasks use this owner: they will be moved to another owner or left unassigned.' $n) } else { (T 'No task uses this owner.') })
        if (Show-Message -Title (T 'Delete owner «{0}»?' $r.name) -Text $txt -Yes (T 'Delete') -No (T 'Cancel') -Danger -Icon 'warn') {
            $removed = Remove-Referent $id
            Load-SettingsView; Refresh-All
            Show-Toast $(if ($removed.Moved -gt 0) { (T 'Owner deleted · {0} tasks moved to «{1}»' $removed.Moved $(if ($removed.TargetName) { $removed.TargetName } else { (T '(no owner)') })) } else { (T 'Owner deleted') })
        }
    }
    On $u.btnRfUp 'Click' { param($s, $e) $id = Get-ListSelectionId $script:Ui.lstReferents (T 'an owner'); if ($id) { Move-Referent $id -1; Load-SettingsView } }
    On $u.btnRfDown 'Click' { param($s, $e) $id = Get-ListSelectionId $script:Ui.lstReferents (T 'an owner'); if ($id) { Move-Referent $id 1; Load-SettingsView } }

    # ---- weights (applied after a short pause to avoid writing to disk on every tick)
    $script:WeightTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:WeightTimer.Interval = [TimeSpan]::FromMilliseconds(450)
    On $script:WeightTimer 'Tick' { param($s, $e)
        $script:WeightTimer.Stop()
        $x = $script:Ui
        Set-ScoringWeights $x.sldPriority.Value $x.sldDeadline.Value $x.sldReminders.Value $x.sldAge.Value
        Show-Toast (T 'Weights updated: ranking recalculated')
    }
    foreach ($sl in $u.sldPriority, $u.sldDeadline, $u.sldReminders, $u.sldAge) {
        On $sl 'ValueChanged' { param($s, $e)
            if ($script:WUpd) { return }
            $script:WUpd = $true
            try { Update-WeightsFromSlider $s } finally { $script:WUpd = $false }
            Update-WeightLabels
            $script:WeightTimer.Stop(); $script:WeightTimer.Start()
        }
    }
    On $u.btnParamsSave 'Click' { param($s, $e)
        $x = $script:Ui
        $x.txtParamsError.Visibility = 'Collapsed'
        $validation = Get-ScoringParameterValidation $x
        if ($validation.Errors.Count -gt 0) {
            $x.txtParamsError.Text = $validation.Errors -join "`n"
            $x.txtParamsError.Visibility = 'Visible'
            return
        }
        Set-ScoringParameters $validation.Values[0] $validation.Values[1] $validation.Values[2]
        Refresh-All; Show-Toast (T 'Parameters applied')
    }
    On $u.btnWeightsReset 'Click' { param($s, $e)
        if (Show-Message -Title (T 'Restore default parameters?') -Text (T 'Weights 35/35/20/10 and original calculation parameters.') -Yes (T 'Restore') -No (T 'Cancel')) {
            Reset-ScoringDefaults; Load-SettingsView; Refresh-All; Show-Toast (T 'Parameters restored')
        }
    }

    # ---- preferences
    On $u.btnPrefSave 'Click' { param($s, $e)
        $x = $script:Ui
        $x.txtPrefError.Visibility = 'Collapsed'
        $validation = Get-PreferenceValidation $x
        if ($validation.Errors.Count -gt 0) {
            $x.txtPrefError.Text = $validation.Errors -join "`n"
            $x.txtPrefError.Visibility = 'Visible'
            return
        }
        $langChanged = ($validation.Language -ne $script:State.Settings.language)
        Set-AppPreferences -Theme $validation.Theme -DateFormat $validation.DateFormat -CodePrefix $validation.Prefix -UserName $x.txtUserName.Text -MaxBackups $validation.MaxBackups -Language $validation.Language -OpenOnStartup $validation.OpenOnStartup -HideOnClose $validation.HideOnClose
        Set-Language $script:State.Settings.language
        Set-Theme $script:State.Settings.theme
        Update-TrayIcon -Enabled ([bool]$script:State.Settings.hideOnClose)
        if ($langChanged) { Switch-MainWindowLanguage; return }   # the language changes on save: the window is rebuilt
        Update-ThemeButton
        Load-SettingsView; Refresh-All; Show-Toast (T 'Preferences saved')
    }
    On $u.btnTheme 'Click' { param($s, $e)
        $new = $(if ($script:State.Settings.theme -eq 'dark') { 'light' } else { 'dark' })
        $script:State.Settings.theme = $new; Save-Settings
        Set-Theme $new; Update-ThemeButton
        if ($script:View -eq 'settings') { Load-SettingsView }
    }

    # ---- backup
    On $u.btnBkNow 'Click' { param($s, $e)
        $p = New-Snapshot -Reason 'manual'
        Remove-OldSnapshots -Keep $script:State.Settings.maxBackups
        Load-BackupList; Show-Toast (T 'Backup created')
    }
    On $u.btnBkRestore 'Click' { param($s, $e)
        $it = $script:Ui.lstBackups.SelectedItem
        if ($null -eq $it) { Show-Toast (T 'Select a backup from the list') -Error; return }
        if (Show-Message -Title (T 'Restore this backup?') -Text (T 'The current data will be replaced with the data of the backup from {0}. A backup of the current state is created before restoring.' $it.when) -Yes (T 'Restore') -No (T 'Cancel') -Danger -Icon 'warn') {
            Restore-BackupArchive $it.path
            Invoke-ReloadAfterRestore; Show-Toast (T 'Backup restored')
        }
    }
    On $u.btnBkExport 'Click' { param($s, $e)
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Filter = (T 'NEXORA backup (*.zip)|*.zip')
        $dlg.FileName = 'Nexora-backup-' + (Get-Date).ToString('yyyyMMdd-HHmm') + '.zip'
        $dlg.Title = (T 'Export full backup')
        if ($dlg.ShowDialog($script:Win)) {
            if (Test-Path -LiteralPath $dlg.FileName) { Remove-Item -LiteralPath $dlg.FileName -Force }
            $null = New-Snapshot -Reason 'manual' -DestinationFile $dlg.FileName
            Show-Toast (T 'Backup exported: {0}' ([System.IO.Path]::GetFileName($dlg.FileName)))
        }
    }
    On $u.btnBkImport 'Click' { param($s, $e)
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Filter = (T 'NEXORA backup (*.zip)|*.zip'); $dlg.Title = (T 'Import full backup')
        if ($dlg.ShowDialog($script:Win)) {
            if (Show-Message -Title (T 'Import this backup?') -Text (T 'The current data will be replaced with the data of the file «{0}». A backup of the current state is created before importing.' ([System.IO.Path]::GetFileName($dlg.FileName))) -Yes (T 'Import') -No (T 'Cancel') -Danger -Icon 'warn') {
                Restore-BackupArchive $dlg.FileName
                Invoke-ReloadAfterRestore; Show-Toast (T 'Backup imported')
            }
        }
    }
    On $u.btnBkOpen 'Click' { param($s, $e) Start-Process explorer.exe -ArgumentList ('"' + $script:DataPath + '"') }
}

function Update-ThemeButton {
    $u = $script:Ui
    $u.lblTheme.Text = $(if ($script:State.Settings.theme -eq 'dark') { (T 'Light theme') } else { (T 'Dark theme') })
}

function Show-MainWindow {
    if ($null -eq $script:Win) { return }
    if (-not $script:Win.IsVisible) { $script:Win.Show() }
    if ($script:Win.WindowState -eq 'Minimized') { $script:Win.WindowState = 'Normal' }
    $script:Win.Activate() | Out-Null
}

function Invoke-PendingInstanceActivation {
    if ($null -ne $script:ActivationEvent -and $script:ActivationEvent.WaitOne(0)) {
        Show-MainWindow
    }
}

function Start-InstanceActivationListener {
    if ($null -ne $script:ActivationTimer) { return }
    $script:ActivationEvent = New-Object System.Threading.EventWaitHandle(
        $false,
        [System.Threading.EventResetMode]::AutoReset,
        $script:ActivationEventName
    )
    $script:ActivationTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:ActivationTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    On $script:ActivationTimer 'Tick' { param($s, $e) Invoke-PendingInstanceActivation }
    $script:ActivationTimer.Start()
    [System.Windows.Application]::Current.add_Exit({
        if ($null -ne $script:ActivationTimer) { $script:ActivationTimer.Stop(); $script:ActivationTimer = $null }
        if ($null -ne $script:ActivationEvent) { $script:ActivationEvent.Dispose(); $script:ActivationEvent = $null }
    })
}

function Exit-Nexora {
    $script:ExitRequested = $true
    [System.Windows.Application]::Current.Shutdown()
}

function Update-TrayIcon {
    param([bool]$Enabled)
    if (-not $Enabled) {
        if ($null -ne $script:Tray) {
            $tray = $script:Tray
            $script:Tray = $null
            $tray.NotifyIcon.Visible = $false
            $tray.NotifyIcon.Dispose()
            $tray.Menu.Dispose()
            $tray.Icon.Dispose()
        }
        return
    }

    if ($null -eq $script:Tray) {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $iconPath = Join-Path $script:AssetsPath 'Branding\nexora-icon.ico'
        if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) { throw "NEXORA tray icon not found: $iconPath" }

        $icon = New-Object System.Drawing.Icon($iconPath)
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        $openItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $notify.Icon = $icon
        $notify.Text = 'NEXORA'
        $notify.ContextMenuStrip = $menu
        [void]$menu.Items.Add($openItem)
        [void]$menu.Items.Add($exitItem)
        $openItem.add_Click({ Show-MainWindow })
        $exitItem.add_Click({ Exit-Nexora })
        $notify.add_DoubleClick({ Show-MainWindow })
        $script:Tray = @{ NotifyIcon = $notify; Menu = $menu; Icon = $icon; OpenItem = $openItem; ExitItem = $exitItem }
    }

    $script:Tray.OpenItem.Text = (T 'Open NEXORA')
    $script:Tray.ExitItem.Text = (T 'Exit NEXORA')
    $script:Tray.NotifyIcon.Visible = $true
}

# ------------------------------------------------------------------ Clock (day change)

function Test-DayRollover {
    if ((Get-Date).Date -ne $script:State.LastScoreDay) {
        Write-Log 'New day: recalculating ranking'
        Update-AllScoresAndSave
        if ($script:View -ne 'settings') { Refresh-Tasks }
    }
}

# ------------------------------------------------------------------ Window construction

function Set-RoundedDataGridClip {
    param($Grid)
    if ($Grid.ActualWidth -le 0 -or $Grid.ActualHeight -le 0) { return }
    $clip = New-Object System.Windows.Media.RectangleGeometry
    $clip.Rect = [System.Windows.Rect]::new(0, 0, $Grid.ActualWidth, $Grid.ActualHeight)
    $clip.RadiusX = 9
    $clip.RadiusY = 9
    $clip.Freeze()
    $Grid.Clip = $clip
}

function New-MainWindow {
    $w = Import-Xaml 'MainWindow.xaml'
    $script:Win = $w
    $script:Ui = Get-Named $w $script:MainNames
    $u = $script:Ui

    $script:ToastTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:ToastTimer.Interval = [TimeSpan]::FromSeconds(3.4)
    On $script:ToastTimer 'Tick' { param($s, $e) $script:ToastTimer.Stop(); $script:Ui.toast.Visibility = 'Collapsed' }

    $script:ClockTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:ClockTimer.Interval = [TimeSpan]::FromSeconds(30)
    On $script:ClockTimer 'Tick' { param($s, $e) Test-DayRollover }
    $script:ClockTimer.Start()
    On $w 'Activated' { param($s, $e) Test-DayRollover }
    On $w 'Closing' { param($s, $e)
        if ($script:State.Settings.hideOnClose -and -not $script:ExitRequested -and -not $script:ReplacingMainWindow) {
            $e.Cancel = $true
            $s.Hide()
        }
    }
    On $w 'Closed' { param($s, $e) if (-not $script:ReplacingMainWindow) { Update-TrayIcon -Enabled $false } }

    # navigation
    On $u.navDashboard 'Checked' { param($s, $e) Set-View 'dashboard' }
    On $u.navAll 'Checked' { param($s, $e) Set-View 'all' }
    On $u.navMine 'Checked' { param($s, $e) Set-View 'mine' }
    On $u.navByRef 'Checked' { param($s, $e) Set-View 'byref' }
    On $u.navDone 'Checked' { param($s, $e) Set-View 'done' }
    On $u.navSettings 'Checked' { param($s, $e) Set-View 'settings' }

    # dashboard cards = quick filters
    On $u.cardOpen 'Click' { param($s, $e) $script:Quick = ''; Refresh-Tasks }
    On $u.cardUrgent 'Click' { param($s, $e) $script:Quick = $(if ($script:Quick -eq 'urgent') { '' } else { 'urgent' }); Refresh-Tasks }
    On $u.cardOverdue 'Click' { param($s, $e) $script:Quick = $(if ($script:Quick -eq 'overdue') { '' } else { 'overdue' }); Refresh-Tasks }
    On $u.cardDone 'Click' { param($s, $e) $script:Ui.navDone.IsChecked = $true }

    # filters
    On $u.txtSearch 'TextChanged' { param($s, $e)
        $script:Ui.searchHint.Visibility = $(if ($script:Ui.txtSearch.Text -eq '') { 'Visible' } else { 'Collapsed' })
        Refresh-Tasks
    }
    foreach ($c in $u.cmbStatus, $u.cmbPriority, $u.cmbReferent) {
        On $c 'SelectionChanged' { param($s, $e) if (-not $script:Updating) { Refresh-Tasks } }
    }
    On $u.btnClear 'Click' { param($s, $e)
        $x = $script:Ui
        $script:Updating = $true
        $x.txtSearch.Text = ''; $x.cmbStatus.SelectedIndex = 0; $x.cmbPriority.SelectedIndex = 0; $x.cmbReferent.SelectedIndex = 0
        $script:Updating = $false
        $script:Quick = ''; $script:ManualSort = $false
        Refresh-Tasks
    }

    # actions
    On $u.btnNew 'Click' { param($s, $e) Invoke-NewTask }
    On $u.btnEmptyNew 'Click' { param($s, $e) Invoke-NewTask }
    On $u.btnEdit 'Click' { param($s, $e) Invoke-EditTask (Get-SelectedTaskId) }
    On $u.btnReminder 'Click' { param($s, $e) Invoke-Reminder (Get-SelectedTaskId) }
    On $u.btnDuplicate 'Click' { param($s, $e) Invoke-DuplicateTask (Get-SelectedTaskId) }
    On $u.btnDelete 'Click' { param($s, $e) Invoke-DeleteTask (Get-SelectedTaskId) }
    $script:OpenTaskLinkCommand = [System.Windows.Input.RoutedUICommand]::new('Open task link', 'OpenTaskLink', [System.Windows.Controls.Button])
    $openLinkBinding = New-Object System.Windows.Input.CommandBinding($script:OpenTaskLinkCommand)
    [void]$openLinkBinding.add_CanExecute({ param($s, $e) $e.CanExecute = $true })
    [void]$openLinkBinding.add_Executed({
        param($s, $e)
        try { Open-TaskLink ([string]$e.Parameter) } catch { Show-UiError $_ }
    })
    [void]$w.CommandBindings.Add($openLinkBinding)
    $script:BulkSelectionCommand = [System.Windows.Input.RoutedUICommand]::new('Update bulk selection', 'UpdateBulkSelection', [System.Windows.Controls.CheckBox])
    $w.Tag = $script:BulkSelectionCommand
    $bulkSelectionBinding = New-Object System.Windows.Input.CommandBinding($script:BulkSelectionCommand)
    [void]$bulkSelectionBinding.add_CanExecute({ param($s, $e) $e.CanExecute = $true })
    [void]$bulkSelectionBinding.add_Executed({
        param($s, $e)
        $check = $e.Parameter
        if ($check -is [System.Windows.Controls.CheckBox] -and $check.DataContext -is [TaskRow]) {
            $check.DataContext.BulkSelected = [bool]$check.IsChecked
        }
        Update-ActionButtons
    })
    [void]$w.CommandBindings.Add($bulkSelectionBinding)

    # table
    On $u.grid 'Loaded' { param($s, $e) Set-RoundedDataGridClip $s }
    On $u.grid 'SizeChanged' { param($s, $e) Set-RoundedDataGridClip $s }
    On $u.grid 'SelectionChanged' { param($s, $e) Update-ActionButtons }
    On $u.grid 'Sorting' { param($s, $e) $script:ManualSort = $true }
    On $u.grid 'MouseDoubleClick' { param($s, $e)
        if ($null -ne (Get-Ancestor $e.OriginalSource ([System.Windows.Controls.DataGridRow]))) { Invoke-EditTask (Get-SelectedTaskId) }
    }
    On $u.grid 'KeyDown' { param($s, $e)
        if ($e.Key -eq 'Delete') { Invoke-DeleteTask (Get-SelectedTaskId); $e.Handled = $true }
        elseif ($e.Key -eq 'Return') { Invoke-EditTask (Get-SelectedTaskId); $e.Handled = $true }
    }
    $menu = New-Object System.Windows.Controls.ContextMenu
    $u.grid.ContextMenu = $menu
    On $u.grid 'PreviewMouseRightButtonDown' { param($s, $e)
        $row = Get-Ancestor $e.OriginalSource ([System.Windows.Controls.DataGridRow])
        if ($row) { $row.IsSelected = $true }
    }
    On $u.grid 'ContextMenuOpening' { param($s, $e) if (-not (Show-RowMenu)) { $e.Handled = $true } }
    $menu.AddHandler([System.Windows.Controls.MenuItem]::ClickEvent, [System.Windows.RoutedEventHandler]{
        param($s, $e)
        try {
            $cmd = [string]$e.OriginalSource.Tag; $id = Get-SelectedTaskId
            if (-not $id) { return }
            if ($cmd -eq 'open') { Invoke-EditTask $id }
            elseif ($cmd -eq 'remind') { Invoke-Reminder $id }
            elseif ($cmd -eq 'dup') { Invoke-DuplicateTask $id }
            elseif ($cmd -eq 'del') { Invoke-DeleteTask $id }
            elseif ($cmd -like 'status:*') { Invoke-SetStatus $id $cmd.Substring(7) }
        } catch { Show-UiError $_ }
    })

    On $u.btnAbout 'Click' { param($s, $e) Show-AboutDialog }
    On $u.btnDonate 'Click' { param($s, $e) Open-DonatePage }

    # window
    On $w 'SizeChanged' { param($s, $e) Update-Layout }
    On $w 'PreviewKeyDown' { param($s, $e)
        $ctrl = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control
        if ($ctrl -and $e.Key -eq 'N' -and $script:View -ne 'settings') { Invoke-NewTask; $e.Handled = $true }
        elseif ($ctrl -and $e.Key -eq 'F' -and $script:View -ne 'settings') { $script:Ui.txtSearch.Focus(); $e.Handled = $true }
        elseif ($e.Key -eq 'F5') { Test-DayRollover; Refresh-All; $e.Handled = $true }
    }

    Register-SettingsHandlers
    Update-ThemeButton
    Update-FilterCombos
    Set-View 'dashboard'
    Update-TrayIcon -Enabled ([bool]$script:State.Settings.hideOnClose)
    Start-InstanceActivationListener
    return $w
}

function Invoke-VersionCheck {
    # If the app was updated since last launch, create a data snapshot first ('pre-upgrade'), then register the new version
    $cur = Get-AppVersion
    $prev = [string]$script:State.Settings.lastRunVersion
    if ($prev -ne $cur) {
        if ($prev -ne '') {
            try { New-Snapshot -Reason 'pre-upgrade' | Out-Null } catch { Write-Log "Pre-upgrade snapshot failed: $($_.Exception.Message)" 'WARN' }
            Write-Log "Application updated: $prev -> $cur"
        }
        $script:State.Settings.lastRunVersion = $cur
        Save-Settings
    }
}

function Close-Splash {
    # The splash is shown by Nexora.exe (if present): it closes it when the main window is ready
    $h = Get-Variable -Name NexoraHost -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $h) { try { $h.CloseSplash() } catch { } }
}

function Start-Nexora {
    param([Parameter(Mandatory)][string]$DataPath)
    $script:DataPath = $DataPath
    Initialize-Storage -DataPath $DataPath
    Write-Log "--- Application start (v$(Get-AppVersion)) ---"
    $state = Initialize-AppState
    try {
        if ($state.Settings.openOnStartup) {
            if (Get-InstalledLauncherPath) { Ensure-StartupRegistration -Enabled $true }
        } else {
            Set-StartupRegistration -Enabled $false
        }
    } catch {
        Write-Log "Startup registration failed: $($_.Exception.Message)" 'WARN'
        $state.Warnings.Add((T 'Automatic startup could not be configured: {0}' $_.Exception.Message))
    }
    Set-Language $state.Settings.language
    Invoke-VersionCheck
    try { Invoke-DailySnapshot -Keep $state.Settings.maxBackups } catch { Write-Log "Daily backup failed: $($_.Exception.Message)" 'WARN' }
    $app = Initialize-Wpf
    Set-Theme $state.Settings.theme
    $app.add_DispatcherUnhandledException({
        param($s, $e)
        Write-Log "Unhandled exception: $($e.Exception.Message)`n$($e.Exception.StackTrace)" 'ERROR'
        $e.Handled = $true
        try { Show-Message -Title (T 'Unexpected error') -Text $e.Exception.Message -Icon 'error' | Out-Null } catch { }
    })
    $app.add_SessionEnding({
        $script:ExitRequested = $true
        Update-TrayIcon -Enabled $false
    })
    $w = New-MainWindow
    $w.add_ContentRendered({ param($s, $e) Close-Splash })
    $w.add_Loaded({
        param($s, $e)
        if ($script:State.Warnings.Count -gt 0) {
            Show-Message -Title (T 'Data warning') -Text ($script:State.Warnings -join "`n`n") -Icon 'warn' | Out-Null
        }
    })
    [void]$app.Run($w)
    Write-Log '--- Application exit ---'
}
