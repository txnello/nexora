<#
.SYNOPSIS
    Generates the NEXORA brand identity: vector SVGs, PNGs, multi-resolution ICO, splash screen and installer images.
.DESCRIPTION
    No stock assets: the symbol is original geometry (an "N" built from three elements + a cyan node
    representing the task to pay attention to). The NEXORA wordmark is converted into paths
    starting from the font outlines, so the SVG does not depend on installed fonts.
    Requires Windows (WPF). Run with:  powershell -STA -File Build\New-Branding.ps1
#>
[CmdletBinding()]
param(
    [string]$OutDir = '',
    [string]$InstallerDir = ''
)
$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Assets\Branding' }
if (-not $InstallerDir) { $InstallerDir = Join-Path $PSScriptRoot 'Installer' }
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
New-Item -ItemType Directory -Force -Path $OutDir, $InstallerDir | Out-Null
$inv = [System.Globalization.CultureInfo]::InvariantCulture

# ------------------------------------------------------------------ palette
$P = @{
    Midnight = '#070B1F'; Navy = '#0B1230'; Indigo = '#2A2A9E'; DeepIndigo = '#3B33D1'
    Electric = '#2F7BFF'; Cyan = '#22D3EE'; White = '#FFFFFF'; Mist = '#C9D6FF'; Grey = '#8A94B8'
}
function Brush([string]$hex) { $b = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex)); $b.Freeze(); $b }
function Gradient([string[]]$colors, [double]$x1, [double]$y1, [double]$x2, [double]$y2) {
    $g = New-Object System.Windows.Media.LinearGradientBrush
    $g.MappingMode = 'Absolute'
    $g.StartPoint = New-Object System.Windows.Point($x1, $y1); $g.EndPoint = New-Object System.Windows.Point($x2, $y2)
    for ($i = 0; $i -lt $colors.Count; $i++) {
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($colors[$i])), ($i / [math]::Max(1, $colors.Count - 1))))
    }
    $g.Freeze(); $g
}

# ------------------------------------------------------------------ symbol (viewBox 256 x 256)
# Elements: left stem, right stem, diagonal, node.
$stemL = New-Object System.Windows.Rect(46, 76, 36, 144)
$stemR = New-Object System.Windows.Rect(174, 76, 36, 144)
$diagPts = @('58,79', '85,79', '198,217', '171,217')
$dot = @{ X = 192; Y = 44; R = 16 }

function Get-DiagonalGeometry {
    $fig = New-Object System.Windows.Media.PathFigure
    $pts = $diagPts | ForEach-Object { $a = $_.Split(','); New-Object System.Windows.Point([double]$a[0], [double]$a[1]) }
    $fig.StartPoint = $pts[0]; $fig.IsClosed = $true
    foreach ($p in $pts[1..3]) { $fig.Segments.Add((New-Object System.Windows.Media.LineSegment($p, $true))) }
    $g = New-Object System.Windows.Media.PathGeometry; $g.Figures.Add($fig); $g.Freeze(); $g
}

# Draws the symbol; $Mode: 'color' (blue->indigo on transparent background) or 'icon' (white on dark tile)
function Draw-Symbol($dc, [string]$Mode) {
    if ($Mode -eq 'icon') { $fill = Gradient @($P.White, $P.Mist) 46 44 210 220 }
    else { $fill = Gradient @($P.Electric, '#6A4DFF') 46 44 210 220 }
    $pen = New-Object System.Windows.Media.Pen($fill, 6); $pen.LineJoin = 'Round'; $pen.Freeze()
    $dc.DrawRoundedRectangle($fill, $null, $stemL, 9, 9)
    $dc.DrawRoundedRectangle($fill, $null, $stemR, 9, 9)
    $dc.DrawGeometry($fill, $pen, (Get-DiagonalGeometry))
    $dc.DrawEllipse((Brush $P.Cyan), $null, (New-Object System.Windows.Point($dot.X, $dot.Y)), $dot.R, $dot.R)
}

# Application icon tile (256 x 256)
function Draw-IconTile($dc) {
    $bg = Gradient @('#2B33B8', '#101A52', $P.Midnight) 20 0 236 256
    $rect = New-Object System.Windows.Rect(8, 8, 240, 240)
    $dc.DrawRoundedRectangle($bg, $null, $rect, 56, 56)
    $edge = New-Object System.Windows.Media.Pen((Brush '#3A4BFF'), 2); $edge.Freeze()
    $dc.DrawRoundedRectangle($null, $edge, (New-Object System.Windows.Rect(9, 9, 238, 238)), 55, 55)
    Draw-Symbol $dc 'icon'
}

