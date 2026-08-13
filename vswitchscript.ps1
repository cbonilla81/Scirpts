# Import the VMware PowerCLI module
Import-Module VMware.PowerCLI

# Suppress certificate warnings
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

# Connect to the vCenter Server
$vCenterServer = Read-Host "Enter the vCenter Server hostname or IP"
$Username = Read-Host "Enter your vCenter username"
$Password = Read-Host "Enter your vCenter password" -AsSecureString
Connect-VIServer -Server $vCenterServer -User $Username -Password $Password

# Get all ESXi hosts
$esxiHosts = Get-VMHost

# Initialize a hashtable to store vSwitch and port group names for comparison
$vSwitchNames = @{}
$portGroupNames = @{}

# Loop through each ESXi host and retrieve its standard switches and port groups
foreach ($host in $esxiHosts) {
    Write-Host "Standard Switches for ESXi Host: $($host.Name)" -ForegroundColor Cyan
    $vSwitches = Get-VirtualSwitch -VMHost $host -Standard
    foreach ($vSwitch in $vSwitches) {
        Write-Host "  vSwitch Name: $($vSwitch.Name)"
        Write-Host "    Number of Ports: $($vSwitch.NumPorts)"
        Write-Host "    MTU: $($vSwitch.Mtu)"
        Write-Host "    NICs: $($vSwitch.Nic.Name -join ', ')"
        Write-Host ""

        # Add vSwitch name to the hashtable
        if (-not $vSwitchNames.ContainsKey($vSwitch.Name)) {
            $vSwitchNames[$vSwitch.Name] = @()
        }
        if (-not $vSwitchNames[$vSwitch.Name].Contains($host.Name)) {
            $vSwitchNames[$vSwitch.Name] += $host.Name
        }
    }

    # Retrieve port groups for the current host
    $portGroups = Get-VirtualPortGroup -VMHost $host
    foreach ($portGroup in $portGroups) {
        Write-Host "  Port Group Name: $($portGroup.Name)"
        Write-Host "    vSwitch: $($portGroup.VirtualSwitch)"
        Write-Host ""

        # Add port group name to the hashtable
        if (-not $portGroupNames.ContainsKey($portGroup.Name)) {
        if (-not $portGroupNames[$portGroup.Name].Contains($host.Name)) {
            $portGroupNames[$portGroup.Name] += $host.Name
        }
        }
        $portGroupNames[$portGroup.Name] += $host.Name
    }
}
# Checking for inconsistencies in vSwitch names
# Note: This assumes all hosts should have the same vSwitches. Adjust logic for environments with different configurations.
Write-Host "`nChecking for inconsistencies in vSwitch names..." -ForegroundColor Yellow
foreach ($vSwitch in $vSwitchNames.Keys) {
    if ($vSwitchNames[$vSwitch].Count -ne $esxiHosts.Count) {
        Write-Host "  vSwitch '$vSwitch' is not present on all hosts. Hosts: $($vSwitchNames[$vSwitch] -join ', ')" -ForegroundColor Red
        # Optional: Add logic to handle exceptions for specific hosts
        # Example: Skip hosts with known configuration differences
        # Write-Host "  Skipping known configuration differences for vSwitch '$vSwitch'." -ForegroundColor Green
    }
}
    
    # Check if the port group exists in the hashtable before accessing its properties
    if ($portGroupNames.ContainsKey($portGroup) -and $portGroupNames[$portGroup].Count -ne $esxiHosts.Count) {
        Write-Host "  Port Group '$portGroup' is not present on all hosts. Hosts: $($portGroupNames[$portGroup] -join ', ')" -ForegroundColor Red
    } else {
        Write-Host "  Port Group '$portGroup' is missing or has inconsistent data." -ForegroundColor Yellow
    }
Write-Host "`nChecking for inconsistencies in port group names..." -ForegroundColor Yellow
foreach ($portGroup in $portGroupNames.Keys) {
    if ($portGroupNames[$portGroup].Count -ne $esxiHosts.Count) {
        Write-Host "  Port Group '$portGroup' is not present on all hosts. Hosts: $($portGroupNames[$portGroup] -join ', ')" -ForegroundColor Red
    }
}

# Disconnect from the vCenter Server
Disconnect-VIServer -Server $vCenterServer -Confirm:$false