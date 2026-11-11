#Requires -Version 5.1
$ErrorActionPreference='Stop'
Set-Location (Resolve-Path "$PSScriptRoot\..")
if (-not (Test-Path '.env')) { throw 'Create .env from .env.example and set session secret and approved roots' }
Get-Content '.env' | ForEach-Object {
  $line=$_.Trim()
  if ($line -and -not $line.StartsWith('#')) {
    $kv=$line -split '=',2
    if ($kv.Count -eq 2) { [Environment]::SetEnvironmentVariable($kv[0].Trim(),$kv[1].Trim(),'Process') }
  }
}
if (-not $env:DATAMOVER_SESSION_SECRET -or $env:DATAMOVER_SESSION_SECRET.Length -lt 32 -or $env:DATAMOVER_SESSION_SECRET.StartsWith('REPLACE_')) { throw 'Set DATAMOVER_SESSION_SECRET to a random secret of at least 32 characters' }
if (-not $env:DATAMOVER_ALLOWED_ROOTS) { throw 'Set DATAMOVER_ALLOWED_ROOTS' }
if (-not (Get-Command robocopy.exe -ErrorAction SilentlyContinue)) { throw 'Robocopy unavailable' }
$bind=if($env:DATAMOVER_BIND){$env:DATAMOVER_BIND}else{'127.0.0.1'}
$port=if($env:DATAMOVER_PORT){$env:DATAMOVER_PORT}else{'8080'}
& .\.venv\Scripts\python.exe -m uvicorn app.main:app --host $bind --port $port --workers 1
