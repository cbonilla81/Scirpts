# Proxmox API setup

From a Proxmox node shell, for a lab proof of concept:

```bash
pveum user add terraform@pve --comment 'Terraform automation'
pveum aclmod / -user terraform@pve -role PVEAdmin
pveum user token add terraform@pve deployment --privsep 0
```

This is broad LAB access only. For production, create a custom role with the minimal privileges required to clone the template, allocate VMs, configure and power them on; scope it to the relevant VM pool, storage, and node resources. Use privilege-separated API tokens with explicit ACLs. Never commit the returned token secret.

On a Windows controller:

```powershell
.\scripts\Set-ProxmoxEnvironment.ps1 -Endpoint 'https://pve1.example.internal:8006/'
```

Prefer a trusted Proxmox TLS certificate. If you intentionally test with a self-signed cert, `PROXMOX_VE_INSECURE=true` disables verification and should never be your production default.

No SSH access is required for the basic cloning resources in this package.
