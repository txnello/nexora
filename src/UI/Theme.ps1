# Theme.ps1 - WPF initialization, light/dark themes, XAML loading, UI error handling

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

$script:UiPath = $PSScriptRoot

# TaskRow and native calls: already compiled in Nexora.exe; when running from sources they are compiled on the fly
if (-not ('TaskRow' -as [type]) -or -not ('Stm.Native' -as [type]) -or -not ('Stm.Dwm' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'Native.cs')
}

$script:Themes = @{
    dark  = @{
        Bg = '#0E1014'; Surface = '#15181E'; Surface2 = '#1D2129'; InputBg = '#11141A'; Line = '#272C36'
        Text = '#E7E9EE'; Muted = '#8A92A2'; Accent = '#7C8BFF'; AccentFg = '#0E1014'
        Danger = '#F0616D'; DangerInputBg = '#2EF0616D'; Warn = '#F5A524'; Ok = '#2BC48A'
        Hover = '#1B1F27'; Select = '#232A4A'; HoverOverlay = '#14FFFFFF'
        RowOverdue = '#2B171B'; RowUrgent = '#2A2214'
    }
    light = @{
        Bg = '#F5F6F8'; Surface = '#FFFFFF'; Surface2 = '#F1F3F6'; InputBg = '#FFFFFF'; Line = '#E2E5EA'
        Text = '#1A1D24'; Muted = '#69707D'; Accent = '#4F5DE8'; AccentFg = '#FFFFFF'
        Danger = '#D93636'; DangerInputBg = '#20D93636'; Warn = '#C9780A'; Ok = '#0E9F6E'
        Hover = '#F2F4F7'; Select = '#E6E9FF'; HoverOverlay = '#10000000'
        RowOverdue = '#FDEDEE'; RowUrgent = '#FEF4DE'
    }
}

function New-FrozenBrush {
    param([string]$Hex)
    $b = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Hex))
    $b.Freeze()
    return $b
}

function ConvertTo-TintHex {
    # '#RRGGBB' -> '#RRGGBB' with transparency (for badges)
    param([string]$Hex, [string]$Alpha = '2E')
    if (-not (Test-HexColor $Hex)) { return '#222B2B2B' }
    return '#' + $Alpha + $Hex.Substring(1)
}

function Initialize-Wpf {
    $app = [System.Windows.Application]::Current
    if ($null -eq $app) { $app = New-Object System.Windows.Application }
    $app.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
    $script:App = $app
    # styles (use DynamicResource: brushes are set by Set-Theme)
    Set-Theme 'dark'
    $dict = [System.Windows.Markup.XamlReader]::Parse([System.IO.File]::ReadAllText((Join-Path $script:UiPath 'Styles.xaml')))
    $app.Resources.MergedDictionaries.Add($dict)
    return $app
}

function Set-Theme {
    param([string]$Name)
    if (-not $script:Themes.ContainsKey($Name)) { $Name = 'dark' }
    $script:CurrentTheme = $Name
    $t = $script:Themes[$Name]
    $app = [System.Windows.Application]::Current
    foreach ($k in $t.Keys) {
        $brush = New-FrozenBrush $t[$k]
        $app.Resources["$($k)Brush"] = $brush.PSObject.BaseObject
    }
    foreach ($w in $app.Windows) { Set-TitleBarTheme $w }
}

function Set-TitleBarTheme {
    # dark/light title bar (Windows 10 20H1+ / 11); ignores errors on old systems
    param($Window)
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper $Window).EnsureHandle()
        $v = $(if ($script:CurrentTheme -eq 'dark') { 1 } else { 0 })
        [void][Stm.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$v, 4)
    } catch { }
}

function Import-Xaml {
    param([string]$Name)
    $xaml = [System.IO.File]::ReadAllText((Join-Path $script:UiPath $Name))
    if ($script:Lang -eq 'it') {
        # XAML texts are in English: in Italian they are replaced with the translation
        $xaml = [regex]::Replace($xaml, '(\b(?:Text|Content|Header|ToolTip|Title)=")([^"]*)(")', [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            $v = [System.Net.WebUtility]::HtmlDecode($m.Groups[2].Value)
            if ($script:It.ContainsKey($v)) { return $m.Groups[1].Value + [System.Security.SecurityElement]::Escape($script:It[$v]) + $m.Groups[3].Value }
            return $m.Value
        })
    }
    $w = [System.Windows.Markup.XamlReader]::Parse($xaml)
    Set-WindowIcon $w
    $w.add_SourceInitialized({ param($s, $e) Set-TitleBarTheme $s })
    return $w
}

function Get-Named {
    param($Root, [string[]]$Names)
    $h = @{}
    foreach ($n in $Names) {
        $c = $Root.FindName($n)
        if ($null -eq $c) { throw "XAML control not found: $n" }
        $h[$n] = $c
    }
    return $h
}

# ------------------------------------------------------------------ Event handling with error protection

$script:Handlers = @{}
$script:HandlerCount = 0

function Invoke-Handler {
    param([int]$Id, $Sender, $EventArgs)
    try { & $script:Handlers[$Id] $Sender $EventArgs }
    catch { Show-UiError $_ }
}

function On {
    # Registers a handler (scriptblock with param($s,$e)) with global try/catch
    param($Control, [string]$Event, [scriptblock]$Body)
    $id = $script:HandlerCount++
    $script:Handlers[$id] = $Body
    $wrapper = [scriptblock]::Create("param(`$s, `$e) Invoke-Handler $id `$s `$e")
    $Control."add_$Event"($wrapper)
}

function Show-UiError {
    param($ErrorRecord)
    $msg = $ErrorRecord.Exception.Message
    Write-Log ("UI error: {0}`n{1}" -f $msg, $ErrorRecord.ScriptStackTrace) 'ERROR'
    if ($script:TestMode) { $script:UiErrors += ("{0} @ {1}" -f $msg, $ErrorRecord.ScriptStackTrace); return }
    try { Show-Message -Title (T 'Operation failed') -Text $msg -Icon 'error' | Out-Null } catch { }
}

function Set-FieldInvalid {
    param($Control, [bool]$Invalid)
    $Control.Tag = $(if ($Invalid) { 'invalid' } else { '' })
}

function Set-WindowIcon {
    # NEXORA icon (multi-resolution ICO) for title bar and taskbar
    param($Window)
    try {
        $ico = Join-Path $script:AssetsPath 'Branding\nexora-icon.ico'
        if (Test-Path -LiteralPath $ico) { $Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri($ico))) }
    } catch { Write-Log "Icon not loaded: $($_.Exception.Message)" 'WARN' }
}

function Get-BrandImage {
    # Loads a brand PNG as ImageSource (null if missing)
    param([string]$Name)
    try {
        $f = Join-Path $script:AssetsPath "Branding\$Name"
        if (-not (Test-Path -LiteralPath $f)) { return $null }
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit(); $bi.UriSource = New-Object System.Uri($f); $bi.CacheOption = 'OnLoad'; $bi.EndInit(); $bi.Freeze()
        return $bi
    } catch { return $null }
}
