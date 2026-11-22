<#
.SYNOPSIS
    Creates fake NEXORA data to prepare Store screenshots.
.DESCRIPTION
    Uses a folder separate from the normal data, refuses already-existing folders,
    creates a dedicated desktop shortcut and launches the app in demo mode.
#>
[CmdletBinding()]
param(
    [string]$DataPath = '',
    [string]$AppExePath = '',
    [switch]$SkipLaunch
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $DataPath) { $DataPath = Join-Path $env:LOCALAPPDATA 'Nexora-StoreDemo' }
$DataPath = [System.IO.Path]::GetFullPath($DataPath)
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop 'NEXORA - Store Demo.lnk'

if (Test-Path -LiteralPath $DataPath) {
    throw "The demo folder already exists and will not be modified: $DataPath. Choose another folder with -DataPath."
}
if (Test-Path -LiteralPath $shortcutPath) {
    Remove-Item -LiteralPath $shortcutPath -Force
}

if (-not $AppExePath) {
    $pkg = Get-AppxPackage -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*Nexora*' -and (Test-Path -LiteralPath (Join-Path $_.InstallLocation 'Nexora.exe')) } |
        Select-Object -First 1
    if ($pkg) { $AppExePath = Join-Path $pkg.InstallLocation 'Nexora.exe' }
}
if (-not $AppExePath) {
    $innoExe = Join-Path $env:LOCALAPPDATA 'Programs\NEXORA\Nexora.exe'
    if (Test-Path -LiteralPath $innoExe) { $AppExePath = $innoExe }
}
if (-not $AppExePath) {
    $stagedExe = Join-Path $PSScriptRoot 'out\stage\Nexora.exe'
    if (Test-Path -LiteralPath $stagedExe) { $AppExePath = $stagedExe }
}
if (-not $AppExePath -or -not (Test-Path -LiteralPath $AppExePath -PathType Leaf)) {
    throw 'Nexora.exe not found. Specify the path with -AppExePath.'
}
$AppExePath = (Resolve-Path -LiteralPath $AppExePath).Path

foreach ($module in 'Utils', 'Strings', 'AppInfo', 'Storage', 'Priority', 'Config', 'Tasks') {
    . (Join-Path $root "src\Modules\$module.ps1")
}

