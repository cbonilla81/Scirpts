#-----------------------------------------------------------
#	Script: VM Snapshot Creation
#	 																							
#	Date: 8.7.2017																						
#	
#	By: Chritian Marrero IS Systems Engineer
#
#------------------------------------------------------------

<# Description
Create snapshot on a Virtual Machine
#>
Write-Host = "

 
.____    .__  _____       _______          __      ___ ___                .__   __  .__     
|    |   |__|/ ____\____  \      \   _____/  |_   /   |   \   ____ _____  |  |_/  |_|  |__  
|    |   |  \   __\/ __ \ /   |   \_/ __ \   __\ /    ~    \_/ __ \\__  \ |  |\   __\  |  \ 
|    |___|  ||  | \  ___//    |    \  ___/|  |   \    Y    /\  ___/ / __ \|  |_|  | |   Y  \
|_______ \__||__|  \___  >____|__  /\___  >__|    \___|_  /  \___  >____  /____/__| |___|  /
        \/             \/        \/     \/              \/       \/     \/               \/ 
"

##################################################################

$snapin = Get-PSSnapin -Name vmware* -ErrorAction SilentlyContinue

if (!$snapin)
    
    {
    
        Add-PSSnapin vmware*
        
    }
        
 if($snapin)
 
     {
 
        Write-Host "VMWare Snap in were imported already"  -ForegroundColor Green
        
      }

$vcenter = Read-Host "Enter vCenter Server Name or IP Address Here"
Connect-VIServer $vcenter -WarningAction SilentlyContinue
$vmn = Read-Host "Enter VM Name Here"
$vm = Get-VM -Name $vmn
############# Do Work #################
foreach ($VM in $vmn){
    Write-Host "Gathering Snapshot Information for VM"
$Snap = Get-Snapshot -vm $vmn

    if ($Snap)

        {
            Write-Warning "There is an old Snapshot.....Delete it !" 
                Get-Snapshot -vm $vmn | Out-GridView         
            
        }
        
      
    if (!$Snap)

        {
        
            Write-Host "There is no snapshot created before, creating snapshot..."  -ForegroundColor Green
            New-Snapshot -VM $vmn -Name "Before_Updates"
            
             Get-Snapshot -vm $vmn | Out-GridView                           

        }
             
    
    }
#END




