
Write-Host = "
                                              ,--.                     ,--, 
,-.----.    .--.--.      ,---,              ,--.'|    ,---,          ,--.'| 
\    /  \  /  /    '.   '  .' \         ,--,:  : |  .'  .' `\     ,--,  | : 
;   :    \|  :  /`. /  /  ;    '.    ,`--.'`|  ' :,---.'     \ ,---.'|  : ' 
|   | .\ :;  |  |--`  :  :       \   |   :  :  | ||   |  .`\  ||   | : _' | 
.   : |: ||  :  ;_    :  |   /\   \  :   |   \ | ::   : |  '  |:   : |.'  | 
|   |  \ : \  \    `. |  :  ' ;.   : |   : '  '; ||   ' '  ;  :|   ' '  ; : 
|   : .  /  `----.   \|  |  ;/  \   \'   ' ;.    ;'   | ;  .  |'   |  .'. | 
;   | |  \  __ \  \  |'  :  | \  \ ,'|   | | \   ||   | :  |  '|   | :  | ' 
|   | ;\  \/  /`--'  /|  |  '  '--'  '   : |  ; .''   : | /  ; '   : |  : ; 
:   ' | \.'--'.     / |  :  :        |   | '`--'  |   | '` ,/  |   | '  ,/  
:   : :-'   `--'---'  |  | ,'        '   : |      ;   :  .'    ;   : ;--'   
|   |.'               `--''          ;   |.'      |   ,.'      |   ,/       
`---'                                '---'        '---'        '---'        
                                                                             
"

$snapin = Find-Module -Name VMware.PowerCLI -ErrorAction SilentlyContinue

if (!$snapin)
    
    {
    
        Add-PSSnapin -Name VMware.PowerCLI
        
    }

            
 if($snapin)
 
     {
 
        Write-Host "VMWare Snap in were imported already"  -ForegroundColor Green
        
      }

$vcenter =  "vcenter60.rsandh.com"
Connect-VIServer $vcenter -WarningAction SilentlyContinue
$myDatacenter = Get-Datacenter -Name "RSH_Corp"
$vms = Get-VM -Location $myDatacenter

############# Do Work #################

 Write-Host "Gathering Snapshot Information for VM" -ForegroundColor Yellow
 $snap = Get-Snapshot -vm $vms |Select-Object vm, name, created, sizegb 


$snap | Select-Object vm, name, created, sizegb | Out-GridView -Title "List of VM with Snapshots"
$snap | Select-Object vm, name, created, sizegb | Export-Csv -Path "$env:USERPROFILE\Downloads\SnapshotReport.csv" -NoTypeInformation -Append

Write-Host "Completed!" -ForegroundColor Green
[Console]::Beep(1000, 500) # Frequency: 1000 Hz, Duration: 500 ms

Add-Type -AssemblyName System.Speech
$speak = New-Object System.Speech.Synthesis.SpeechSynthesizer
$speak.Speak("Script Completed. Please check the CSV Report under the Downloads Folder and Remove the Snapshot listed. Have a great day!")
    
#END