# DataMover Enterprise v1.2 — Robocopy-only Windows edition

A light-themed FastAPI + HTML pilot for **Windows Server SMB/NTFS migrations**. This release does not include Rclone, cloud object-storage connectors, remote Linux workers, or automatic DFS/DNS changes.

**Production status: PILOT.** Validate against non-production shares first. A successful Robocopy exit code does not prove ACL parity, file content parity, source freeze, or successful user cutover. Operator-attested checks are clearly labeled.

## Quick start

1. Install **Windows Server 2019/2022/2025**, Python 3.11+ available to all users (or otherwise readable/executable by the worker gMSA), and Robocopy (included with Windows). Run `Get-Command robocopy.exe` and `robocopy /?` in PowerShell.
2. Extract this repository to `C:\DataMover`. Open PowerShell in that directory.
3. Run `py -3 -m venv .venv`, then `.\.venv\Scripts\python.exe -m pip install -r requirements.txt`.
4. Copy `.env.example` to `.env`; generate a random session secret with `[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))` in PowerShell 7, or use `[guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')` in Windows PowerShell. Set `DATAMOVER_SESSION_SECRET` and approved roots. Configure optional AD and Entra settings as applicable.
5. Copy `.worker.env.example` to `.worker.env`. Set `DATAMOVER_STATE` to exactly the same directory in `.env` and `.worker.env`; set the same initial roots in both files. The worker file contains no web authentication secrets.
6. Run `.\scripts\Start-DataMover.ps1`. On first startup, retrieve the one-time setup code from the service log (or set a protected `DATAMOVER_SETUP_TOKEN` before starting), then open `http://127.0.0.1:8080/login` **on the management host** to create the first local administrator. The console also opens at `/`. For a presentation preview of the same console and login page, open `http://127.0.0.1:8080/demo` or open `app\static\demo.html` directly. The demo file provides a **Skip sign-in · Open demo** button; sign-ins and actions use sample data only and never call the production API. You can also enter any username/password, or open `/demo?setup=1` to preview first-admin setup using `DEMO-SETUP-CODE-000000000000`.
7. Grant the dedicated gMSA read/execute access to the project `app`, `scripts`, and `.venv` folders, read access to `.worker.env`, and Modify access to the shared state folder. Do not grant it access to the web console `.env`. In elevated PowerShell, install the worker service: `.\scripts\Install-DataMover-ReplicationService.ps1 -ServiceAccount 'CONTOSO\svc_DataMover$'`. The worker runs queued and continuous Robocopy jobs even when the interactive PowerShell console closes; the web console itself remains available only while the API is running.
8. Create a small test job using approved source/destination paths, run **Dry-Run**, inspect the run history and `state\logs`, then run initial sync and independently verify files and ACLs.

**Important `.env` example** (no quotes, no backslash escaping):

```ini
DATAMOVER_ALLOWED_ROOTS=\\FS01\Shares;\\FS02\Shares
DATAMOVER_STATE=C:\ProgramData\DataMover
DATAMOVER_BIND=127.0.0.1
DATAMOVER_PORT=8080
DATAMOVER_TZ=America/New_York
DATAMOVER_MAX_WORKERS=2
```

The `.worker.env` file must use the same state directory and initial roots, and may set `DATAMOVER_RECONCILE_SECONDS` (default 300; minimum 60) to control the full-tree reconciliation interval.

Keep `.env` readable only by administrators and the API identity. Keep `.worker.env` readable only by administrators and the replication service identity. `DATAMOVER_SESSION_SECRET` must be a random value of at least 32 characters. Set `DATAMOVER_COOKIE_SECURE=true` when serving the application over HTTPS. On first startup, `DATAMOVER_ALLOWED_ROOTS` seeds the approved roots stored in the application database. Signed-in users can manage those roots through **Manage approved roots** in the UI; changes persist in SQLite and do not require editing either environment file or restarting the app.

Authentication options:

- **Local:** username/password accounts are stored in the application SQLite database. The first administrator is created through the one-time setup page; administrators can create and disable additional local accounts.
- **Active Directory:** local administrators can configure the LDAP URL, CA certificate path, search base DN, and direct Operators and Administrators group DNs in the Active Directory section. The optional `DATAMOVER_AD_*` environment values provide initial defaults. Authentication uses LDAP StartTLS with certificate validation; users sign in with their user principal name. Administrators inherit operator access; users must be direct members of at least one configured group. Test credentials are transient and are never stored.
- **Microsoft Entra ID:** configure the app registration client ID/secret, HTTPS redirect URI (`https://<host>/auth/entra/callback`), and comma-separated tenant UUID allowlist. Only identities issued by an allowlisted tenant can sign in.

Authorized operators can operate migration jobs; local administrator privileges also allow local account management and Active Directory configuration.

## Architecture

```text
Browser (localhost) --> FastAPI + HTML console --> SQLite job/events/runs queue
                          |                              ^
                          --> APScheduler triggers        |
                                                         |
Windows replication worker service ----------------------+
       |-- watches continuous source roots
       |-- reconciles missed events with Robocopy
       +-- runs queued one-time, scheduled, and manual jobs
                 SMB source --> SMB destination
```

The API persists run requests to SQLite; a separate Windows service claims and executes them. Run the worker under a **dedicated least-privilege domain identity**, with source read/backup and destination write/restore/security privileges as required. `/COPYALL` requires support for owner and SACL transfer; test privileges, NTFS semantics, and inherited ACL behavior. Share-level permissions are **not** copied by Robocopy and require a separate plan.

