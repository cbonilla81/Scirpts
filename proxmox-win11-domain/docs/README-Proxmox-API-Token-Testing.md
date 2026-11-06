# Proxmox VE 9 API Token Testing Guide

Test a Proxmox API token from a Windows PowerShell workstation **before** configuring Terraform environment variables. This guide targets the `bpg/proxmox` Terraform provider and a Windows 11 VM deployment from a Proxmox template.

> **Security:** Never commit token secrets to Git, paste them into logs, or embed them in Terraform configuration. The examples prompt for the secret interactively.

## Prerequisites

- Proxmox VE 9 management hostname or IP address, reachable over HTTPS on TCP port **8006**.
- API token ID, for example `terraform@pve!deployment`, and its secret.
- Windows PowerShell 5.1 or PowerShell 7+. **PowerShell 7 is recommended** for the optional `-SkipCertificateCheck` lab-only switch.
- A Proxmox account/token with permissions to view the intended nodes and VM template.

## 1. Test the token (no environment variables required)

Save the following as `Test-ProxmoxApiToken.ps1` or paste it into PowerShell. Update `$ProxmoxServer`, `$TokenID`, `$NodeName`, and `$TemplateVMID`.

```powershell
$ProxmoxServer = '192.168.1.100'
$TokenID       = 'terraform@pve!deployment'
$NodeName      = 'pve1'
$TemplateVMID  = 9000

# Set to $true ONLY for a lab with a self-signed certificate and PowerShell 7+.
$LabSkipCertificateCheck = $false

$SecureToken = Read-Host 'Enter Proxmox API token secret' -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureToken)
try {
    $TokenSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

$Headers = @{ Authorization = "PVEAPIToken=$TokenID=$TokenSecret" }
$BaseUri = "https://${ProxmoxServer}:8006/api2/json"
$RequestOptions = @{ Headers = $Headers; Method = 'Get'; ErrorAction = 'Stop' }
if ($LabSkipCertificateCheck) {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw '-SkipCertificateCheck requires PowerShell 7 or later.'
    }
    $RequestOptions['SkipCertificateCheck'] = $true
}

try {
    Write-Host 'Testing node visibility...' -ForegroundColor Cyan
    $nodes = Invoke-RestMethod -Uri "$BaseUri/nodes" @RequestOptions
    Write-Host 'SUCCESS: Proxmox API request succeeded.' -ForegroundColor Green
    $nodes.data | Select-Object node, status, cpu, maxmem | Format-Table -AutoSize

    Write-Host "Checking template $TemplateVMID on $NodeName..." -ForegroundColor Cyan
    $template = Invoke-RestMethod -Uri "$BaseUri/nodes/$NodeName/qemu/$TemplateVMID/config" @RequestOptions
    Write-Host 'SUCCESS: Template configuration is readable.' -ForegroundColor Green
    $template.data | Select-Object name, template, cores, memory, bios, machine | Format-List
}
catch {
    Write-Host 'FAILED: Proxmox API request failed.' -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host 'Review the troubleshooting table below. Do not share your token secret.'
}
finally {
    Remove-Variable TokenSecret, SecureToken, Headers, RequestOptions -ErrorAction SilentlyContinue
}
```

Run the script:

```powershell
.\Test-ProxmoxApiToken.ps1
```

**Note:** The script keeps the plaintext secret in process memory temporarily to create the HTTP Authorization header. It does not write the secret to disk or set any environment variable.

## 2. Example successful output

```text
Testing node visibility...
SUCCESS: Proxmox API request succeeded.

node    status   cpu    maxmem
----    ------   ---    ------
pve1    online   0.12   68719476736
pve2    online   0.08   68719476736

Checking template 9000 on pve1...
SUCCESS: Template configuration is readable.
```

These values are **illustrative**, not a real test result. If the template check fails but node listing succeeds, authentication may work while template permissions, VM ID, or node location are incorrect.

## 3. Troubleshooting

| Symptom | Likely cause | Next check |
| --- | --- | --- |
| `401 Unauthorized` | Invalid token ID/secret, expired token, or disabled user | Verify the exact `user@realm!tokenid` format and token validity in Proxmox |
| `403 Forbidden` | Missing user/token privileges | Check Datacenter → Permissions and any privilege-separated token ACLs |
| Connection refused or timeout | Port 8006 unreachable | Check DNS, firewall, routing, and `pveproxy` service |
| TLS/certificate error | Certificate not trusted or hostname mismatch | Install a trusted certificate or use the PowerShell 7 lab-only bypass |
| Node list succeeds; template fails | Wrong node/VM ID or insufficient VM privileges | Confirm template VM ID, node name, and VM.Audit access |

## 4. After successful testing: configure Terraform

For the **current PowerShell session only**, set the BPG provider variables:

```powershell
$env:PROXMOX_VE_ENDPOINT = 'https://192.168.1.100:8006/'
$env:PROXMOX_VE_API_TOKEN = 'terraform@pve!deployment=YOUR_TOKEN_SECRET'
```

For a safer interactive token entry without putting the secret in command history, prompt and compose the environment variable in memory:

```powershell
$tokenId = 'terraform@pve!deployment'
$secure = Read-Host 'Enter API token secret' -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $secret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    $env:PROXMOX_VE_API_TOKEN = "$tokenId=$secret"
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    Remove-Variable secret, secure -ErrorAction SilentlyContinue
}
```

Verify presence **without printing the secret**:

```powershell
if ($env:PROXMOX_VE_API_TOKEN) { 'Token configured' } else { 'Token missing' }
```

Then run Terraform from your project directory:

```powershell
terraform init
terraform validate
terraform plan
# Only after reviewing the plan:
terraform apply
```

The API tests prove that the token can read the requested resources. They **do not** prove that it can clone a VM, allocate storage, create TPM state, or join Windows to Active Directory. Test deployment with one VM before scaling to ten.

## 5. Cleanup

Remove the token from the current PowerShell process when finished:

```powershell
Remove-Item Env:PROXMOX_VE_API_TOKEN -ErrorAction SilentlyContinue
```

Avoid persisting token secrets in user-level environment variables on shared machines. Use an approved secrets manager or CI secret store for repeatable automation.

## References

- [Proxmox VE API documentation](https://pve.proxmox.com/pve-docs/api-viewer/)
- [Proxmox VE user management and API tokens](https://pve.proxmox.com/pve-docs/pveum.1.html)
- [BPG Proxmox Terraform provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Microsoft Invoke-RestMethod](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/invoke-restmethod)
