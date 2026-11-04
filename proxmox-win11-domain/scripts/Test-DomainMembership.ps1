param([Parameter(Mandatory)][string]$CsvPath,[Parameter(Mandatory)][string]$DomainName)
$rows = Import-Csv $CsvPath
foreach ($row in $rows) {
  if (-not $row.IPAddress) { continue }
  try {
    $dns = Resolve-DnsName -Name $row.Name -ErrorAction Stop
    Write-Host "$($row.Name): DNS resolved; verify domain join using Get-ADComputer and/or an interactive guest logon."
  } catch { Write-Warning "$($row.Name): DNS resolution not yet available" }
}
Write-Host "On a domain-joined admin workstation with RSAT: Get-ADComputer -Filter 'Name -like \"WIN11-*\"'"
