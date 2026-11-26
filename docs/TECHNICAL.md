# NEXORA – Technical documentation

Document version: 1.0.7 · Verification status is reported at the end (see *Verification status* section).

## 1. Analysis of the starting project (Phase 1)

The existing project was a WPF app written in PowerShell (5.1/7), JSON-based, with no database.

| Element | Initial state | Change |
|---|---|---|
| Scripts | `Start-Nexora.ps1` + `src\Modules\*.ps1` modules (Utils, Storage, Priority, Config, Tasks, Strings) | kept; added `AppInfo.ps1` (version, paths, migration) |
| UI | XAML in `src\UI` (MainWindow, TaskDialog, ItemDialog, MessageDialog, Styles) + `Theme/Dialogs/Ui.ps1` | added About, vector logo, window icon, `Native.cs` |
| BAT file | `Start Nexora.cmd` (launcher with hidden console) | renamed `Run-Dev.cmd`, **developer-only, not distributed** |
| Data | `.\Data` next to the scripts (`tasks/settings/history.json`, `Backups`, `Logs`) | moved to `%LOCALAPPDATA%\Nexora` (automatic copy on first launch, nothing deleted) |
| Dependencies | Windows PowerShell 5.1 / WPF (.NET Framework 4.x), no external modules | unchanged |
| Architectural issues | data inside the app folder (incompatible with Program Files); launch via console; `TaskRow` class and P/Invoke recompiled at every launch with `Add-Type` | data separated; `Nexora.exe`; native code compiled into the exe |

Existing JSON files remain compatible: format unchanged, new fields (`language`, `lastRunVersion`, `openOnStartup`, `hideOnClose`, `preferencesVersion`, and since 1.0.5 `settings.projects`, `settings.clients`, `task.project`, `task.client`) are optional and added on first launch. Files written by 1.0.4 have none of the project/client keys: a task without them is read as "no project" / "no client", no migration runs and nothing is rewritten until the user uses the new fields. The preferences migration updates `hideOnClose` to the new active default only once.

## 2. Product architecture

```
Nexora.exe  ──(single process)──►  embedded Windows PowerShell 5.1 engine (hosted in-process)
   │                                    └─ app\Start-Nexora.ps1 → modules (src\Modules) + WPF UI (src\UI)
   ├─ splash screen (WinForms, separate thread, closed when the main window is ready)
   ├─ global mutex for the instance (a second launch signals the already-running window)
   └─ mutex per data folder (only one instance per local store)
```

**Why a native launcher that hosts PowerShell** (evaluation requested in Phase 4):

| Option | Outcome |
|---|---|
| PS2EXE | not used: compatibility with the project's WPF/STA/dot-sourcing not verified |
| `powershell.exe -WindowStyle Hidden` from a shortcut | the console appears for a moment; the process shows up as "powershell.exe" in Task Manager; icon/taskbar need fixing |
| Requiring PowerShell 7 | PowerShell 7 is not preinstalled on Windows; it would add a requirement. It is not even installed on the dev machine, so **not verified** |
| **C# launcher hosting the PS 5.1 engine (chosen)** | no console, `Nexora.exe` process, own icon and metadata, WPF on an STA thread, no dependency beyond Windows 10/11 |

The launcher (`Build\Launcher\Program.cs`) is compiled with .NET Framework 4's `csc.exe` (part of Windows), so the build does not require Visual Studio or the SDK.

### Installed layout
```
<install folder>\           (per-user default: %LOCALAPPDATA%\Programs\NEXORA)
  Nexora.exe  LICENSE.txt  README.txt  unins000.exe
  app\  Start-Nexora.ps1  VERSION  src\...  Assets\Branding\...
%LOCALAPPDATA%\Nexora\                 (default data folder + persisted choice)
  data-path.txt                        (only written by versions up to 1.0.5; read once and migrated to the registry)
  tasks.json  settings.json  history.json  (+ .bak)  Backups\  Logs\
```
Startup and background options are saved immediately when a checkbox changes. Auto-start uses `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\NEXORA`. In both cases the user can disable it from Task Manager. The background option uses `NotifyIcon` and cancels window closure when active (default); the tray icon menu lets the user restore or exit the app. Reopening NEXORA from the shortcut while it is already running sends a request to the active instance, which restores the hidden window instead of showing a warning. Windows session logoff and the *Exit* command terminate the process regardless.
Data path: `NEXORA_DATA` variable (test/IT) › path chosen by the user, stored in the registry (`HKCU\Software\Nexora`, value `DataPath`; the `data-path.txt` file of versions up to 1.0.5 is still read as a fallback and migrated) › portable mode (`portable.flag` file next to the app → `.\Data`) › `%LOCALAPPDATA%\Nexora`.
In normal use another folder can be chosen from *Settings → Backup and data*. The persistent selection is in the registry (`HKCU\Software\Nexora`, value `DataPath`), independent of the transferred files and of any data folder: after a switch NEXORA writes nothing into the previous folder, so the user can delete it and the app does not recreate it or go back to it. The installer reads the same value (with the old file as fallback) to find the data for the startup option and for the uninstall prompt, and removes the key only when the user chooses to delete the data. For an empty destination, copying current data is preselected and the source is left intact. For a populated destination you can replace it (after saving a backup copy), switch to the data already there without copying the current data into it, or merge tasks, statuses, priorities, referents, clients, projects and history. During the merge the destination wins for scalar preferences and, in case of identical status/priority names, for their colors and values; entities with different names are kept.
The selection is local to the Windows profile and does not coordinate multiple instances across different devices: use a synchronized folder only once synchronization is complete and with NEXORA closed on the other devices.

