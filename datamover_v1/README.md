# DataMover Enterprise v1

A deployable, single-controller migration and replication console for Windows and Linux. Includes an HTML dashboard, REST API, persistent jobs and events, scheduled copies, validation, and operator-gated final cutover.

## Presentation demo
Open `app/static/demo-login.html` directly in a browser, or visit `/static/demo-login.html` while the app is running, to start the presentation demo. The sign-in accepts any valid email and non-empty password (or use **Continue as demo operator**) and opens `app/static/demo.html`; **Sign out** on the dashboard returns to the login screen. The RS&H logo appears on both demo screens and is served from the project-root `RS&H_Logo.png`. This is a visual mock only: it does not authenticate users or contact the DataMover API. The dashboard supports job selection, status filtering, and adding sample jobs; it does not start transfers. Its progress values and activity are illustrative only. Use `/` for the live, API-connected dashboard.

## Production-readiness roadmap
Treat production readiness as a set of security, reliability, and recovery requirements, not just a deployment choice. The following capabilities are recommendations and are not all implemented in v1:

1. **Define the operating requirements:** Set expected data volumes, supported providers, concurrent-job needs, uptime and recovery objectives, and whether Windows ACLs must be preserved. Establish measurable acceptance criteria before migration.
2. **Secure access and credentials:** Add Entra ID/SSO and role-based access; require HTTPS behind a protected proxy or private network; use a secret manager or managed identities for provider credentials. Keep the current API off the public Internet.
3. **Make jobs durable and recoverable:** Replace SQLite with a production database such as PostgreSQL for multi-user or higher-availability deployments. Separate the API from workers and use a durable queue, job leases/heartbeats, bounded retries, and explicit handling of interrupted jobs. Add pause/cancel controls if required by operators.
4. **Strengthen transfer and cutover safeguards:** Test each provider's transfer and metadata behavior. Make validation repeatable, keep cutover operator-approved, and document and test rollback procedures. Preserve the non-deleting default unless a separately reviewed requirement changes it.
5. **Add operational visibility and recovery:** Centralize logs, metrics, and alerts; monitor failed or stalled jobs and storage capacity; back up the database and configuration; and regularly test restore and disaster-recovery procedures.
6. **Prove the design before rollout:** Pilot representative data volumes, file sizes, permissions, and providers. Test process/worker restarts, network interruptions, duplicate requests, and recovery from partial runs. Do not move critical or 10–100 TB workloads until representative-scale testing meets the agreed acceptance criteria.

Docker Compose on Linux is a reasonable starting point for a controlled pilot or single-controller deployment, but does not provide high availability by itself. For Windows shares where Robocopy or NTFS metadata preservation is required, use a Windows worker with the necessary permissions, even if the control plane runs elsewhere. For 10–100 TB environments, distributed workers and accurate transfer monitoring are especially important to validate at representative scale.

## What works
- `rclone copy` transfers supported local, SFTP, SMB-mounted, S3, Azure Blob, and other configured rclone remotes without deleting destination-only files.
- `rclone check --one-way` compares source objects against destination (size/hash where backend supports it); this is not a universal bit-for-bit proof and cloud backends may lack matching hashes.
- Windows `robocopy /E /COPYALL /DCOPY:DAT /ZB /MT:16` supports NTFS metadata on compatible Windows SMB paths when the worker identity has necessary rights.
- APScheduler cron jobs, SQLite event history, run/validate/approve/final-sync/handoff APIs.
- Browser dashboard refreshes every 10 seconds; worker events expose rclone stats and errors. v1 does **not** compute an accurate percentage or ETA; file/byte counters are reserved for future releases.
- Cutover approval requires successful validation and operator attestation that the source is write-frozen. Final sync is non-deleting; handoff is an operator-confirmed external step.

## Important limits for production
This is a functional v1 foundation, **not a certified production migration appliance**. Before moving 10–100 TB, test on representative data and ACLs, validate storage provider semantics, create backups, and test recovery. Single-process SQLite and in-process threads are not HA; unexpected process termination interrupts transfers. The worker does not resume a partial command automatically, but subsequent rclone copy runs re-evaluate the delta. Jobs cannot be paused or cancelled from the UI. Cron schedules are in `DATAMOVER_TZ`. Robocopy verification via `/L` checks differences in its listing, not cryptographic integrity. No automatic source freeze, DFS/DNS switch, rollback, alerting, RBAC, SSO, or tamper-evident audit log.

**Security:** The API key is a single shared operator credential, not RBAC. The dashboard holds it only in JavaScript memory; protect the UI with HTTPS via an authenticated reverse proxy/VPN and do not expose the API directly to the Internet. Secrets for cloud storage should be injected via protected rclone config/environment/managed identities, never embedded in job paths. Limit allowed roots and IAM to least privilege. No delete operation is offered. Do not expose the local SQLite state or log files to untrusted users. Consider separate worker identities and isolated controllers for tenants.

