# Dialogs.ps1 - dialog windows: messages, items (statuses/priorities), tasks

function Get-ActiveOwner {
    $app = [System.Windows.Application]::Current
    if ($null -eq $app) { return $null }
    $act = $app.Windows | Where-Object { $_.IsActive -and $_.IsVisible } | Select-Object -First 1
    if ($null -ne $act) { return $act }
    if ($null -ne $script:Win -and $script:Win.IsVisible) { return $script:Win }
    return $null
}

function Open-PublisherWebsite {
    Start-Process -FilePath 'https://www.txnello.com/'
}

function Open-DonatePage {
    Start-Process -FilePath 'https://ko-fi.com/txnello'
}

function Set-DialogOwner {
    param($Dialog, $Owner)
    $o = $Owner
    if ($null -eq $o) { $o = Get-ActiveOwner }
    if ($null -ne $o -and $o -ne $Dialog) { $Dialog.Owner = $o } else { $Dialog.WindowStartupLocation = 'CenterScreen' }
}

function Show-DataFolderChoice {
    param([string]$Path, $Owner)
    $w = Import-Xaml 'DataFolderChoiceDialog.xaml'
    $n = Get-Named $w 'folderChoiceTitle', 'folderChoiceText', 'folderChoicePath', 'folderChoiceOverwrite', 'folderChoiceKeep', 'folderChoiceMerge', 'folderChoiceCancel'
    $n.folderChoiceTitle.Text = (T 'Data folder contains existing data')
    $n.folderChoiceText.Text = (T 'The destination folder contains NEXORA data. Choose how to switch. Overwrite creates a safety copy first; merge keeps tasks, statuses, priorities, owners and history from both folders.')
    $n.folderChoicePath.Text = $Path
    $n.folderChoiceOverwrite.Content = (T 'Change and overwrite')
    $n.folderChoiceOverwrite.ToolTip = (T 'Replace the destination data with the current data; keep a safety copy of the destination.')
    $n.folderChoiceKeep.Content = (T 'Change without overwriting')
    $n.folderChoiceKeep.ToolTip = (T 'Switch to the destination data unchanged and leave the current folder untouched.')
    $n.folderChoiceMerge.Content = (T 'Merge')
    $n.folderChoiceMerge.ToolTip = (T 'Combine tasks, statuses, priorities, owners and history from both folders.')
    $n.folderChoiceCancel.Content = (T 'Cancel')
    $script:DataFolderChoiceDialog = @{ W = $w; Result = 'Cancel' }
    On $n.folderChoiceOverwrite 'Click' { param($s, $e) $script:DataFolderChoiceDialog.Result = 'Overwrite'; $script:DataFolderChoiceDialog.W.Close() }
    On $n.folderChoiceKeep 'Click' { param($s, $e) $script:DataFolderChoiceDialog.Result = 'Keep'; $script:DataFolderChoiceDialog.W.Close() }
    On $n.folderChoiceMerge 'Click' { param($s, $e) $script:DataFolderChoiceDialog.Result = 'Merge'; $script:DataFolderChoiceDialog.W.Close() }
    On $n.folderChoiceCancel 'Click' { param($s, $e) $script:DataFolderChoiceDialog.Result = 'Cancel'; $script:DataFolderChoiceDialog.W.Close() }
    Set-DialogOwner $w $Owner
    [void]$w.ShowDialog()
    return $script:DataFolderChoiceDialog.Result
}

# ------------------------------------------------------------------ Message / confirmation

