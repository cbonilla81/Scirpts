# Proxmox VE 9 — Terraform Windows 11 AD Deployment

Deploy 10 Windows 11 VMs by full-cloning a sysprepped template, then customize names and join Active Directory in a separate, explicit PowerShell stage.

**Scope:** Terraform provisions VMs; it does **not** automatically complete Windows OOBE, set up WinRM, or domain-join machines during `terraform apply`.

## Directory structure

- `terraform/` — Terraform provider, clone resources, variables, outputs, example tfvars
- `scripts/Set-ProxmoxEnvironment.ps1` — process-scoped Proxmox API environment variables
- `scripts/Export-VMInventory.ps1` — inventory CSV for domain join
- `scripts/Join-WindowsDomain.ps1` — interactive-credential, WinRM HTTPS join workflow
- `scripts/Test-DomainMembership.ps1` — DNS smoke test, not authoritative domain join proof
- `docs/TEMPLATE.md` — golden-image prerequisites
- `docs/API-ACCESS.md` — API token and least-privilege guidance

## 1. Prerequisites

- Proxmox VE 9, a tested Windows 11 template, working QEMU Guest Agent, sufficient storage, and available VM IDs 2200–2209.
- Windows workstation with Terraform >=1.6 and PowerShell, network access to TCP 8006 on Proxmox.
- DHCP reservations or lease lookup for the cloned VM IPs, working DNS and AD access.
- Windows guests must complete OOBE and expose **trusted WinRM HTTPS** on port 5986 before the optional domain join stage.
- Valid Windows 11 licenses; ensure organizational licensing allows cloning.

Read `docs/TEMPLATE.md` before proceeding.

## 2. Set up Proxmox API access

Follow `docs/API-ACCESS.md`. Set `PROXMOX_VE_ENDPOINT` and `PROXMOX_VE_API_TOKEN` in your terminal environment. Use trusted TLS certificates.

## 3. Configure and deploy

```powershell
cd .\terraform
Copy-Item .\terraform.tfvars.example .\terraform.tfvars
# Edit node_name, template_node_name, template_vm_id, and other values.
terraform init
terraform validate
terraform plan -out=deployment.tfplan
terraform apply deployment.tfplan
terraform output vm_inventory
```

**Note:** Provider version constraint is pinned to `~> 0.116.0` as a starting point. If that version is unavailable or newer breaking changes exist, update it after reviewing the provider release notes and commit your generated lockfile to version control (the sample `.gitignore` currently excludes it for portability).

## 4. Export inventory and populate IPs

```powershell
cd ..
.\scripts\Export-VMInventory.ps1
```

Edit `scripts/vm-inventory.csv` and fill `IPAddress` for every VM. Use DHCP leases or Proxmox guest-agent data. Prefer DNS names matching WinRM certificate SANs if your security setup uses DNS-based certificates; the script currently uses the `IPAddress` column as the remote endpoint.

## 5. Join the AD domain

First verify guest first-boot completion, trusted WinRM HTTPS, guest firewall rules, domain DNS, time sync, and local admin account access. Run from a Windows controller with access to the guests:

```powershell
.\scripts\Join-WindowsDomain.ps1 -CsvPath .\scripts\vm-inventory.csv -DomainName 'corp.example.com' -OUPath 'OU=Workstations,DC=corp,DC=example,DC=com' -WhatIf
.\scripts\Join-WindowsDomain.ps1 -CsvPath .\scripts\vm-inventory.csv -DomainName 'corp.example.com' -OUPath 'OU=Workstations,DC=corp,DC=example,DC=com'
```

The script prompts for local and AD credentials. It renames and joins the domain with `Add-Computer`, then reboots. Each machine is processed sequentially. Confirm each result using Active Directory tools and `Get-CimInstance Win32_ComputerSystem` after reboot. The DNS-only helper is not authoritative.

## 6. Scale or retire

Change `vm_count` in `terraform.tfvars`, then run `terraform plan` and `terraform apply`. Increasing creates additional clones. **Decreasing destroys the highest-numbered managed VMs.** Back up state and VMs, and inspect the plan carefully. `terraform destroy` removes managed VMs and their disks.

## Security and limitations

- Never commit Terraform state, secrets, or CSV files containing sensitive infrastructure details.
- This is a template-based deployment, not an unattended Windows installation. Windows first-boot setup is a required external prerequisite.
- WinRM HTTPS requires certificates trusted by the controller. Certificate-validation bypass is intentionally not implemented.
- Ensure local credentials remain valid after Sysprep, and never reuse a shared privileged local password in production; use a managed bootstrap mechanism and Windows LAPS after domain join.
- VM names and IDs must be unused. The project assumes a single target Proxmox node for all 10 VMs.
- The script is not idempotent for already domain-joined guests; review status before rerunning.
- Test one VM first (`vm_count = 1`), then scale to 10.

## References

- https://bpg.sh/docs/
- https://bpg.sh/docs/guides/clone-vm/
- https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep--generalize--a-windows-installation
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/add-computer