# ------------------------------------------------------------------ rendering / saving
function Render-Png([scriptblock]$Draw, [int]$W, [int]$H, [string]$Path, [double]$Scale = 1.0) {
    $dv = New-Object System.Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $dc.PushTransform((New-Object System.Windows.Media.ScaleTransform($Scale, $Scale)))
    & $Draw $dc
    $dc.Pop(); $dc.Close()
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($W, $H, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($dv)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $ms = New-Object System.IO.MemoryStream; $enc.Save($ms); $bytes = $ms.ToArray(); $ms.Dispose()
    if ($Path) { [System.IO.File]::WriteAllBytes($Path, $bytes) }
    return , $bytes
}

function Save-Bmp([scriptblock]$Draw, [int]$W, [int]$H, [string]$Path) {
    $dv = New-Object System.Windows.Media.DrawingVisual; $dc = $dv.RenderOpen(); & $Draw $dc; $dc.Close()
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($W, $H, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($dv)
    $conv = New-Object System.Windows.Media.Imaging.FormatConvertedBitmap($rtb, [System.Windows.Media.PixelFormats]::Bgr24, $null, 0)
    $enc = New-Object System.Windows.Media.Imaging.BmpBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($conv))
    $fs = [System.IO.File]::Create($Path); $enc.Save($fs); $fs.Dispose()
}

# ------------------------------------------------------------------ NEXORA wordmark (font outlines -> vectors)
$typeface = New-Object System.Windows.Media.Typeface('Bahnschrift SemiBold')
$gt = $null
if (-not $typeface.TryGetGlyphTypeface([ref]$gt) -or -not ($gt.FamilyNames.Values -match 'Bahnschrift')) {
    $typeface = New-Object System.Windows.Media.Typeface('Segoe UI Semibold')
}
Write-Host "Font wordmark: $($typeface.FontFamily.Source)"
function Get-WordmarkGeometry([double]$EmSize, [double]$Tracking, [double]$Left, [double]$CenterY) {
    $group = New-Object System.Windows.Media.GeometryGroup
    $group.FillRule = 'Nonzero'
    $x = 0.0
    foreach ($ch in 'NEXORA'.ToCharArray()) {
        $ft = New-Object System.Windows.Media.FormattedText([string]$ch, $inv, 'LeftToRight', $typeface, $EmSize, [System.Windows.Media.Brushes]::Black)
        $group.Children.Add($ft.BuildGeometry((New-Object System.Windows.Point($x, 0))))
        $x += $ft.WidthIncludingTrailingWhitespace + $Tracking
    }
    $b = $group.Bounds
    $group.Transform = New-Object System.Windows.Media.TranslateTransform(($Left - $b.X), ($CenterY - ($b.Y + $b.Height / 2)))
    $pg = [System.Windows.Media.PathGeometry]::CreateFromGeometry($group)
    $pg = $pg.GetFlattenedPathGeometry(0.02, 'Absolute')
    $pg.Freeze()
    return $pg
}
function ConvertTo-SvgPath([System.Windows.Media.PathGeometry]$pg) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($f in $pg.Figures) {
        [void]$sb.Append(('M{0} {1}' -f $f.StartPoint.X.ToString('0.##', $inv), $f.StartPoint.Y.ToString('0.##', $inv)))
        foreach ($s in $f.Segments) {
            if ($s -is [System.Windows.Media.LineSegment]) { [void]$sb.Append(('L{0} {1}' -f $s.Point.X.ToString('0.##', $inv), $s.Point.Y.ToString('0.##', $inv))) }
            elseif ($s -is [System.Windows.Media.PolyLineSegment]) { foreach ($p in $s.Points) { [void]$sb.Append(('L{0} {1}' -f $p.X.ToString('0.##', $inv), $p.Y.ToString('0.##', $inv))) } }
            else { throw "Unhandled segment: $($s.GetType().Name)" }
        }
        if ($f.IsClosed) { [void]$sb.Append('Z') }
    }
    $sb.ToString()
}

# Horizontal logo layout (units = symbol viewBox): 256x256 symbol on the left, wordmark on the right
$wordLeft = 290.0; $emSize = 150.0; $tracking = 22.0
$wordGeo = Get-WordmarkGeometry $emSize $tracking $wordLeft 132
$logoW = [int][math]::Ceiling($wordGeo.Bounds.Right + 24); $logoH = 256

function Draw-Logo($dc, [string]$WordColor) {
    Draw-Symbol $dc 'color'
    $dc.DrawGeometry((Brush $WordColor), $null, $wordGeo)
}

