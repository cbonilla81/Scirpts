# VMware Tools Manager v1.0

A PowerCLI-based, **read-only-by-default** vCenter VMware Tools assessment tool. Produces a light-themed standalone HTML dashboard, full CSV inventory, search/status filters, distribution chart, and client-side CSV export. Includes a tightly gated Windows VMware Tools upgrade workflow.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7 (PowerCLI-compatible release)
- VMware PowerCLI: `Install-Module VMware.PowerCLI -Scope CurrentUser`
- Network connectivity to vCenter; an account with read-only inventory privileges for assessment
- For upgrades: appropriate VM guest operations/Tools upgrade privileges, approved maintenance window, and VM backups

**Security:** The tool uses PowerCLI's standard `Connect-VIServer` login and does not store credentials. Do not disable certificate verification globally; configure trusted vCenter certificates. Run in an isolated administrator shell with minimum necessary permissions.

## Quick start

```powershell
cd .\vmware-tools-manager
.\scripts\Invoke-VMToolsManager.ps1 -Server 'vcsa.example.org' -OutputDirectory '.\reports'
```

Optional filters:

```powershell
.\scripts\Invoke-VMToolsManager.ps1 -Server 'vcsa.example.org' -Cluster 'Production' -VMName 'APP-*'
```

Open `reports/dashboard-YYYYMMDD-HHMMSS.html` in a browser. No server or Internet access is required to view it.

## Upgrade workflow (explicit opt-in)

Only powered-on **Windows** VMs with running Tools classified as **Outdated** are eligible. No missing-Tools installation, Linux package upgrade, guest service start, VM reboot, or guest credential operation is performed.

1. Inspect the report and identify approved VM names.
2. Put one **exact** VM name per line in `config/approved-vms.txt`; lines beginning with `#` are ignored.
3. Dry-run:

```powershell
.\scripts\Invoke-VMToolsManager.ps1 -Server 'vcsa.example.org' -Mode Upgrade -ApprovedVMsFile '.\config\approved-vms.txt'
```

4. Review `actions-*.csv` and arrange a maintenance window.
5. Execute explicitly:

```powershell
.\scripts\Invoke-VMToolsManager.ps1 -Server 'vcsa.example.org' -Mode Upgrade -ApprovedVMsFile '.\config\approved-vms.txt' -Execute
```

**Caution:** `Update-Tools -NoReboot` is not a guarantee against reboot; follow VMware compatibility guidance. Upgrades are requested sequentially (not parallel). The action log records API request outcomes, **not verified completion**. Re-run assessment to verify. Multiple VMs with the same name in scope can match one approval line; narrow with `-Cluster` or `-VMName` before executing.

## Categories

- **Healthy**: powered on, agent running, version current or supported-new.
- **Outdated**: powered on, agent running, version needs upgrade or supported-old/too-old.
- **Not Installed**: vCenter reports Tools not installed.
- **Not Running / Unknown**: powered on but agent not reporting running.
- **Guest Managed**: Linux open-vm-tools/OSP agent running and version marked unmanaged.
- **Powered Off**: live agent state unavailable.
- **Review**: ambiguous or unrecognized status; verify manually.

Status names reflect vCenter API values and can differ by vSphere/Tools version. A healthy Linux open-vm-tools deployment may show guest-managed rather than current. Powered-off VM version details may be stale.

## Troubleshooting

- `Connect-VIServer` errors: check DNS, TCP 443, SSO credentials, TLS trust and permissions.
- Missing VM data: confirm vCenter inventory visibility and `VirtualMachine.Guest` read privileges.
- Windows guest shows `Not Running`: inspect `VMTools` service and Windows Event Logs.
- Linux guest shows `Not Running`: inspect `systemctl status vmtoolsd`, installed `open-vm-tools`, and journal logs.
- `Not Installed`: install from the vSphere client (Windows), or via OS package manager (Linux).
- VMs powered off: power on only according to your operational policy, then rescan.

## Package contents

- `scripts/Invoke-VMToolsManager.ps1` – discovery, classification, HTML/CSV report, gated upgrade
- `config/approved-vms.txt` – approval file example (commented out)
- `samples/sample-inventory.csv` – example data, not actual infrastructure
- `tests/README.md` – validation checklist
- `docs/OPERATIONS.md` – rollout guidance

## Limitations

The HTML dashboard is an **offline report**, not a live server or remote-control console. It cannot itself execute remediations. This release intentionally does not perform mass installation of missing Tools, restart guest services, or automatically reboot VMs. Run the script again to refresh results.
