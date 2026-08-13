# Import the VMware PowerCLI module
Import-Module VMware.PowerCLI

# Suppress certificate warnings
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false

# Connect to the vCenter Server

Connect-VIServer -Server 10.100.10.80 -User administrator@vsphere.local -Password R3yn0ld$

# Get all ESXi hosts
$esxiHosts = Get-VMHost -Datastore LAB_Container01

# Define the vSwitch and port group names
$vSwitchName = "vSwitchBmc"
$portGroupName = "host-bmc-pg"

# Loop through each ESXi host to create the vSwitch and port group
foreach ($host in $esxiHosts) {
    Write-Host "Configuring ESXi Host: $($host.Name)" -ForegroundColor Cyan

    # Check if the vSwitch already exists
    $existingSwitch = Get-VirtualSwitch -VMHost $host -Standard | Where-Object { $_.Name -eq $vSwitchName }
    if (-not $existingSwitch) {
        # Create the vSwitch
        New-VirtualSwitch -VMHost $host -Name $vSwitchName -NumPorts 128 -Mtu 1500
        Write-Host "  Created vSwitch: $vSwitchName" -ForegroundColor Green
    } else {
        Write-Host "  vSwitch $vSwitchName already exists on $($host.Name)" -ForegroundColor Yellow
    }

    # Check if the port group already exists
    $existingPortGroup = Get-VirtualPortGroup -VMHost $host | Where-Object { $_.Name -eq $portGroupName }
    if (-not $existingPortGroup) {
        # Create the port group
        New-VirtualPortGroup -VirtualSwitch $vSwitchName -Name $portGroupName -VMHost $host
        Write-Host "  Created Port Group: $portGroupName" -ForegroundColor Green
    } else {
        Write-Host "  Port Group $portGroupName already exists on $($host.Name)" -ForegroundColor Yellow
    }
}

# Disconnect from the vCenter Server
Disconnect-VIServer -Server 10.100.10.80 -Confirm:$false