function Show-Message {
    # Returns $true if the user confirms. With -No the cancel button is also shown.
    param([string]$Title, [string]$Text = '', [string]$Yes = 'OK', [string]$No = '', [switch]$Danger, [string]$Icon = 'info')
    $w = Import-Xaml 'MessageDialog.xaml'
    $n = Get-Named $w 'msgIcon', 'msgTitle', 'msgText', 'msgNo', 'msgYes'
    $n.msgTitle.Text = $Title
    $n.msgText.Text = $Text
    if ($Text -eq '') { $n.msgText.Visibility = 'Collapsed' }
    $n.msgYes.Content = $Yes
    switch ($Icon) {
        'error' { $n.msgIcon.Text = [string][char]0xE783; $n.msgIcon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'DangerBrush') }
        'warn'  { $n.msgIcon.Text = [string][char]0xE7BA; $n.msgIcon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'WarnBrush') }
        'ok'    { $n.msgIcon.Text = [string][char]0xE73E; $n.msgIcon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'OkBrush') }
        default { $n.msgIcon.Text = [string][char]0xE946 }
    }
    if ($No -eq '') { $n.msgNo.Visibility = 'Collapsed'; $n.msgYes.IsCancel = $true } else { $n.msgNo.Content = $No; $n.msgNo.IsCancel = $true }
    if ($Danger) { $n.msgYes.Style = $w.FindResource('DangerButton') }
    $n.msgYes.IsDefault = $true
    $script:Md = @{ W = $w; Result = $false }
    On $n.msgYes 'Click' { param($s, $e) $script:Md.Result = $true; $script:Md.W.Close() }
    Set-DialogOwner $w
    [void]$w.ShowDialog()
    return $script:Md.Result
}

# ------------------------------------------------------------------ Status / priority dialog

function Show-ItemDialog {
    # $Initial: @{ Name; Value; Color; IsClosed }. $OnSave receives a hashtable and throws if invalid.
    param([string]$Title, [hashtable]$Initial, [bool]$ShowValue, [bool]$ShowClosed, [scriptblock]$OnSave, [bool]$ShowColor = $true, [int]$MaxNameLength = 40)
    $w = Import-Xaml 'ItemDialog.xaml'
    $n = Get-Named $w 'itmTitle', 'itmName', 'itmValuePanel', 'itmValue', 'itmPalette', 'itmPreview', 'itmColor', 'itmColorPanel', 'itmClosed', 'itmError', 'itmCancel', 'itmSave'
    $script:Id = @{ W = $w; N = $n; Saved = $false; OnSave = $OnSave; ShowValue = $ShowValue; ShowClosed = $ShowClosed }
    $w.Title = $Title; $n.itmTitle.Text = $Title
    $n.itmName.MaxLength = $MaxNameLength
    $n.itmName.Text = [string]$Initial.Name
    if ($ShowValue) { $n.itmValuePanel.Visibility = 'Visible'; $n.itmValue.Text = ([double]$Initial.Value).ToString($script:Inv) }
    if ($ShowClosed) { $n.itmClosed.Visibility = 'Visible'; $n.itmClosed.IsChecked = [bool]$Initial.IsClosed }
    if (-not $ShowColor) { $n.itmColorPanel.Visibility = 'Collapsed' }
    $n.itmColor.Text = [string]$Initial.Color
    $n.itmPreview.Background = New-FrozenBrush $(if (Test-HexColor $n.itmColor.Text) { $n.itmColor.Text } else { '#6B7280' })

    foreach ($c in (Get-ColorPalette)) {
        $b = New-Object System.Windows.Controls.Button
        $b.Width = 28; $b.Height = 28; $b.Padding = New-Object System.Windows.Thickness 0
        $b.Margin = New-Object System.Windows.Thickness(0, 0, 6, 6)
        $b.Background = New-FrozenBrush $c; $b.Tag = $c; $b.ToolTip = $c
        On $b 'Click' { param($s, $e) $script:Id.N.itmColor.Text = [string]$s.Tag }
        [void]$n.itmPalette.Children.Add($b)
    }
    On $n.itmColor 'TextChanged' { param($s, $e)
        $t = $script:Id.N.itmColor.Text
        if (Test-HexColor $t) {
            $script:Id.N.itmPreview.Background = New-FrozenBrush $t
            Set-FieldInvalid $s $false
        }
    }
    On $n.itmName 'TextChanged' { param($s, $e) if ($s.Text.Trim() -ne '') { Set-FieldInvalid $s $false } }
    On $n.itmValue 'TextChanged' { param($s, $e)
        $v = 0.0
        if ([double]::TryParse($s.Text.Trim().Replace(',', '.'), [System.Globalization.NumberStyles]::Float, $script:Inv, [ref]$v)) { Set-FieldInvalid $s $false }
    }
    On $n.itmCancel 'Click' { param($s, $e) $script:Id.W.Close() }
    On $n.itmSave 'Click' { param($s, $e)
        $d = $script:Id; $nn = $d.N
        foreach ($field in $nn.itmName, $nn.itmValue, $nn.itmColor) { Set-FieldInvalid $field $false }
        try {
            $data = @{ Name = $nn.itmName.Text.Trim(); Color = $nn.itmColor.Text.Trim(); Value = 0.0; IsClosed = [bool]$nn.itmClosed.IsChecked }
            if ($data.Name -eq '') { Set-FieldInvalid $nn.itmName $true; throw (T 'The name is required.') }
            if (-not (Test-HexColor $data.Color)) { Set-FieldInvalid $nn.itmColor $true; throw (T 'The color must be in #RRGGBB format (e.g. #3B82F6).') }
            if ($d.ShowValue) {
                $v = 0.0
                if (-not [double]::TryParse($nn.itmValue.Text.Trim().Replace(',', '.'), [System.Globalization.NumberStyles]::Float, $script:Inv, [ref]$v)) {
                    Set-FieldInvalid $nn.itmValue $true
                    throw (T 'The numeric value is not valid.')
                }
                $data.Value = $v
            }
            & $d.OnSave $data
            $d.Saved = $true
            $d.W.Close()
        } catch {
            $message = $_.Exception.Message
            foreach ($pattern in (T 'A status named "{0}" already exists.' '*'), (T 'A priority level named "{0}" already exists.' '*'), (T 'An owner named "{0}" already exists.' '*')) {
                if ($message -like $pattern) { Set-FieldInvalid $nn.itmName $true; break }
            }
            $nn.itmError.Text = $message
            $nn.itmError.Visibility = 'Visible'
        }
    }
    $w.add_ContentRendered({ param($s, $e) $script:Id.N.itmName.Focus(); $script:Id.N.itmName.SelectAll() })
    Set-DialogOwner $w
    [void]$w.ShowDialog()
    return $script:Id.Saved
}

