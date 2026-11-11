$ErrorActionPreference='Stop'
Write-Host 'Robocopy executable:'
Get-Command robocopy.exe | Select-Object Source
Write-Host 'Robocopy version / help:'
robocopy.exe /? | Select-Object -First 8
Write-Host 'Python:'
py -3 --version
Write-Host 'Service account:'
whoami
Write-Host 'Use Test-Path \\SOURCE\share and \\DEST\share to validate SMB connectivity.'
