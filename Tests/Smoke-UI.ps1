# Smoke-UI.ps1 - UI tests: creates the real window, navigates between screens, simulates the main actions
# and saves PNG screenshots. Briefly shows the windows on screen.
# Usage: powershell -STA -File Tests\Smoke-UI.ps1 -OutDir <screenshot folder>
param([string]$OutDir = (Join-Path ([IO.Path]::GetTempPath()) 'nexora-shots'))

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
foreach ($f in 'Modules\Utils.ps1', 'Modules\Strings.ps1', 'Modules\AppInfo.ps1', 'Modules\Storage.ps1', 'Modules\Priority.ps1', 'Modules\Config.ps1', 'Modules\Tasks.ps1', 'UI\Theme.ps1', 'UI\Dialogs.ps1', 'UI\Ui.ps1') {
    . (Join-Path $root "src\$f")
}
$script:TestMode = $true
$script:UiErrors = @()
$script:ActivationEventName = 'Local\NEXORA-UI-' + [guid]::NewGuid().ToString('N')
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('nexora-ui-' + [guid]::NewGuid().ToString('N'))
$script:DataPath = $tmp
Initialize-Storage -DataPath $tmp
$null = Initialize-AppState

# test data
$today = (Get-Date).Date
function Seed([string]$code, [string]$title, [string]$desc, [string]$ref, [string]$status, [string]$prio, $due, [int]$rem = 0, [string]$link = '') {
    $t = Add-AppTask @{ Code = $code; Title = $title; Description = $desc; Referent = $ref; Link = $link; StatusId = $status; PriorityId = $prio; DueDate = $due }
    for ($i = 0; $i -lt $rem; $i++) { $null = Add-TaskReminder $t.id }
    return $t
}
$null = Seed 'DEV-1024' 'Correggere il login con SSO' "Gli utenti AD ricevono errore 500.`nVerificare il token." 'Anna Rossi' 'doing' 'urgent' $today.AddDays(-2) 3
$null = Seed 'DEV-1025' 'Aggiornare la documentazione API' 'Aggiungere gli endpoint v2' 'Marco Bianchi' 'todo' 'medium' $today.AddDays(6)
$null = Seed 'OPS-210' 'Rinnovo certificato wildcard' '' 'Anna Rossi' 'waiting' 'high' $today 1
$null = Seed 'OPS-211' 'Migrazione backup su nuovo NAS' 'In attesa di hardware' 'Luca Verdi' 'blocked' 'high' $today.AddDays(3) 2
$null = Seed 'HR-12' 'Preparare onboarding nuovo collega' '' 'Giulia Neri' 'todo' 'low' $null
$null = Seed 'DEV-1030' 'Refactoring modulo report' 'Ridurre la complessità' 'Marco Bianchi' 'todo' 'medium' $today.AddDays(20)
$null = Seed 'FIN-77' 'Chiusura trimestre' '' 'Giulia Neri' 'doing' 'high' $today.AddDays(1) 1
$null = Seed 'DEV-1001' 'Setup pipeline CI' '' 'Anna Rossi' 'done' 'medium' $today.AddDays(-10)
$null = Seed 'DEV-1002' 'Revisione policy password' '' 'Luca Verdi' 'done' 'low' $null
$script:State.Settings.userName = 'Anna Rossi'; Save-Settings

function Shot([string]$name) {
    $w = $script:Win
    $w.UpdateLayout()
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$w.ActualWidth, [int]$w.ActualHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($w)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create((Join-Path $OutDir "$name.png")); $enc.Save($fs); $fs.Dispose()
}
function ShotWin($win, [string]$name) {
    $win.UpdateLayout()
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$win.ActualWidth, [int]$win.ActualHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($win)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create((Join-Path $OutDir "$name.png")); $enc.Save($fs); $fs.Dispose()
}
function Queue-ItemDialogSave([string]$Name, [string]$Value = '', [switch]$TestValidation) {
    $script:SmokeItemName = $Name
    $script:SmokeItemValue = $Value
    $script:SmokeItemValidation = [bool]$TestValidation
    $script:SmokeItemTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:SmokeItemTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:SmokeItemTimer.add_Tick({
        param($s, $e)
        $s.Stop()
        if ($script:SmokeItemValidation) {
            $script:Id.N.itmName.Text = ''
            $script:Id.N.itmSave.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            $script:Id.W.UpdateLayout()
            $itemNameBorder = $script:Id.N.itmName.Template.FindName('bd', $script:Id.N.itmName)
            Check 'nome elemento obbligatorio evidenziato in rosso' ($script:Id.N.itmName.Tag -eq 'invalid' -and $itemNameBorder.BorderBrush.Color -eq $script:App.Resources['DangerBrush'].Color -and $itemNameBorder.Background.Color -eq $script:App.Resources['DangerInputBgBrush'].Color)
            $script:Id.N.itmName.Text = $script:SmokeItemName
            if ($script:Id.N.itmColorPanel.Visibility -eq [System.Windows.Visibility]::Visible) {
                $script:Id.N.itmColor.Text = 'invalid'
                $script:Id.N.itmSave.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
                $script:Id.W.UpdateLayout()
                $itemColorBorder = $script:Id.N.itmColor.Template.FindName('bd', $script:Id.N.itmColor)
                Check 'colore elemento obbligatorio evidenziato in rosso' ($script:Id.N.itmColor.Tag -eq 'invalid' -and $itemColorBorder.BorderBrush.Color -eq $script:App.Resources['DangerBrush'].Color -and $itemColorBorder.Background.Color -eq $script:App.Resources['DangerInputBgBrush'].Color)
                $script:Id.N.itmColor.Text = '#3B82F6'
            }
            if ($script:Id.ShowValue) {
                $script:Id.N.itmValue.Text = 'invalid'
                $script:Id.N.itmSave.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
                $script:Id.W.UpdateLayout()
                $itemValueBorder = $script:Id.N.itmValue.Template.FindName('bd', $script:Id.N.itmValue)
                Check 'valore numerico obbligatorio evidenziato in rosso' ($script:Id.N.itmValue.Tag -eq 'invalid' -and $itemValueBorder.BorderBrush.Color -eq $script:App.Resources['DangerBrush'].Color -and $itemValueBorder.Background.Color -eq $script:App.Resources['DangerInputBgBrush'].Color)
                $script:Id.N.itmValue.Text = $script:SmokeItemValue
            }
        }
        $script:Id.N.itmName.Text = $script:SmokeItemName
        if ($script:Id.ShowValue) { $script:Id.N.itmValue.Text = $script:SmokeItemValue }
        $script:Id.N.itmSave.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    })
    $script:SmokeItemTimer.Start()
}

