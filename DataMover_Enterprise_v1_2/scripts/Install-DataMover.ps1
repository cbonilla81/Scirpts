#Requires -Version 5.1
param([string]$InstallPath='C:\DataMover')
$ErrorActionPreference='Stop'
if (-not (Get-Command py -ErrorAction SilentlyContinue)) { throw 'Install Python 3.11+ and the Python launcher first.' }
if (-not (Get-Command robocopy.exe -ErrorAction SilentlyContinue)) { throw 'Robocopy not found. Run on Windows Server.' }
New-Item -ItemType Directory -Force -Path $InstallPath | Out-Null
Copy-Item "$PSScriptRoot\..\*" $InstallPath -Recurse -Force -Exclude 'state','.venv' # Review contents before production installation
Push-Location $InstallPath
try {
  py -3 -m venv .venv
  & .\.venv\Scripts\python.exe -m pip install -r requirements.txt
  if (-not (Test-Path '.env')) { Copy-Item '.env.example' '.env' }
  Write-Host 'Edit .env and then run scripts\Start-DataMover.ps1. Do not expose port 8080 publicly.'
} finally { Pop-Location }
