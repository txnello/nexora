# Changelog

All notable changes to NEXORA are listed here, newest first.

## [1.0.7] - 2026-11-26

### Added
- **Complete button:** select a task and press "Complete" to move it straight to the Done status. The completion date is set, the change is recorded in the task history and the task leaves the ranking, exactly as if you had changed the status by hand. The same command is available in the right-click menu. The button is disabled when no task is selected or the task is already completed.
- If the default Done status was renamed it is still used; if it is no longer a "closed" status, the first closed status is used instead. When no closed status exists, NEXORA asks you to mark one as closed in Settings.
- **Score weight per status:** every status now has a weight from 1 to 10 (10 = no reduction). New installations start with Waiting at 7, Blocked at 5 and every other status at 10; new statuses you create start at 10. The score of a task is multiplied by weight/10, so tasks in a status such as Waiting, or in a custom status of yours, count less in the ranking. Set the weight when you create a status (also from the task dialog) or edit it in Settings; several statuses can share the same value. Statuses and data from earlier versions weigh 10, so no score changes until you set a weight. The task details show the reduction when the weight is below 10. A task with the highest priority stays "urgent" whatever its status weight, and completed statuses are still left out of the ranking. Older versions ignore the weights.
- **Your name is now required:** NEXORA asks "What is your name?" whenever no name is saved, so that "My tasks" always works. Any name will do. The name is also the default owner of new tasks. The question cannot be skipped: closing it or pressing "Exit NEXORA" closes the application. If you already have a name, you are not asked; if you had none, you are asked after updating. In Settings the name field is now required and marked with *, like the other preferences. The name is stored in the data folder: if you switch to a folder that already contains your data (using it as it is, or merging), the name saved there is the one you get, and if that folder has no name you are asked for it right away.

### Fixed
- The message shown in "My tasks" when no name is set had square top corners that stuck out of the rounded card. The corners are now rounded.
- The Settings page was limited to 1000 px and aligned to the left, unlike the other pages. Its blocks now use the full width of the window.

## [1.0.6] - 2026-11-24

### Fixed
- After changing the data folder, deleting the original folder in `%LOCALAPPDATA%` and restarting NEXORA recreated that folder and went back to it. The chosen folder is now remembered in the Windows registry (`HKCU\Software\Nexora`) instead of in a file inside the original folder, so NEXORA no longer writes anything to the old folder and does not recreate it.
- The due-date calendar was too small and, on the dark theme, its numbers were dark gray on a dark background and barely visible. It is now larger (about 274 x 284 px instead of 177 x 166 px) and follows the light and dark themes: readable day numbers, today outlined, the selected day highlighted and days of the neighboring months dimmed. The month and year pickers (click the calendar header) were restyled as well.

### Data and compatibility
- The data folder choice made with 1.0.5 or earlier is migrated automatically the first time 1.0.6 starts. Start 1.0.6 at least once before deleting the old folder, otherwise the choice stored in it is lost.
- Going back to 1.0.5 or earlier after changing the data folder in 1.0.6 may bring back the old default folder, because those versions do not read the registry.

## [1.0.5] - 2026-11-24

### Added
- **Clients:** every task can now belong to a client. Create clients from the task dialog ("Create new client...") or manage them in Settings (create, edit, reorder, delete).
- **Projects:** every task can now belong to a project, with the same options as clients. Client and project are independent fields.
- **New views and filters:** "By client" and "By project" views in the side menu (open tasks grouped by client or project), "All clients" and "All projects" filters, and Client and Project columns in the task table. The search box also matches client and project.
- **Completed tasks:** the Completed view shows a new "Completed on" column and sorts by it by default, newest first.
- **One-step installer build:** `Build\UpdateInstaller.bat` now installs Inno Setup 6 through `winget` when it is missing, runs the tests, builds the installer and launches it.

### Changed
- The task dialog has a new layout: Client and Project, then Owner and Status, then Due date and Manual priority.
- The main window opens wider (1560 px) so that the Link column stays visible with the new columns. Some columns are slightly narrower and the search box is wider.
- README: simplified installation steps, updated feature list and a link to this changelog.

### Fixed
- With a narrow window the side menu collapses to icons: the three icons at the bottom (Support, About, theme) were slightly cut off on the right and are now centered like the others.
- Hovering the title of a task without a description showed an empty box; the tooltip now appears only when there is a description.

### Data and compatibility
- Data created with 1.0.4 opens unchanged. Tasks without a client or project are shown as "(no client)" and "(no project)". There is no data migration and no file is rewritten until you use the new fields.
- Renaming a client or project updates its tasks. Deleting one never deletes tasks: they simply stay without a client or project.
- Going back to 1.0.4 after using clients or projects keeps your tasks, but 1.0.4 does not know these fields and drops them the next time it saves.

## [1.0.4]

- INIT of the project!
