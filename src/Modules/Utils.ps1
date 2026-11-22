# Utils.ps1 - shared utility functions (no UI dependencies)

$script:Lang = 'en'
$script:UiCulture = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
$script:It = New-Object System.Collections.Hashtable   # English -> Italian table (Strings.ps1)
$script:Inv = [System.Globalization.CultureInfo]::InvariantCulture

function Initialize-Logging {
    param([Parameter(Mandatory)][string]$LogDir)
    $script:LogDir = $LogDir
    if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        if (-not $script:LogDir) { return }
        $file = Join-Path $script:LogDir 'app.log'
        if ((Test-Path -LiteralPath $file) -and ((Get-Item -LiteralPath $file).Length -gt 1MB)) {
            Move-Item -LiteralPath $file -Destination "$file.old" -Force
        }
        $line = '{0} [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message
        Add-Content -LiteralPath $file -Value $line -Encoding UTF8
    } catch { }
}

function New-Id { [guid]::NewGuid().ToString('N') }

function ConvertTo-List {
    # Converts any value (null, scalar, array) to List[object]
    param($Value)
    $list = New-Object 'System.Collections.Generic.List[psobject]'
    if ($null -ne $Value) { foreach ($i in @($Value)) { if ($null -ne $i) { $list.Add($i) } } }
    return , $list
}

function ConvertTo-DateTimeValue {
    # Accepts DateTime or ISO string; returns [datetime] or $null
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $d = [datetime]::MinValue
    if ([datetime]::TryParse($s, $script:Inv, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$d)) {
        if ($d.Kind -eq [System.DateTimeKind]::Utc) { $d = $d.ToLocalTime() }
        return $d
    }
    return $null
}

function Format-IsoDateTime {
    param($Value)
    $d = ConvertTo-DateTimeValue $Value
    if ($null -eq $d) { return $null }
    return $d.ToString('yyyy-MM-ddTHH:mm:ss', $script:Inv)
}

function Format-IsoDate {
    param($Value)
    $d = ConvertTo-DateTimeValue $Value
    if ($null -eq $d) { return $null }
    return $d.ToString('yyyy-MM-dd', $script:Inv)
}

function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Set-Prop {
    # Sets (or creates) a property on a PSCustomObject
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
}

function Test-HexColor {
    param([string]$Value)
    return ($Value -match '^#[0-9A-Fa-f]{6}$')
}

function Set-Language {
    # Sets the UI language: 'en' (default) or 'it'
    param([string]$Code)
    if ($Code -ne 'it') { $Code = 'en' }
    $script:Lang = $Code
    $script:UiCulture = [System.Globalization.CultureInfo]::GetCultureInfo($(if ($Code -eq 'it') { 'it-IT' } else { 'en-US' }))
}

function T {
    # Translates text (key is English text). Optional args: placeholders {0}, {1}...
    param([string]$Key)
    $s = $Key
    if ($script:Lang -eq 'it' -and $script:It.ContainsKey($Key)) { $s = $script:It[$Key] }
    if ($args.Count -gt 0) { $s = $s -f $args }
    return $s
}
