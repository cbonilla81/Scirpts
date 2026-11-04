# Run in the same PowerShell session used for terraform commands.
param([Parameter(Mandatory)][string]$Endpoint)
$env:PROXMOX_VE_ENDPOINT = $Endpoint
$env:PROXMOX_VE_API_TOKEN = Read-Host 'Enter Proxmox API token (terraform@pve!deployment=SECRET)' -MaskInput
# Prefer a CA-trusted TLS certificate. Do not disable verification in production.
Write-Host 'Proxmox endpoint and API token set for this process.'
