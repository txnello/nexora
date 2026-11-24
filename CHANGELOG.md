# Changelog

All notable changes to NEXORA are listed here, newest first.

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
