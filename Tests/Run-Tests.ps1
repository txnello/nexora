# Run-Tests.ps1 - automatic logic tests (no UI). Uses a temporary data folder.
# Run:  pwsh -File Tests\Run-Tests.ps1     (also works with Windows PowerShell 5.1)

$ErrorActionPreference = 'Stop'
$script:TestMode = $true
$root = Split-Path -Parent $PSScriptRoot
foreach ($m in 'Utils', 'Strings', 'AppInfo', 'Storage', 'Priority', 'Config', 'Tasks') { . (Join-Path $root "src\Modules\$m.ps1") }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('nexora-test-' + [guid]::NewGuid().ToString('N'))
Initialize-Storage -DataPath $tmp

$script:pass = 0; $script:fail = 0
function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:pass++; Write-Host "  [OK]   $Name" -ForegroundColor Green }
    catch { $script:fail++; Write-Host "  [FAIL] $Name -> $($_.Exception.Message)" -ForegroundColor Red }
}
function Assert-True { param($Cond, [string]$Msg = 'condizione falsa') if (-not $Cond) { throw $Msg } }
function Assert-Eq { param($Actual, $Expected, [string]$Msg = '') if ($Actual -ne $Expected) { throw "attesi '$Expected', trovati '$Actual' $Msg" } }
function Assert-Throws { param([scriptblock]$Body, [string]$Msg = 'eccezione attesa') $ok = $false; try { & $Body } catch { $ok = $true }; if (-not $ok) { throw $Msg } }
function New-In { param([string]$Code, [string]$Title = 'Prova', $Due = $null, [string]$Prio = 'medium', [string]$Status = 'todo', [string]$Ref = 'Anna', [string]$Link = '')
    @{ Code = $Code; Title = $Title; Description = 'desc'; Referent = $Ref; Link = $Link; StatusId = $Status; PriorityId = $Prio; DueDate = $Due } }

Write-Host "`nNexora - test (PowerShell $($PSVersionTable.PSVersion))" -ForegroundColor Cyan
Write-Host "Cartella dati di test: $tmp`n"

Write-Host 'Primo avvio e persistenza' -ForegroundColor Yellow
Test-Case 'primo avvio senza file: crea settings/tasks/history con default' {
    $st = Initialize-AppState
    Assert-Eq $st.Tasks.Count 0
    Assert-Eq $st.Settings.statuses.Count 5
    Assert-Eq $st.Settings.priorities.Count 4
    Assert-True $st.Settings.openOnStartup 'avvio automatico non attivo per default'
    Assert-True $st.Settings.hideOnClose 'nascondi alla chiusura non attivo per default'
    Assert-Eq $st.Settings.preferencesVersion 2
    foreach ($f in 'tasks.json', 'settings.json', 'history.json') { Assert-True (Test-Path (Join-Path $tmp $f)) "manca $f" }
    Assert-Eq $st.Warnings.Count 0
}

