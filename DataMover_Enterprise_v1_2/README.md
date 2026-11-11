# DataMover Enterprise v1.2 — Robocopy-only Windows edition

A light-themed FastAPI + HTML pilot for **Windows Server SMB/NTFS migrations**. This release does not include Rclone, cloud object-storage connectors, remote Linux workers, or automatic DFS/DNS changes.

**Production status: PILOT.** Validate against non-production shares first. A successful Robocopy exit code does not prove ACL parity, file content parity, source freeze, or successful user cutover. Operator-attested checks are clearly labeled.

## Quick start

1. Install **Windows Server 2019/2022/2025**, Python 3.11+ and Robocopy (included with Windows). Run `Get-Command robocopy.exe` and `robocopy /?` in PowerShell.
2. Extract this repository to `C:\DataMover`. Open PowerShell in that directory.
3. Run `py -3 -m venv .venv`, then `.\.venv\Scripts\python.exe -m pip install -r requirements.txt`.
4. Copy `.env.example` to `.env`; generate a random session secret with `[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))` in PowerShell 7, or use `[guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')` in Windows PowerShell. Set `DATAMOVER_SESSION_SECRET` and exact approved root paths such as `\\FS01\Shares;\\FS02\Shares` (single backslashes in the actual `.env` value; see below). Configure optional AD and Entra settings as applicable.
5. Run `.\scripts\Start-DataMover.ps1`. On first startup, retrieve the one-time setup code from the service log (or set a protected `DATAMOVER_SETUP_TOKEN` before starting), then open `http://127.0.0.1:8080/login` **on the management host** to create the first local administrator. The console also opens at `/`. For a presentation preview of the same console and login page, open `http://127.0.0.1:8080/demo`. Demo sign-ins and actions use sample data only and never call the production API; enter any username/password, or open `/demo?setup=1` to preview first-admin setup using `DEMO-SETUP-CODE-000000000000`.
6. Create a small test job using approved source/destination paths, run **Dry-Run**, inspect the run history and `state\logs`, then run initial sync and independently verify files and ACLs.

**Important `.env` example** (no quotes, no backslash escaping):

```ini
DATAMOVER_ALLOWED_ROOTS=\\FS01\Shares;\\FS02\Shares
DATAMOVER_STATE=C:\ProgramData\DataMover
DATAMOVER_BIND=127.0.0.1
DATAMOVER_PORT=8080
DATAMOVER_TZ=America/New_York
DATAMOVER_MAX_WORKERS=2
```

Keep `.env` readable only by administrators and the dedicated service identity. `DATAMOVER_SESSION_SECRET` must be a random value of at least 32 characters. Set `DATAMOVER_COOKIE_SECURE=true` when serving the application over HTTPS.

Authentication options:

- **Local:** username/password accounts are stored in the application SQLite database. The first administrator is created through the one-time setup page; administrators can create and disable additional local accounts.
- **Active Directory:** set `DATAMOVER_AD_LDAP_URL` to an `ldap://` directory URL. Authentication uses LDAP StartTLS with certificate validation; configure `DATAMOVER_AD_CA_CERT` when the directory CA is not in the host trust store. Users sign in with their user principal name.
- **Microsoft Entra ID:** configure the app registration client ID/secret, HTTPS redirect URI (`https://<host>/auth/entra/callback`), and comma-separated tenant UUID allowlist. Only identities issued by an allowlisted tenant can sign in.

All authenticated users can operate migration jobs; local administrator privileges are limited to local account management.

## Architecture

```text
Browser (localhost) --> FastAPI + HTML console --> SQLite job/events/runs
                          |                     --> APScheduler cron triggers
                          v
                 Windows Robocopy worker
                          |
                  SMB source --> SMB destination
```

Run the worker under a **dedicated least-privilege domain identity**, with source read/backup and destination write/restore/security privileges as required. `/COPYALL` requires support for owner and SACL transfer; test privileges, NTFS semantics, and inherited ACL behavior. Share-level permissions are **not** copied by Robocopy and require a separate plan.

## Migration commands

