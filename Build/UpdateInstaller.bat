@echo off
:: Check for administrator privileges
net session >nul 2>&1

if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell.exe -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

:: Install Inno Setup 6 if it is not already present
set "ISCC="
for %%P in (
    "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
    "%ProgramFiles%\Inno Setup 6\ISCC.exe"
    "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
) do if exist %%P set "ISCC=%%~P"

if not defined ISCC (
    echo Inno Setup 6 not found. Installing it with winget...
    winget install --id JRSoftware.InnoSetup -e --accept-source-agreements --accept-package-agreements
    if errorlevel 1 (
        echo.
        echo ERROR: Inno Setup installation failed. Install it manually and run this script again.
        pause
        exit /b 1
    )
)

:: Run the PowerShell build script (tests, Nexora.exe, installer)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-Nexora.ps1"
if errorlevel 1 (
    echo.
    echo ERROR: build failed. The installer was not launched.
    pause
    exit /b 1
)

:: Launch the freshly built installer
if exist "%~dp0..\Release\Nexora-Setup.exe" (
    echo Launching the installer...
    start "" "%~dp0..\Release\Nexora-Setup.exe"
)

pause
