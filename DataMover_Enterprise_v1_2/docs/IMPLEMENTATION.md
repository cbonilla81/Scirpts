# Windows Server implementation and acceptance guide

## 1. Prerequisites

- Windows Server 2019/2022/2025 migration host with Python 3.11+ and built-in Robocopy.
- Dedicated domain service identity, approved source/destination SMB shares, change ticket, backup/rollback owner.
- Confirm network connectivity and disk space; for 10–100 TB, benchmark throughput, plan change windows and run small pilots first.
- Ensure NTFS ACLs, owner and SACL requirements are understood. Share permissions, alternate data streams, open files, EFS, reparse points, and path-length behavior need separate acceptance testing.

## 2. Verify Robocopy and SMB permissions

```powershell
Get-Command robocopy.exe
where.exe robocopy
robocopy /?
whoami /all
Test-Path '\\FS01\Shares\Pilot'
Test-Path '\\FS02\Shares\Pilot'
```

Execute those checks as the same domain identity that will run the application. A test under an elevated administrator session does not prove the worker account has access.

## 3. Install

Extract the ZIP to `C:\DataMover` and open PowerShell there:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
notepad .env
.\scripts\Start-DataMover.ps1
```

Set a random `DATAMOVER_SESSION_SECRET` of at least 32 characters and initial approved source/destination roots. On first startup, `DATAMOVER_ALLOWED_ROOTS` seeds the roots persisted in the application database. Signed-in users can add and remove roots from **Manage approved roots** in the web UI; these changes persist without editing `.env` or restarting. Any signed-in user can manage roots, so adding a root expands the paths available to every user. At least one root must remain, and a root needed by an active migration cannot be removed. Removing a root prevents affected saved jobs from starting again. Keep the environment file readable only by administrators and the service identity. The app starts on localhost port 8080. Avoid public binding. Run one process only. For long-running production services, use an approved Windows service manager with automatic restart and a dedicated domain account; verify service environment variables and profile access.

### Configure sign-in

- On first startup, retrieve the one-time setup code from the service log, or set a protected `DATAMOVER_SETUP_TOKEN` (at least 24 characters) before starting. Visit `/login` on the management host and use it once to create the first local administrator.
- For Active Directory, configure `DATAMOVER_AD_LDAP_URL=ldap://<directory-host>` and optionally `DATAMOVER_AD_CA_CERT`. The app uses LDAP StartTLS, certificate validation and user principal name binds; do not use plain LDAP binds.
- For Microsoft Entra ID, configure the client ID, secret, HTTPS callback URI (`https://<host>/auth/entra/callback`) and comma-separated allowed tenant UUIDs. Register the exact callback URI in the Entra app registration.
- Local administrators can create and disable local accounts in the dashboard. Local, AD and Entra identities are operators; account administration is restricted to local administrators.
- If exposed through HTTPS, set `DATAMOVER_COOKIE_SECURE=true` and verify the proxy preserves the external host and scheme. The application uses signed eight-hour sessions and CSRF protection for state-changing API requests.

## 4. Dry-Run acceptance

Create a small pilot job. Click **Dry-Run**. Verify that the job returns `success`, the run's exit code is under 8, and `state\logs` contains a Robocopy log. Review the listed changes, extras, mismatches, inaccessible paths, and permissions. `/L` does not prove write access or successful ACL application.

## 5. Baseline and incremental sync

Click **Start Sync**. Inspect run logs and independently compare source/destination file counts, sizes, timestamps, selected hashes and NTFS ACLs. Schedule a cron expression such as `0 1 * * *`. Changes to permissions on unchanged files may need `/SECFIX`; final sync includes it. Note: `/E` does not remove destination-only files.

## 6. Controlled cutover

Stop application writes and confirm source freeze externally. Run fresh Dry-Run, record validation evidence, attest freeze and approve final sync. Click **Final Sync**. Confirm successful completion, independently validate again, and attest final verification. Make DFS/DNS/share mapping changes manually under change control, then record handoff. Rollback plan is available from the dashboard.

## 7. Pilot acceptance checklist

- [ ] API only reachable from approved management access path
- [ ] Session secret, provider credentials and `.env` ACLs protected; dedicated service identity used
- [ ] First administrator created using the one-time setup code, then setup code invalidated
- [ ] Enabled sign-in methods tested; AD StartTLS certificate and Entra tenant allowlist verified
- [ ] HTTPS reverse proxy and secure session cookie configured for remote access
- [ ] Robocopy located on worker PATH and executed under service identity
- [ ] Approved-root enforcement tested
- [ ] Dry-Run does not write or delete data
- [ ] Initial copy succeeds on a representative sample
- [ ] DACL, SACL, owner, inheritance, and effective access verified independently
- [ ] Destination-only files remain untouched
- [ ] Scheduler fires and does not overlap a job
- [ ] Final sync blocked before approvals
- [ ] Handoff disables future schedules
- [ ] Rollback plan reviewed and source retained
- [ ] Backups, logs, alerting, service recovery, and storage capacity validated

## 8. Troubleshooting

- **401**: Invalid credentials or expired session; verify provider configuration and sign in again.
- **403**: Missing/invalid CSRF token or Entra tenant not on the configured allowlist.
- **429**: Too many failed sign-in attempts from the client address; wait ten minutes.
- **Setup unavailable**: Check whether an initial administrator already exists and retrieve the one-time setup code from the service log.
- **422**: UNC paths outside approved roots, unsafe characters, or invalid cron expression.
- **409**: Job running, cutover prerequisite missing, source frozen, or job handed off.
- **Exit >=8**: Inspect per-run Robocopy log and source/destination SMB permissions.
- **Access denied**: Check worker identity, share permissions, NTFS DACL, backup/restore/security privileges, and remote access restrictions.
- **No jobs scheduled**: Confirm one API process, valid cron and time zone, and the application is running during the scheduled window.

## 9. Limits for 10–100 TB

This pilot does not offer reliable byte progress or ETA, distributed durable queues, automatic integrity/ACL diffs, long-path edge-case handling, or unattended enterprise cutover. Benchmark large directories and high file counts before scaling. Logs can grow substantially and need managed retention. Add a service supervisor, central monitoring, security review, and restore tests before production.