Write-Host 'Creazione / modifica / eliminazione' -ForegroundColor Yellow
$today = (Get-Date).Date
Test-Case 'creazione task valido' {
    $t = Add-AppTask (New-In 'DEV-1024' 'Primo task' $today.AddDays(3))
    Assert-Eq $t.code 'DEV-1024'; Assert-Eq $script:State.Tasks.Count 1
    Assert-True ($null -ne $t.score) 'punteggio non calcolato'
}
Test-Case 'validazione: titolo/codice vuoti, codice duplicato, stato non valido' {
    Assert-Throws { Add-AppTask (New-In 'X-1' '') }
    Assert-Throws { Add-AppTask (New-In '' 'T') }
    Assert-Throws { Add-AppTask (New-In 'dev-1024' 'dup') } 'codice duplicato (case-insensitive) accettato'
    Assert-Throws { Add-AppTask (New-In 'X-2' 'T' $null 'medium' 'inesistente') }
    Assert-Throws { Add-AppTask (New-In 'bad code!' 'T') }
    Assert-Eq $script:State.Tasks.Count 1
}
Test-Case 'codice automatico progressivo' {
    $c = Get-NextTaskCode; Assert-Eq $c 'TSK-1001'
    $null = Add-AppTask (New-In $c 'Auto')
    Assert-Eq (Get-NextTaskCode) 'TSK-1002'
}
Test-Case 'modifica task: campi, cronologia, data modifica' {
    $t = Get-TaskById ($script:State.Tasks[0].id)
    $old = $t.updatedAt; Start-Sleep -Milliseconds 1100
    $null = Update-AppTask $t.id (New-In 'DEV-1024' 'Titolo nuovo' $today.AddDays(1) 'high' 'doing' 'Bruno')
    $t = Get-TaskById $t.id
    Assert-Eq $t.title 'Titolo nuovo'; Assert-Eq $t.referent 'Bruno'; Assert-Eq $t.statusId 'doing'
    Assert-True ($t.updatedAt -gt $old) 'updatedAt non aggiornato'
    $h = Get-TaskHistory $t.id
    Assert-True (@($h | Where-Object type -eq 'stato').Count -ge 1) 'manca voce di cronologia per lo stato'
}
Test-Case 'duplicazione task' {
    $src = $script:State.Tasks[0]
    $c = Copy-AppTask $src.id
    Assert-True ($c.id -ne $src.id); Assert-True ($c.code -ne $src.code); Assert-Eq $c.reminders 0
    Assert-True ($c.title -like '*(copy)')
}
Test-Case 'duplicazione multipla conserva i dati e genera codici unici' {
    $sources = @($script:State.Tasks[0], $script:State.Tasks[1])
    $copies = @(Copy-AppTasks @($sources[0].id, $sources[1].id))
    Assert-Eq $copies.Count 2
    Assert-True ($copies[0].id -ne $sources[0].id -and $copies[1].id -ne $sources[1].id)
    Assert-True ($copies[0].code -ne $copies[1].code)
    Assert-Eq $copies[0].title (T '{0} (copy)' $sources[0].title)
    Assert-Eq $copies[1].description $sources[1].description
    Assert-Eq $copies[0].reminders 0; Assert-Eq $copies[1].reminders 0
    Assert-Throws { Copy-AppTasks @($sources[0].id) }
}
Test-Case 'link facoltativo: validazione, persistenza, modifica, stato e duplicazione' {
    $url = 'https://example.test/tasks/42?view=full'
    $t = Add-AppTask (New-In 'LINK-1' 'Task con link' $null 'medium' 'todo' 'Anna' $url)
    Assert-Eq $t.link $url
    Assert-True (Test-TaskLink '')
    Assert-True (Test-TaskLink 'http://example.test')
    Assert-True (Test-TaskLink $url)
    Assert-True (-not (Test-TaskLink 'javascript:alert(1)'))
    Assert-True (-not (Test-TaskLink ('https://example.test/' + ('a' * 2049))))
    Assert-Throws { Add-AppTask (New-In 'LINK-2' 'Link non valido' $null 'medium' 'todo' 'Anna' 'javascript:alert(1)') }
    $taskInput = New-In 'LINK-1' 'Task con link' $null 'medium' 'doing' 'Anna'
    $taskInput.Remove('Link')
    $null = Update-AppTask $t.id $taskInput
    Assert-Eq (Get-TaskById $t.id).link $url 'aggiornamento senza Link deve preservare il collegamento'
    $copy = Copy-AppTask $t.id
    Assert-Eq $copy.link $url
    $null = Reload-AppState
    Assert-Eq (Get-TaskById $t.id).link $url 'link perso dopo round-trip JSON'
    $null = Update-AppTask $t.id (New-In 'LINK-1' 'Task senza link' $null 'medium' 'doing' 'Anna')
    Assert-Eq (Get-TaskById $t.id).link ''
}
Test-Case 'eliminazione task (con snapshot di sicurezza)' {
    $n = $script:State.Tasks.Count; $id = $script:State.Tasks[-1].id
    Remove-AppTask $id
    Assert-Eq $script:State.Tasks.Count ($n - 1)
    Assert-True ($null -eq (Get-TaskById $id))
    Assert-True (@(Get-Snapshots | Where-Object Reason -eq 'pre-delete').Count -ge 1) 'snapshot mancante'
}
Test-Case 'eliminazione multipla crea un solo snapshot e conserva la cronologia' {
    $copies = @($script:State.Tasks | Where-Object { $_.title -like '*(copy)' } | Select-Object -First 2)
    Assert-Eq $copies.Count 2
    $before = @(Get-Snapshots | Where-Object Reason -eq 'pre-delete').Count
    $removed = Remove-AppTasks @($copies[0].id, $copies[1].id)
    Assert-Eq $removed 2
    Assert-True ($null -eq (Get-TaskById $copies[0].id) -and $null -eq (Get-TaskById $copies[1].id))
    Assert-Eq @(Get-Snapshots | Where-Object Reason -eq 'pre-delete').Count ($before + 1)
    Assert-Eq @($script:State.History | Where-Object { $_.taskId -in @($copies[0].id, $copies[1].id) -and $_.type -eq 'eliminato' }).Count 2
    Assert-Throws { Remove-AppTasks @($script:State.Tasks[0].id) }
}
Test-Case 'salvataggio e ricaricamento JSON (round-trip)' {
    $before = $script:State.Tasks | ForEach-Object { "$($_.id)|$($_.code)|$($_.title)|$($_.dueDate)|$($_.statusId)|$($_.score)" }
    $st = Reload-AppState
    $after = $st.Tasks | ForEach-Object { "$($_.id)|$($_.code)|$($_.title)|$($_.dueDate)|$($_.statusId)|$($_.score)" }
    Assert-Eq ($after -join ';') ($before -join ';')
}