## Migration commands

The worker launches an argument list via `subprocess.Popen(shell=False)` and uses the system `robocopy.exe`. Normal runs use `/E /COPYALL /DCOPY:DAT /ZB /MT:16 /R:3 /W:5 /XJ /NP /TEE /BYTES` and per-run `/LOG:`. Continuous jobs also use `/IS /IT /IM` so source files take precedence over destination edits. **No `/MIR` or `/PURGE**; source deletions are not propagated and destination-only data remains. Dry-Run adds `/L /R:0 /W:0`. Final sync adds `/SECFIX /TIMFIX`. Robocopy exit codes 0–7 are treated as non-fatal; 8+ is failure. Exit codes 2–7 may still require manual review of extras/mismatches.

## Scheduling

Jobs can run manually, once at a selected date/time, daily, weekly, monthly, or continuously. **Continuous** requires a successful Dry-Run followed by a successful initial Run Sync; only then does the worker start watching. It uses Windows file-change notifications, coalesces bursts for two seconds, and runs a full-tree reconciliation every `DATAMOVER_RECONCILE_SECONDS` (default five minutes) to recover missed network-share notifications. This is near-real-time, not instantaneous. Deletions are not propagated; source-side file content overwrites destination edits. The dashboard reports worker and per-job watcher state, latest sync outcome, and errors, but not byte progress or ETA. The worker service must remain running. If it is offline, jobs remain queued and the console reports the worker as offline.

Migration jobs can be edited while idle. Queued, running, and handed-off jobs cannot be changed. Saving an edit clears prior Dry-Run, validation, freeze, approval, final-verification, and continuous-readiness state; repeat the required checks before operating the updated job.

**Manual run response** only controls whether the browser request waits for the worker result or returns after queueing; it does not control replication frequency. Long waits can exceed browser or proxy timeouts. Times for one-time and recurring jobs use `DATAMOVER_TZ`; monthly days 29–31 are skipped in months without that day. Existing five-field cron schedules continue to work. The single API instance schedules dated/recurring triggers; start only **one** Uvicorn worker. Do not run multiple API replicas against the same SQLite file.

## Cutover

1. Run Dry-Run and review the proposed operations.
2. Run baseline and scheduled/continuous incremental syncs; each incremental sync invalidates prior dry-run/validation approvals.
3. Before cutover, run a fresh Dry-Run and **independently** compare file counts, file content as needed, owner/DACL/SACL, inheritance, and effective access. Record a change ticket and attest validation.
4. Stop source writes using an external operational procedure, confirm the source freeze in the console, and approve final sync. For continuous jobs, confirming freeze stops the watcher.
5. Approve final sync, then run **Final Sync**. Verify exit code and logs.
6. Perform independent final data and ACL verification; attest verification.
7. Redirect clients/DFS/share mappings through your organization's change process; confirm handoff in the dashboard. Handoff disables scheduling and continuous watching.
8. Retain the original source until the rollback window expires. The rollback endpoint provides a checklist, **not** a reverse-sync action.

## Security and known limits

- Bind to `127.0.0.1` by default; use a vetted TLS reverse proxy for remote access and set `DATAMOVER_COOKIE_SECURE=true`. Local, Active Directory and Entra ID sign-in use eight-hour signed sessions and CSRF protection on mutations. The application does not provide granular job-level RBAC.
- Approved source/destination roots are enforced; any signed-in user can add or remove roots in the UI, so root management expands or restricts the network paths available to all users. Path traversal, nested paths, unsafe switches, and arbitrary command execution are blocked.
- Only Windows can run Robocopy. Network shares must be reachable under the **worker service account**.
- Current dashboard shows job state and run summaries; **not trustworthy byte-level progress, throughput, or ETA**. The progress bar is decorative and does not claim actual percentage.
- Operator attestations are not automated integrity verification. No automatic NTFS ACL diff, hash compare, share ACL export, DFS/DNS switch, backup, general failed-run retry policy, or rollback execution.
- SQLite is suitable for a single-host pilot. Use an external database and distributed queue before production multiworker operation.
- Running a service under a user account, log rotation, service recovery, security event forwarding, and backups require deployment-specific configuration.
- Run tests with `.\.venv\Scripts\python.exe -m pytest -q`. Python unit tests can run on non-Windows with mocked executable detection.

## API endpoints

Protected job and health endpoints require a signed session. Mutating requests also require the session's `X-CSRF-Token`. Public auth endpoints are `GET /api/auth/methods`, `POST /api/auth/setup`, `POST /api/auth/local`, and `POST /api/auth/ad`; Entra uses `/auth/entra/login` and `/auth/entra/callback`. Authenticated operators can use `POST /api/auth/logout`, `GET /api/health`, `GET /api/jobs`, `POST /api/jobs`, `GET` and `PUT /api/jobs/{id}`, `GET /api/jobs/{id}/events`, `GET /api/jobs/{id}/runs`, `POST /api/jobs/{id}/run/{dry-run|sync|final}`, `POST /api/jobs/{id}/validate`, `/freeze`, `/approve`, `/verify-final`, `/handoff` and `GET /api/jobs/{id}/rollback-plan`. Local administrators manage local accounts through `/api/users` and Active Directory settings through `/api/admin/ad-settings`; the AD connection test is `/api/admin/ad-settings/test`. Attestation requests use `{"confirmed":true,"note":"Change ticket CHG-12345 verified by operator"}`.

See `docs/IMPLEMENTATION.md` for detailed deployment and acceptance checklist.
