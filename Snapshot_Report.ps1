$snapin = Find-Module -Name VMware.PowerCLI -ErrorAction SilentlyContinue

if (!$snapin)
    
    {
    
        Add-PSSnapin -Name VMware.PowerCLI
        
    }
        
 if($snapin)
 
     {
 
        Write-Host "VMWare Snap in were imported already"  -ForegroundColor Green
        
      }

$vcenter = Read-Host "Enter vCenter Server Name or IP Address Here"
Connect-VIServer $vcenter -WarningAction SilentlyContinue
$myDatacenter = Get-Datacenter -Name "RSH_Corp"
$vms = Get-VM -Location $myDatacenter

############# Do Work #################

 Write-Host "Gathering Snapshot Information for VM" -ForegroundColor Yellow
 $snap = Get-Snapshot -vm $vms |Select-Object vm, name, created, sizegb 


$snap | Select-Object vm, name, created, sizegb | Out-GridView -Title "List of VM with Snapshots"

Write-Host "Completed!" -ForegroundColor Green
    
#### Do Email ####

$body = $Snap | ConvertTo-Html
$mailParams = @{
    To = "christian.bonilla@rsandh.com"
    From = "vCenter60.rsandh.com"
    Subject = "Snapshot Report"
    Body = $body
    smtpServer = "smtp.office365.com"
    BodyAsHtml = $true
}

#Send Email

try {

    Send-MailMessage @mailParams
    Write-Host "Email sent successfully."
} catch {
    Write-Host "Error sending email: $($_.Exception.Message)"
}
#END