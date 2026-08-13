$path = 'c:\Users\bonillac\OneDrive - RSandH\Documents\Scirpts\FileArchiveUtility\FileArchiveUtility\FileArchiveUtility\Archive-OldFiles-GUI.ps1'
$errors = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors) {
    foreach ($error in $errors) {
        Write-Host "Message: $($error.Message)"
        Write-Host "Line: $($error.Extent.StartLineNumber) Char: $($error.Extent.StartColumnNumber)"
        Write-Host "Text: $($error.Extent.Text)"
        Write-Host '---'
    }
    exit 1
}
Write-Host 'OK'
