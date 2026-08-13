$path = 'c:\Users\bonillac\OneDrive - RSandH\Documents\Scirpts\FileArchiveUtility\FileArchiveUtility\FileArchiveUtility\Archive-OldFiles-GUI.ps1'
$lines = Get-Content -LiteralPath $path
$start = 402
$end = 418
for ($i = $start; $i -le $end; $i++) {
    $line = $lines[$i-1]
    Write-Host "Line $i: $line"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
    Write-Host "Bytes: $([string]::Join(' ', $bytes))"
}
