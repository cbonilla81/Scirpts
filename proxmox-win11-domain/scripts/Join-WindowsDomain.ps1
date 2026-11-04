# Requires Windows PowerShell 5.1 or PowerShell 7 on Windows and WinRM over HTTPS
# with trusted guest certificates. Run only on your authorized Windows machines.
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
  [Parameter(Mandatory)][string]$CsvPath,
  [Parameter(Mandatory)][string]$DomainName,
  [string]$OUPath,
  [switch]$SkipCertificateValidation
)
$ErrorActionPreference = 'Stop'
if ($SkipCertificateValidation) { throw 'Certificate validation bypass is intentionally unsupported. Install trusted WinRM HTTPS certificates instead.' }
$rows = Import-Csv $CsvPath
if (-not $rows) { throw 'Inventory CSV is empty.' }
$localCred = Get-Credential -Message 'Enter the local administrator credentials on the sysprepped Windows 11 clones'
$domainCred = Get-Credential -Message "Enter AD credentials authorized to join machines to $DomainName"
foreach ($row in $rows) {
  $name = $row.Name
  $ip = $row.IPAddress
  if ([string]::IsNullOrWhiteSpace($ip)) { Write-Warning "Skipping $name: IPAddress is blank"; continue }
  if ($name -notmatch '^[A-Za-z0-9-]{1,15}$') { Write-Warning "Skipping invalid NetBIOS hostname: $name"; continue }
  if (-not $PSCmdlet.ShouldProcess("$name ($ip)", "Rename and join $DomainName (reboots guest)")) { continue }
  try {
    # Certificate must be valid for the DNS name or IP used to connect.
    $s = New-PSSession -ComputerName $ip -UseSSL -Credential $localCred -Authentication Negotiate -ErrorAction Stop
    try {
      Invoke-Command -Session $s -ArgumentList $name,$DomainName,$OUPath,$domainCred -ScriptBlock {
        param($ComputerName,$Domain,$OU,$JoinCredential)
        $params = @{ DomainName=$Domain; NewName=$ComputerName; Credential=$JoinCredential; Force=$true; ErrorAction='Stop' }
        if ($OU) { $params.OUPath = $OU }
        Add-Computer @params
        Restart-Computer -Force
      } -ErrorAction Stop
      Write-Host "Join submitted for $name; wait for reboot and verify AD membership."
    } finally { Remove-PSSession $s -ErrorAction SilentlyContinue }
  } catch {
    Write-Warning "Failed $name : $($_.Exception.Message)"
  }
}