function Get-TaskDialogReferentItems {
    param([string]$CurrentName = '')
    $items = New-Object 'System.Collections.Generic.List[psobject]'
    $items.Add([pscustomobject]@{ name = (T '(no owner)'); value = ''; IsCreateAction = $false })
    $seen = @{}
    foreach ($r in $script:State.Settings.referents) {
        $name = [string]$r.name
        if ($name -and -not $seen.ContainsKey($name)) {
            $seen[$name] = $true
            $items.Add([pscustomobject]@{ name = $name; value = $name; IsCreateAction = $false })
        }
    }
    foreach ($name in (Get-Referents)) {
        if ($name -and -not $seen.ContainsKey($name)) {
            $seen[$name] = $true
            $items.Add([pscustomobject]@{ name = $name; value = $name; IsCreateAction = $false })
        }
    }
    if ($CurrentName -and -not $seen.ContainsKey($CurrentName)) {
        $items.Add([pscustomobject]@{ name = $CurrentName; value = $CurrentName; IsCreateAction = $false })
    }
    $items.Add([pscustomobject]@{ name = (T 'Create new owner…'); value = ''; IsCreateAction = $true })
    return @($items.ToArray())
}

# ------------------------------------------------------------------ Task dialog

function Show-TaskDialog {
    # Creates or edits a task. Returns $true if something was saved (task, reminder, deletion).
    param([string]$TaskId = '', [switch]$NoModal)
    $w = Import-Xaml 'TaskDialog.xaml'
    $names = 'colSide', 'dlgTitle', 'txtCode', 'txtTitle', 'txtDesc', 'txtLink', 'cmbReferent', 'cmbStatus', 'cmbPriority', 'txtDue', 'dueHint',
        'btnCal', 'calPopup', 'calendar', 'btnToday', 'btnTomorrow', 'btnWeek', 'btnNoDue', 'txtMeta', 'txtError', 'taskFormScroll', 'sidePanel', 'txtScore', 'barScore',
        'txtBreakdown', 'txtRemCount', 'txtRemLast', 'btnRemind', 'btnUnRemind', 'lstHistory', 'btnDelete', 'btnSave', 'btnCancel'
    $n = Get-Named $w $names
    $st = $script:State.Settings
    $script:Td = @{ W = $w; N = $n; TaskId = $TaskId; Changed = $false }

    $statusItems = @($st.statuses) + @([pscustomobject]@{ id = ''; name = (T 'Create new status…'); color = '#2F7BFF'; IsCreateAction = $true })
    $priorityItems = @($st.priorities | Sort-Object { [double]$_.value }) + @([pscustomobject]@{ id = ''; name = (T 'Create new priority level…'); color = '#2F7BFF'; IsCreateAction = $true })
    $n.cmbStatus.ItemsSource = $statusItems
    $n.cmbPriority.ItemsSource = $priorityItems
    $script:Td.LastStatusId = $null
    $script:Td.LastPriorityId = $null
    $script:Td.HandlingSelection = $false

    if ($TaskId) {
        $t = Get-TaskById $TaskId
        if ($null -eq $t) { throw (T 'Task not found.') }
        $w.Title = (T 'Task {0}' $t.code); $n.dlgTitle.Text = (T '{0} · edit task' $t.code)
        $n.txtCode.Text = $t.code; $n.txtTitle.Text = $t.title; $n.txtDesc.Text = $t.description; $n.txtLink.Text = [string]$t.link
        $currentReferent = [string]$t.referent
        $n.cmbStatus.SelectedItem = (@($n.cmbStatus.ItemsSource) | Where-Object { -not $_.IsCreateAction -and $_.id -eq $t.statusId } | Select-Object -First 1)
        $n.cmbPriority.SelectedItem = (@($n.cmbPriority.ItemsSource) | Where-Object { -not $_.IsCreateAction -and $_.id -eq $t.priorityId } | Select-Object -First 1)
        $script:Td.LastStatusId = $t.statusId
        $script:Td.LastPriorityId = $t.priorityId
        $n.txtDue.Text = $(if ($t.dueDate) { Format-AppDate $t.dueDate $st } else { '' })
    } else {
        $d = Get-DefaultTaskInput
        $w.Title = 'Nuovo task'; $n.dlgTitle.Text = 'Nuovo task'
        $n.txtCode.Text = $d.Code
        $n.txtLink.Text = $d.Link
        $currentReferent = [string]$d.Referent
        $n.cmbStatus.SelectedItem = (@($n.cmbStatus.ItemsSource) | Where-Object { -not $_.IsCreateAction -and $_.id -eq $d.StatusId } | Select-Object -First 1)
        $n.cmbPriority.SelectedItem = (@($n.cmbPriority.ItemsSource) | Where-Object { -not $_.IsCreateAction -and $_.id -eq $d.PriorityId } | Select-Object -First 1)
        $script:Td.LastStatusId = $d.StatusId
        $script:Td.LastPriorityId = $d.PriorityId
        $n.sidePanel.Visibility = 'Collapsed'; $n.colSide.Width = New-Object System.Windows.GridLength 0
        $n.btnDelete.Visibility = 'Collapsed'
        $w.Width = 660
    }
    $w.Height = 800
    $n.cmbReferent.ItemsSource = Get-TaskDialogReferentItems $currentReferent
    $n.cmbReferent.SelectedItem = ($n.cmbReferent.ItemsSource | Where-Object { -not $_.IsCreateAction -and $_.value -ieq $currentReferent } | Select-Object -First 1)
    $script:Td.LastReferent = $currentReferent
    $script:Td.HandlingReferentSelection = $false
    $n.dueHint.Text = 'es. ' + (Format-AppDate (Get-Date) $st)
    $n.dueHint.Visibility = $(if ($n.txtDue.Text -eq '') { 'Visible' } else { 'Collapsed' })

    Update-TaskDialogSide

    On $n.cmbStatus 'SelectionChanged' { param($s, $e)
        $td = $script:Td
        if ($td.HandlingSelection) { return }
        $selected = $s.SelectedItem
        if ($null -eq $selected) { return }
        if (-not $selected.IsCreateAction) { Set-FieldInvalid $s $false; $td.LastStatusId = $selected.id; return }
        $td.HandlingSelection = $true
        try { $s.SelectedItem = Get-StatusById $td.LastStatusId } finally { $td.HandlingSelection = $false }
        $saved = Show-ItemDialog -Title (T 'New status') -Initial @{ Name = ''; Color = '#3B82F6'; IsClosed = $false } -ShowValue $false -ShowClosed $true -OnSave {
            param($d) $created = Add-Status $d.Name $d.Color $d.IsClosed; $script:Td.CreatedStatusId = $created.id }
        if ($saved) {
            $id = $td.CreatedStatusId
            $td.HandlingSelection = $true
            try {
                $s.ItemsSource = @($script:State.Settings.statuses) + @([pscustomobject]@{ id = ''; name = (T 'Create new status…'); color = '#2F7BFF'; IsCreateAction = $true })
                $s.SelectedItem = Get-StatusById $id
                Set-FieldInvalid $s $false
                $td.LastStatusId = $id
            } finally { $td.HandlingSelection = $false }
        }
    }
    On $n.cmbPriority 'SelectionChanged' { param($s, $e)
        $td = $script:Td
        if ($td.HandlingSelection) { return }
        $selected = $s.SelectedItem
        if ($null -eq $selected) { return }
        if (-not $selected.IsCreateAction) { Set-FieldInvalid $s $false; $td.LastPriorityId = $selected.id; return }
        $td.HandlingSelection = $true
        try { $s.SelectedItem = Get-PriorityById $td.LastPriorityId } finally { $td.HandlingSelection = $false }
        $max = ($script:State.Settings.priorities | Measure-Object -Property value -Maximum).Maximum
        $saved = Show-ItemDialog -Title (T 'New priority level') -Initial @{ Name = ''; Value = ([double]$max + 1); Color = '#F97316' } -ShowValue $true -ShowClosed $false -OnSave {
            param($d) $created = Add-PriorityLevel $d.Name $d.Value $d.Color; $script:Td.CreatedPriorityId = $created.id }
        if ($saved) {
            $id = $td.CreatedPriorityId
            $td.HandlingSelection = $true
            try {
                $s.ItemsSource = @($script:State.Settings.priorities | Sort-Object { [double]$_.value }) + @([pscustomobject]@{ id = ''; name = (T 'Create new priority level…'); color = '#2F7BFF'; IsCreateAction = $true })
                $s.SelectedItem = Get-PriorityById $id
                Set-FieldInvalid $s $false
                $td.LastPriorityId = $id
            } finally { $td.HandlingSelection = $false }
        }
    }
    On $n.cmbReferent 'SelectionChanged' { param($s, $e)
        $td = $script:Td
        if ($td.HandlingReferentSelection) { return }
        $selected = $s.SelectedItem
        if ($null -eq $selected) { return }
        if (-not $selected.IsCreateAction) { $td.LastReferent = [string]$selected.value; return }
        $td.HandlingReferentSelection = $true
        try {
            $s.SelectedItem = ($s.ItemsSource | Where-Object { -not $_.IsCreateAction -and $_.value -ieq $td.LastReferent } | Select-Object -First 1)
        } finally { $td.HandlingReferentSelection = $false }
        $saved = Show-ItemDialog -Title (T 'New owner') -Initial @{ Name = ''; Color = '#6B7280'; IsClosed = $false } -ShowValue $false -ShowClosed $false -ShowColor $false -MaxNameLength 80 -OnSave {
            param($d) $created = Add-Referent $d.Name; $script:Td.CreatedReferentName = $created.name }
        if ($saved) {
            $name = $td.CreatedReferentName
            $td.HandlingReferentSelection = $true
            try {
                $s.ItemsSource = Get-TaskDialogReferentItems $name
                $s.SelectedItem = ($s.ItemsSource | Where-Object { -not $_.IsCreateAction -and $_.value -ieq $name } | Select-Object -First 1)
                $td.LastReferent = $name
            } finally { $td.HandlingReferentSelection = $false }
        }
    }
    On $n.txtCode 'TextChanged' { param($s, $e)
        $code = $s.Text.Trim()
        if ($code -match '^[A-Za-z0-9][A-Za-z0-9_\-\./]{0,24}$' -and -not ($script:State.Tasks | Where-Object { $_.id -ne $script:Td.TaskId -and $_.code -ieq $code })) { Set-FieldInvalid $s $false }
    }
    On $n.txtTitle 'TextChanged' { param($s, $e) if ($s.Text.Trim().Length -gt 0 -and $s.Text.Length -le 200) { Set-FieldInvalid $s $false } }
    On $n.txtDesc 'TextChanged' { param($s, $e) if ($s.Text.Length -le 10000) { Set-FieldInvalid $s $false } }
    On $n.txtLink 'TextChanged' { param($s, $e) if (Test-TaskLink $s.Text) { Set-FieldInvalid $s $false } }
    On $n.txtDue 'TextChanged' { param($s, $e)
        $x = $script:Td.N
        if ($s.Text.Trim() -eq '' -or $null -ne (ConvertFrom-AppDate $s.Text $script:State.Settings)) { Set-FieldInvalid $s $false }
        $x.dueHint.Visibility = $(if ($x.txtDue.Text -eq '') { 'Visible' } else { 'Collapsed' })
    }
    On $n.btnToday 'Click' { param($s, $e) $script:Td.N.txtDue.Text = Format-AppDate (Get-Date) $script:State.Settings }
    On $n.btnTomorrow 'Click' { param($s, $e) $script:Td.N.txtDue.Text = Format-AppDate (Get-Date).AddDays(1) $script:State.Settings }
    On $n.btnWeek 'Click' { param($s, $e) $script:Td.N.txtDue.Text = Format-AppDate (Get-Date).AddDays(7) $script:State.Settings }
    On $n.btnNoDue 'Click' { param($s, $e) $script:Td.N.txtDue.Text = '' }
    On $n.btnCal 'Click' { param($s, $e)
        $x = $script:Td.N
        $d = ConvertFrom-AppDate $x.txtDue.Text $script:State.Settings
        if ($null -eq $d) { $d = (Get-Date).Date }
        $x.calendar.DisplayDate = $d
        $x.calendar.SelectedDate = $d
        $x.calPopup.IsOpen = $true
    }
    On $n.calendar 'SelectedDatesChanged' { param($s, $e)
        $x = $script:Td.N
        if ($null -ne $x.calendar.SelectedDate) {
            $x.txtDue.Text = Format-AppDate $x.calendar.SelectedDate $script:State.Settings
            $x.calPopup.IsOpen = $false
        }
    }
    On $n.btnRemind 'Click' { param($s, $e)
        $td = $script:Td
        $t = Add-TaskReminder $td.TaskId
        $td.Changed = $true
        Update-TaskDialogSide
    }
    On $n.btnUnRemind 'Click' { param($s, $e)
        $td = $script:Td
        $null = Undo-TaskReminder $td.TaskId
        $td.Changed = $true
        Update-TaskDialogSide
    }
    On $n.btnDelete 'Click' { param($s, $e)
        $td = $script:Td
        $t = Get-TaskById $td.TaskId
        $ok = Show-Message -Title (T 'Delete task {0}?' $t.code) -Text (T '«{0}» will be permanently deleted. A safety backup is created first.' $t.title) -Yes (T 'Delete') -No (T 'Cancel') -Danger -Icon 'warn'
        if ($ok) { Remove-AppTask $td.TaskId; $td.Changed = $true; $td.W.Close() }
    }
    On $n.btnCancel 'Click' { param($s, $e) $script:Td.W.Close() }
    On $n.btnSave 'Click' { param($s, $e) Save-TaskDialog }
    On $w 'PreviewKeyDown' { param($s, $e)
        $ctrl = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control
        if ($e.Key -eq 'Escape' -and -not $script:Td.N.calPopup.IsOpen) { $script:Td.W.Close(); $e.Handled = $true }
        elseif ($e.Key -eq 'Return' -and $ctrl) { Save-TaskDialog; $e.Handled = $true }
    }
    $w.add_ContentRendered({ param($s, $e) if (-not $script:Td.TaskId) { $script:Td.N.txtTitle.Focus() } })

    Set-DialogOwner $w
    if ($NoModal) { $w.Show(); return $w }
    [void]$w.ShowDialog()
    return $script:Td.Changed
}

