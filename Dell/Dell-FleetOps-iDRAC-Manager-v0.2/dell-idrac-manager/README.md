# Dell FleetOps iDRAC Manager v0.2

Self-hosted web UI for centralized Dell PowerEdge iDRAC inventory, firmware compliance and controlled Redfish firmware updates.

## v0.2 features
- Central iDRAC inventory and encrypted stored credentials
- Redfish hardware + firmware inventory
- Approved firmware baselines per PowerEdge model/component
- Compliance scans: current vs approved target
- Server groups
- Preflight health/power checks
- Rolling multi-server update batches with stop-on-failure
- Redfish TaskService URI capture/status support
- Maintenance-window data model/API for policy integration
- Job/batch history
- Docker deployment
- Simulation mode enabled by default

## Start
```bash
cp .env.example .env
# Replace SECRET_KEY before storing real credentials.
docker compose up -d --build
```
Open `http://SERVER:8080`.

## Safe evaluation
Leave `SIMULATION_MODE=true`. Add test servers in the UI; Redfish calls are simulated. Define an approved baseline, run a compliance scan, select servers, then test a rolling update.

## Production checklist
1. Set a long random `SECRET_KEY` and protect `.env`.
2. Set `SIMULATION_MODE=false` only after validation.
3. Prefer `VERIFY_TLS=true` with trusted iDRAC certificates.
4. Put FleetOps behind your enterprise reverse proxy/SSO and restrict it to the management network/VPN.
5. Use a dedicated least-privilege iDRAC service account where your update workflow permits it.
6. Host approved Dell DUP/firmware packages on a controlled HTTPS repository reachable by iDRAC.
7. Test baselines on non-production hardware before approving fleet rollout.
8. Back up the persistent `idrac_data` Docker volume.

## Core API
- `GET/POST /api/servers`
- `POST /api/servers/{id}/scan`
- `GET /api/servers/{id}/firmware`
- `POST /api/servers/{id}/compliance`
- `GET /api/servers/{id}/preflight`
- `GET/POST /api/baselines`
- `GET/POST /api/groups`
- `POST /api/rolling-update`
- `GET/POST /api/windows`
- `GET /api/jobs`

## Firmware baseline workflow
FleetOps intentionally separates *discovery* from *approval*. Import/enter a target version and a controlled HTTPS firmware URI, scan compliance, and then launch a rolling update. It does not automatically install an arbitrary newest package.

## Important
Firmware behavior varies by PowerEdge generation, iDRAC/Lifecycle Controller release and package type. Validate the Redfish SimpleUpdate flow against your exact Dell models before production rollout. Some updates may stage until a reboot or require a Dell job queue/reboot workflow; extend the worker for those model-specific cases.