Write-Host 'Motore di prioritizzazione' -ForegroundColor Yellow
$S = (Get-DefaultSettings)
Test-Case 'fattori normalizzati 0..100' {
    foreach ($d in -30, -1, 0, 1, 7, 30, 365) { $v = Get-DeadlineFactor $today.AddDays($d) $today $S.scoring; Assert-True ($v -ge 0 -and $v -le 100) "scadenza $d -> $v" }
    foreach ($n in 0, 1, 5, 50) { $v = Get-ReminderFactor $n $S.scoring; Assert-True ($v -ge 0 -and $v -le 100) }
    foreach ($a in 0, 10, 90, 5000) { $v = Get-AgeFactor $today.AddDays(-$a) $today $S.scoring; Assert-True ($v -ge 0 -and $v -le 100) }
}
Test-Case 'scadenza: scaduto >= oggi > domani > lontano; nessuna scadenza = neutro' {
    $o = Get-DeadlineFactor $today.AddDays(-3) $today $S.scoring
    $t0 = Get-DeadlineFactor $today $today $S.scoring
    $t1 = Get-DeadlineFactor $today.AddDays(1) $today $S.scoring
    $t30 = Get-DeadlineFactor $today.AddDays(30) $today $S.scoring
    Assert-True ($o -ge $t0 -and $t0 -gt $t1 -and $t1 -gt $t30) "$o $t0 $t1 $t30"
    Assert-True ($o -eq 100); Assert-True ($t0 -ge 90)
    Assert-Eq (Get-DeadlineFactor $null $today $S.scoring) 40
}
Test-Case 'solleciti: crescenti, progressivi (rendimenti decrescenti) e limitati' {
    $a = 0..8 | ForEach-Object { Get-ReminderFactor $_ $S.scoring }
    for ($i = 1; $i -lt $a.Count; $i++) { Assert-True ($a[$i] -gt $a[$i - 1]) "non crescente a $i" }
    Assert-True (($a[1] - $a[0]) -gt ($a[8] - $a[7])) 'incrementi non decrescenti'
    Assert-True ((Get-ReminderFactor 1000 $S.scoring) -le 100)
}
Test-Case 'anzianita: cresce e si ferma al tetto' {
    $x = Get-AgeFactor $today.AddDays(-10) $today $S.scoring
    $y = Get-AgeFactor $today.AddDays(-60) $today $S.scoring
    Assert-True ($y -gt $x)
    Assert-Eq (Get-AgeFactor $today.AddDays(-90) $today $S.scoring) 100
    Assert-Eq (Get-AgeFactor $today.AddDays(-900) $today $S.scoring) 100
}
Test-Case 'priorita manuale: min=0, max=100, ordine rispettato' {
    $lv = $S.priorities
    Assert-Eq (Get-PriorityFactor 'low' $lv) 0; Assert-Eq (Get-PriorityFactor 'urgent' $lv) 100
    Assert-True ((Get-PriorityFactor 'high' $lv) -gt (Get-PriorityFactor 'medium' $lv))
}
Test-Case 'formula: punteggio = somma pesata dei fattori' {
    $t = [pscustomobject]@{ priorityId = 'high'; dueDate = Format-IsoDate $today.AddDays(2); reminders = 2; createdAt = Format-IsoDateTime $today.AddDays(-30) }
    $b = Get-ScoreBreakdown $t $S $today
    $exp = ($b.Priority * 35 + $b.Deadline * 35 + $b.Reminders * 20 + $b.Age * 10) / 100
    Assert-True ([math]::Abs($b.Total - $exp) -lt 0.15) "$($b.Total) vs $exp"
}
Test-Case 'la priorita manuale da sola non determina il punteggio' {
    $urg = [pscustomobject]@{ priorityId = 'urgent'; dueDate = $null; reminders = 0; createdAt = Format-IsoDateTime $today }
    $late = [pscustomobject]@{ priorityId = 'low'; dueDate = Format-IsoDate $today.AddDays(-2); reminders = 4; createdAt = Format-IsoDateTime $today.AddDays(-60) }
    Assert-True ((Get-TaskScore $late $S $today) -gt (Get-TaskScore $urg $S $today)) 'task scaduto+sollecitato dovrebbe superare urgente senza scadenza'
}
Test-Case 'pesi: somma sempre 100 dopo normalizzazione' {
    foreach ($set in @(@(35, 35, 20, 10), @(1, 1, 1, 1), @(50, 50, 50, 50), @(0, 0, 0, 0), @(33.3, 33.3, 33.3, 0.1), @(100, 0, 0, 0))) {
        $n = Get-NormalizedWeights ([double[]]$set); Assert-Eq (($n | Measure-Object -Sum).Sum) 100 ($set -join ',')
    }
    Set-ScoringWeights 10 10 10 10
    $w = $script:State.Settings.scoring.weights
    Assert-Eq ($w.priority + $w.deadline + $w.reminders + $w.age) 100
    Set-ScoringWeights 35 35 20 10
}
Test-Case 'cambiare i pesi cambia la classifica' {
    $a = Add-AppTask (New-In 'RK-1' 'solo priorita' $null 'urgent')
    $b = Add-AppTask (New-In 'RK-2' 'solo scadenza' $today 'low')
    Set-ScoringWeights 90 4 3 3; $r1 = (Get-TaskById $a.id).score - (Get-TaskById $b.id).score
    Set-ScoringWeights 4 90 3 3; $r2 = (Get-TaskById $a.id).score - (Get-TaskById $b.id).score
    Assert-True ($r1 -gt 0 -and $r2 -lt 0) "$r1 / $r2"
    Set-ScoringWeights 35 35 20 10
}

Write-Host 'Solleciti' -ForegroundColor Yellow
Test-Case 'registrazione sollecito: contatore, data, punteggio, cronologia' {
    $t = $script:State.Tasks[0]; $s0 = $t.score
    $null = Add-TaskReminder $t.id; $null = Add-TaskReminder $t.id
    $t = Get-TaskById $t.id
    Assert-Eq $t.reminders 2; Assert-True ($null -ne $t.lastReminderAt); Assert-True ($t.score -gt $s0)
    Assert-Eq (@(Get-TaskHistory $t.id | Where-Object type -eq 'sollecito').Count) 2
}
Test-Case 'annulla ultimo sollecito' {
    $t = $script:State.Tasks[0]
    $null = Undo-TaskReminder $t.id; $t = Get-TaskById $t.id
    Assert-Eq $t.reminders 1
    $null = Undo-TaskReminder $t.id; $t = Get-TaskById $t.id
    Assert-Eq $t.reminders 0; Assert-True ($null -eq $t.lastReminderAt)
}

Write-Host 'Stati personalizzabili' -ForegroundColor Yellow
Test-Case 'crea, rinomina, ricolora stato' {
    $s = Add-Status 'In revisione' '#8B5CF6' $false
    Assert-Eq $script:State.Settings.statuses.Count 6
    Update-Status $s.id 'In review' '#06B6D4' $false
    Assert-Eq (Get-StatusById $s.id).name 'In review'
    Assert-Throws { Add-Status 'in review' } 'nome duplicato accettato'
    Assert-Throws { Add-Status 'x' 'rosso' } 'colore non valido accettato'
}
Test-Case 'riordino stati' {
    $first = $script:State.Settings.statuses[0].id
    Move-Status $first 1
    Assert-Eq $script:State.Settings.statuses[1].id $first
    Move-Status $first -1
    Assert-Eq $script:State.Settings.statuses[0].id $first
}
Test-Case 'stato concluso: escluso dalla classifica e dalle statistiche aperte' {
    $t = Add-AppTask (New-In 'CL-1' 'da chiudere' $today 'urgent')
    Assert-True ($null -ne (Get-TaskById $t.id).score)
    $open0 = (Get-DashboardStats).Open
    $null = Set-AppTaskStatus $t.id 'done'
    $t = Get-TaskById $t.id
    Assert-True ($null -eq $t.score) 'task concluso ha ancora un punteggio'
    Assert-True ($null -ne $t.completedAt)
    Assert-Eq (Get-DashboardStats).Open ($open0 - 1)
    Assert-Throws { Add-TaskReminder $t.id } 'sollecito su task concluso accettato'
}
Test-Case 'configurare quali stati sono conclusi (cambia i conteggi)' {
    $s = Add-Status 'Archiviato' '#6B7280' $false
    $t = Add-AppTask (New-In 'AR-1' 'arch' $null 'medium' $s.id)
    $o = (Get-DashboardStats).Open
    Update-Status $s.id 'Archiviato' '#6B7280' $true
    Assert-Eq (Get-DashboardStats).Open ($o - 1)
    Assert-True ($null -eq (Get-TaskById $t.id).score)
    Update-Status $s.id 'Archiviato' '#6B7280' $false
    Assert-Eq (Get-DashboardStats).Open $o
}
Test-Case 'eliminazione stato in uso: i task vengono spostati' {
    $s = Add-Status 'Temp' '#EAB308' $false
    $t = Add-AppTask (New-In 'TM-1' 'tmp' $null 'medium' $s.id)
    $r = Remove-Status $s.id
    Assert-Eq $r.Moved 1; Assert-True ($null -ne (Get-StatusById (Get-TaskById $t.id).statusId))
}
Test-Case 'non si puo eliminare/chiudere l ultimo stato aperto' {
    $open = @($script:State.Settings.statuses | Where-Object { -not $_.isClosed })
    $ids = @($open | Select-Object -Skip 1 | ForEach-Object { $_.id })
    foreach ($id in $ids) { $null = Remove-Status $id }
    Assert-Throws { Remove-Status $open[0].id }
    $o = Get-StatusById $open[0].id
    Assert-Throws { Update-Status $o.id $o.name $o.color $true }
    # restore defaults for the subsequent tests
    $script:State.Settings.statuses = (Get-DefaultSettings).statuses; Save-Settings
    foreach ($t in $script:State.Tasks) { if (-not (Get-StatusById $t.statusId)) { $t.statusId = 'todo' } }
    Update-AllScoresAndSave
}

