param(
  [string]$TerraformDirectory = (Join-Path $PSScriptRoot '..\terraform'),
  [string]$OutputCsv = (Join-Path $PSScriptRoot 'vm-inventory.csv')
)
$ErrorActionPreference = 'Stop'
Push-Location $TerraformDirectory
try {
  $raw = terraform output -json vm_inventory
  if ($LASTEXITCODE -ne 0) { throw 'terraform output failed' }
  $inventory = $raw | ConvertFrom-Json
  $rows = foreach ($property in $inventory.PSObject.Properties) {
    [pscustomobject]@{ Name = $property.Name; VMID = $property.Value.vm_id; Node = $property.Value.node; IPAddress = '' }
  }
  $rows | Sort-Object Name | Export-Csv -Path $OutputCsv -NoTypeInformation
  Write-Host "Inventory saved to $OutputCsv. Populate IPAddress from DHCP leases or QEMU Guest Agent before domain joining."
} finally { Pop-Location }