function Save-TaskDialog {
    $td = $script:Td; $n = $td.N; $st = $script:State.Settings
    $n.txtError.Visibility = 'Collapsed'
    foreach ($field in $n.txtCode, $n.txtTitle, $n.txtDesc, $n.txtLink, $n.txtDue, $n.cmbReferent, $n.cmbStatus, $n.cmbPriority) { Set-FieldInvalid $field $false }
    try {
        $due = $null
        if ($n.txtDue.Text.Trim() -ne '') {
            $due = ConvertFrom-AppDate $n.txtDue.Text $st
            if ($null -eq $due) {
                Set-FieldInvalid $n.txtDue $true
                throw "La scadenza non è una data valida. Formato atteso: $($st.dateFormat.Replace('yyyy','aaaa').Replace('dd','gg'))  (oppure usa il calendario)."
            }
        }
        $in = @{
            Code = $n.txtCode.Text; Title = $n.txtTitle.Text; Description = $n.txtDesc.Text; Link = $n.txtLink.Text
            Referent = $(if ($n.cmbReferent.SelectedItem -and -not $n.cmbReferent.SelectedItem.IsCreateAction) { [string]$n.cmbReferent.SelectedItem.value } else { '' })
            StatusId = $(if ($n.cmbStatus.SelectedItem) { $n.cmbStatus.SelectedItem.id } else { '' })
            PriorityId = $(if ($n.cmbPriority.SelectedItem) { $n.cmbPriority.SelectedItem.id } else { '' })
            DueDate = $due
        }
        Set-TaskDialogFieldErrors $n $in $td.TaskId
        if ($td.TaskId) { $null = Update-AppTask $td.TaskId $in } else { $null = Add-AppTask $in }
        $td.Changed = $true
        $td.W.Close()
    } catch {
        $n.txtError.Text = $_.Exception.Message
        $n.txtError.Visibility = 'Visible'
    }
}