Initialize-Storage -DataPath $DataPath
$state = Initialize-AppState
Set-Language 'en'
Set-AppPreferences -Theme 'dark' -DateFormat 'dd/MM/yyyy' -CodePrefix 'DEMO' `
    -UserName 'Alex Morgan' -MaxBackups 30 -Language 'en'

$referents = @('Alex Morgan', 'Jordan Lee', 'Sofia Rossi', 'Taylor Reed', 'Morgan Chen', 'Sam Patel')
foreach ($name in $referents) { Add-Referent $name | Out-Null }

$definitions = @(
    @{ Title = 'Resolve delayed invoice approvals'; Description = 'Two supplier invoices are waiting for final approval. Confirm the cost centre and notify Finance.'; Owner = 'Jordan Lee'; Status = 'blocked'; Priority = 'urgent'; Due = -1; Age = 19; Reminders = 4 }
    @{ Title = 'Review open support escalations'; Description = 'Summarize the customer impact and agree on owners for the remaining high-priority cases.'; Owner = 'Sofia Rossi'; Status = 'todo'; Priority = 'urgent'; Due = 0; Age = 12; Reminders = 3 }
    @{ Title = 'Prepare quarterly operations review'; Description = 'Collect team metrics, highlight delivery risks, and prepare the review deck for Friday.'; Owner = 'Alex Morgan'; Status = 'doing'; Priority = 'high'; Due = 2; Age = 15; Reminders = 2 }
    @{ Title = 'Reconcile monthly expense report'; Description = 'Match submitted receipts to the monthly ledger and flag any missing documentation.'; Owner = 'Morgan Chen'; Status = 'todo'; Priority = 'high'; Due = -2; Age = 21; Reminders = 3 }
    @{ Title = 'Publish updated service playbook'; Description = 'Apply the approved edits and share the new service procedures with the operations team.'; Owner = 'Taylor Reed'; Status = 'todo'; Priority = 'high'; Due = 1; Age = 8; Reminders = 0 }
    @{ Title = 'Investigate duplicate work orders'; Description = 'Trace the duplicate records to their source and confirm that the cleanup will not affect active work.'; Owner = 'Sam Patel'; Status = 'blocked'; Priority = 'high'; Due = 4; Age = 17; Reminders = 3 }
    @{ Title = 'Confirm maintenance window'; Description = 'Confirm the proposed maintenance window with service owners and update the change calendar.'; Owner = 'Jordan Lee'; Status = 'doing'; Priority = 'high'; Due = 1; Age = 5; Reminders = 1 }
    @{ Title = 'Update customer handoff checklist'; Description = 'Add the new escalation contacts and clarify the acceptance criteria for customer handoffs.'; Owner = 'Sofia Rossi'; Status = 'waiting'; Priority = 'medium'; Due = 3; Age = 11; Reminders = 2 }
    @{ Title = 'Review onboarding feedback'; Description = 'Group recent feedback by theme and suggest two improvements for the next onboarding cycle.'; Owner = 'Taylor Reed'; Status = 'waiting'; Priority = 'medium'; Due = 5; Age = 9; Reminders = 1 }
    @{ Title = 'Schedule regional planning session'; Description = 'Find a time that works across regions and circulate the agenda before sending the invitation.'; Owner = 'Alex Morgan'; Status = 'doing'; Priority = 'urgent'; Due = 7; Age = 6; Reminders = 1 }
    @{ Title = 'Draft Q1 capacity forecast'; Description = 'Estimate team capacity using current project commitments and the latest staffing plan.'; Owner = 'Morgan Chen'; Status = 'todo'; Priority = 'medium'; Due = 16; Age = 7; Reminders = 0 }
    @{ Title = 'Prepare vendor renewal summary'; Description = 'Compare renewal terms, current usage, and support history for the upcoming vendor review.'; Owner = 'Sam Patel'; Status = 'waiting'; Priority = 'medium'; Due = 12; Age = 14; Reminders = 1 }
    @{ Title = 'Validate supplier contact list'; Description = 'Check the shared supplier directory for outdated contacts and missing escalation details.'; Owner = 'Jordan Lee'; Status = 'doing'; Priority = 'low'; Due = 9; Age = 4; Reminders = 0 }
    @{ Title = 'Refresh internal knowledge base'; Description = 'Identify articles that need review and assign owners for the next documentation pass.'; Owner = 'Sofia Rossi'; Status = 'todo'; Priority = 'low'; Due = 25; Age = 3; Reminders = 0 }
    @{ Title = 'Complete security awareness module'; Description = 'Finish the annual awareness module and record completion in the team training tracker.'; Owner = 'Alex Morgan'; Status = 'done'; Priority = 'medium'; Due = -4; Age = 10; Reminders = 0 }
    @{ Title = 'Archive completed project records'; Description = 'Move the approved project records to the archive and confirm the retention labels.'; Owner = 'Taylor Reed'; Status = 'done'; Priority = 'low'; Due = $null; Age = 24; Reminders = 0 }
    @{ Title = 'Publish the revised escalation guide'; Description = 'The final guide is published and the support leads have confirmed the new workflow.'; Owner = 'Sam Patel'; Status = 'done'; Priority = 'high'; Due = -2; Age = 13; Reminders = 1 }
    @{ Title = 'Confirm training room equipment'; Description = 'Check the room setup and confirm the display and conferencing equipment are ready.'; Owner = ''; Status = 'todo'; Priority = 'low'; Due = $null; Age = 2; Reminders = 0 }
    @{ Title = 'Send weekly delivery update'; Description = 'Share a concise progress update with completed work, upcoming milestones, and current risks.'; Owner = 'Morgan Chen'; Status = 'doing'; Priority = 'medium'; Due = 4; Age = 1; Reminders = 0 }
    @{ Title = 'Review travel policy changes'; Description = 'Read the proposed policy updates and send any comments to the operations coordinator.'; Owner = ''; Status = 'todo'; Priority = 'medium'; Due = 20; Age = 5; Reminders = 0 }
)

$today = (Get-Date).Date
$random = New-Object System.Random
$sequence = 0
foreach ($definition in $definitions) {
    $sequence++
    $created = $today.AddDays(-[int]$definition.Age).AddHours($random.Next(8, 17)).AddMinutes($random.Next(0, 60))
    $updatedDaysAgo = [math]::Min([int]$definition.Age, $random.Next(0, 4))
    $updated = $today.AddDays(-$updatedDaysAgo).AddHours($random.Next(8, 17)).AddMinutes($random.Next(0, 60))
    if ($updated -lt $created) { $updated = $created.AddHours(1) }
    $dueDate = if ($null -eq $definition.Due) { $null } else { $today.AddDays([int]$definition.Due) }
    $demoTaskInput = @{
        Code = ('DEMO-{0:D4}' -f (1000 + $sequence))
        Title = $definition.Title
        Description = $definition.Description
        Referent = $definition.Owner
        Link = ''
        StatusId = $definition.Status
        PriorityId = $definition.Priority
        DueDate = $dueDate
    }
    $task = Add-AppTask $demoTaskInput
    $task.createdAt = Format-IsoDateTime $created
    $task.updatedAt = Format-IsoDateTime $updated
    if (Test-StatusClosed $task.statusId $state.Settings.statuses) {
        $task.completedAt = Format-IsoDateTime $updated
    }

    $createdEntry = $state.History | Where-Object { $_.taskId -eq $task.id -and $_.type -eq 'creato' } | Select-Object -First 1
    if ($createdEntry) { $createdEntry.at = $task.createdAt }

    $reminderCount = [int]$definition.Reminders
    $task.reminders = $reminderCount
    if ($reminderCount -gt 0) {
        $lastReminder = $updated.AddHours(-1)
        if ($lastReminder -lt $created) { $lastReminder = $created.AddMinutes(10) }
        $task.lastReminderAt = Format-IsoDateTime $lastReminder
        for ($reminder = 1; $reminder -le $reminderCount; $reminder++) {
            $entry = [pscustomobject]@{
                id = New-Id
                taskId = $task.id
                code = $task.code
                at = Format-IsoDateTime ($created.AddDays([math]::Max(0, [int]($definition.Age / ($reminderCount + 1)) * $reminder)))
                type = 'sollecito'
                text = "Reminder #$reminder logged"
            }
            $state.History.Add($entry)
        }
    } else {
        $task.lastReminderAt = $null
    }
}

Update-AllScores -State $state
Save-Settings
Save-Tasks
Save-History

if (@($state.Tasks).Count -ne $definitions.Count) { throw 'Unexpected number of demo tasks.' }
$savedTasks = Read-JsonStrict -Path (Get-DataFilePath 'tasks.json')
if (@($savedTasks.tasks).Count -ne $definitions.Count) { throw 'tasks.json verification failed.' }

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $AppExePath
$shortcut.Arguments = '-DataPath "' + $DataPath + '"'
$shortcut.WorkingDirectory = Split-Path -Parent $AppExePath
$shortcut.Description = 'NEXORA demo data for Microsoft Store screenshots'
$shortcut.IconLocation = "$AppExePath,0"
$shortcut.Save()

Write-Host "Demo data created: $DataPath" -ForegroundColor Green
Write-Host ("Tasks: {0} ({1} open, {2} completed)" -f $state.Tasks.Count,
    @($state.Tasks | Where-Object { -not (Test-StatusClosed $_.statusId $state.Settings.statuses) }).Count,
    @($state.Tasks | Where-Object { Test-StatusClosed $_.statusId $state.Settings.statuses }).Count)
Write-Host "Dedicated shortcut: $shortcutPath"
Write-Host 'The normal data in %LOCALAPPDATA%\Nexora was not modified.'

if (-not $SkipLaunch) {
    $running = Get-Process -Name 'Nexora' -ErrorAction SilentlyContinue
    if ($running) {
        Write-Warning 'NEXORA is already running. Close it and use the desktop shortcut "NEXORA - Store Demo".'
    } else {
        Start-Process -FilePath $AppExePath -ArgumentList ('-DataPath "' + $DataPath + '"') | Out-Null
        Write-Host 'NEXORA was started with the demo data.'
    }
}
