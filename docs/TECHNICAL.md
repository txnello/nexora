# NEXORA – Technical documentation

Document version: 1.0.4 · Verification status is reported at the end (see *Verification status* section).

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

Existing JSON files remain compatible: format unchanged, new fields (`language`, `lastRunVersion`, `openOnStartup`, `hideOnClose`, `preferencesVersion`) are optional and added on first launch. The preferences migration updates `hideOnClose` to the new active default only once.

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
  data-path.txt                        (chosen path, if different from the default)
  tasks.json  settings.json  history.json  (+ .bak)  Backups\  Logs\
```
Startup and background options are saved immediately when a checkbox changes. Auto-start uses `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\NEXORA`. In both cases the user can disable it from Task Manager. The background option uses `NotifyIcon` and cancels window closure when active (default); the tray icon menu lets the user restore or exit the app. Reopening NEXORA from the shortcut while it is already running sends a request to the active instance, which restores the hidden window instead of showing a warning. Windows session logoff and the *Exit* command terminate the process regardless.
Data path: `NEXORA_DATA` variable (test/IT) › path chosen by the user in `%LOCALAPPDATA%\Nexora\data-path.txt` › portable mode (`portable.flag` file next to the app → `.\Data`) › `%LOCALAPPDATA%\Nexora`.
In normal use another folder can be chosen from *Settings → Backup and data*. The persistent selection is in `%LOCALAPPDATA%\Nexora\data-path.txt`, independent of the transferred files. For an empty destination, copying current data is preselected and the source is left intact. For a populated destination you can replace it (after saving a backup copy), switch to the data already there without copying the current data into it, or merge tasks, statuses, priorities, referents and history. During the merge the destination wins for scalar preferences and, in case of identical status/priority names, for their colors and values; entities with different names are kept.
The selection is local to the Windows profile and does not coordinate multiple instances across different devices: use a synchronized folder only once synchronization is complete and with NEXORA closed on the other devices.

### 2.1 Support (donation) button
In the sidebar, **above** the *About NEXORA* item, and in the About window **below the product description**, there is a **Support NEXORA** button (heart icon ♥). On click it opens `https://ko-fi.com/txnello` in the default browser via the `Open-DonatePage` function (`Start-Process`), defined in `src\UI\Dialogs.ps1` and reused by both `src\UI\Ui.ps1` (sidebar) and `Show-AboutDialog` (About). It does not use the network: it only opens the browser and transmits no data.

The button uses the `DonateButton` style (`src\UI\Styles.xaml`): a brand gradient (Electric `#2F7BFF` → `#6A4DFF` → Cyan `#22D3EE`, like the NEXORA symbol) with a **light beam** sweeping from left to right in a loop — a `Rectangle` with a translucent white gradient animated via an `EventTrigger` on `Loaded` (`DoubleAnimationUsingKeyFrames` on a `TranslateTransform`, `ClipToBounds` on the corners). Text and tooltip are translatable like the rest of the interface: the source strings are `Support NEXORA` and `Support NEXORA with a donation`, with Italian translations *Sostieni NEXORA* and *Sostieni NEXORA con una donazione* in `src\Modules\Strings.ps1`. In compact sidebar mode (window < 1020 px) the `lblDonate` label is hidden like the other items, while the button remains.

## 3. Data, backups, integrity
- Atomic writes (temporary file + replacement, `.bak` copy), corrupted JSON → restore from `.bak` with a notice and a copy of the corrupted file in `Backups\corrotto-*`.
- Daily automatic backup, before deletions/imports and **before the first launch of a new version** (`pre-upgrade`); manual backups are never deleted; `.zip` export/import.
- Data repaired on load (nonexistent statuses/priorities, wrong dates, duplicate codes).

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
| Logic tests (55) and real-UI tests with screenshots (96) | Passed (22/11/2026) |
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