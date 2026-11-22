# Tools-AddBom.ps1 - saves all .ps1 files as UTF-8 with BOM (required by Windows PowerShell 5.1 to read accented characters).
# Run after editing the sources with an editor that saves UTF-8 without BOM.
Get-ChildItem -Path $PSScriptRoot -Recurse -Filter *.ps1 | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    if (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
        $text = [System.IO.File]::ReadAllText($_.FullName, (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::WriteAllText($_.FullName, $text, (New-Object System.Text.UTF8Encoding($true)))
        Write-Host "BOM aggiunto: $($_.Name)"
    }
}