$script:Results = @()
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    $script:Results += [pscustomobject]@{ Name = $name; Ok = $ok; Detail = $detail }
    Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'OK  ' } else { 'FAIL' }), $name, $detail) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
}
function global:Start-Process { param([string]$FilePath) $script:OpenedTaskLink = $FilePath }
function Find-VisualChild {
    param($Element, [type]$Type)
    if ($null -eq $Element) { return $null }
    if ($Type.IsInstanceOfType($Element)) { return $Element }
    if ($Element -isnot [System.Windows.DependencyObject]) { return $null }
    for ($i = 0; $i -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Element); $i++) {
        $found = Find-VisualChild ([System.Windows.Media.VisualTreeHelper]::GetChild($Element, $i)) $Type
        if ($found) { return $found }
    }
    return $null
}

$app = Initialize-Wpf
Set-Theme 'dark'
$w = New-MainWindow
$defaultWindowWidth = $w.Width
$w.Height = 820

$u = $script:Ui
$steps = New-Object System.Collections.Generic.Queue[scriptblock]
$steps.Enqueue({
    Check 'larghezza iniziale include la colonna di selezione' ($defaultWindowWidth -eq 1560) "larghezza=$defaultWindowWidth"
    $rows = @($u.grid.ItemsSource)
    Check 'dashboard: solo task aperti' ($rows.Count -eq 7) "righe=$($rows.Count)"
    $scores = @($u.grid.Items | ForEach-Object { $_.ScoreValue })
    $sorted = @($scores | Sort-Object -Descending)
    Check 'dashboard: ordinata per punteggio decrescente' (($scores -join ',') -eq ($sorted -join ',')) ($scores -join ' > ')
    Check 'dashboard: statistiche' ($u.txtOpen.Text -eq '7' -and $u.txtDone.Text -eq '2' -and [int]$u.txtOverdue.Text -ge 1) "aperti=$($u.txtOpen.Text) urgenti=$($u.txtUrgent.Text) scaduti=$($u.txtOverdue.Text) completati=$($u.txtDone.Text)"
    Check 'dashboard: primo = task scaduto e sollecitato' ($u.grid.Items[0].Code -eq 'DEV-1024') $u.grid.Items[0].Code
    Check 'checkbox column is first' ($u.grid.Columns[$script:ColBulk].Width.Value -eq 42)
    Check 'dropdowns and buttons use the hand cursor' ($u.cmbStatus.Cursor -eq [System.Windows.Input.Cursors]::Hand -and $u.btnEdit.Cursor -eq [System.Windows.Input.Cursors]::Hand)
    Load-SettingsView
    Check 'background behavior defaults to startup enabled and hide-on-close enabled' ($script:State.Settings.openOnStartup -and $script:State.Settings.hideOnClose -and $u.chkOpenOnStartup.IsChecked -and $u.chkHideOnClose.IsChecked)
    $previousHideOnClose = $script:State.Settings.hideOnClose
    try {
        $script:State.Settings.hideOnClose = $true
        Update-TrayIcon -Enabled $true
        $w.Close()
        Check 'close hides the window but keeps the tray icon running' (-not $w.IsVisible -and $null -ne $script:Tray -and $script:Tray.NotifyIcon.Visible -and $script:Tray.OpenItem.Text -eq 'Open NEXORA' -and $script:Tray.ExitItem.Text -eq 'Exit NEXORA')
        Check 'a second launch signals the existing instance' (Request-ExistingInstanceActivation)
        Invoke-PendingInstanceActivation
        Check 'a second launch restores the hidden main window without an error dialog' ($w.IsVisible -and $script:UiErrors.Count -eq 0)
        $w.Hide()
        $script:Tray.OpenItem.PerformClick()
        Check 'tray restore brings the window back' $w.IsVisible
    } finally {
        $script:State.Settings.hideOnClose = $previousHideOnClose
        Update-TrayIcon -Enabled $previousHideOnClose
    }
    $bulkRows = @($u.grid.Items | Select-Object -First 2)
    $bulkChecks = @()
    foreach ($row in $bulkRows) {
        $u.grid.ScrollIntoView($row); $u.grid.UpdateLayout()
        $cell = $u.grid.Columns[$script:ColBulk].GetCellContent($row)
        $bulkChecks += Find-VisualChild $cell ([System.Windows.Controls.CheckBox])
    }
    $checkboxesWork = ($bulkChecks.Count -eq 2 -and $bulkChecks[0].IsEnabled -and $bulkChecks[1].IsEnabled -and $null -ne $bulkChecks[0].Command -and $null -ne $bulkChecks[1].Command)
    Check 'caselle di selezione interattive' $checkboxesWork
    if ($checkboxesWork) {
        foreach ($check in $bulkChecks) {
            $check.IsChecked = $true
            $check.Command.Execute($check.CommandParameter, $check)
        }
    }
    $checkedCount = @(Get-BulkSelectedTaskIds).Count
    Check 'bulk checkbox state stores both rows' ($checkedCount -eq 2) "checked=$checkedCount values=$($bulkRows[0].BulkSelected),$($bulkRows[1].BulkSelected)"
    $otherRow = $u.grid.Items | Where-Object { -not $_.BulkSelected -and -not $_.IsClosed } | Select-Object -First 1
    $u.grid.SelectedItem = $otherRow
    Update-ActionButtons
    Check 'i pulsanti normali restano attivi con più righe selezionate' ($u.btnEdit.IsEnabled -and $u.btnReminder.IsEnabled -and $u.btnDuplicate.IsEnabled -and $u.btnDelete.IsEnabled)
    Check 'i tooltip indicano che Duplica/Elimina agiscono sulle checkbox' ($u.btnDuplicate.ToolTip -eq 'Duplicate checked tasks' -and $u.btnDelete.ToolTip -eq 'Delete checked tasks (Del)')
    $savedBulkDuplicate = (Get-Command Invoke-BulkDuplicateTasks).ScriptBlock
    $savedBulkDelete = (Get-Command Invoke-BulkDeleteTasks).ScriptBlock
    $script:SmokeBulkDuplicateIds = @()
    $script:SmokeBulkDeleteIds = @()
    try {
        Set-Item Function:\Invoke-BulkDuplicateTasks -Value { $script:SmokeBulkDuplicateIds = @(Get-BulkSelectedTaskIds) }
        Set-Item Function:\Invoke-BulkDeleteTasks -Value { $script:SmokeBulkDeleteIds = @(Get-BulkSelectedTaskIds) }
        $u.btnDuplicate.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        $u.btnDelete.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    } finally {
        Set-Item Function:\Invoke-BulkDuplicateTasks -Value $savedBulkDuplicate
        Set-Item Function:\Invoke-BulkDeleteTasks -Value $savedBulkDelete
    }
    Check 'i pulsanti Duplica ed Elimina normali agiscono sulle checkbox selezionate' ($script:SmokeBulkDuplicateIds.Count -eq 2 -and $script:SmokeBulkDeleteIds.Count -eq 2)
    $savedTaskDialog = (Get-Command Show-TaskDialog).ScriptBlock
    $script:SmokeEditedTaskId = ''
    try {
        Set-Item Function:\Show-TaskDialog -Value { param([string]$TaskId = '', [switch]$NoModal) $script:SmokeEditedTaskId = $TaskId; return $false }
        Invoke-EditTask (Get-SelectedTaskId)
    } finally { Set-Item Function:\Show-TaskDialog -Value $savedTaskDialog }
    Check 'la modifica agisce sulla riga attiva anche con altre checkbox spuntate' ($script:SmokeEditedTaskId -eq $otherRow.Id) $script:SmokeEditedTaskId
    if ($checkboxesWork) {
        foreach ($check in $bulkChecks) {
            $check.IsChecked = $false
            $check.Command.Execute($check.CommandParameter, $check)
        }
    }
    Shot '01-dashboard-dark'
})
$steps.Enqueue({ $u.cardOverdue.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
$steps.Enqueue({
    Check 'filtro rapido scaduti' ($u.grid.Items.Count -eq 1) "righe=$($u.grid.Items.Count)"
    $u.cardOpen.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
})
$steps.Enqueue({
    $u.txtSearch.Text = 'anna'
})
$steps.Enqueue({
    Check 'ricerca per referente' ($u.grid.Items.Count -eq 2) "righe=$($u.grid.Items.Count)"
    $u.txtSearch.Text = 'OPS-21'
})
$steps.Enqueue({
    Check 'ricerca per codice' ($u.grid.Items.Count -eq 2) "righe=$($u.grid.Items.Count)"
    $u.txtSearch.Text = 'refactoring'
})
$steps.Enqueue({
    Check 'ricerca per titolo' ($u.grid.Items.Count -eq 1) "righe=$($u.grid.Items.Count)"
    $u.btnClear.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    $u.navAll.IsChecked = $true
})
$steps.Enqueue({
    Check 'tutti i task: 9 righe, chiusi in fondo' ($u.grid.Items.Count -eq 9 -and $u.grid.Items[8].IsClosed) "righe=$($u.grid.Items.Count)"
    $u.cmbStatus.SelectedIndex = 2   # In lavorazione
})
$steps.Enqueue({
    Check 'filtro per stato' ($u.grid.Items.Count -eq 2) "righe=$($u.grid.Items.Count)"
    $u.cmbStatus.SelectedIndex = 0
    # manual sort by code via header event
    $col = $u.grid.Columns[$script:ColCode]
    $script:ManualSort = $true
    $u.grid.Items.SortDescriptions.Clear()
    $u.grid.Items.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('Code', 'Ascending')))
    Refresh-Tasks
})
$steps.Enqueue({
    $codes = @($u.grid.Items | ForEach-Object { $_.Code })
    Check 'ordinamento manuale persiste al refresh' ($codes[0] -eq 'DEV-1001') ($codes -join ',')
    $noDescRow = $u.grid.Items | Where-Object { $_.Code -eq 'HR-12' } | Select-Object -First 1
    $descRow = $u.grid.Items | Where-Object { $_.Code -eq 'DEV-1025' } | Select-Object -First 1
    Check 'tooltip titolo: nessuna descrizione -> nessun tooltip (non un riquadro vuoto)' ($null -ne $noDescRow -and $null -eq $noDescRow.Description)
    Check 'tooltip titolo: con descrizione mostra il testo' ($null -ne $descRow -and $descRow.Description -eq 'Aggiungere gli endpoint v2')
    $gridScroll = Find-VisualChild $u.grid ([System.Windows.Controls.ScrollViewer])
    Check 'larghezza iniziale: tutte le colonne (Link incluso) visibili senza scorrimento orizzontale' ($null -ne $gridScroll -and $gridScroll.ScrollableWidth -lt 1) "scorrimento=$($gridScroll.ScrollableWidth)"
    Shot '02-all-dark'
    $u.navMine.IsChecked = $true
})
$steps.Enqueue({
    Check 'i miei task (Anna Rossi)' ($u.grid.Items.Count -eq 3) "righe=$($u.grid.Items.Count)"
    $u.navByRef.IsChecked = $true
})
$steps.Enqueue({
    Check 'per referente: raggruppato' ($u.grid.Items.Groups.Count -eq 4) "gruppi=$($u.grid.Items.Groups.Count)"
    $groupedRows = @($u.grid.ItemsSource | Select-Object -First 2)
    foreach ($row in $groupedRows) { $row.BulkSelected = $true }
    Check 'le checkbox funzionano anche nella vista raggruppata' (@(Get-BulkSelectedTaskIds).Count -eq 2)
    foreach ($row in $groupedRows) { $row.BulkSelected = $false }
    Update-ActionButtons
    Shot '03-byref-dark'
    $u.navDone.IsChecked = $true
})
$steps.Enqueue({
    Check 'completati: 2 righe' ($u.grid.Items.Count -eq 2) "righe=$($u.grid.Items.Count)"
    $ccol = $u.grid.Columns[$script:ColCompleted]
    Check 'completati: colonna data di completamento visibile' ($ccol.Visibility -eq 'Visible')
    Check 'completati: ordinamento di default per data di completamento decrescente' ($ccol.SortDirection -eq 'Descending' -and $u.grid.Items.SortDescriptions[0].PropertyName -eq 'CompletedSort')
    Check 'completati: date di completamento valorizzate e in ordine decrescente' ($u.grid.Items[0].CompletedText -ne '—' -and $u.grid.Items[0].CompletedSort -ge $u.grid.Items[1].CompletedSort)
    $u.navDashboard.IsChecked = $true
})
$steps.Enqueue({
    Check 'colonna data di completamento nascosta fuori da Completati' ($u.grid.Columns[$script:ColCompleted].Visibility -eq 'Collapsed')
})
$steps.Enqueue({
    # first-run name question: the helper types the name and saves the dialog; the same name is restored afterwards
    $script:State.Settings.userName = ''
    Check 'nome obbligatorio: la domanda serve se manca il nome' (Test-UserNamePromptNeeded)
    Queue-ItemDialogSave 'Anna Rossi'
    Invoke-UserNamePrompt
    Check 'nome obbligatorio: nome salvato e domanda non piu'' necessaria' ($script:State.Settings.userName -eq 'Anna Rossi' -and -not (Test-UserNamePromptNeeded))
    # Settings: the name field is required like the other preference fields
    $u.txtUserName.Text = ''; [void](Get-PreferenceValidation $u)
    Check 'Impostazioni: nome vuoto segnalato come non valido' ($u.txtUserName.Tag -eq 'invalid')
    $u.txtUserName.Text = 'Anna Rossi'; [void](Get-PreferenceValidation $u)
    Check 'Impostazioni: nome valido, campo non segnalato' ($u.txtUserName.Tag -ne 'invalid')
    # "My tasks" without a name shows a message bar: its top corners must be rounded like the card around it
    $script:State.Settings.userName = ''; $u.navMine.IsChecked = $true
    $infoBar = $u.txtInfo.Parent
    Check 'My tasks senza nome: messaggio visibile con gli angoli superiori arrotondati' ($u.txtInfo.Visibility -eq 'Visible' -and $infoBar.CornerRadius.TopLeft -ge 8 -and $infoBar.CornerRadius.TopRight -ge 8) "raggio=$($infoBar.CornerRadius)"
    Shot '03b-mine-no-name'
    $script:State.Settings.userName = 'Anna Rossi'; $u.navDashboard.IsChecked = $true
    # Complete button: a selected open task goes straight to Done (a temporary task keeps the other checks unchanged)
    $cmpTask = Add-AppTask @{ Code = 'CMP-UI'; Title = 'Task per il pulsante Completa'; Description = ''; Referent = ''; Link = ''; StatusId = 'todo'; PriorityId = 'urgent'; DueDate = $null }
    Refresh-All
    $u.grid.SelectedItem = $null; Update-ActionButtons
    Check 'pulsante Completa: disabilitato senza selezione' (-not $u.btnComplete.IsEnabled)
    $cmpRow = $u.grid.Items | Where-Object { $_.Id -eq $cmpTask.id } | Select-Object -First 1
    $u.grid.SelectedItem = $cmpRow; Update-ActionButtons
    Check 'pulsante Completa: abilitato su un task aperto' ($u.btnComplete.IsEnabled)
    $cmpMenu = Show-RowMenu
    $cmpItem = $u.grid.ContextMenu.Items | Where-Object { $_.Tag -eq 'complete' } | Select-Object -First 1
    Check 'menu contestuale: voce Completa presente e attiva su un task aperto' ($cmpMenu -and $null -ne $cmpItem -and $cmpItem.IsEnabled)
    $u.btnComplete.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    $cmpDone = Get-TaskById $cmpTask.id
    Check 'pulsante Completa: il task passa in stato Done con data di completamento' ($cmpDone.statusId -eq 'done' -and [bool]$cmpDone.completedAt) "stato=$($cmpDone.statusId)"
    Check 'pulsante Completa: il task esce dall''elenco dei task aperti' ($null -eq ($u.grid.Items | Where-Object { $_.Id -eq $cmpTask.id }))
    $u.navAll.IsChecked = $true
    $cmpRow = $u.grid.Items | Where-Object { $_.Id -eq $cmpTask.id } | Select-Object -First 1
    $u.grid.SelectedItem = $cmpRow; Update-ActionButtons
    Check 'pulsante Completa: disabilitato su un task gia'' completato' ($null -ne $cmpRow -and -not $u.btnComplete.IsEnabled)
    [void](Show-RowMenu)
    $cmpItem = $u.grid.ContextMenu.Items | Where-Object { $_.Tag -eq 'complete' } | Select-Object -First 1
    Check 'menu contestuale: voce Completa disattivata su un task gia'' completato' ($null -ne $cmpItem -and -not $cmpItem.IsEnabled)
    Remove-AppTask $cmpTask.id
    $u.navDashboard.IsChecked = $true
    Refresh-All
    # selection + quick reminder
    $u.grid.SelectedIndex = 1
    $id = Get-SelectedTaskId; $before = (Get-TaskById $id).reminders
    $u.btnReminder.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    Check 'sollecito rapido da pulsante' ((Get-TaskById $id).reminders -eq $before + 1) "da $before a $((Get-TaskById $id).reminders)"
    $script:dlg = Show-TaskDialog -TaskId $id -NoModal
    $script:dlg.UpdateLayout()
    Check 'dialogo di modifica usa altezza estesa' ([math]::Abs($script:dlg.ActualHeight - $script:dlg.Height) -lt 1) "altezza=$($script:dlg.ActualHeight)"
})
$steps.Enqueue({
    ShotWin $script:dlg '04-task-dialog-dark'
    $script:Td.N.btnRemind.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    Check 'sollecito dal dettaglio aggiorna contatore' ($script:Td.N.txtRemCount.Text -ne '0') $script:Td.N.txtRemCount.Text
    $script:Td.N.txtTitle.Text = 'Titolo modificato dal test'
    $script:Td.N.txtLink.Text = 'https://example.test/edited'
    $script:Td.N.txtDue.Text = 'data-sbagliata'
    Save-TaskDialog
    Check 'validazione data errata nel dialogo' ($script:Td.N.txtError.Visibility -eq 'Visible') $script:Td.N.txtError.Text
    $script:Td.N.txtDue.Text = (Get-Date).AddDays(4).ToString('dd/MM/yyyy')
    Save-TaskDialog
})
$steps.Enqueue({
    $t = $script:State.Tasks | Where-Object { $_.title -eq 'Titolo modificato dal test' }
    Check 'modifica dal dialogo salvata' ($null -ne $t)
    Check 'link modificato dal dialogo salvato' ($t.link -eq 'https://example.test/edited') $t.link
    Refresh-All
    $script:dlg = Show-TaskDialog -NoModal
    $script:dlg.UpdateLayout()
    Check 'dialogo di creazione usa altezza estesa' ([math]::Abs($script:dlg.ActualHeight - $script:dlg.Height) -lt 1) "altezza=$($script:dlg.ActualHeight)"
})
$steps.Enqueue({
    ShotWin $script:dlg '05-new-task-dark'
    $n = $script:Td.N
    # the due-date calendar must be large enough to read comfortably (it used to be the tiny default size)
    $n.calPopup.IsOpen = $true; $n.calendar.UpdateLayout()
    ShotWin $n.calendar.Parent '05c-calendar-dark'   # the popup card (dark background) around the calendar
    Check 'calendario scadenza: abbastanza grande da leggere' ($n.calendar.ActualWidth -ge 265 -and $n.calendar.ActualHeight -ge 275) "dimensioni=$([int]$n.calendar.ActualWidth)x$([int]$n.calendar.ActualHeight)"
    # picking a day still fills the due-date field (and closes the popup)
    $pickDate = (Get-Date).Date.AddDays(3)
    $n.calendar.SelectedDate = $pickDate
    Check 'calendario scadenza: la data scelta riempie il campo e chiude il popup' ($n.txtDue.Text -eq (Format-AppDate $pickDate $script:State.Settings) -and -not $n.calPopup.IsOpen) $n.txtDue.Text
    $n.txtDue.Text = ''
    # month/year picker (opened by clicking the calendar header) uses the restyled month buttons
    $n.calPopup.IsOpen = $true; $n.calendar.DisplayMode = 'Year'; $n.calendar.UpdateLayout()
    ShotWin $n.calendar.Parent '05d-calendar-months-dark'
    $calItem = Find-VisualChild $n.calendar ([System.Windows.Controls.Primitives.CalendarItem])
    $mv = $calItem.Template.FindName('PART_MonthView', $calItem); $yv = $calItem.Template.FindName('PART_YearView', $calItem)
    Check 'calendario scadenza: vista dei mesi leggibile' ($n.calendar.ActualWidth -ge 240 -and $n.calendar.ActualHeight -ge 200 -and $yv.Visibility -eq 'Visible' -and $mv.Visibility -ne 'Visible' -and $yv.Children.Count -ge 12) "mode=$($n.calendar.DisplayMode) month=$($mv.Visibility)/$($mv.Children.Count) year=$($yv.Visibility)/$($yv.Children.Count)"
    $n.calendar.DisplayMode = 'Month'
    $n.calPopup.IsOpen = $false
    $n.txtTitle.Text = ''
    Save-TaskDialog
    $script:Td.W.UpdateLayout()
    $titleBorder = $n.txtTitle.Template.FindName('bd', $n.txtTitle)
    Check 'titolo obbligatorio evidenziato in rosso' ($n.txtTitle.Tag -eq 'invalid' -and $titleBorder.BorderBrush.Color -eq $script:App.Resources['DangerBrush'].Color -and $titleBorder.Background.Color -eq $script:App.Resources['DangerInputBgBrush'].Color)
    Check 'solo il titolo non valido è evidenziato' ($n.txtCode.Tag -ne 'invalid' -and $n.cmbStatus.Tag -ne 'invalid' -and $n.cmbPriority.Tag -ne 'invalid')
    $errorPoint = $n.txtError.TransformToAncestor($n.taskFormScroll).Transform([System.Windows.Point]::new(0, 0))
    $errorBottom = $errorPoint.Y + $n.txtError.ActualHeight
    Check 'titolo obbligatorio visibile senza scorrere' ($n.txtError.IsVisible -and $n.taskFormScroll.VerticalOffset -eq 0 -and $errorBottom -le $n.taskFormScroll.ViewportHeight) $n.txtError.Text
    $defaultTaskCode = $n.txtCode.Text
    $n.txtTitle.Text = 'Task con codice mancante'
    $n.txtCode.Text = ''
    Save-TaskDialog
    Check 'solo il codice non valido è evidenziato' ($n.txtCode.Tag -eq 'invalid' -and $n.txtTitle.Tag -ne 'invalid' -and $n.cmbStatus.Tag -ne 'invalid' -and $n.cmbPriority.Tag -ne 'invalid')
    $n.txtCode.Text = $defaultTaskCode
    $n.txtTitle.Text = 'Task creato dal test UI'
    $n.txtLink.Text = 'https://example.test/new-task'
    Check 'referente senza assegnazione disponibile' ($null -ne ($n.cmbReferent.Items | Where-Object { -not $_.IsCreateAction -and $_.value -eq '' }))
    Queue-ItemDialogSave 'Stato creato dal task' '8' -TestValidation
    $n.cmbStatus.SelectedIndex = $n.cmbStatus.Items.Count - 1
    $statusCreated = $n.cmbStatus.SelectedItem.name
    Check 'creazione stato dal menu del task' ($statusCreated -eq 'Stato creato dal task' -and $n.txtTitle.Text -eq 'Task creato dal test UI') $statusCreated
    Check 'creazione stato: il peso nel punteggio scelto nel dialogo e'' salvato' ((Get-StatusScoreValue $n.cmbStatus.SelectedItem.id $script:State.Settings.statuses) -eq 8) "peso=$((Get-StatusScoreValue $n.cmbStatus.SelectedItem.id $script:State.Settings.statuses))"
    Queue-ItemDialogSave 'Priorità creata dal task' '12' -TestValidation
    $n.cmbPriority.SelectedIndex = $n.cmbPriority.Items.Count - 1
    $priorityCreated = $n.cmbPriority.SelectedItem.name
    Check 'creazione priorità dal menu del task' ($priorityCreated -eq 'Priorità creata dal task' -and $n.txtTitle.Text -eq 'Task creato dal test UI') $priorityCreated
    Queue-ItemDialogSave 'Referente creato dal task'
    Check 'referente non modificabile in linea' (-not $n.cmbReferent.IsEditable)
    $n.cmbReferent.SelectedIndex = $n.cmbReferent.Items.Count - 1
    Check 'creazione referente dal menu del task' ($n.cmbReferent.SelectedItem.value -eq 'Referente creato dal task' -and $n.txtTitle.Text -eq 'Task creato dal test UI') $n.cmbReferent.SelectedItem.name
    Check 'progetto: (nessun progetto) disponibile e preselezionato' ($null -ne ($n.cmbProject.Items | Where-Object { -not $_.IsCreateAction -and $_.value -eq '' }) -and $n.cmbProject.SelectedItem.value -eq '')
    Check 'progetto non modificabile in linea' (-not $n.cmbProject.IsEditable)
    Queue-ItemDialogSave 'Progetto creato dal task'
    $n.cmbProject.SelectedIndex = $n.cmbProject.Items.Count - 1
    Check 'creazione progetto dal menu del task' ($n.cmbProject.SelectedItem.value -eq 'Progetto creato dal task' -and $n.txtTitle.Text -eq 'Task creato dal test UI') $n.cmbProject.SelectedItem.name
    Check 'cliente: (nessun cliente) disponibile e preselezionato' ($null -ne ($n.cmbClient.Items | Where-Object { -not $_.IsCreateAction -and $_.value -eq '' }) -and $n.cmbClient.SelectedItem.value -eq '')
    Check 'cliente non modificabile in linea' (-not $n.cmbClient.IsEditable)
    Queue-ItemDialogSave 'Cliente creato dal task'
    $n.cmbClient.SelectedIndex = $n.cmbClient.Items.Count - 1
    Check 'creazione cliente dal menu del task' ($n.cmbClient.SelectedItem.value -eq 'Cliente creato dal task' -and $n.txtTitle.Text -eq 'Task creato dal test UI' -and $n.cmbProject.SelectedItem.value -eq 'Progetto creato dal task') $n.cmbClient.SelectedItem.name
    $n.txtDue.Text = (Get-Date).ToString('dd/MM/yyyy')
    Save-TaskDialog
})
$steps.Enqueue({
    Refresh-All
    $createdTask = $script:State.Tasks | Where-Object { $_.title -eq 'Task creato dal test UI' } | Select-Object -First 1
    Check 'nuovo task dal dialogo' ($null -ne $createdTask)
    Check 'referente selezionato salvato nel task' ($createdTask.referent -eq 'Referente creato dal task') $createdTask.referent
    Check 'progetto selezionato salvato nel task' ($createdTask.project -eq 'Progetto creato dal task') $createdTask.project
    Check 'cliente selezionato salvato nel task' ($createdTask.client -eq 'Cliente creato dal task') $createdTask.client
    Check 'altri task restano senza cliente' (@($script:State.Tasks | Where-Object { -not $_.client }).Count -eq ($script:State.Tasks.Count - 1))
    $clientRow = $u.grid.Items | Where-Object { $_.Id -eq $createdTask.id } | Select-Object -First 1
    Check 'riga mostra il cliente' ($clientRow.Client -eq 'Cliente creato dal task') $clientRow.Client
    Check 'filtro clienti: tutte le voci + il cliente creato' ($u.cmbClient.Items.Count -eq 2 -and $u.cmbClient.Items[1].name -eq 'Cliente creato dal task')
    $u.cmbClient.SelectedIndex = 1
    Check 'filtro per cliente mostra solo i task del cliente' ($u.grid.Items.Count -eq 1 -and $u.grid.Items[0].Id -eq $createdTask.id) "righe=$($u.grid.Items.Count)"
    $u.btnClear.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    Check 'Clear azzera anche il filtro cliente' ($u.cmbClient.SelectedIndex -eq 0 -and $u.grid.Items.Count -gt 1)
    $u.txtSearch.Text = 'Cliente creato'
    Check 'la ricerca trova anche per cliente' ($u.grid.Items.Count -eq 1) "righe=$($u.grid.Items.Count)"
    $u.txtSearch.Text = ''
    $u.navByClient.IsChecked = $true
    Check 'vista Per cliente: raggruppata per cliente, icona negozio, colonna cliente nascosta' ($u.grid.Items.Groups.Count -eq 2 -and $u.grid.Tag -eq [string][char]0xE719 -and $u.grid.Columns[$script:ColClient].Visibility -eq 'Collapsed') "gruppi=$($u.grid.Items.Groups.Count)"
    $clientGroupNames = @($u.grid.Items.Groups | ForEach-Object { $_.Name })
    Check 'vista Per cliente: gruppo (senza cliente) e gruppo del cliente' ($clientGroupNames -contains 'Cliente creato dal task' -and $clientGroupNames -contains (T '(no client)')) ($clientGroupNames -join ', ')
    Check 'altri task restano senza progetto' (@($script:State.Tasks | Where-Object { -not $_.project }).Count -eq ($script:State.Tasks.Count - 1))
    $projRow = $u.grid.Items | Where-Object { $_.Id -eq $createdTask.id } | Select-Object -First 1
    $otherRow = $u.grid.Items | Where-Object { $_.Id -ne $createdTask.id } | Select-Object -First 1
    Check 'riga mostra il progetto, le altre il trattino' ($projRow.Project -eq 'Progetto creato dal task' -and $otherRow.Project -eq '—') "$($projRow.Project) / $($otherRow.Project)"
    Check 'filtro progetti: tutte le voci + il progetto creato' ($u.cmbProject.Items.Count -eq 2 -and $u.cmbProject.Items[1].name -eq 'Progetto creato dal task')
    $u.cmbProject.SelectedIndex = 1
    Check 'filtro per progetto mostra solo i task del progetto' ($u.grid.Items.Count -eq 1 -and $u.grid.Items[0].Id -eq $createdTask.id) "righe=$($u.grid.Items.Count)"
    $u.btnClear.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    Check 'Clear azzera anche il filtro progetto' ($u.cmbProject.SelectedIndex -eq 0 -and $u.grid.Items.Count -gt 1)
    $u.txtSearch.Text = 'Progetto creato'
    Check 'la ricerca trova anche per progetto' ($u.grid.Items.Count -eq 1) "righe=$($u.grid.Items.Count)"
    $u.txtSearch.Text = ''
    $u.navByProject.IsChecked = $true
    Check 'vista Per progetto: raggruppata per progetto, icona cartella' ($u.grid.Items.Groups.Count -eq 2 -and $u.grid.Tag -eq [string][char]0xE8B7 -and $u.grid.Columns[$script:ColProject].Visibility -eq 'Collapsed') "gruppi=$($u.grid.Items.Groups.Count)"
    $groupNames = @($u.grid.Items.Groups | ForEach-Object { $_.Name })
    Check 'vista Per progetto: gruppo (senza progetto) e gruppo del progetto' ($groupNames -contains 'Progetto creato dal task' -and $groupNames -contains (T '(no project)')) ($groupNames -join ', ')
    $u.navByRef.IsChecked = $true
    Check 'vista Per referente: icona persona ripristinata' ($u.grid.Tag -eq [string][char]0xE77B)
    Check 'link del nuovo task salvato e visibile nella riga' ($createdTask.link -eq 'https://example.test/new-task' -and ($u.grid.Items | Where-Object { $_.Id -eq $createdTask.id }).Link -eq $createdTask.link) $createdTask.link
    $script:OpenedTaskLink = ''
    $linkRow = $u.grid.Items | Where-Object { $_.Id -eq $createdTask.id } | Select-Object -First 1
    $u.grid.ScrollIntoView($linkRow); $u.grid.UpdateLayout()
    $linkCell = $u.grid.Columns[$script:ColLink].GetCellContent($linkRow)
    $linkButton = Find-VisualChild $linkCell ([System.Windows.Controls.Button])
    Check 'riga task ha il comando configurato' ($null -ne $linkRow.LinkCommand) ([string]$linkRow.LinkCommand)
    Check 'riga con link mostra il pulsante di apertura' ($null -ne $linkButton -and $linkButton.Visibility -eq 'Visible')
    Check 'pulsante Link allineato a sinistra' ($null -ne $linkButton -and $linkButton.HorizontalAlignment -eq 'Left')
    Check 'pulsante collegato al comando di apertura' ($null -ne $linkButton -and $null -ne $linkButton.Command)
    if ($linkButton -and $linkButton.Command) { $linkButton.Command.Execute($linkButton.CommandParameter, $linkButton) }
    Check 'pulsante passa al browser il solo URL valido' ($script:OpenedTaskLink -eq 'https://example.test/new-task')
    $noLinkRow = $u.grid.Items | Where-Object { [string]::IsNullOrWhiteSpace($_.Link) } | Select-Object -First 1
    $u.grid.ScrollIntoView($noLinkRow); $u.grid.UpdateLayout()
    $noLinkCell = $u.grid.Columns[$script:ColLink].GetCellContent($noLinkRow)
    $noLinkButton = Find-VisualChild $noLinkCell ([System.Windows.Controls.Button])
    Check 'nessun pulsante per i task senza link' ($null -ne $noLinkButton -and $noLinkButton.Visibility -eq 'Collapsed')
    $u.grid.ScrollIntoView($linkRow); $u.grid.UpdateLayout()
    Shot '05b-task-link-column-dark'
    $unsafeLinkRejected = $false
    try { Open-TaskLink 'javascript:alert(1)' } catch { $unsafeLinkRejected = $true }
    Check 'apertura di schemi diversi da HTTP/HTTPS rifiutata' $unsafeLinkRejected
    Check 'nuovo task urgente/oggi in cima' ($u.grid.Items.Count -ge 1) $u.grid.Items[0].Code
    $u.navSettings.IsChecked = $true
})
$steps.Enqueue({
    Shot '06-settings-dark'
    Check 'Impostazioni: elenco clienti con il cliente creato' (@($u.lstClients.ItemsSource | Where-Object { $_.name -eq 'Cliente creato dal task' }).Count -eq 1)
    Check 'Impostazioni: elenco progetti con il progetto creato' (@($u.lstProjects.ItemsSource | Where-Object { $_.name -eq 'Progetto creato dal task' }).Count -eq 1)
    Check 'data-folder controls visible with copy enabled by default' ($u.chkMoveData.IsChecked -and $u.btnChangeDataFolder.Content -eq 'Change data folder…' -and $u.txtDataPath.Text -like '*tasks.json*')
    $folderChoice = Import-Xaml 'DataFolderChoiceDialog.xaml'
    $folderChoiceButtons = Get-Named $folderChoice 'folderChoiceOverwrite', 'folderChoiceKeep', 'folderChoiceMerge', 'folderChoiceCancel'
    Check 'dialogo cartella dati offre le quattro scelte richieste' ($folderChoiceButtons.Count -eq 4)
    $newFolder = Join-Path $OutDir 'ABC'
    New-Item -ItemType Directory -Path $newFolder -Force | Out-Null
    $pickerSelection = Join-Path $newFolder (T 'Select this folder')
    Check 'il selettore risolve il nome aggiornato della nuova cartella' ((Resolve-FolderPickerPath -Selection $pickerSelection -Placeholder (T 'Select this folder')) -eq [IO.Path]::GetFullPath($newFolder))
    $script:OpenedTaskLink = ''
    $u.btnWebsiteSettings.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    Check 'link Settings apre il sito autore' ($script:OpenedTaskLink -eq 'https://www.txnello.com/') $script:OpenedTaskLink
    # test weight change from slider: the sum stays 100
    $u.sldPriority.Value = 60
    $sum = [int]$u.sldPriority.Value + [int]$u.sldDeadline.Value + [int]$u.sldReminders.Value + [int]$u.sldAge.Value
    Check 'pesi: dopo aver mosso un cursore somma = 100' ($sum -eq 100) "somma=$sum"
    $script:WeightTimer.Stop(); Set-ScoringWeights $u.sldPriority.Value $u.sldDeadline.Value $u.sldReminders.Value $u.sldAge.Value
    Check 'pesi salvati in settings' (($script:State.Settings.scoring.weights.priority) -eq 60)
    $errorsBeforeValidation = $script:UiErrors.Count
    $u.txtNoDue.Text = ''
    $u.txtAgeCap.Text = ''
    $u.txtUrgent2.Text = ''
    $u.btnParamsSave.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    $scoreBorder = $u.txtNoDue.Template.FindName('bd', $u.txtNoDue)
    Check 'tutti i parametri numerici non validi sono evidenziati' ($u.txtNoDue.Tag -eq 'invalid' -and $u.txtAgeCap.Tag -eq 'invalid' -and $u.txtUrgent2.Tag -eq 'invalid' -and $scoreBorder.BorderBrush.Color -eq $script:App.Resources['DangerBrush'].Color -and $scoreBorder.Background.Color -eq $script:App.Resources['DangerInputBgBrush'].Color)
    Check 'errori parametri mostrati inline senza popup' ($u.txtParamsError.Visibility -eq 'Visible' -and $u.txtParamsError.Text -match 'Due date score when missing' -and $u.txtParamsError.Text -match 'Age cap' -and $u.txtParamsError.Text -match 'Urgent threshold' -and $script:UiErrors.Count -eq $errorsBeforeValidation)
    $u.txtNoDue.Text = '40'
    $u.txtAgeCap.Text = '90'
    $u.txtUrgent2.Text = '70'
    Check 'errori ed evidenziazioni parametri rimossi quando corretti' ($u.txtNoDue.Tag -ne 'invalid' -and $u.txtAgeCap.Tag -ne 'invalid' -and $u.txtUrgent2.Tag -ne 'invalid' -and $u.txtParamsError.Visibility -eq 'Collapsed')
    Reset-ScoringDefaults; Load-SettingsView
    $u.settingsView.ScrollToEnd()
    $prefixBeforeValidation = $u.txtPrefix.Text
    $backupsBeforeValidation = $u.txtMaxBackups.Text
    $errorsBeforeValidation = $script:UiErrors.Count
    $u.txtPrefix.Text = ''
    $u.txtMaxBackups.Text = ''
    $u.btnPrefSave.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    $prefixBorder = $u.txtPrefix.Template.FindName('bd', $u.txtPrefix)
    Check 'prefisso e backup non validi evidenziati' ($u.txtPrefix.Tag -eq 'invalid' -and $u.txtMaxBackups.Tag -eq 'invalid' -and $prefixBorder.BorderBrush.Color -eq $script:App.Resources['DangerBrush'].Color -and $prefixBorder.Background.Color -eq $script:App.Resources['DangerInputBgBrush'].Color)
    Check 'errori preferenze mostrati inline senza popup' ($u.txtPrefError.Visibility -eq 'Visible' -and $u.txtPrefError.Text -match 'code prefix' -and $u.txtPrefError.Text -match 'Backups to keep' -and $script:UiErrors.Count -eq $errorsBeforeValidation)
    $u.txtPrefix.Text = $prefixBeforeValidation
    $u.txtMaxBackups.Text = $backupsBeforeValidation
    Check 'errori ed evidenziazioni preferenze rimossi quando corretti' ($u.txtPrefix.Tag -ne 'invalid' -and $u.txtMaxBackups.Tag -ne 'invalid' -and $u.txtPrefError.Visibility -eq 'Collapsed')
    $u.chkOpenOnStartup.IsChecked = $false
    $u.chkHideOnClose.IsChecked = $true
    $autoSavedPreferences = Read-JsonStrict (Get-DataFilePath 'settings.json')
    Check 'startup/background checkboxes save immediately without the preferences button' (-not $autoSavedPreferences.openOnStartup -and $autoSavedPreferences.hideOnClose)
    $u.btnPrefSave.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    Check 'startup and hide-on-close preferences save and create the tray icon' (-not $script:State.Settings.openOnStartup -and $script:State.Settings.hideOnClose -and $null -ne $script:Tray)
    $savedPreferences = Read-JsonStrict (Get-DataFilePath 'settings.json')
    Check 'startup and hide-on-close preferences persist to disk' (-not $savedPreferences.openOnStartup -and $savedPreferences.hideOnClose)
    $w.Close()
    Check 'closing after saving hide-on-close keeps NEXORA running' (-not $w.IsVisible -and $null -ne $script:Tray -and $script:Tray.NotifyIcon.Visible)
    $script:Tray.OpenItem.PerformClick()
    Check 'tray restores NEXORA after the saved close behavior' $w.IsVisible
    $u.chkOpenOnStartup.IsChecked = $true
    $u.chkHideOnClose.IsChecked = $false
    $autoSavedPreferences = Read-JsonStrict (Get-DataFilePath 'settings.json')
    Check 'disabling startup/background checkboxes is saved immediately' ($autoSavedPreferences.openOnStartup -and -not $autoSavedPreferences.hideOnClose)
    $u.btnPrefSave.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    Check 'startup and hide-on-close preferences can be disabled again' ($script:State.Settings.openOnStartup -and -not $script:State.Settings.hideOnClose -and $null -eq $script:Tray)
})
$steps.Enqueue({
    # language change on save: English -> Italian
    Check 'language is English before saving' ($script:Ui.txtTitle.Text -eq 'Settings') $script:Ui.txtTitle.Text
    $script:Ui.cmbLanguage.SelectedIndex = 1
    Check 'language does not change before Save' ($script:Ui.txtTitle.Text -eq 'Settings')
    $script:Ui.btnPrefSave.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
})
$steps.Enqueue({
    $script:u = $script:Ui; $script:w = $script:Win
    Check 'language switched to Italian on save' ($u.txtTitle.Text -eq 'Impostazioni' -and $script:State.Settings.language -eq 'it') $u.txtTitle.Text
    Check 'default status names translated' ((Get-StatusById 'todo').name -eq 'Da fare')
    Check 'window keeps the settings view' ($u.settingsView.Visibility -eq 'Visible')
    Shot '06b-settings-italian-dark'
    $u.navDashboard.IsChecked = $true
})
$steps.Enqueue({
    Check 'Italian dashboard texts' ($u.cardOpen.ToolTip -eq 'Mostra tutti i task aperti') "$($u.cardOpen.ToolTip)"
    Shot '06c-dashboard-italian-dark'
    $u.navSettings.IsChecked = $true
})
$steps.Enqueue({
    $u.cmbLanguage.SelectedIndex = 0
    $u.btnPrefSave.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
})
$steps.Enqueue({
    $script:u = $script:Ui; $script:w = $script:Win
    Check 'switched back to English on save' ($u.txtTitle.Text -eq 'Settings' -and $script:State.Settings.language -eq 'en') $u.txtTitle.Text
    $u.settingsView.ScrollToEnd()
})
$steps.Enqueue({
    Shot '07-settings-bottom-dark'
    $u.btnTheme.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    $u.settingsView.ScrollToTop()
})
$steps.Enqueue({
    Check 'tema chiaro attivato e salvato' ($script:State.Settings.theme -eq 'light')
    Shot '08-settings-light'
    $u.navDashboard.IsChecked = $true
})
$steps.Enqueue({
    Shot '09-dashboard-light'
    $u.navAll.IsChecked = $true
    $script:dlg = Show-TaskDialog -TaskId ($script:State.Tasks[0].id) -NoModal
})
$steps.Enqueue({
    ShotWin $script:dlg '10-task-dialog-light'
    $script:Td.N.calPopup.IsOpen = $true; $script:Td.N.calendar.UpdateLayout()
    ShotWin $script:Td.N.calendar.Parent '10c-calendar-light'
    $script:Td.N.calPopup.IsOpen = $false
    $script:Td.W.Close()
    $w.Width = 900; $w.Height = 700
})
$steps.Enqueue({
    Shot '11-narrow-light'
    foreach ($bn in 'btnDonate', 'btnAbout', 'btnTheme') {
        $b = $u[$bn]; $inner = $b.ActualWidth - $b.BorderThickness.Left - $b.BorderThickness.Right - $b.Padding.Left - $b.Padding.Right
        Check "sidebar compatta: icona di $bn non tagliata" ($b.Content.ActualWidth -le ($inner + 0.5)) "contenuto=$($b.Content.ActualWidth) spazio=$inner"
    }
    $u.navDashboard.IsChecked = $true
    # change the status of all open tasks to 'done': empty dashboard
    foreach ($t in @($script:State.Tasks)) { $null = Set-AppTaskStatus $t.id 'done' }
    Refresh-All
})
$steps.Enqueue({
    Check 'dashboard vuota con stato vuoto visibile' ($u.emptyState.Visibility -eq 'Visible')
    Shot '12-empty-light'
})
$steps.Enqueue({
    $script:dlg = Show-AboutDialog -NoModal
})
$steps.Enqueue({
    ShotWin $script:dlg '13-about-light'
    Check 'About shows the version' ($script:Ab.W.FindName('aboutVersion').Text -match 'Version \d+\.\d+\.\d+') $script:Ab.W.FindName('aboutVersion').Text
    Check 'About shows the current data folder' ($script:Ab.N.aboutData.Text -eq $script:DataPath) $script:Ab.N.aboutData.Text
    $savedChooseDataFolder = (Get-Command Invoke-ChooseDataFolder).ScriptBlock
    $originalDataPath = $script:DataPath
    $script:SmokeExpectedAboutPath = Join-Path $env:TEMP 'NexoraAboutSmoke'
    $script:SmokeDataFolderOwner = $null
    try {
        Set-Item Function:\Invoke-ChooseDataFolder -Value { param($Owner) $script:SmokeDataFolderOwner = $Owner; $script:DataPath = $script:SmokeExpectedAboutPath }
        $script:Ab.N.aboutChangeData.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        Check 'About change-folder button reuses the folder flow and refreshes the path' ($script:SmokeDataFolderOwner -eq $script:Ab.W -and $script:Ab.N.aboutData.Text -eq $script:SmokeExpectedAboutPath) $script:Ab.N.aboutData.Text
    } finally {
        Set-Item Function:\Invoke-ChooseDataFolder -Value $savedChooseDataFolder
        $script:DataPath = $originalDataPath
        $script:Ab.N.aboutData.Text = $originalDataPath
    }
    $script:OpenedTaskLink = ''
    $script:Ab.W.FindName('aboutWebsite').RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    Check 'link About apre il sito autore' ($script:OpenedTaskLink -eq 'https://www.txnello.com/') $script:OpenedTaskLink
    Check 'main window has the NEXORA icon' ($null -ne $script:Win.Icon) ''
    Check 'main window is titled NEXORA' ($script:Win.Title -eq 'NEXORA') $script:Win.Title
    $script:Ab.W.Close()
})
$steps.Enqueue({
    Check 'nessun errore UI intercettato' ($script:UiErrors.Count -eq 0) ($script:UiErrors -join ' | ')
    $app.Shutdown()
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(450)
$timer.add_Tick({
    if ($steps.Count -eq 0) { $timer.Stop(); return }
    $s = $steps.Dequeue()
    try { & $s } catch { Check "step fallito" $false $_.Exception.Message; $script:UiErrors += $_.Exception.Message }
})
$w.add_Loaded({ $timer.Start() })
$app.add_DispatcherUnhandledException({ param($s, $e) Check 'eccezione non gestita' $false $e.Exception.Message; $e.Handled = $true })
[void]$app.Run($w)

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
$fail = @($script:Results | Where-Object { -not $_.Ok }).Count
Write-Host ("`nRisultato UI: {0} controlli, {1} falliti. Screenshot in {2}" -f $script:Results.Count, $fail, $OutDir) -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $(if ($fail) { 1 } else { 0 })