Write-Host 'Livelli di priorita' -ForegroundColor Yellow
Test-Case 'crea, modifica, elimina livello (con riassegnazione)' {
    $p = Add-PriorityLevel 'Critica' 5 '#DC2626'
    $t = Add-AppTask (New-In 'PR-1' 'p' $null $p.id)
    Assert-Eq (Get-PriorityFactor $p.id $script:State.Settings.priorities) 100
    Update-PriorityLevel $p.id 'Critica!' 6 '#DC2626'
    $r = Remove-PriorityLevel $p.id
    Assert-Eq $r.Moved 1; Assert-Eq (Get-TaskById $t.id).priorityId 'urgent'
}

Write-Host 'Referenti personalizzabili' -ForegroundColor Yellow
Test-Case 'crea, rinomina e riordina referente' {
    $r = Add-Referent 'Mario Rossi'
    Assert-True ($null -ne (Get-ReferentById $r.id))
    Update-Referent $r.id 'Mario R.'
    Assert-Eq (Get-ReferentById $r.id).name 'Mario R.'
    Assert-Throws { Add-Referent 'mario r.' } 'nome referente duplicato accettato'
    $s = Add-Referent 'Anna Verdi'
    $beforeIndex = $script:State.Settings.referents.IndexOf($s)
    Move-Referent $s.id -1
    if ($beforeIndex -gt 0) {
        Assert-Eq $script:State.Settings.referents[$beforeIndex - 1].id $s.id
    } else {
        Assert-Eq $script:State.Settings.referents[0].id $s.id
    }
}
Test-Case 'rinomina ed eliminazione referente aggiornano i task' {
    $r = Add-Referent 'Team Test'
    $t = Add-AppTask (New-In 'RF-1' 'referente' $null 'medium' 'todo' 'Team Test')
    Update-Referent $r.id 'Team QA'
    Assert-Eq (Get-TaskById $t.id).referent 'Team QA'
    $removed = Remove-Referent $r.id
    Assert-Eq $removed.Moved 1
    Assert-Eq (Get-TaskById $t.id).referent $removed.TargetName
}
Test-Case 'referenti dei task esistenti vengono importati nelle impostazioni' {
    $t = Add-AppTask (New-In 'RF-2' 'legacy owner' $null 'medium' 'todo' 'Legacy Owner')
    $script:State.Settings.referents = ConvertTo-List @()
    Save-Settings
    $st = Reload-AppState
    Assert-True ($null -ne ($st.Settings.referents | Where-Object { $_.name -ieq 'Legacy Owner' })) 'referente legacy non importato'
}

Write-Host 'Backup, ripristino, robustezza' -ForegroundColor Yellow
Test-Case 'export backup completo e import (ripristino)' {
    $n = $script:State.Tasks.Count
    $zip = Join-Path $tmp 'export-test.zip'
    $null = New-Snapshot -Reason 'manual' -DestinationFile $zip
    Assert-True (Test-Path $zip)
    $id = $script:State.Tasks[0].id
    Remove-AppTask $id
    Assert-Eq $script:State.Tasks.Count ($n - 1)
    Restore-BackupArchive $zip
    $st = Reload-AppState
    Assert-Eq $st.Tasks.Count $n; Assert-True ($null -ne (Get-TaskById $id))
    Assert-True (@(Get-Snapshots | Where-Object Reason -eq 'pre-import').Count -ge 1) 'manca snapshot pre-import'
}
Test-Case 'import di archivio non valido viene rifiutato senza toccare i dati' {
    $bad = Join-Path $tmp 'bad.zip'; Set-Content $bad 'non sono uno zip'
    $n = $script:State.Tasks.Count
    Assert-Throws { Restore-BackupArchive $bad }
    Assert-Eq (Reload-AppState).Tasks.Count $n
}
Test-Case 'tasks.json corrotto: ripristino automatico da .bak con avviso' {
    $null = Update-AppTask $script:State.Tasks[0].id (New-In $script:State.Tasks[0].code 'dopo-bak')  # genera un .bak recente
    $n = $script:State.Tasks.Count
    Set-Content (Join-Path $tmp 'tasks.json') '{ questo non e json'
    $st = Reload-AppState
    Assert-True ($st.Warnings.Count -ge 1) 'nessun avviso'
    Assert-Eq $st.Tasks.Count $n
    Assert-True (@(Get-ChildItem (Join-Path $tmp 'Backups') -Filter 'corrotto-*').Count -ge 1) 'file corrotto non conservato'
}
Test-Case 'file mancanti e JSON vuoto: l app riparte senza errori' {
    Remove-Item (Join-Path $tmp 'tasks.json'), (Join-Path $tmp 'tasks.json.bak'), (Join-Path $tmp 'settings.json') -ErrorAction SilentlyContinue
    Set-Content (Join-Path $tmp 'history.json') ''
    $st = Reload-AppState
    Assert-Eq $st.Tasks.Count 0; Assert-Eq $st.Settings.statuses.Count 5
    Assert-True (Test-Path (Join-Path $tmp 'tasks.json'))
}
Test-Case 'dati incoerenti nel JSON vengono riparati (stato/priorita inesistenti, date, duplicati)' {
    $raw = '{"version":1,"tasks":[{"id":"a","code":"Z-1","title":"x","statusId":"boh","priorityId":"boh","createdAt":"non-una-data","dueDate":"2026-13-45","reminders":-4,"link":"javascript:alert(1)"},{"id":"a","code":"z-1","title":"y"}]}'
    Set-Content (Join-Path $tmp 'tasks.json') $raw
    $st = Reload-AppState
    Assert-Eq $st.Tasks.Count 2
    Assert-True ($null -ne (Get-StatusById $st.Tasks[0].statusId)); Assert-True ($null -ne (Get-PriorityById $st.Tasks[0].priorityId))
    Assert-True ($st.Tasks[0].id -ne $st.Tasks[1].id); Assert-True ($st.Tasks[0].code -ne $st.Tasks[1].code)
    Assert-Eq $st.Tasks[0].reminders 0; Assert-True ($null -eq $st.Tasks[0].dueDate); Assert-Eq $st.Tasks[0].link ''
}
Test-Case 'scrittura atomica: nessun file .tmp residuo' {
    Assert-Eq @(Get-ChildItem $tmp -Filter '*.tmp').Count 0
}
Test-Case 'pulizia snapshot: tiene gli ultimi N, mai i manuali' {
    1..5 | ForEach-Object { $null = New-Snapshot -Reason 'auto'; Start-Sleep -Milliseconds 20 }
    $null = New-Snapshot -Reason 'manual'
    Remove-OldSnapshots -Keep 2
    Assert-Eq @(Get-Snapshots | Where-Object Reason -ne 'manual').Count 2
    Assert-True (@(Get-Snapshots | Where-Object Reason -eq 'manual').Count -ge 1)
}