function Set-TaskDialogFieldErrors {
    param($Controls, $TaskInput, [string]$ExceptId)
    $code = ([string]$TaskInput.Code).Trim()
    $codeInvalid = ($code -notmatch '^[A-Za-z0-9][A-Za-z0-9_\-\./]{0,24}$')
    if (-not $codeInvalid -and ($script:State.Tasks | Where-Object { $_.id -ne $ExceptId -and $_.code -ieq $code })) { $codeInvalid = $true }
    Set-FieldInvalid $Controls.txtCode $codeInvalid
    Set-FieldInvalid $Controls.txtTitle (([string]$TaskInput.Title).Trim().Length -eq 0 -or ([string]$TaskInput.Title).Length -gt 200)
    Set-FieldInvalid $Controls.cmbReferent (([string]$TaskInput.Referent).Trim().Length -gt 80)
    Set-FieldInvalid $Controls.txtDesc (([string]$TaskInput.Description).Length -gt 10000)
    Set-FieldInvalid $Controls.txtLink (-not (Test-TaskLink ([string]$TaskInput.Link)))
    Set-FieldInvalid $Controls.cmbStatus ($null -eq (Get-StatusById $TaskInput.StatusId))
    Set-FieldInvalid $Controls.cmbPriority ($null -eq (Get-PriorityById $TaskInput.PriorityId))
}

