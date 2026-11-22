<#
.SYNOPSIS
    Builds NEXORA: tests, assets, Nexora.exe, package, installer (Inno Setup) and Release folder.
.DESCRIPTION
    1. runs the logic tests (unless -SkipTests)
    2. generates the brand assets if missing (or with -RegenerateBranding)
    3. compiles Nexora.exe (console-less launcher) with icon, manifest and version metadata
    4. prepares the package in Build\out\stage  (Nexora.exe + app\ with scripts, src, Assets, VERSION)
    5. compiles the installer with Inno Setup  ->  Release\Nexora-Setup.exe
    6. also copies README.txt and LICENSE.txt into Release

    The version (Major.Minor.Patch) is read from the VERSION file at the root: it is the only one to change for a new release.
    Requires: Windows, Inno Setup 6 (winget install JRSoftware.InnoSetup). The C# compiler (csc.exe) is part of Windows.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File Build\Build-Nexora.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipTests,
    [switch]$SkipInstaller,
    [switch]$RegenerateBranding,
    # Authenticode digital signature (recommended for distribution: without a signature Windows Defender/SmartScreen may block the exe)
    [string]$CertThumbprint = '',                 # certificate already installed in Cert:\CurrentUser\My
    [string]$PfxPath = '',                        # or a .pfx file ...
    [securestring]$PfxPassword,                   # ... with its password
    [string]$TimestampUrl = 'http://timestamp.digicert.com'   # '' to not use the timestamp
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$build = $PSScriptRoot
$out = Join-Path $build 'out'
$stage = Join-Path $out 'stage'
$release = Join-Path $root 'Release'
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Step([string]$m) { Write-Host "`n== $m" -ForegroundColor Cyan }

# ---------------------------------------------------------------- digital signature (optional)
$signCert = $null
if ($CertThumbprint) {
    $signCert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Thumbprint -eq $CertThumbprint } | Select-Object -First 1
    if (-not $signCert) { throw "Certificato $CertThumbprint non trovato in Cert:\CurrentUser\My" }
} elseif ($PfxPath) {
    $signCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($PfxPath, $PfxPassword)
}
function Sign-File([string]$path) {
    if (-not $signCert) { return }
    $args2 = @{ FilePath = $path; Certificate = $signCert; HashAlgorithm = 'SHA256' }
    if ($TimestampUrl) { $args2.TimestampServer = $TimestampUrl }
    $r = Set-AuthenticodeSignature @args2
    if (-not $r.SignerCertificate) { throw "Firma non applicata a $path ($($r.StatusMessage))" }
    Write-Host ("Firmato: {0}  [{1}]" -f (Split-Path $path -Leaf), $r.Status)
}
if (-not $signCert) {
    Write-Host 'ATTENZIONE: build NON firmata. Windows Defender/SmartScreen possono bloccare Nexora.exe e l''installer (vedi docs\TECHNICAL.md, "Firma digitale").' -ForegroundColor Yellow
}

# ---------------------------------------------------------------- version
$version = ([IO.File]::ReadAllText((Join-Path $root 'VERSION'))).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION non valida: '$version' (formato richiesto Major.Minor.Patch)" }
Write-Host "NEXORA $version" -ForegroundColor Green

# ---------------------------------------------------------------- 1. tests
if (-not $SkipTests) {
    Step 'Test della logica'
    & $ps51 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Tests\Run-Tests.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Test falliti: build interrotta.' }
}

# ---------------------------------------------------------------- 2. asset
$brand = Join-Path $root 'Assets\Branding'
$required = 'nexora-logo.svg', 'nexora-logo.png', 'nexora-logo-white.png', 'nexora-symbol.svg', 'nexora-symbol.png', 'nexora-icon.ico', 'nexora-icon.png', 'nexora-splash.png'
if ($RegenerateBranding -or ($required | Where-Object { -not (Test-Path (Join-Path $brand $_)) })) {
    Step 'Generazione asset del brand'
    & $ps51 -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $build 'New-Branding.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Generazione asset fallita.' }
}
foreach ($f in $required) { if (-not (Test-Path (Join-Path $brand $f))) { throw "Asset mancante: $f" } }

# ---------------------------------------------------------------- 3. Nexora.exe
Step 'Compilazione di Nexora.exe'
if (Test-Path $out) { Remove-Item -LiteralPath $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
$csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw 'csc.exe (.NET Framework 4) non trovato.' }
$sma = Get-ChildItem (Join-Path $env:SystemRoot 'Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation') -Recurse -Filter 'System.Management.Automation.dll' |
    Where-Object { $_.FullName -match 'v4\.0_3\.0\.0\.0' } | Select-Object -First 1
