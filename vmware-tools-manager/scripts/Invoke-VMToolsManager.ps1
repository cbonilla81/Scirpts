#Requires -Version 5.1
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$Server,
 [string]$OutputDirectory = './reports',
 [string]$Cluster,
 [string]$VMName,
 [ValidateSet('Assess','Upgrade')][string]$Mode='Assess',
 [switch]$Execute,
 [string]$ApprovedVMsFile
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (-not (Get-Module -ListAvailable -Name VMware.VimAutomation.Core)) { throw 'VMware PowerCLI is missing. Install-Module VMware.PowerCLI -Scope CurrentUser' }
Import-Module VMware.VimAutomation.Core
$OutputDirectory=[System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath=Join-Path $OutputDirectory "actions-$stamp.csv"
$vi=$null
function Get-ToolsCategory {
 param([string]$Power,[string]$Running,[string]$VersionStatus,[string]$InstallType)
 if ($Power -ne 'PoweredOn') { return 'Powered Off' }
 if ($InstallType -match 'OpenVMTools|OSP' -and $Running -eq 'guestToolsRunning' -and $VersionStatus -match 'guestToolsUnmanaged') { return 'Guest Managed' }
 if ($Running -eq 'guestToolsNotRunning' -and $VersionStatus -match 'guestToolsNotInstalled') { return 'Not Installed' }
 if ($VersionStatus -match 'guestToolsNotInstalled') { return 'Not Installed' }
 if ($Running -ne 'guestToolsRunning') { return 'Not Running / Unknown' }
 if ($VersionStatus -match 'guestToolsNeedUpgrade|guestToolsSupportedOld|guestToolsTooOld|guestToolsUnmanaged') {
  if ($VersionStatus -match 'guestToolsUnmanaged') { return 'Guest Managed' }
  return 'Outdated'
 }
 if ($VersionStatus -match 'guestToolsCurrent|guestToolsSupportedNew') { return 'Healthy' }
 return 'Review'
}
function Write-HtmlReport {
 param([object[]]$Rows,[string]$Path,[string]$Endpoint)
 $json=ConvertTo-Json -InputObject @($Rows) -Depth 5 -Compress
 # JSON is embedded as text, not executable JS, and safely escaped for HTML.
 $json=$json.Replace('&','\u0026').Replace('<','\u003c').Replace('>','\u003e').Replace([string][char]0x2028,'\u2028').Replace([string][char]0x2029,'\u2029')
 $template=@'
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>VMware Tools Health</title><style>
:root{font-family:Inter,Segoe UI,Arial,sans-serif;color:#17243a;background:#f5f7fb}*{box-sizing:border-box}body{margin:0}.wrap{max-width:1440px;margin:auto;padding:32px}header{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:12px}h1{margin:0;font-size:28px}small,.muted{color:#65748a}.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(175px,1fr));gap:16px;margin:26px 0}.card,.panel{background:white;border:1px solid #e4eaf2;border-radius:14px;padding:20px;box-shadow:0 3px 12px #17243a08}.num{font-size:32px;font-weight:750;margin-top:8px}.controls{display:flex;gap:10px;flex-wrap:wrap;margin:18px 0}input,select{border:1px solid #ccd6e3;border-radius:8px;padding:10px 12px;font-size:14px;background:white}input{min-width:240px;flex:1}table{width:100%;border-collapse:collapse;font-size:13px}th{text-align:left;background:#f0f4fa;position:sticky;top:0}th,td{padding:12px;border-bottom:1px solid #e9edf3}tr:hover{background:#f8faff}.scroll{overflow:auto;max-height:65vh}.pill{display:inline-block;padding:5px 9px;border-radius:50px;background:#e9eef7;font-weight:600;white-space:nowrap}.Healthy{background:#daf5e8;color:#087a4a}.Outdated{background:#fff0c7;color:#875a00}.NotInstalled,.NotRunning{background:#ffe2e2;color:#b52525}.bar{display:flex;overflow:hidden;border-radius:20px;height:15px;background:#e6eaf0}.bar span{height:100%}.note{line-height:1.5;color:#52627a}button{background:#155eef;color:white;border:0;border-radius:8px;padding:10px 14px;cursor:pointer}@media(max-width:650px){.wrap{padding:15px}th,td{padding:8px}}
</style></head><body><main class="wrap"><header><div><h1>VMware Tools Health</h1><p class="muted">vCenter: __SERVER__ · Generated: __DATE__</p></div><button onclick="downloadFiltered()">Export filtered CSV</button></header><section id="cards" class="cards"></section><section class="panel"><strong>Tools health distribution</strong><div class="bar" id="bar" style="margin:15px 0"></div><p class="note">Guest-managed Linux packages are assessed separately from hypervisor-managed VMware Tools. Powered-off VMs cannot report live agent health.</p></section><section class="panel" style="margin-top:18px"><h2>VM inventory</h2><div class="controls"><input id="search" placeholder="Search VM, cluster, host, OS…" oninput="render()"><select id="status" onchange="render()"><option value="">All statuses</option></select><select id="power" onchange="render()"><option value="">All power states</option><option>PoweredOn</option><option>PoweredOff</option></select></div><div class="scroll"><table><thead><tr id="headers"></tr></thead><tbody id="rows"></tbody></table></div><p id="count" class="muted"></p></section></main><script id="vm-data" type="application/json">__DATA__</script><script>
const data=JSON.parse(document.getElementById('vm-data').textContent);const columns=['VMName','PowerState','Category','ToolsRunningStatus','ToolsVersionStatus','ToolsVersion','ToolsInstallType','GuestOS','Cluster','ESXiHost'];const labels=['VM','Power','Assessment','Runtime','Version status','Version','Install type','Guest OS','Cluster','ESXi host'];
function escapeHtml(x){return String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function filtered(){let q=document.getElementById('search').value.toLowerCase(),s=document.getElementById('status').value,p=document.getElementById('power').value;return data.filter(r=>(!s||r.Category===s)&&(!p||r.PowerState===p)&&columns.some(k=>String(r[k]??'').toLowerCase().includes(q)))}
function render(){let rows=filtered();document.getElementById('rows').innerHTML=rows.map(r=>'<tr>'+columns.map(k=>'<td>'+(k==='Category'?'<span class="pill '+(r[k]||'').replace(/[^a-zA-Z]/g,'')+'">'+escapeHtml(r[k])+'</span>':escapeHtml(r[k]))+'</td>').join('')+'</tr>').join('');document.getElementById('count').textContent=`Showing ${rows.length} of ${data.length} VMs`}
function csvCell(v){let s=String(v??'');if(/^[\s]*[=+@\-\t\r]/.test(s))s="'"+s;return '"'+s.replace(/"/g,'""')+'"'}
function downloadFiltered(){let lines=[columns.map(csvCell).join(','),...filtered().map(r=>columns.map(k=>csvCell(r[k])).join(','))];let blob=new Blob([lines.join('\r\n')],{type:'text/csv;charset=utf-8'}),a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='vmtools-filtered.csv';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000)}
document.getElementById('headers').innerHTML=labels.map(x=>'<th>'+escapeHtml(x)+'</th>').join('');let statuses=[...new Set(data.map(r=>r.Category))].sort();document.getElementById('status').innerHTML+=[...statuses].map(s=>'<option>'+escapeHtml(s)+'</option>').join('');let colors={'Healthy':'#15a36c','Outdated':'#f4b942','Not Installed':'#df5454','Not Running / Unknown':'#f08080','Powered Off':'#8b99ad','Guest Managed':'#5788d5','Review':'#ac86d4'};document.getElementById('cards').innerHTML=[['Total VMs',data.length],...statuses.map(s=>[s,data.filter(r=>r.Category===s).length])].map(([label,count])=>'<div class="card"><small>'+escapeHtml(label)+'</small><div class="num">'+count+'</div></div>').join('');document.getElementById('bar').innerHTML=statuses.map(s=>'<span title="'+escapeHtml(s)+'" style="width:'+(100*data.filter(r=>r.Category===s).length/Math.max(1,data.length))+'%;background:'+(colors[s]||'#64748b')+'"></span>').join('');render();
</script></body></html>
'@
 $safeServer=[System.Net.WebUtility]::HtmlEncode($Endpoint)
 $template=$template.Replace('__SERVER__',$safeServer).Replace('__DATE__',(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')).Replace('__DATA__',$json)
 [System.IO.File]::WriteAllText($Path,$template,[System.Text.UTF8Encoding]::new($false))
}
try {
 $vi=Connect-VIServer -Server $Server -ErrorAction Stop
 $vms=@(Get-VM)
 if ($Cluster) { $vms=@($vms | Where-Object { (Get-Cluster -VM $_ -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -eq $Cluster }) }
 if ($VMName) { $vms=@($vms | Where-Object { $_.Name -like $VMName }) }
 $rows=@(foreach($vm in $vms) {
  $g=$vm.ExtensionData.Guest
  $clusterName=try { (Get-Cluster -VM $vm -ErrorAction Stop).Name } catch { '' }
  $install=if($null -ne $g.ToolsInstallType){[string]$g.ToolsInstallType}else{''}
  $running=[string]$g.ToolsRunningStatus
  $versionStatus=[string]$g.ToolsVersionStatus2
  [PSCustomObject]@{
   VMName=$vm.Name; VMId=$vm.Id; PowerState=[string]$vm.PowerState; Category=(Get-ToolsCategory -Power ([string]$vm.PowerState) -Running $running -VersionStatus $versionStatus -InstallType $install)
   ToolsRunningStatus=$running; ToolsVersionStatus=$versionStatus; ToolsVersion=[string]$g.ToolsVersion; ToolsInstallType=$install
   GuestOS=[string]$vm.ExtensionData.Config.GuestFullName; Cluster=[string]$clusterName; ESXiHost=[string]$vm.VMHost.Name
  }
 })
 $csv=Join-Path $OutputDirectory "inventory-$stamp.csv"; $html=Join-Path $OutputDirectory "dashboard-$stamp.html"
 if($rows.Count -gt 0) { $rows | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8 } else { 'VMName,VMId,PowerState,Category,ToolsRunningStatus,ToolsVersionStatus,ToolsVersion,ToolsInstallType,GuestOS,Cluster,ESXiHost' | Set-Content -Path $csv -Encoding UTF8 }
 Write-HtmlReport -Rows $rows -Path $html -Endpoint $Server
 Write-Host "Assessment complete: $($rows.Count) VMs" -ForegroundColor Green
 Write-Host "HTML: $html`nCSV: $csv"
 $rows | Group-Object Category | Sort-Object Name | Format-Table Name,Count -AutoSize
 if($Mode -eq 'Upgrade') {
  if (-not $ApprovedVMsFile) { throw 'Upgrade mode requires -ApprovedVMsFile (one exact VM name per line).' }
  if (-not (Test-Path -LiteralPath $ApprovedVMsFile)) { throw "Approval file missing: $ApprovedVMsFile" }
  $approved=@(Get-Content -LiteralPath $ApprovedVMsFile | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
  $candidates=@($rows | Where-Object { $_.VMName -cin $approved -and $_.Category -eq 'Outdated' -and $_.PowerState -eq 'PoweredOn' -and $_.ToolsInstallType -notmatch 'OpenVMTools|OSP' -and $_.GuestOS -match 'Windows' })
  $actions=@()
  foreach($r in $candidates) {
   $outcome='DryRun';$detail='Eligible; no changes made'
   if($Execute) {
    try { $vm=Get-VM -Id $r.VMId -ErrorAction Stop; Update-Tools -VM $vm -NoReboot -ErrorAction Stop | Out-Null; $outcome='Requested';$detail='Upgrade initiated; verify guest status and reboot requirements' }
    catch { $outcome='Failed';$detail=$_.Exception.Message }
   }
   $actions += [PSCustomObject]@{Timestamp=(Get-Date).ToString('o');VMName=$r.VMName;Outcome=$outcome;Detail=$detail}
  }
  $actions | Export-Csv -Path $logPath -NoTypeInformation -Encoding UTF8
  Write-Host "Upgrade mode: $($candidates.Count) eligible Windows VMs. Execute=$Execute. Action log: $logPath"
  if($Execute) { Write-Warning 'VMware Tools upgrades may still require or trigger a reboot despite -NoReboot. Validate maintenance windows.' }
 }
} finally { if($null -ne $vi) { Disconnect-VIServer -Server $vi -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } }
