NEXORA - Intelligent task management system
===========================================

NEXORA calculates automatically which tasks deserve your attention first, based on priority, due date,
reminders and age. Everything works on your PC: no account, no cloud, no Internet connection needed.

INSTALL
  1. Run Nexora-Setup.exe and follow the wizard (a few clicks).
  2. By default NEXORA installs for the current user and does not need administrator rights.
     Choose "all users" when asked if you want to install it for every account on the PC.
  3. Optional desktop shortcut; a Start menu shortcut is always created.

REQUIREMENTS
  Windows 10 or Windows 11. Nothing else to install: NEXORA uses components that are already part of
  Windows (Windows PowerShell 5.1 and .NET Framework 4.x).

YOUR DATA
  Your tasks, settings, history, backups and logs are stored in:   %LOCALAPPDATA%\Nexora
  (for example C:\Users\<you>\AppData\Local\Nexora). They are separate from the program files:
  updating NEXORA never deletes them. Uninstalling asks whether to keep or delete them (default: keep).
  Automatic daily backups are created in the Backups folder; you can also export/import a full backup
  from Settings > Backups and data.

UPDATE
  Run the new Nexora-Setup.exe over the existing installation. Your data is kept, and NEXORA makes a safety
  backup of it the first time the new version starts.

UNINSTALL
  Settings > Apps > Installed apps > NEXORA > Uninstall.
  Silent uninstall for IT:   unins000.exe /VERYSILENT                    (keeps personal data)
                             unins000.exe /VERYSILENT /DELETEDATA=1      (also deletes personal data)

SILENT INSTALL (IT)
  Nexora-Setup.exe /VERYSILENT /CURRENTUSER     (current user)     |     /ALLUSERS  (all users, requires admin)

LANGUAGE
  English by default. Settings > Appearance and preferences > Language lets you switch to Italian.

LICENSE
  See LICENSE.txt.
