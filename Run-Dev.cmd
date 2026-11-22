@echo off
rem Run NEXORA from source (developer launcher, not shipped) without a console window. Prefers PowerShell 7, falls back to Windows PowerShell.
where pwsh >nul 2>nul
if %errorlevel%==0 (
    start "" pwsh -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Start-Nexora.ps1"
) else (
    start "" powershell -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Start-Nexora.ps1"
)