if (-not $sma) { throw 'System.Management.Automation (Windows PowerShell 5.1) non trovato.' }
$fileVersion = "$version.0"
$year = (Get-Date).Year
$asm = Join-Path $out 'AssemblyInfo.g.cs'
@"
using System.Reflection;
[assembly: AssemblyTitle("NEXORA")]
[assembly: AssemblyDescription("NEXORA - intelligent task management system")]
[assembly: AssemblyCompany("Manuel Tonello")]
[assembly: AssemblyProduct("NEXORA")]
[assembly: AssemblyCopyright("Copyright (C) $year Manuel Tonello. All rights reserved.")]
[assembly: AssemblyVersion("$fileVersion")]
[assembly: AssemblyFileVersion("$fileVersion")]
[assembly: AssemblyInformationalVersion("$version")]
"@ | Set-Content -LiteralPath $asm -Encoding UTF8
$exe = Join-Path $stage 'Nexora.exe'
$cscArgs = @('/nologo', '/target:winexe', '/platform:anycpu', '/optimize+', "/out:$exe",
    "/win32icon:$(Join-Path $brand 'nexora-icon.ico')", "/win32manifest:$(Join-Path $build 'Launcher\Nexora.manifest')",
    "/reference:$($sma.FullName)", '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll',
    (Join-Path $build 'Launcher\Program.cs'), (Join-Path $root 'src\UI\Native.cs'), $asm)
& $csc @cscArgs
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) { throw 'Compilazione di Nexora.exe fallita.' }
Sign-File $exe
Write-Host ("Nexora.exe: {0:N0} byte, versione file {1}" -f (Get-Item $exe).Length, (Get-Item $exe).VersionInfo.FileVersion)

# ---------------------------------------------------------------- 4. package
Step 'Preparazione del pacchetto'
$app = Join-Path $stage 'app'
New-Item -ItemType Directory -Force -Path $app | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'Start-Nexora.ps1') -Destination $app
Copy-Item -LiteralPath (Join-Path $root 'VERSION') -Destination $app
Copy-Item -LiteralPath (Join-Path $root 'src') -Destination (Join-Path $app 'src') -Recurse
New-Item -ItemType Directory -Force -Path (Join-Path $app 'Assets') | Out-Null
Copy-Item -LiteralPath $brand -Destination (Join-Path $app 'Assets\Branding') -Recurse
Copy-Item -LiteralPath (Join-Path $root 'LICENSE.txt') -Destination $stage
Copy-Item -LiteralPath (Join-Path $build 'Installer\README.txt') -Destination $stage
Write-Host ("Pacchetto: {0} file, {1:N1} MB" -f (Get-ChildItem $stage -Recurse -File).Count, ((Get-ChildItem $stage -Recurse -File | Measure-Object Length -Sum).Sum / 1MB))

if ($SkipInstaller) { Write-Host "`nInstaller saltato (-SkipInstaller). Pacchetto in $stage" -ForegroundColor Yellow; return }

# ---------------------------------------------------------------- 5. installer
Step 'Compilazione dell''installer (Inno Setup)'
$iscc = @(
    (Get-Command ISCC.exe -ErrorAction SilentlyContinue | ForEach-Object { $_.Source }),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 non trovato. Installalo con:  winget install JRSoftware.InnoSetup' }
New-Item -ItemType Directory -Force -Path $release | Out-Null
Get-ChildItem $release -File -ErrorAction SilentlyContinue | Remove-Item -Force
& $iscc "/DAppVersion=$version" "/DStageDir=$stage" "/DRepoRoot=$root" "/DOutDir=$release" (Join-Path $build 'Installer\Nexora.iss')
if ($LASTEXITCODE -ne 0) { throw 'Compilazione dell''installer fallita.' }

# ---------------------------------------------------------------- 6. Release
Step 'Cartella Release'
Copy-Item -LiteralPath (Join-Path $build 'Installer\README.txt') -Destination $release
Copy-Item -LiteralPath (Join-Path $root 'LICENSE.txt') -Destination $release
$setup = Join-Path $release 'Nexora-Setup.exe'
if (-not (Test-Path $setup)) { throw 'Nexora-Setup.exe non generato.' }
Sign-File $setup
Get-ChildItem $release | ForEach-Object { '{0,-20} {1,12:N0} byte' -f $_.Name, $_.Length }
Write-Host ("SHA-256 Nexora-Setup.exe: {0}" -f (Get-FileHash $setup -Algorithm SHA256).Hash)
Write-Host "`nBuild completata: NEXORA $version" -ForegroundColor Green
