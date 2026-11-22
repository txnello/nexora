@echo off
:: Check for administrator privileges
net session >nul 2>&1

if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell.exe -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Remove the previous folder, if it exists
if exist "%LOCALAPPDATA%\Nexora-StoreDemo" (
    rmdir /s /q "%LOCALAPPDATA%\Nexora-StoreDemo"
)

:: Run the PowerShell script
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-StoreDemoData.ps1"

pause