### PowerShell Script: Harden-WindowsServer.ps1

# Disable Unnecessary Services
$servicesToDisable = @(
    "RemoteRegistry",
    "Fax",
    "SSDPSRV",
    "upnphost",
    "bthserv",
    "Spooler"
)

foreach ($svc in $servicesToDisable) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Stop-Service -Name $svc -Force
        Set-Service -Name $svc -StartupType Disabled
        Write-Output "Disabled service: $svc"
    }
}

# Disable SMBv1
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart

# Disable NetBIOS over TCP/IP
Get-WmiObject -Query "Select * from Win32_NetworkAdapterConfiguration where IPEnabled = True" | ForEach-Object {
    $_.SetTcpipNetbios(2)
    Write-Output "Disabled NetBIOS on adapter: $($_.Description)"
}

# Disable LLMNR via registry
Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableMulticast" -Value 0 -Force

# Configure Windows Firewall: Block unused ports
$portsToBlock = @(21, 23, 135, 137, 138, 139, 161, 162, 445, 5353, 5355)
foreach ($port in $portsToBlock) {
    New-NetFirewallRule -DisplayName "Block Port $port" -Direction Inbound -LocalPort $port -Protocol TCP -Action Block
    New-NetFirewallRule -DisplayName "Block Port $port UDP" -Direction Inbound -LocalPort $port -Protocol UDP -Action Block
    Write-Output "Blocked Port: $port"
}

# Disable IPv6 (Optional - use with caution)
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -PropertyType DWord -Value 0xFF -Force

Write-Output "Windows Server hardening complete. Reboot recommended."
