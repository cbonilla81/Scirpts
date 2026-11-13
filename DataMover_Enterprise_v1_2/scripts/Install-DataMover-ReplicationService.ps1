#Requires -Version 5.1
#Requires -RunAsAdministrator
param([Parameter(Mandatory=$true)][string]$ServiceAccount)
$ErrorActionPreference='Stop'
Set-Location (Resolve-Path "$PSScriptRoot\..")
if (-not (Test-Path '.env')) { throw 'Create .env from .env.example before installing the worker service.' }
if (-not (Test-Path '.worker.env')) { throw 'Create .worker.env from .worker.env.example and set the shared state path and approved roots.' }
if (-not (Test-Path '.venv\Scripts\python.exe')) { throw 'Create the project virtual environment before installing the worker service.' }
function Get-EnvironmentValue([string]$Path, [string]$Name) {
  $entry = Get-Content $Path | Where-Object { $_ -match "^\s*$Name\s*=" } | Select-Object -First 1
  if (-not $entry) { return $null }
  return ($entry -split '=',2)[1].Trim()
}
$apiState = Get-EnvironmentValue '.env' 'DATAMOVER_STATE'
$workerState = Get-EnvironmentValue '.worker.env' 'DATAMOVER_STATE'
$apiRoots = Get-EnvironmentValue '.env' 'DATAMOVER_ALLOWED_ROOTS'
$workerRoots = Get-EnvironmentValue '.worker.env' 'DATAMOVER_ALLOWED_ROOTS'
if (-not $apiState -or $apiState -ine $workerState) { throw 'DATAMOVER_STATE must match in .env and .worker.env.' }
if (-not $apiRoots -or $apiRoots -ine $workerRoots) { throw 'Initial DATAMOVER_ALLOWED_ROOTS must match in .env and .worker.env.' }
$python = Resolve-Path '.venv\Scripts\python.exe'
& $python -m pip install -r requirements.txt
if ($LASTEXITCODE -ne 0) { throw 'Could not install DataMover worker dependencies.' }
& $python 'scripts\DataMoverReplicationService.py' install
if ($LASTEXITCODE -ne 0) { throw 'Could not install the DataMover replication service.' }
& sc.exe config DataMoverReplication 'start= auto' "obj= $ServiceAccount" 'password= ""'
if ($LASTEXITCODE -ne 0) { throw 'Could not configure the service account and automatic startup.' }
Write-Host 'Set the service Log On account to a dedicated gMSA with source read and destination write/security rights.'
Write-Host 'Grant the service account access to DATAMOVER_STATE and .worker.env, not the web console .env file.'
Write-Host 'Starting the service now.'
Start-Service DataMoverReplication
