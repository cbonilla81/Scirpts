

#################### DFT ESXi Post Install Configuration ############################
#                                                                                   #
#    Created By: Christian Marrero Bonilla                                          #
#    CVENT Systems Engineering Team                                                 #
#                                                                                   #
#####################################################################################

Clear-Host
Write-Output 'Greetings Systems Engineer, Initializing Post Install Configuration'
cmd /c pause
Add-PSSnapin VMware*
$esxi = Read-Host "Enter ESXi host IP or FQDN"
$psswrd = Read-Host "Enter Root Password Here"

Connect-VIServer $esxi -User root -Password $psswrd -WarningAction SilentlyContinue

############ Variables ##################

$VMK_VMO1_IP = Read-Host "Enter VMK_VMO1 IP Address"
$VMK_VMO2_IP = Read-Host "Enter VMK_VMO2 IP Address"
$VMK_NFS_IP = Read-Host "Enter NFS IP Address"
$vSwitch0 = Get-VirtualSwitch -VMHost $esxi -Name "vSwitch0"
$VMNIC = Get-VMhost $esxi | Get-VMHostNetworkAdapter -Physical -Name vmnic3

############ Add second vmnic & Rename Management Port Group #################

Get-VirtualSwitch -Name "vSwitch0" | Add-VirtualSwitchPhysicalNetworkAdapter -VMHostPhysicalNic $VMNIC
Get-VirtualSwitch | Where-Object {$_.Name -eq "vSwitch0"} | Set-VirtualSwitch -Mtu 9000 -Confirm:$false
Get-VirtualPortGroup -Name "Management Network" | Set-VirtualPortGroup -Name  VMK_MGT
$vspa = Get-VirtualSwitch -VMHost $esxi -Name vSwitch0 | Get-NicTeamingPolicy
$vspa | Set-NicTeamingPolicy -FailbackEnabled $false

$ppolicy0 = Get-VirtualSwitch -VMHost $esxi -Name vSwitch0 | Get-VirtualPortGroup | Where-Object {$_.Name -eq "VMK_MGT"} | Get-NicTeamingPolicy 
$ppolicy0 | Set-NicTeamingPolicy -InheritFailoverOrder $false | Set-NicTeamingPolicy -MakeNicActive vmnic3 -Confirm:$false

############ Configure vMotion & NFS VMKernel Interface ###############

New-VMHostNetworkAdapter -VMHost $esxi `
    -PortGroup "VMK_VMO1" `
    -VirtualSwitch $vSwitch0 `
    -IP $VMK_VMO1_IP `
    -SubnetMask 255.255.254.0 `
    -vMotionEnabled:$true

    Get-VMHostNetworkAdapter | Where-Object { $_.PortGroupName -eq "VMK_VMO1" } | Set-VMHostNetworkAdapter -Mtu 9000
    Get-VirtualPortGroup -Name "VMK_VMO1" | Set-VirtualPortGroup -VLanId 47
    
    $ppolicy1 = Get-VirtualSwitch -VMHost $esxi -Name vSwitch0 | Get-VirtualPortGroup | Where-Object {$_.Name -eq "VMK_VMO1"} | Get-NicTeamingPolicy 
    $ppolicy1 | Set-NicTeamingPolicy -InheritFailoverOrder $false | Set-NicTeamingPolicy -MakeNicStandby vmnic3 -Confirm:$false

New-VMHostNetworkAdapter -VMHost $esxi `
    -PortGroup "VMK_VMO2" `
    -VirtualSwitch $vSwitch0 `
    -IP $VMK_VMO2_IP `
    -SubnetMask 255.255.254.0 `
    -vMotionEnabled:$true

    Get-VMHostNetworkAdapter | Where-Object { $_.PortGroupName -eq "VMK_VMO2" } | Set-VMHostNetworkAdapter -Mtu 9000
    Get-VirtualPortGroup -Name "VMK_VMO2" | Set-VirtualPortGroup -VLanId 47
    
    $ppolicy2 = Get-VirtualSwitch -VMHost $esxi -Name vSwitch0 | Get-VirtualPortGroup | Where-Object {$_.Name -eq "VMK_VMO2"} | Get-NicTeamingPolicy 
    $ppolicy2 | Set-NicTeamingPolicy -InheritFailoverOrder $false | Set-NicTeamingPolicy -MakeNicStandby vmnic2