### 2.1 Support (donation) button
In the sidebar, **above** the *About NEXORA* item, and in the About window **below the product description**, there is a **Support NEXORA** button (heart icon ♥). On click it opens `https://ko-fi.com/txnello` in the default browser via the `Open-DonatePage` function (`Start-Process`), defined in `src\UI\Dialogs.ps1` and reused by both `src\UI\Ui.ps1` (sidebar) and `Show-AboutDialog` (About). It does not use the network: it only opens the browser and transmits no data.

The button uses the `DonateButton` style (`src\UI\Styles.xaml`): a brand gradient (Electric `#2F7BFF` → `#6A4DFF` → Cyan `#22D3EE`, like the NEXORA symbol) with a **light beam** sweeping from left to right in a loop — a `Rectangle` with a translucent white gradient animated via an `EventTrigger` on `Loaded` (`DoubleAnimationUsingKeyFrames` on a `TranslateTransform`, `ClipToBounds` on the corners). Text and tooltip are translatable like the rest of the interface: the source strings are `Support NEXORA` and `Support NEXORA with a donation`, with Italian translations *Sostieni NEXORA* and *Sostieni NEXORA con una donazione* in `src\Modules\Strings.ps1`. In compact sidebar mode (window < 1020 px) the `lblDonate` label is hidden like the other items, while the button remains.

## 3. Data, backups, integrity
- Atomic writes (temporary file + replacement, `.bak` copy), corrupted JSON → restore from `.bak` with a notice and a copy of the corrupted file in `Backups\corrotto-*`.
- Daily automatic backup, before deletions/imports and **before the first launch of a new version** (`pre-upgrade`); manual backups are never deleted; `.zip` export/import.
- Data repaired on load (nonexistent statuses/priorities, wrong dates, duplicate codes).
- Status score weight (1.0.7): each status has an optional `scoreValue`, a whole number from 1 to 10 (10 = no reduction). The score is `(P×wP + S×wS + L×wL + A×wA) × scoreValue / 10`, so the four factor weights and their "sum = 100" rule are untouched. A status without the field (files of older versions, objects built by hand) or with an invalid one counts as 10 (`Get-StatusScoreValue`): existing data keeps exactly the same scores until the user sets a weight. Values outside 1-10 found in a file are clamped, text becomes 10. New statuses you create default to 10. The built-in statuses of a brand-new data folder weigh 10 except Waiting (7) and Blocked (5) (`Get-DefaultSettings`); files of earlier versions have no weight and stay at 10 on every status, Waiting and Blocked included, so updating changes nothing. The merge between data folders copies the weight of the statuses it adds; a status already in the destination keeps the destination's. Versions older than 1.0.7 ignore the field and drop it the next time they save.
- Clients and projects (1.0.5) follow the same model as owners: the list lives in `settings.clients` / `settings.projects` (`{id, name}`, name up to 80 characters, unique case-insensitively) and each task stores the **name** in `task.client` / `task.project` (empty string = none). The two fields are independent: a client does not own projects. Names used by tasks but missing from the list are added on load. Renaming updates the tasks that use the name. Deleting never deletes tasks: they go back to "no client" / "no project", after a safety snapshot (`pre-delete-client`, `pre-delete-project`). An update call whose input has no `Client` / `Project` key (older callers) leaves the stored value untouched; `Repair-Tasks` and the merge in `Storage.ps1` list task fields explicitly, so any new task field must be added to both. A version older than 1.0.5 ignores these fields and drops them the next time it saves.