Write-Host 'Formato date' -ForegroundColor Yellow
Test-Case 'formattazione e parsing nel formato configurato' {
    foreach ($f in Get-DateFormats) {
        $s = [pscustomobject]@{ dateFormat = $f }
        $txt = Format-AppDate ([datetime]'2026-03-09') $s
        $back = ConvertFrom-AppDate $txt $s
        Assert-Eq $back.Date ([datetime]'2026-03-09').Date "formato $f ('$txt')"
    }
    Assert-True ($null -eq (ConvertFrom-AppDate 'pippo' $null))
}
Test-Case 'suggerimento relativo della scadenza' {
    Assert-Eq (Format-DueHint $today $today) 'today'; Assert-Eq (Format-DueHint $today.AddDays(1) $today) 'tomorrow'
    Assert-Eq (Format-DueHint $today.AddDays(-3) $today) 'overdue by 3 days'; Assert-Eq (Format-DueHint $today.AddDays(5) $today) 'in 5 days'
}

Write-Host 'Product: version, data location, migration' -ForegroundColor Yellow
Test-Case 'version is Major.Minor.Patch and read from the VERSION file' {
    $v = Get-AppVersion
    Assert-True ($v -match '^\d+\.\d+\.\d+$') "version '$v'"
    Assert-Eq $v (([IO.File]::ReadAllText((Join-Path $root 'VERSION'))).Trim())
}
Test-Case 'personal data lives in LOCALAPPDATA\Nexora, never next to the application' {
    $save = $env:NEXORA_DATA; $saveLocal = $env:LOCALAPPDATA; $oldRoot = $script:AppRoot
    $env:NEXORA_DATA = $null
    $env:LOCALAPPDATA = Join-Path $tmp 'local-profile'
    $script:AppRoot = Join-Path $tmp 'no-portable-mode'
    try {
        $p = Get-DefaultDataPath
        Assert-Eq $p (Join-Path $env:LOCALAPPDATA 'Nexora')
        Assert-True (-not $p.StartsWith($script:AppRoot, 'OrdinalIgnoreCase')) 'data path inside the app folder'
        $custom = Join-Path $tmp 'cloud-data'
        Set-DataPathPreference -Path $custom
        Assert-Eq (Get-DefaultDataPath) $custom 'saved data path not used'
        $env:NEXORA_DATA = 'C:\x\override'; Assert-Eq (Get-DefaultDataPath) 'C:\x\override'
    } finally { $env:NEXORA_DATA = $save; $env:LOCALAPPDATA = $saveLocal; $script:AppRoot = $oldRoot }
}
Test-Case 'a second instance requests activation instead of showing an already-running error' {
    $previousEventName = $script:ActivationEventName
    $script:ActivationEventName = 'Local\NEXORA-Test-' + [guid]::NewGuid().ToString('N')
    $activation = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, $script:ActivationEventName)
    try {
        Assert-True (Request-ExistingInstanceActivation) 'activation event was not signaled'
        Assert-True ($activation.WaitOne(0)) 'activation request was not delivered to the existing instance'
    } finally {
        $activation.Dispose()
        $script:ActivationEventName = $previousEventName
    }
}
Test-Case 'MSIX declares an enabled startup task' {
    $manifestPath = Join-Path $root 'Build\MSIX\Package.appxmanifest'
    $manifest = New-Object System.Xml.XmlDocument
    $manifest.Load($manifestPath)
    $extension = $manifest.SelectSingleNode("//*[local-name()='Extension' and @Category='windows.startupTask']")
    $task = $null
    if ($extension) { $task = $extension.SelectSingleNode("./*[local-name()='StartupTask']") }
    Assert-True ($task -and $task.GetAttribute('TaskId') -eq 'NexoraStartup' -and
        $task.GetAttribute('Enabled') -eq 'true' -and $extension.GetAttribute('Executable') -eq 'Nexora.exe') 'MSIX startup task missing or disabled'
}
Test-Case 'legacy Data folder is COPIED to the new location (original untouched, nothing overwritten)' {
    $fakeRoot = Join-Path $tmp 'fakeapp'; New-Item -ItemType Directory -Force (Join-Path $fakeRoot 'Data') | Out-Null
    Set-Content (Join-Path $fakeRoot 'Data\tasks.json') '{"version":1,"tasks":[{"id":"z","code":"OLD-1","title":"legacy"}]}'
    Set-Content (Join-Path $fakeRoot 'Data\settings.json') '{"language":"it"}'
    $oldRoot = $script:AppRoot; $script:AppRoot = $fakeRoot
    try {
        $target = Join-Path $tmp 'newdata'
        Assert-True (Import-LegacyData -Target $target) 'not copied'
        Assert-True (Test-Path (Join-Path $target 'tasks.json')); Assert-True (Test-Path (Join-Path $fakeRoot 'Data\tasks.json')) 'legacy original removed!'
        Assert-Eq (Get-Content (Join-Path $target 'tasks.json') -Raw) (Get-Content (Join-Path $fakeRoot 'Data\tasks.json') -Raw)
        Set-Content (Join-Path $target 'tasks.json') 'USER CHANGES'
        Assert-True (-not (Import-LegacyData -Target $target)) 'second run must not copy again'
        Assert-Eq (Get-Content (Join-Path $target 'tasks.json') -Raw).Trim() 'USER CHANGES'
    } finally { $script:AppRoot = $oldRoot }
}
Test-Case 'migrated legacy files load with the current code (compatibility with existing JSON)' {
    $d = Join-Path $tmp 'compat'; New-Item -ItemType Directory -Force $d | Out-Null
    Set-Content (Join-Path $d 'tasks.json') '{"version":1,"tasks":[{"id":"a1","code":"DEV-1","title":"t","description":"","referent":"Ann","statusId":"todo","priorityId":"high","createdAt":"2026-01-01T10:00:00","updatedAt":"2026-01-02T10:00:00","dueDate":"2026-02-01","reminders":2,"lastReminderAt":"2026-01-03T10:00:00","completedAt":null,"score":50}]}'
    Initialize-Storage -DataPath $d
    $st = Initialize-AppState
    Assert-Eq $st.Tasks.Count 1; Assert-Eq $st.Tasks[0].code 'DEV-1'; Assert-Eq $st.Tasks[0].reminders 2
    Assert-Eq $st.Tasks[0].link ''
    Initialize-Storage -DataPath $tmp; $null = Initialize-AppState
}
Test-Case 'data folder switch protects existing data, copies current data, and persists the choice' {
    $saveLocal = $env:LOCALAPPDATA; $saveData = $env:NEXORA_DATA
    $env:LOCALAPPDATA = Join-Path $tmp 'switch-profile'
    $env:NEXORA_DATA = $null
    $source = $tmp
    $sourceLanguage = $script:State.Settings.language
    $target = Join-Path ([IO.Path]::GetTempPath()) ('nexora-cloud-' + [guid]::NewGuid().ToString('N'))
    $existing = Join-Path ([IO.Path]::GetTempPath()) ('nexora-existing-' + [guid]::NewGuid().ToString('N'))
    $merge = Join-Path ([IO.Path]::GetTempPath()) ('nexora-merge-' + [guid]::NewGuid().ToString('N'))
    try {
        Initialize-Storage -DataPath $target
        $null = Initialize-AppState
        Initialize-Storage -DataPath $existing
        $null = Initialize-AppState
        $null = Add-AppTask (New-In 'EXIST-1' 'Task gia presente nella destinazione')

        Initialize-Storage -DataPath $merge
        $null = Initialize-AppState
        $script:State.Settings.statuses.Add([pscustomobject]@{ id = 'shared-status'; name = 'Status B'; color = '#3B82F6'; isClosed = $false })
        $script:State.Settings.priorities.Add([pscustomobject]@{ id = 'shared-priority'; name = 'Priority B'; value = 5; color = '#3B82F6' })
        $script:State.Settings.referents.Add([pscustomobject]@{ id = 'shared-owner'; name = 'Owner B' })
        Save-Settings
        $targetMergeTask = Add-AppTask (New-In 'MERGE-COLLISION' 'Task B' $null 'shared-priority' 'shared-status' 'Owner B')
        $targetMergeTaskOldId = $targetMergeTask.id
        $targetMergeTask.id = 'shared-task-id'
        foreach ($entry in $script:State.History | Where-Object taskId -eq $targetMergeTaskOldId) { $entry.taskId = 'shared-task-id' }
        Save-Tasks; Save-History

        Initialize-Storage -DataPath $source
        $null = Initialize-AppState
        $script:State.Settings.statuses.Add([pscustomobject]@{ id = 'shared-status'; name = 'Status A'; color = '#10B981'; isClosed = $false })
        $script:State.Settings.priorities.Add([pscustomobject]@{ id = 'shared-priority'; name = 'Priority A'; value = 6; color = '#10B981' })
        $script:State.Settings.referents.Add([pscustomobject]@{ id = 'shared-owner'; name = 'Owner A' })
        $script:State.Settings.language = 'it'
        Convert-DefaultNames $script:State.Settings 'it'
        Save-Settings
        $sourceMergeTask = Add-AppTask (New-In 'MERGE-COLLISION' 'Task A' $null 'shared-priority' 'shared-status' 'Owner A')
        $sourceMergeTaskOldId = $sourceMergeTask.id
        $sourceMergeTask.id = 'shared-task-id'
        foreach ($entry in $script:State.History | Where-Object taskId -eq $sourceMergeTaskOldId) { $entry.taskId = 'shared-task-id' }
        Save-Tasks; Save-History
        $sourceCount = $script:State.Tasks.Count

        Assert-True (Switch-AppDataDirectory -Path $merge -Mode Merge)
        Assert-Eq $script:State.Tasks.Count ($sourceCount + 1) 'merge did not combine tasks from both folders'
        $taskA = $script:State.Tasks | Where-Object title -eq 'Task A' | Select-Object -First 1
        $taskB = $script:State.Tasks | Where-Object title -eq 'Task B' | Select-Object -First 1
        Assert-True ($taskA -and $taskB) 'tasks from both folders missing after merge'
        Assert-True ($taskA.id -ne $taskB.id) 'task ID collision was not resolved'
        Assert-True ($taskA.code -ne $taskB.code) 'code collision was not resolved'
        Assert-Eq $script:State.Settings.statuses.Count 7 'default statuses were duplicated across languages'
        Assert-Eq $script:State.Settings.priorities.Count 6 'default priorities were duplicated across languages'
        Assert-Eq (Get-StatusById $taskA.statusId).name 'Status A' 'source task status ID was not remapped'
        Assert-Eq (Get-StatusById $taskB.statusId).name 'Status B' 'destination task status changed'
        Assert-Eq (Get-PriorityById $taskA.priorityId).name 'Priority A' 'source task priority ID was not remapped'
        Assert-Eq (Get-PriorityById $taskB.priorityId).name 'Priority B' 'destination task priority changed'
        Assert-True ($script:State.Settings.referents | Where-Object name -eq 'Owner A') 'source owner missing after merge'
        Assert-True ($script:State.Settings.referents | Where-Object name -eq 'Owner B') 'destination owner missing after merge'
        Assert-True ($script:State.History | Where-Object { $_.taskId -eq $taskA.id }) 'source task history was not remapped'
        Assert-True ($script:State.History | Where-Object { $_.taskId -eq $taskB.id }) 'destination task history missing'
        Assert-True (Test-Path (Join-Path $merge 'Nexora-data-backup-*')) 'destination data was not backed up before merge'
        Assert-True (Test-Path (Join-Path $source 'tasks.json')) 'source data was moved or deleted by merge'
        Assert-True (Switch-AppDataDirectory -Path $source -Mode Keep)

        Assert-True (Switch-AppDataDirectory -Path $target -Mode Overwrite)
        Assert-Eq $script:DataPath $target
        Assert-Eq $script:State.Tasks.Count $sourceCount
        Assert-True (Test-Path (Join-Path $source 'tasks.json')) 'source data was moved or deleted'
        Assert-True (Test-Path (Join-Path $target 'tasks.json'))
        Assert-True (@(Get-ChildItem -LiteralPath $target -Directory -Filter 'Nexora-data-backup-*').Count -gt 0) 'previous destination data not backed up'
        Assert-Eq (Get-DefaultDataPath) $target 'selected folder not persisted'
        Assert-True (Switch-AppDataDirectory -Path $existing -Mode Keep)
        Assert-Eq $script:State.Tasks.Count 1 'without copy, destination data should be loaded as-is'
        Assert-Eq $script:State.Tasks[0].code 'EXIST-1'
        Assert-True (Switch-AppDataDirectory -Path $source -Mode Keep)
        Assert-Eq $script:DataPath $source
        Assert-Eq (Get-DefaultDataPath) $source
    } finally {
        if ($script:DataPath -ne $source) { $null = Switch-AppDataDirectory -Path $source -Mode Keep }
        Exit-DataPathMutex $script:DataMutex
        $script:DataMutex = $null
        $env:LOCALAPPDATA = $saveLocal; $env:NEXORA_DATA = $saveData
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        if (Test-Path -LiteralPath $existing) { Remove-Item -LiteralPath $existing -Recurse -Force }
        if (Test-Path -LiteralPath $merge) { Remove-Item -LiteralPath $merge -Recurse -Force }
        Initialize-Storage -DataPath $source
        $null = Initialize-AppState
        $script:State.Settings.language = $sourceLanguage
        Convert-DefaultNames $script:State.Settings $sourceLanguage
        Save-Settings
    }
}
Test-Case 'branding assets exist and the ICO has the 6 required resolutions' {
    $dir = Join-Path $root 'Assets\Branding'
    foreach ($f in 'nexora-logo.svg', 'nexora-logo.png', 'nexora-logo-white.png', 'nexora-symbol.svg', 'nexora-symbol.png', 'nexora-icon.ico', 'nexora-icon.png', 'nexora-splash.png') {
        Assert-True ((Test-Path (Join-Path $dir $f)) -and ((Get-Item (Join-Path $dir $f)).Length -gt 500)) "missing/empty $f"
    }
    $b = [IO.File]::ReadAllBytes((Join-Path $dir 'nexora-icon.ico'))
    Assert-Eq ([BitConverter]::ToUInt16($b, 2)) 1 'not an ICO'
    $n = [BitConverter]::ToUInt16($b, 4); $dims = @()
    for ($i = 0; $i -lt $n; $i++) { $w = $b[6 + 16 * $i]; $dims += $(if ($w -eq 0) { 256 } else { $w }) }
    foreach ($need in 16, 32, 48, 64, 128, 256) { Assert-True ($dims -contains $need) "ICO lacks $need px (has $($dims -join ','))" }
}