New-VMHostNetworkAdapter -VMHost $esxi `
    -PortGroup "VMK_NFS" `
    -VirtualSwitch $vSwitch0 `
    -IP $VMK_NFS_IP `
    -SubnetMask 255.255.254.0 `
    -vMotionEnabled:$false
    
    Get-VirtualPortGroup -Name "VMK_NFS" | Set-VirtualPortGroup -VLanId 608

############# Create second vSwitch #############

New-VirtualSwitch -VMHost $esxi -Name "vSwitch1" -Nic vmnic7,vmnic6
$vspb = Get-VirtualSwitch -VMHost $esxi -Name vSwitch1 | Get-NicTeamingPolicy
$vspb | Set-NicTeamingPolicy -FailbackEnabled $false

############ Configure NTP Server ###############

Get-VMHost $esxi | Add-VMHostNtpServer 172.21.54.29
Get-VMHost $esxi | Add-VMHostNtpServer 172.21.54.30
Get-VMHost $esxi | Add-VMHostNtpServer 10.20.34.47
Get-VMHost $esxi | Get-VMHostFirewallException | Where-Object {$_.Name -eq "NTP client"} | Set-VMHostFirewallException -Enabled:$true
Get-VMHost $esxi | Get-VmHostService | Where-Object {$_.key -eq "ntpd"} | Start-VMHostService
Get-VMhost $esxi | Get-VmHostService | Where-Object {$_.key -eq "ntpd"} | Set-VMHostService -policy "On"

############ Configure SNMP Settings #############

$vmhostSNMP = Get-VMHostSNMP
Set-VMHostSNMP $vmhostSNMP -Enabled:$true -ReadOnlyCommunity 'qp74Mv9YAZP'

########### Create SATP Custom Rules #############

$esxcli=get-esxcli -VMHost $esxi
$esxcli.storage.nmp.satp.rule.add($null, $null, "PURE FlashArray RR IO Operation Limit Rule", $null, $null, $null, "FlashArray",
$null, "VMW_PSP_RR", "iops=1", "VMW_SATP_ALUA", $null, $null, "PURE")

$esxcli=get-esxcli -VMHost $esxi
$esxcli.storage.nmp.satp.rule.add($null, "tpgs_on", "3PAR FlashArray RR IO Operation Limit Rule", $null, $null, $null, "VV",
$null, "VMW_PSP_RR", "iops=1", "VMW_SATP_ALUA", $null, $null, "3PARdata")


########### Security Profile Settings #############

Get-VMHost $esxi | Get-VmHostService | Where-Object {$_.key -eq "TSM-SSH"} | Start-VMHostService
Get-VMhost $esxi | Get-VmHostService | Where-Object {$_.key -eq "TSM-SSH"} | Set-VMHostService -policy "On"

############# Syslog ##################

Get-VMHost $esxi | Get-VMHostFirewallException | Where-Object {$_.Name -eq "syslog"} | Set-VMHostFirewallException -Enabled:$true
Get-AdvancedSetting -Entity $esxi -Name Syslog.global.logDirUnique | Set-AdvancedSetting -Value True -Confirm:$false
Get-AdvancedSetting -Entity $esxi -Name Syslog.global.logHost | Set-AdvancedSetting -Value 'tcp://172.21.55.192:514' -Confirm:$false

############# Configure Host Advance Settings ############

Get-AdvancedSetting -Entity $esxi -Name Mem.AllocGuestLargePage | Set-AdvancedSetting -Value '1' -Confirm:$false
Get-AdvancedSetting -Entity $esxi -Name UserVars.SuppressShellWarning | Set-AdvancedSetting -Value '1' -Confirm:$false
Get-AdvancedSetting -Entity $esxi -Name Net.FollowhardwareMac | Set-AdvancedSetting -Value '1' -Confirm:$false
Get-AdvancedSetting -Entity $esxi -Name Syslog.global.defaultRotate | Set-AdvancedSetting -Value '16' -Confirm:$false

############ DNS Search Domain Configuration ##############

 Get-VMHost $esxi | Get-VMHostNetwork | Set-VMHostNetwork -SearchDomain core.cvent.org,cvent.net

############################################################################################################################

Clear-Host

Write-Output 'Post Install Configuration Completed! Have a Nice Day!'