function Update-TaskDialogSide {
    $td = $script:Td; $n = $td.N
    if (-not $td.TaskId) { return }
    $t = Get-TaskById $td.TaskId
    if ($null -eq $t) { return }
    $st = $script:State.Settings
    $closed = Test-StatusClosed $t.statusId $st.statuses
    if ($closed) {
        $n.txtScore.Text = '—'; $n.barScore.Value = 0
        $n.txtBreakdown.Text = (T 'Closed task: excluded from the priority ranking.')
    } else {
        $b = Get-ScoreBreakdown $t $st (Get-Date); $w = $st.scoring.weights
        $n.txtScore.Text = $b.Total.ToString('0.0', $script:UiCulture); $n.barScore.Value = $b.Total
        $n.txtBreakdown.Text = ("{0}: {1}  ×{2}%`n{3}: {4}  ×{5}%`n{6}: {7}  ×{8}%`n{9}: {10}  ×{11}%" -f
            (T 'Priority'), $b.Priority.ToString('0', $script:UiCulture), $w.priority,
            (T 'Due date'), $b.Deadline.ToString('0', $script:UiCulture), $w.deadline,
            (T 'Reminders'), $b.Reminders.ToString('0', $script:UiCulture), $w.reminders,
            (T 'Age'), $b.Age.ToString('0', $script:UiCulture), $w.age)
    }
    $n.txtRemCount.Text = [string]$t.reminders
    $last = ConvertTo-DateTimeValue $t.lastReminderAt
    $n.txtRemLast.Text = $(if ($last) { (T 'Last: ') + $last.ToString((($st.dateFormat) + ' HH:mm'), $script:UiCulture) } else { (T 'No reminders logged') })
    $n.btnRemind.IsEnabled = -not $closed
    $n.btnUnRemind.IsEnabled = ([int]$t.reminders -gt 0)
    $c = ConvertTo-DateTimeValue $t.createdAt; $u = ConvertTo-DateTimeValue $t.updatedAt; $d = ConvertTo-DateTimeValue $t.completedAt
    $meta = (T 'Created {0}  ·  Last modified {1}' $c.ToString(($st.dateFormat + ' HH:mm'), $script:UiCulture) $u.ToString(($st.dateFormat + ' HH:mm'), $script:UiCulture))
    if ($d) { $meta += (T '  ·  Completed {0}' $d.ToString(($st.dateFormat + ' HH:mm'), $script:UiCulture)) }
    $n.txtMeta.Text = $meta
    $items = foreach ($h in (Get-TaskHistory $t.id)) {
        [pscustomobject]@{ text = $h.text; when = (ConvertTo-DateTimeValue $h.at).ToString(($st.dateFormat + ' HH:mm'), $script:UiCulture) }
    }
    $n.lstHistory.ItemsSource = @($items)
}