# ------------------------------------------------------------------ SVG
function Get-SymbolSvgBody([string]$c1, [string]$c2) {
    $lines = @(
        "<defs><linearGradient id=`"g`" gradientUnits=`"userSpaceOnUse`" x1=`"46`" y1=`"44`" x2=`"210`" y2=`"220`"><stop offset=`"0`" stop-color=`"$c1`"/><stop offset=`"1`" stop-color=`"$c2`"/></linearGradient></defs>",
        "  <rect x=`"46`" y=`"76`" width=`"36`" height=`"144`" rx=`"9`" fill=`"url(#g)`"/>",
        "  <rect x=`"174`" y=`"76`" width=`"36`" height=`"144`" rx=`"9`" fill=`"url(#g)`"/>",
        "  <polygon points=`"58,79 85,79 198,217 171,217`" fill=`"url(#g)`" stroke=`"url(#g)`" stroke-width=`"6`" stroke-linejoin=`"round`"/>",
        "  <circle cx=`"$($dot.X)`" cy=`"$($dot.Y)`" r=`"$($dot.R)`" fill=`"$($P.Cyan)`"/>"
    )
    $lines -join "`n"
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
$symSvg = "<svg xmlns=`"http://www.w3.org/2000/svg`" viewBox=`"0 0 256 256`" width=`"512`" height=`"512`" role=`"img`" aria-label=`"NEXORA symbol`">`n  <title>NEXORA</title>`n  " + (Get-SymbolSvgBody $P.Electric '#6A4DFF') + "`n</svg>`n"
[System.IO.File]::WriteAllText((Join-Path $OutDir 'nexora-symbol.svg'), $symSvg, $utf8)

$wordPath = ConvertTo-SvgPath $wordGeo
function Get-LogoSvg([string]$wordColor) {
    "<svg xmlns=`"http://www.w3.org/2000/svg`" viewBox=`"0 0 $logoW $logoH`" width=`"$($logoW * 2)`" height=`"$($logoH * 2)`" role=`"img`" aria-label=`"NEXORA`">`n  <title>NEXORA</title>`n  " +
    (Get-SymbolSvgBody $P.Electric '#6A4DFF') + "`n  <path fill=`"$wordColor`" fill-rule=`"nonzero`" d=`"$wordPath`"/>`n</svg>`n"
}
[System.IO.File]::WriteAllText((Join-Path $OutDir 'nexora-logo.svg'), (Get-LogoSvg $P.Navy), $utf8)
[System.IO.File]::WriteAllText((Join-Path $OutDir 'nexora-logo-white.svg'), (Get-LogoSvg $P.White), $utf8)

# ------------------------------------------------------------------ PNG
[void](Render-Png { param($dc) Draw-Symbol $dc 'color' } 512 512 (Join-Path $OutDir 'nexora-symbol.png') 2.0)
[void](Render-Png { param($dc) Draw-Logo $dc $P.Navy } ($logoW * 2) ($logoH * 2) (Join-Path $OutDir 'nexora-logo.png') 2.0)
[void](Render-Png { param($dc) Draw-Logo $dc $P.White } ($logoW * 2) ($logoH * 2) (Join-Path $OutDir 'nexora-logo-white.png') 2.0)
[void](Render-Png { param($dc) Draw-IconTile $dc } 512 512 (Join-Path $OutDir 'nexora-icon.png') 2.0)

# ------------------------------------------------------------------ multi-resolution ICO (real PNG frames 16/32/48/64/128/256)
$sizes = 16, 32, 48, 64, 128, 256
$frames = @()
foreach ($s in $sizes) { $frames += , @($s, (Render-Png { param($dc) Draw-IconTile $dc } $s $s '' ($s / 256.0))) }
$ms = New-Object System.IO.MemoryStream; $bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
foreach ($f in $frames) {
    $dim = $f[0]; $bytes = [byte[]]$f[1]
    $b = $(if ($dim -ge 256) { [byte]0 } else { [byte]$dim })
    $bw.Write($b); $bw.Write($b)
    $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$bytes.Length); $bw.Write([uint32]$offset)
    $offset += $bytes.Length
}
foreach ($f in $frames) { $bw.Write([byte[]]$f[1]) }
$bw.Flush()
[System.IO.File]::WriteAllBytes((Join-Path $OutDir 'nexora-icon.ico'), $ms.ToArray()); $bw.Dispose()

# ------------------------------------------------------------------ splash 1600 x 900
function Draw-Splash($dc) {
    $W = 1600; $H = 900
    $dc.DrawRectangle((Gradient @($P.Midnight, '#0E1650', $P.Navy) 0 0 $W $H), $null, (New-Object System.Windows.Rect(0, 0, $W, $H)))
    $glow = New-Object System.Windows.Media.RadialGradientBrush
    $glow.Center = New-Object System.Windows.Point(0.5, 0.42); $glow.GradientOrigin = $glow.Center; $glow.RadiusX = 0.45; $glow.RadiusY = 0.55
    $glow.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(110, 47, 123, 255)), 0))
    $glow.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(0, 47, 123, 255)), 1))
    $dc.DrawRectangle($glow, $null, (New-Object System.Windows.Rect(0, 0, $W, $H)))
    $dotBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(34, 160, 190, 255)); $dotBrush.Freeze()
    for ($gx = 40; $gx -lt $W; $gx += 40) { for ($gy = 40; $gy -lt $H; $gy += 40) { $dc.DrawEllipse($dotBrush, $null, (New-Object System.Windows.Point($gx, $gy)), 1.3, 1.3) } }
    $dc.PushTransform((New-Object System.Windows.Media.TranslateTransform(($W / 2 - 192), 150)))
    $dc.PushTransform((New-Object System.Windows.Media.ScaleTransform(1.5, 1.5)))
    Draw-Symbol $dc 'icon'
    $dc.Pop(); $dc.Pop()
    $wg = Get-WordmarkGeometry 120 18 0 0
    $wm = Get-WordmarkGeometry 120 18 (($W - $wg.Bounds.Width) / 2) 600
    $dc.DrawGeometry((Brush $P.White), $null, $wm)
    $tag = New-Object System.Windows.Media.FormattedText('INTELLIGENT TASK MANAGEMENT', $inv, 'LeftToRight', (New-Object System.Windows.Media.Typeface('Segoe UI Semibold')), 26, (Brush $P.Cyan))
    $dc.DrawText($tag, (New-Object System.Windows.Point((($W - $tag.Width) / 2 + 2), 690)))
    $line = New-Object System.Windows.Media.Pen((Gradient @('#002F7BFF', $P.Cyan, '#002F7BFF') 600 0 1000 0), 2); $line.Freeze()
    $dc.DrawLine($line, (New-Object System.Windows.Point(600, 760)), (New-Object System.Windows.Point(1000, 760)))
}
[void](Render-Png { param($dc) Draw-Splash $dc } 1600 900 (Join-Path $OutDir 'nexora-splash.png') 1.0)

