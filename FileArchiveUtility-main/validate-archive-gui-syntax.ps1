$errors = $null
$tokens = $null
$path = Join-Path $PSScriptRoot 'Archive-OldFiles-GUI.ps1'
[System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors) {
    $errors | Format-List *
    exit 1
}
Write-Host 'OK'