The backend launches an argument list via `subprocess.Popen(shell=False)` and uses the system `robocopy.exe`. It uses `/E /COPYALL /DCOPY:DAT /ZB /MT:16 /R:3 /W:5 /XJ /NP /TEE /BYTES` and per-run `/LOG:`. Dry-Run adds `/L /R:0 /W:0`. Final sync adds `/SECFIX /TIMFIX`. **No `/MIR` or `/PURGE`**. Destination-only data is not deleted. Robocopy exit codes 0–7 are treated as non-fatal; 8+ is failure. Exit codes 2–7 may still require manual review of extras/mismatches.

## Scheduling

Jobs accept a five-field cron expression (minute hour day month weekday), e.g. `0 2 * * *` for daily 02:00 in `DATAMOVER_TZ`. APScheduler runs within the single API process; start only **one** Uvicorn worker. Scheduled sync is skipped when the job is already running, frozen, or handed off. The scheduler does not catch up missed executions after shutdown. Do not run multiple API replicas against the same SQLite file.

## Cutover

1. Run Dry-Run and review the proposed operations.
2. Run baseline and scheduled incremental syncs; each successful incremental sync invalidates prior dry-run/validation approvals.
3. Run a fresh Dry-Run and **independently** compare file counts, file content as needed, owner/DACL/SACL, inheritance, and effective access. Record a change ticket and attest validation.
4. Actually freeze source writes using an external operational procedure; attest freeze. The application **does not enforce the freeze**.
5. Approve final sync, then run **Final Sync**. Verify exit code and logs.
6. Perform independent final data and ACL verification; attest verification.
7. Redirect clients/DFS/share mappings through your organization's change process; confirm handoff in the dashboard. Handoff disables scheduling.
8. Retain the original source until the rollback window expires. The rollback endpoint provides a checklist, **not** a reverse-sync action.

## Security and known limits

- Bind to `127.0.0.1` by default; use a vetted TLS reverse proxy for remote access and set `DATAMOVER_COOKIE_SECURE=true`. Local, Active Directory and Entra ID sign-in use eight-hour signed sessions and CSRF protection on mutations. The application does not provide granular job-level RBAC.
- Approved source/destination roots are enforced; path traversal, nested paths, unsafe switches, and arbitrary command execution are blocked.
- Only Windows can run Robocopy. Network shares must be reachable under the **worker service account**.
- Current dashboard shows job state and run summaries; **not trustworthy byte-level progress, throughput, or ETA**. The progress bar is decorative and does not claim actual percentage.
- Operator attestations are not automated integrity verification. No automatic NTFS ACL diff, hash compare, share ACL export, DFS/DNS switch, backup, retry orchestration, or rollback execution.
- SQLite is suitable for a single-host pilot. Use an external database and durable job queue before production multiworker operation.
- Running a service under a user account, log rotation, service recovery, security event forwarding, and backups require deployment-specific configuration.
- Run tests with `.\.venv\Scripts\python.exe -m pytest -q`. Python unit tests can run on non-Windows with mocked executable detection.

## API endpoints

Protected job and health endpoints require a signed session. Mutating requests also require the session's `X-CSRF-Token`. Public auth endpoints are `GET /api/auth/methods`, `POST /api/auth/setup`, `POST /api/auth/local`, and `POST /api/auth/ad`; Entra uses `/auth/entra/login` and `/auth/entra/callback`. Authenticated users can use `POST /api/auth/logout`, `GET /api/health`, `GET /api/jobs`, `POST /api/jobs`, `GET /api/jobs/{id}`, `GET /api/jobs/{id}/events`, `GET /api/jobs/{id}/runs`, `POST /api/jobs/{id}/run/{dry-run|sync|final}`, `POST /api/jobs/{id}/validate`, `/freeze`, `/approve`, `/verify-final`, `/handoff` and `GET /api/jobs/{id}/rollback-plan`. Local administrators manage local accounts through `/api/users`. Attestation requests use `{"confirmed":true,"note":"Change ticket CHG-12345 verified by operator"}`.

See `docs/IMPLEMENTATION.md` for detailed deployment and acceptance checklist.