Write-Host 'Language (English default, Italian selectable)' -ForegroundColor Yellow
Test-Case 'default language is English, with English default names' {
    $st = Reload-AppState
    Assert-Eq $st.Settings.language 'en'
    Assert-Eq (Get-StatusById 'todo').name 'To do'; Assert-Eq (Get-PriorityById 'urgent').name 'Urgent'
    Set-Language 'en'
    Assert-Eq (T 'Task created') 'Task created'
}
Test-Case 'switching to Italian: texts, default names, culture and persistence' {
    Set-AppPreferences -Theme 'dark' -DateFormat 'dd/MM/yyyy' -CodePrefix 'TSK' -UserName '' -MaxBackups 30 -Language 'it'
    Set-Language 'it'
    Assert-Eq (T 'Task created') 'Task creato'
    Assert-Eq (T 'Task {0} deleted' 'X1') 'Task X1 eliminato'
    Assert-Eq (Get-StatusById 'todo').name 'Da fare'; Assert-Eq (Get-PriorityById 'urgent').name 'Urgente'
    Assert-Eq (Format-DueHint $today $today) 'oggi'
    $st = Reload-AppState
    Assert-Eq $st.Settings.language 'it'; Assert-Eq (Get-StatusById 'todo').name 'Da fare'
}
Test-Case 'startup and background preferences persist and default safely' {
    $savedStartupSetter = (Get-Command Set-StartupRegistration).ScriptBlock
    $requestStartupSetter = { param([bool]$Enabled) $script:StartupRequests += $Enabled }
    $script:StartupRequests = @()
    try {
        Set-Item Function:\Set-StartupRegistration -Value $requestStartupSetter
        Set-AppPreferences -Theme 'dark' -DateFormat 'dd/MM/yyyy' -CodePrefix 'TSK' -UserName '' -MaxBackups 30 -Language 'en' -OpenOnStartup $false -HideOnClose $true
        Assert-True (-not $script:State.Settings.openOnStartup) 'avvio automatico ancora attivo'
        Assert-True $script:State.Settings.hideOnClose 'nascondi alla chiusura non salvato'
        Assert-Eq $script:StartupRequests.Count 1
        Assert-True (-not $script:StartupRequests[0]) 'disattivazione avvio non propagata a Windows'
        Set-AppPreferences -Theme 'dark' -DateFormat 'dd/MM/yyyy' -CodePrefix 'TSK' -UserName '' -MaxBackups 30 -Language 'en' -OpenOnStartup $false -HideOnClose $true
        Assert-Eq $script:StartupRequests.Count 1 'salvataggio invariato ha riscritto la registrazione di startup'
        $st = Reload-AppState
        Assert-True (-not $st.Settings.openOnStartup) 'avvio automatico non persistito'
        Assert-True $st.Settings.hideOnClose 'nascondi alla chiusura non persistito'
        Set-AppPreferences -Theme 'dark' -DateFormat 'dd/MM/yyyy' -CodePrefix 'TSK' -UserName '' -MaxBackups 30 -Language 'en' -OpenOnStartup $false -HideOnClose $false
        $st = Reload-AppState
        Assert-True (-not $st.Settings.openOnStartup) 'avvio disattivato non persiste dopo il reload'
        Assert-True (-not $st.Settings.hideOnClose) 'background disattivato non persiste dopo il reload'
        $savedSettings = Read-JsonStrict (Get-DataFilePath 'settings.json')
        Assert-True (-not $savedSettings.openOnStartup -and -not $savedSettings.hideOnClose) 'preferenze disattivate non salvate nel JSON'
        Set-AppPreferences -Theme 'dark' -DateFormat 'dd/MM/yyyy' -CodePrefix 'TSK' -UserName '' -MaxBackups 30 -Language 'en' -OpenOnStartup $true -HideOnClose $true
        Assert-Eq $script:StartupRequests.Count 2
        Assert-True $script:StartupRequests[1] 'attivazione avvio non propagata a Windows'
        Set-Item Function:\Set-StartupRegistration -Value { param([bool]$Enabled) throw 'startup registration failed' }
        $registrationFailed = $false
        try {
            Set-AppPreferences -Theme 'dark' -DateFormat 'dd/MM/yyyy' -CodePrefix 'TSK' -UserName '' -MaxBackups 30 -Language 'en' -OpenOnStartup $false -HideOnClose $false
        } catch { $registrationFailed = $true }
        Assert-True $registrationFailed 'startup registration failure was not surfaced'
        $st = Reload-AppState
        Assert-True (-not $st.Settings.openOnStartup -and -not $st.Settings.hideOnClose) 'startup registration failure discarded saved preferences'
        Set-Item Function:\Set-StartupRegistration -Value $requestStartupSetter
    } finally {
        try {
            Set-AppPreferences -Theme 'dark' -DateFormat 'dd/MM/yyyy' -CodePrefix 'TSK' -UserName '' -MaxBackups 30 -Language 'en' -OpenOnStartup $true -HideOnClose $false
        } finally {
            Set-Item Function:\Set-StartupRegistration -Value $savedStartupSetter
        }
    }
}
Test-Case 'custom status names are not renamed by a language change' {
    $null = Update-Status 'doing' 'Mio stato' '#3B82F6' $false
    Set-AppPreferences -Theme 'dark' -DateFormat 'dd/MM/yyyy' -CodePrefix 'TSK' -UserName '' -MaxBackups 30 -Language 'en'
    Set-Language 'en'
    Assert-Eq (Get-StatusById 'doing').name 'Mio stato'; Assert-Eq (Get-StatusById 'todo').name 'To do'
    Assert-Throws { Set-AppPreferences -Theme 'dark' -DateFormat 'dd/MM/yyyy' -CodePrefix 'TSK' -UserName '' -MaxBackups 30 -Language 'xx' } 'invalid language accepted'
}
Test-Case 'legacy settings without language migrate to English default names' {
    $raw = '{"openOnStartup":true,"hideOnClose":false,"statuses":[{"id":"todo","name":"Da fare","color":"#6B7280","isClosed":false},{"id":"done","name":"Completato","color":"#10B981","isClosed":true}],"priorities":[{"id":"low","name":"Bassa","value":1,"color":"#6B7280"}]}'
    Set-Content (Join-Path $tmp 'settings.json') $raw
    $st = Reload-AppState
    Assert-Eq (Get-StatusById 'todo').name 'To do'; Assert-Eq (Get-PriorityById 'low').name 'Low'
    Assert-True $st.Settings.openOnStartup 'avvio automatico legacy non default true'
    Assert-True $st.Settings.hideOnClose 'preferenza legacy false non migrata al nuovo default'
    Assert-Eq $st.Settings.preferencesVersion 2
    $saved = Read-JsonStrict (Join-Path $tmp 'settings.json')
    Assert-True $saved.hideOnClose 'preferenza migrata non salvata su disco'
}
Test-Case 'every visible text in the XAML files has an Italian translation' {
    $miss = @()
    foreach ($f in Get-ChildItem (Join-Path $root 'src/UI') -Filter '*.xaml' | Where-Object Name -ne 'Styles.xaml') {
        $x = [IO.File]::ReadAllText($f.FullName)
        foreach ($m in [regex]::Matches($x, '\b(?:Text|Content|Header|ToolTip|Title)="([^"{]*)"')) {
            $v = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
            if ($v -match '[A-Za-z]{2,}' -and $v -notmatch '^(Nexora|Dashboard|OK|Task|Cascadia)' -and -not $script:It.ContainsKey($v)) { $miss += "$($f.Name): $v" }
        }
    }
    Assert-True ($miss.Count -eq 0) ("missing: " + ($miss -join ' | '))
}
Test-Case 'every T ''...'' text used in the PowerShell code has an Italian translation' {
    $miss = @()
    foreach ($f in Get-ChildItem (Join-Path $root 'src') -Recurse -Filter '*.ps1' | Where-Object Name -ne 'Strings.ps1') {
        $x = [IO.File]::ReadAllText($f.FullName)
        foreach ($m in [regex]::Matches($x, "\(T '((?:[^']|'')*)'")) {
            $k = $m.Groups[1].Value.Replace("''", "'")
            if (-not $script:It.ContainsKey($k)) { $miss += "$($f.Name): $k" }
        }
    }
    Assert-True ($miss.Count -eq 0) ("missing: " + ($miss -join ' | '))
}
Set-Language 'en'

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("`nRisultato: {0} superati, {1} falliti" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $(if ($script:fail) { 1 } else { 0 })