# ------------------------------------------------------------------ About

function Show-AboutDialog {
    param([switch]$NoModal)
    $w = Import-Xaml 'AboutDialog.xaml'
    $n = Get-Named $w 'aboutLogo', 'aboutVersion', 'aboutData', 'aboutChangeData', 'aboutCopy', 'aboutWebsite', 'aboutDonate', 'aboutOpenData', 'aboutClose'
    $logo = Get-BrandImage $(if ($script:CurrentTheme -eq 'dark') { 'nexora-logo-white.png' } else { 'nexora-logo.png' })
    if ($null -ne $logo) { $n.aboutLogo.Source = $logo } else { $n.aboutLogo.Visibility = 'Collapsed' }
    $n.aboutVersion.Text = (T 'Version {0}' (Get-AppVersion))
    $n.aboutData.Text = $script:DataPath
    $n.aboutCopy.Text = (T '© {0} Manuel Tonello. All rights reserved.' (Get-Date).Year)
    $script:Ab = @{ W = $w; N = $n }
    On $n.aboutClose 'Click' { param($s, $e) $script:Ab.W.Close() }
    On $n.aboutWebsite 'Click' { param($s, $e) Open-PublisherWebsite }
    On $n.aboutDonate 'Click' { param($s, $e) Open-DonatePage }
    On $n.aboutOpenData 'Click' { param($s, $e) Start-Process explorer.exe -ArgumentList ('"' + $script:DataPath + '"') }
    On $n.aboutChangeData 'Click' { param($s, $e)
        Invoke-ChooseDataFolder -Owner $script:Ab.W
        $script:Ab.N.aboutData.Text = $script:DataPath
    }
    $n.aboutClose.IsCancel = $true; $n.aboutClose.IsDefault = $true
    Set-DialogOwner $w
    if ($NoModal) { $w.Show(); return $w }
    [void]$w.ShowDialog()
}
