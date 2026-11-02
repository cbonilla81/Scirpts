# Operations runbook

1. Install PowerCLI on an administrative workstation with a trusted vCenter certificate.
2. Connect to vCenter with an inventory-read account. Run `-Mode Assess` (default).
3. Open the HTML report. Filter by cluster, status, guest OS, and power state.
4. Check whether Linux systems are guest-managed and whether VMs are powered off before treating them as failures.
5. For Windows VMs, check `Get-Service VMTools` inside the guest when status is Not Running.
6. For Linux VMs, check `systemctl status vmtoolsd` and OS package versions.
7. For approved Windows upgrades, prepare an exact-name approval file, run a dry-run, then execute within a maintenance window.
8. Re-run the assessment and compare reports; investigate failures individually.

## Operational safeguards

- Assessment requires no guest credentials.
- Upgrade requires both `-Mode Upgrade` and `-Execute` plus an approval file.
- Upgrades only target powered-on Windows VMs with an Outdated assessment; guest-managed Linux excluded.
- Avoid targeting critical infrastructure until maintenance is coordinated.
- Protect generated reports because they expose hostnames and guest OS inventory.
- Do not treat API success as confirmed installation success.
