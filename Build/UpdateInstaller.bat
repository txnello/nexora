@echo off
:: Check for administrator privileges
net session >nul 2>&1

if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell.exe -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Run the PowerShell script
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-Nexora.ps1"

pause