# ------------------------------------------------------------------ installer images (24-bit BMP, 100% and 200%)
function Draw-WizardLarge($dc, [double]$k) {
    $W = 164 * $k; $H = 314 * $k
    $dc.DrawRectangle((Gradient @($P.Midnight, '#16206B', '#0B1230') 0 0 $W $H), $null, (New-Object System.Windows.Rect(0, 0, $W, $H)))
    $tx = ($W - 128 * $k) / 2; $ty = 40 * $k
    $dc.PushTransform((New-Object System.Windows.Media.TranslateTransform($tx, $ty)))
    $dc.PushTransform((New-Object System.Windows.Media.ScaleTransform((0.5 * $k), (0.5 * $k))))
    Draw-Symbol $dc 'icon'
    $dc.Pop(); $dc.Pop()
    $wg = Get-WordmarkGeometry (22 * $k) (4 * $k) 0 0
    $wm = Get-WordmarkGeometry (22 * $k) (4 * $k) (($W - $wg.Bounds.Width) / 2) (212 * $k)
    $dc.DrawGeometry((Brush $P.White), $null, $wm)
    $t = New-Object System.Windows.Media.FormattedText('INTELLIGENT TASK MANAGEMENT', $inv, 'LeftToRight', (New-Object System.Windows.Media.Typeface('Segoe UI')), (7.5 * $k), (Brush $P.Cyan))
    $dc.DrawText($t, (New-Object System.Windows.Point((($W - $t.Width) / 2), (232 * $k))))
}
function Draw-WizardSmall($dc, [double]$k) {
    $W = 55 * $k; $H = 58 * $k
    $dc.DrawRectangle((Brush $P.White), $null, (New-Object System.Windows.Rect(0, 0, $W, $H)))
    $dc.PushTransform((New-Object System.Windows.Media.TranslateTransform((3 * $k), (2 * $k))))
    $dc.PushTransform((New-Object System.Windows.Media.ScaleTransform((49 * $k / 256), (49 * $k / 256))))
    Draw-IconTile $dc
    $dc.Pop(); $dc.Pop()
}
Save-Bmp { param($dc) Draw-WizardLarge $dc 1.0 } 164 314 (Join-Path $InstallerDir 'wizard-large.bmp')
Save-Bmp { param($dc) Draw-WizardLarge $dc 2.0 } 328 628 (Join-Path $InstallerDir 'wizard-large@2x.bmp')
Save-Bmp { param($dc) Draw-WizardSmall $dc 1.0 } 55 58 (Join-Path $InstallerDir 'wizard-small.bmp')
Save-Bmp { param($dc) Draw-WizardSmall $dc 2.0 } 110 116 (Join-Path $InstallerDir 'wizard-small@2x.bmp')

Write-Host "Brand assets generated in $OutDir"
Get-ChildItem $OutDir | ForEach-Object { '{0,-26} {1,8} B' -f $_.Name, $_.Length }