## 4. Versioning
- `VERSION` file at the root: `Major.Minor.Patch` (e.g. `1.0.0`). **This is the only place to change for a release.**
- Read by: About and windows (`Get-AppVersion`), `Nexora.exe` metadata (generated at build: FileVersion `1.0.0.0`, ProductVersion `1.0.0`), installer (`AppVersion`, Windows registry, `VersionInfo`).
- Future updates: the installer uses a fixed `AppId` and overwrites the previous version (`app\` folder cleaned, data intact); on first launch `Invoke-VersionCheck` compares `settings.lastRunVersion` with the current version, creates a `pre-upgrade` snapshot and records the new version. Anchor point for future data-schema migrations.

## 5. Brand
Generated by code (`Build\New-Branding.ps1`, original geometry, no stock assets) into `Assets\Branding\`:
`nexora-logo.svg/.png`, `nexora-logo-white.png/.svg`, `nexora-symbol.svg/.png`, `nexora-icon.ico` (16/32/48/64/128/256 px, real PNG frames), `nexora-icon.png`, `nexora-splash.png` (1600×900). Palette: Midnight `#070B1F`, Navy `#0B1230`, Deep Indigo `#3B33D1`, Electric Blue `#2F7BFF`, Cyan `#22D3EE`, white/grays. Symbol: a three-element "N" with a cyan node (the task that deserves attention). The NEXORA wordmark is converted into vector paths from the Bahnschrift font (the SVG does not depend on installed fonts). Regeneration: `Build\Build-Nexora.ps1 -RegenerateBranding`.

## 6. Build and release
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Build\Build-Nexora.ps1            # test + exe + installer + Release\
powershell -NoProfile -ExecutionPolicy Bypass -File Build\Build-Nexora.ps1 -CertThumbprint <thumbprint>   # signed
```
Steps: logic tests → assets → `Nexora.exe` (icon, manifest, metadata) → package in `Build\out\stage` → `ISCC` (Inno Setup 6, `winget install JRSoftware.InnoSetup`) → `Release\` (`Nexora-Setup.exe`, `README.txt`, `LICENSE.txt`).

One-step alternative for people building from the downloaded sources: `Build\UpdateInstaller.bat` asks for administrator rights, installs Inno Setup 6 with `winget` when `ISCC.exe` is not found, runs `Build-Nexora.ps1` (it stops there if the build fails) and launches `Release\Nexora-Setup.exe`.

Release checklist: change `VERSION`, add the new section at the top of `CHANGELOG.md`, update "Document version" at the top of this file, then build.

Installer (`Build\Installer\Nexora.iss`): modern wizard with brand images, license to accept, folder choice, optional desktop shortcut, Start menu, per-user installation without administrator rights (or "all users" by choice), registration in *Installed apps*, closing the app if running, English/Italian languages. Interactive uninstallation: asks whether to delete data (default **No**); silent: keeps them (`/DELETEDATA=1` to delete). IT parameters: `/VERYSILENT /CURRENTUSER|/ALLUSERS`.

## 7. Code signing and antivirus — KNOWN LIMIT, TO BE RESOLVED BEFORE SALE
During testing **Microsoft Defender detected unsigned `Nexora.exe` as `Trojan:Win32/Bearfoos.A!ml`** and blocked its execution (heuristic/cloud verdict on hash; Defender 4.18.26100.4, signatures 1.463.386.0). It is a **false positive**, typical of unsigned, reputation-less executables that host the PowerShell engine and hide windows. The first launch after each build works; after a few minutes the cloud verdict may block it.

What is needed to actually distribute it:
1. **Code signing certificate** (OV or, better, EV) and a signed build: `Build-Nexora.ps1 -CertThumbprint …` or `-PfxPath … -PfxPassword …` (signs `Nexora.exe` and `Nexora-Setup.exe`, SHA-256 + timestamp). The mechanism was tested with a trial certificate (the signature is applied); **it was not tested with a trusted certificate**, which is not available here, so it is not proven that signing removes the detection.
2. Send the file to Microsoft for false-positive analysis (Security Intelligence → *Submit a file*) and build SmartScreen reputation.
3. The `unins000.exe` generated by the installer is not signed by the build (it would require Inno Setup's `SignTool` directive with signtool installed).
4. More robust structural alternative for a commercial product: move the logic into a compiled .NET application (no hosted scripting engine). It was not done because the requirement was to not rewrite the app.

Temporary internal workarounds: Defender exclusion for the install folder (requires administrator, IT decision), or launch from sources (`Run-Dev.cmd`).

## 8. Verification status (Windows 11 Enterprise 26200, Windows PowerShell 5.1)
| Verification | Outcome |
|---|---|
| Due-date calendar: size, readable colors in the dark and light themes, picking a day fills the field and closes the popup, month picker | Passed (UI tests and screenshots of both themes). Clicking the day buttons and the header with a real mouse was not done: the date selection and the display mode were driven from the test |
| Required name: the question is needed whenever the name is empty (start and after a data-folder change), the Settings field is required, settings of older versions load fine; the "My tasks" message bar has rounded top corners | Passed (automatic tests; the dialog is saved by a test helper and the corners are checked in a screenshot of the message bar). The refusal path (closing the dialog exits the application), the dialog layout and the real first launch were not tried |
| Defaults: a data folder with no files starts in English with the dark theme; so do settings without language/theme or with invalid values. The application does not read the Windows language | Passed (automatic test for the empty folder; the other two cases were checked once by hand with a throw-away folder) |
| Settings page uses the full window width | Passed (screenshots at the initial width); not tried at very large widths |
| Status score weight: scaling (weight 5 halves the score, 10 restores it), missing weight = 10, validation (0, 11, decimals and text rejected), creation with a weight, editing, statuses sharing a value, closed statuses unranked, invalid values repaired on load, weight kept in a folder merge, weight chosen in the status dialog | Passed (automatic tests). The new field in the status dialog and the "open · n/10" text in the status list were not looked at in a screenshot |
| Status weight defaults: a new data folder starts with Waiting 7, Blocked 5 and the rest 10; an older settings file with Waiting and Blocked but no weights keeps all of them at 10 | Passed (automatic tests with synthetic files; not tried with a real update from an installed version) |
| Logic tests (76) and real-UI tests with screenshots (150) | Passed (26/11/2026), source version 1.0.7 |
| "Complete" action (button and context-menu item): selected open task goes to Done with completion date, history entry and no ranking score; no change on an already completed task; fallback to another closed status; clear error when no closed status exists | Passed (automatic tests; the UI test drives the button by raising its click event, not with a real mouse click) |
| Data folder pointer in the registry: choosing a folder writes nothing to the default folder; deleting the default folder keeps the choice and does not recreate it; the pointer file of 1.0.5 or earlier is migrated and a stale file never overrides the registry | Passed (automatic tests with a throw-away registry key; the real key was not touched). Not tried end to end with the installed app |
| Installer script with the registry lookup | Compiles (ISCC, temporary output with dummy files); the new lookup and the key removal on uninstall were **not run** |
| Compatibility with 1.0.4 data: files without `project`/`client`, files with projects but no clients, merge between folders, round trip on disk | Passed (automatic tests with synthetic files). A copy of the developer's real data folder also loaded without warnings, but it contained no tasks, so it proves nothing about task data |
| Initial window width: all columns, Link included, visible without horizontal scrolling | Passed (UI test on `ScrollableWidth`) |
| Collapsed sidebar: bottom icons not clipped; title tooltip hidden when the description is empty | Passed (UI tests and screenshots) |
| Build and install of 1.0.7, `Build\UpdateInstaller.bat`, launch of the installed 1.0.7 | Not verified: the sources were tested, but the installer was not rebuilt and the `.bat` was not run |
| "Support NEXORA" button (sidebar + About), `DonateButton` style and IT texts | Partial — presence and rendering verified (UI smoke 96/96 + modal About test); Ko-fi page opening **not yet tested with a click** |
| `Nexora.exe` launch with no console or technical windows, single process, no child process | Verified (process/window list) |
| NEXORA icon in title bar and taskbar, window title "NEXORA" | Verified (screenshot) |
| Splash visible during load and closed when window is ready, without blocking | Verified (screenshot at 0.9 s; the app stays alive after close) |
| Data in `%LOCALAPPDATA%\Nexora` (or `NEXORA_DATA`), nothing in the install folder | Verified |
| JSON load/save, backup, restore, corrupted JSON | Passed (automatic tests) |
| Silent per-user installation, Start menu shortcut, Windows registration, exe metadata, update over existing | Verified |
| Uninstallation: files and registry removed, **data preserved**; `/DELETEDATA=1` deletes them | Verified (silent mode) |
| Interactive uninstallation ("delete data?" window) | Partial — code present, **not clicked**: only silent mode tested |
| Optional desktop shortcut, graphical wizard | Not verified — not exercised (silent-only testing); the wizard images are generated but were not viewed on screen |
| Launch of the installed app after the Defender block | Blocked — **blocked by antivirus** (see section 7) |
| Windows 10 | Not verified — **not verified** (only Windows 11 available). Compatibility by design: fallback fonts (Segoe MDL2, Segoe UI), `MinVersion=10.0` |
| Clean Windows machine (without dev environment) | Not verified — **not verified**; the installed app used only Windows components (PowerShell 5.1, WPF/.NET 4.x) |
| PowerShell 7 | Not verified — not installed; the product does not require it |