## Linux Docker deployment
1. Install Docker Engine and Compose plugin; create `state/` and `rclone/` directories, owned by UID 10001 (e.g. `sudo chown -R 10001:10001 state`).
2. Copy `.env.example` to `.env`, generate a random secret with `python3 -c 'import secrets;print(secrets.token_urlsafe(48))'` and set `DATAMOVER_API_KEY`.
3. Set `DATAMOVER_ALLOWED_ROOTS` to **only** your approved prefixes. Example: `onprem:;azure:my-container;aws:my-bucket`. Do not use generic `s3:` or `azure:` prefixes in a multi-tenant environment.
4. Create `rclone/rclone.conf` with properly configured source/destination remotes. For the container user, rclone looks for `/opt/datamover/.config/rclone/rclone.conf`. Restrict permissions. Prefer workload identity and short-lived tokens.
5. For local paths, add bind mounts to `docker-compose.yml` and allowlist the paths as visible **inside** the container.
6. Run `docker compose up -d --build`.
7. Access `http://127.0.0.1:8080` from the host or expose behind a properly secured HTTPS reverse proxy. Use a VPN/SSH tunnel for remote access.
8. Enter the API key to unlock the dashboard. Create a small test job, run sync, then validate.

**Azure Blob example:** configure an rclone remote called `azure` with `type = azureblob` and the appropriate managed identity or credential. Source might be `onprem:files` (another configured remote) and destination `azure:my-container/files`. **AWS S3 example:** use an `aws` remote of `type = s3` with IAM role credentials and destination `aws:my-bucket/files`. Rclone configuration differs by provider and authentication method; verify with `rclone lsd remote:` and `rclone ls remote:bucket/prefix` first.

## Windows deployment
1. Install Python 3.12 and either `rclone.exe` or built-in `robocopy.exe`. Put the selected engine on PATH.
2. Open PowerShell in the project root. Set environment variables for the session:
   ```powershell
   $env:DATAMOVER_API_KEY = (python -c "import secrets;print(secrets.token_urlsafe(48))")
   $env:DATAMOVER_ALLOWED_ROOTS = '\\FS01\Shares;\\FS02\Shares;azure:my-container'
   $env:DATAMOVER_TZ = 'America/New_York'
   ```
3. Run `./scripts/start-windows.ps1`. Open `http://127.0.0.1:8080` on the same host.
4. For Robocopy, use UNC paths and a service identity with read permissions, destination write permissions, and backup/restore/security privileges as appropriate. Test ACLs, SACLs, ownership, long paths, reparse points, and open files on a pilot share.
5. For remote access, put the app behind a hardened TLS reverse proxy. For an unattended service, use a managed Windows service wrapper and protected service account; do not depend on an interactive PowerShell session.

## Suggested 10–100 TB rollout
- Discovery: inventory file counts, size distribution, ACLs, path lengths, file locks, cloud target limits, and network bandwidth.
- Pilot: 100 GB–1 TB of representative data and permission scenarios. Measure throughput, error rate, provider request charges and recovery.
- Baseline: run initial non-deleting copy, then scheduled delta copies.
- Validation: run `rclone check` or Robocopy listing comparison; supplement with independent ACL and application access tests.
- Cutover: freeze source writes externally, approve with change ticket, run final copy, verify final delta and permissions manually, then change client paths externally and confirm handoff.
- Rollback: retain the source unchanged and read-only for a defined period. Test reverse procedures **before** cutover; there is no automated rollback in v1.

## API endpoints
All `/api/*` routes require `X-API-Key` except `/` and static assets. `GET /api/health`, `GET /api/jobs`, `POST /api/jobs`, `GET /api/jobs/{id}`, `GET /api/jobs/{id}/events`, `POST /api/jobs/{id}/sync`, `POST /api/jobs/{id}/validate`, `POST /api/jobs/{id}/approve`, `POST /api/jobs/{id}/final-sync`, `POST /api/jobs/{id}/handoff`.

Example job JSON:
```json
{"name":"Azure finance migration","source":"onprem:finance","destination":"azure:my-container/finance","engine":"rclone","cron":"0 */4 * * *"}
```

## Testing
```bash
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
```

## Operations
- Backup the `state/` folder (SQLite DB and job logs), `.env`, and protected rclone configuration separately. Never commit credentials.
- Review logs under `state/job-<id>.log`. Events show only selected output lines; log output may contain filenames and sensitive paths.
- Run one API worker only (`--workers 1`). Running multiple processes against this controller is unsupported.
- On restart, previously running jobs are marked `interrupted`; inspect logs and re-run them deliberately.
- Docker binds to localhost only by default. An HTTPS reverse proxy is required for secure remote access.

## License
MIT. See LICENSE.

## v1.1: Dry run, final verification and rollback planning

Before a real migration, select a job and click **Dry run**. For rclone this invokes
`rclone copy SOURCE DEST --dry-run`; for Robocopy this invokes `/L` (list only).
Neither mode intentionally copies or deletes files. However, cloud providers can
still incur API listing charges, and provider-specific read operations may occur.
Inspect the job's event history and full log file under `state/job-ID.log`.

A successful dry run is required before cutover approval, together with a successful
validation. Dry runs **do not prove** that writes, permission translation, capacity,
or cutover will succeed. Rclone dry runs are planning estimates; they are not a
complete ACL audit. Validation with rclone check requires a compatible provider
and may not compare all metadata. Robocopy `/L` return codes are only a coarse
preflight and do not prove equivalent ACLs; use independent ACL comparison for
production acceptance.

After the approved final sync, select **Verify final sync**. Handoff is blocked
until final verification succeeds. **Rollback plan** displays a manual advisory
checklist; no automatic DNS/DFS or rollback action is performed.

**Current limitations:** No Entra ID/RBAC, notification integration, distributed
worker coordination, resumable per-file checkpoints, verified byte-accurate ETAs,
or automatic ACL translation across cloud providers. These require dedicated
integration and testing before enterprise production use. A single worker process
and scheduler instance must be deployed; do not scale the API horizontally.
