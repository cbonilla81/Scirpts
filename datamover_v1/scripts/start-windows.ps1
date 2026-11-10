$ErrorActionPreference='Stop'
if (-not $env:DATAMOVER_API_KEY -or $env:DATAMOVER_API_KEY.Length -lt 32) { throw 'Set DATAMOVER_API_KEY to 32+ character secret' }
if (-not $env:DATAMOVER_ALLOWED_ROOTS) { throw 'Set DATAMOVER_ALLOWED_ROOTS' }
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --host 127.0.0.1 --port 8080 --workers 1
