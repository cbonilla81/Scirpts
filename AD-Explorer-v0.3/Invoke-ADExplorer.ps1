#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath = (Join-Path (Get-Location) 'AD-Report'),[switch]$IncludeReplication,[switch]$IncludeHealth,[int]$StaleDays=90)
$ErrorActionPreference='Stop'
Import-Module ActiveDirectory -ErrorAction Stop
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$errorsList = [System.Collections.Generic.List[object]]::new()
function Try-Collect([string]$Section,[scriptblock]$Action) {
 try { @(& $Action) } catch { $errorsList.Add([pscustomobject]@{Section=$Section;Error=$_.Exception.Message}); @() }
}
$forest = Get-ADForest
$domains = @(foreach($dn in $forest.Domains){ Try-Collect "Domain $dn" { Get-ADDomain -Identity $dn | Select-Object DNSRoot,NetBIOSName,DomainMode,PDCEmulator,RIDMaster,InfrastructureMaster,ParentDomain,ChildDomains } })
$dcs = @(foreach($dn in $forest.Domains){ Try-Collect "DCs $dn" { Get-ADDomainController -Filter * -Server $dn | Select-Object Name,HostName,Domain,Site,IPv4Address,OperatingSystem,IsGlobalCatalog,IsReadOnly,OperationMasterRoles } })
$sites = @(Try-Collect 'Sites' { Get-ADReplicationSite -Filter * | Select-Object Name,Description })
$subnets = @(Try-Collect 'Subnets' { Get-ADReplicationSubnet -Filter * | Select-Object Name,Site,Location })
$links = @(Try-Collect 'Site links' { Get-ADReplicationSiteLink -Filter * | Select-Object Name,Cost,ReplicationFrequencyInMinutes,SitesIncluded })
$trusts = @(foreach($dn in $forest.Domains){ Try-Collect "Trusts $dn" { Get-ADTrust -Filter * -Server $dn | Select-Object Name,Source,Target,Direction,TrustType,ForestTransitive } })
$replication = @()
$replicationFailures = @()
$dcStatus = @()
foreach($dc in $dcs) {
 $reachable = $null
 try { $reachable = Test-Connection -ComputerName $dc.HostName -Count 1 -Quiet -ErrorAction Stop } catch { $reachable = $null }
 $dcStatus += [pscustomobject]@{HostName=$dc.HostName;PingReachable=$reachable;Assessment= $(if($null -eq $reachable){'Not assessed'} elseif($reachable){'ICMP reachable'}else{'ICMP unavailable'})}
}
if($IncludeReplication){
 $replication = @(foreach($dc in $dcs){ Try-Collect "Replication $($dc.HostName)" { Get-ADReplicationPartnerMetadata -Target $dc.HostName -Partition * -ErrorAction Stop | Select-Object Server,Partner,Partition,LastReplicationSuccess,LastReplicationAttempt,LastReplicationResult,ConsecutiveReplicationFailures } })
 $replicationFailures = @(foreach($dc in $dcs){ Try-Collect "Replication failures $($dc.HostName)" { Get-ADReplicationFailure -Target $dc.HostName -ErrorAction Stop | Select-Object Server,Partner,FirstFailureTime,FailureCount,LastError } })
}
# v0.3 read-only assessments. A failed probe is never treated as a healthy result.
$health = @(); $dnsChecks=@(); $privileged=@(); $staleComputers=@(); $passwordPolicies=@(); $sysvolChecks=@()
if($IncludeHealth){
 foreach($dc in $dcs){
  $hostName=$dc.HostName
  $dns = Try-Collect "DNS $hostName" { Resolve-DnsName -Name $hostName -Type A -ErrorAction Stop | Where-Object {$_.IPAddress} | Select-Object Name,IPAddress }
  $dnsChecks += [pscustomobject]@{Controller=$hostName;Status=$(if($dns.Count -gt 0){'Resolved'}else{'Unknown / failed'});Addresses=@($dns | ForEach-Object {$_.IPAddress}) -join ', '}
  foreach($share in @('SYSVOL','NETLOGON')){
   $status='Unknown / failed';$detail=''
   try { $unc='\\'+$hostName+'\'+$share; $status=if(Test-Path -LiteralPath $unc -ErrorAction Stop){'Accessible'}else{'Unavailable'} } catch { $detail=$_.Exception.Message }
   $sysvolChecks += [pscustomobject]@{Controller=$hostName;Share=$share;Status=$status;Detail=$detail}
  }
  $dcReplication=@($replication | Where-Object {$_.Server -like "*$hostName*" -or $_.Server -eq $dc.Name})
  $failed=@($dcReplication | Where-Object {[int]$_.LastReplicationResult -ne 0 -or [int]$_.ConsecutiveReplicationFailures -gt 0})
  $health += [pscustomobject]@{Controller=$hostName;ReplicationRecords=$dcReplication.Count;ReplicationFailures=$failed.Count;ReplicationStatus=$(if(-not $IncludeReplication){'Not assessed'}elseif($dcReplication.Count -eq 0){'Unknown / no records'}elseif($failed.Count -gt 0){'Attention'}else{'No errors in collected records'})}
 }
 foreach($dn in $forest.Domains){
  $passwordPolicies += @(Try-Collect "Password policy $dn" { Get-ADDefaultDomainPasswordPolicy -Server $dn | Select-Object @{Name='Domain';Expression={$dn}},MinPasswordLength,ComplexityEnabled,LockoutThreshold,MaxPasswordAge,MinPasswordAge,PasswordHistoryCount })
  $privileged += @(Try-Collect "Privileged groups $dn" {
    foreach($sidSuffix in @('512','518','519','520')){
     $domainSid=(Get-ADDomain -Identity $dn -Server $dn).DomainSID.Value
     $group=Get-ADGroup -Identity ($domainSid+'-'+$sidSuffix) -Server $dn -ErrorAction SilentlyContinue
     if($group){$members=@(Get-ADGroupMember -Identity $group -Server $dn -ErrorAction Stop);[pscustomobject]@{Domain=$dn;Group=$group.Name;MemberCount=$members.Count;Members=($members | ForEach-Object {$_.SamAccountName}) -join '; '}}
    }
  })
  $cutoff=(Get-Date).AddDays(-$StaleDays)
  $staleComputers += @(Try-Collect "Stale computers $dn" {Get-ADComputer -Filter {LastLogonTimeStamp -lt $cutoff -and Enabled -eq $true} -Server $dn -Properties LastLogonDate,OperatingSystem | Select-Object @{Name='Domain';Expression={$dn}},Name,LastLogonDate,OperatingSystem})
 }
}
$data = [ordered]@{
 Generated=(Get-Date).ToString('o');Forest=[pscustomobject]@{Name=$forest.Name;ForestMode="$($forest.ForestMode)";RootDomain=$forest.RootDomain;SchemaMaster=$forest.SchemaMaster;DomainNamingMaster=$forest.DomainNamingMaster;GlobalCatalogs=@($forest.GlobalCatalogs)}
 Domains=$domains;DomainControllers=$dcs;Sites=$sites;Subnets=$subnets;SiteLinks=$links;Trusts=$trusts;Replication=$replication;ReplicationFailures=$replicationFailures;DCStatus=$dcStatus;Health=$health;DNSChecks=$dnsChecks;SYSVOLChecks=$sysvolChecks;PasswordPolicies=$passwordPolicies;PrivilegedGroups=$privileged;StaleComputers=$staleComputers;HealthIncluded=[bool]$IncludeHealth;Errors=@($errorsList.ToArray())
}
$json = ConvertTo-Json -InputObject $data -Depth 12
$jsonPath=Join-Path $OutputPath 'AD-Inventory.json'
[System.IO.File]::WriteAllText($jsonPath,$json,[System.Text.UTF8Encoding]::new($false))
# Escape embedded JSON so directory names cannot inject HTML or close the script tag.
$safeJson=$json.Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026')
$html=@'
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AD Infrastructure Explorer</title>
<style>:root{font-family:Segoe UI,Arial,sans-serif;color:#dbeafe;background:#0b1220}body{margin:0;padding:28px;max-width:1500px;margin:auto}h1{margin-bottom:4px}p{color:#a5b4ce}.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:14px}.card,.panel{background:#152238;border:1px solid #293e5d;border-radius:13px;padding:17px;margin:15px 0}.metric{font-size:30px;font-weight:700;color:#60a5fa}button,select,input{padding:9px;border-radius:7px;border:1px solid #52657f;background:#101d30;color:white}button{cursor:pointer}.scroll{overflow:auto;max-height:440px}table{border-collapse:collapse;width:100%;font-size:13px}td,th{padding:10px;border-bottom:1px solid #304159;text-align:left;vertical-align:top}th{position:sticky;top:0;background:#1d3150}svg{background:#0c192d;border-radius:10px;min-width:750px}#diagram{overflow:auto} .muted{color:#a5b4ce} .pill{color:#93c5fd}</style></head><body>
<h1>Active Directory Infrastructure Explorer</h1><p id="meta"></p><div id="cards" class="cards"></div>
<section class="panel"><h2>Topology diagram</h2><p>Logical forest → domains → sites → domain controllers. Lines represent membership, not replication connections.</p><div id="diagram"></div></section>
<section class="panel"><h2>Replication and site-link map</h2><p>Observed replication partner relationships (when collected) and configured intersite links. Select a node for details. Replication edges are not physical network cables.</p><div id="network" style="overflow:auto"></div><div id="detail" class="card" aria-live="polite">Select a domain controller or site.</div></section>
<section class="panel"><h2>Health assessment</h2><p>Checks are read-only. Unknown means the test could not establish status; this is not a security certification.</p><div id="healthSummary"></div></section>
<section class="panel"><h2>Inventory</h2><select id="section"></select> <input id="filter" placeholder="Search rows..." aria-label="Search inventory"><button id="csv">Export selected CSV</button><div class="scroll" id="table"></div></section>
<section class="panel"><h2>Collection issues</h2><div id="issues"></div></section>
<script id="inventory" type="application/json">__JSON__</script>
<script>
const data=JSON.parse(document.getElementById('inventory').textContent);
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const txt=v=>Array.isArray(v)?v.map(txt).join(', '):v&&typeof v==='object'?JSON.stringify(v):String(v??'');
document.getElementById('meta').textContent='Forest: '+data.Forest.Name+'  •  Generated: '+data.Generated;
const sections=['Domains','DomainControllers','Sites','Subnets','SiteLinks','Trusts','Replication','ReplicationFailures','DCStatus','Health','DNSChecks','SYSVOLChecks','PasswordPolicies','PrivilegedGroups','StaleComputers','Errors'];
document.getElementById('cards').innerHTML=[['Domains',data.Domains.length],['Domain controllers',data.DomainControllers.length],['Sites',data.Sites.length],['Subnets',data.Subnets.length],['Trusts',data.Trusts.length],['Replication records',data.Replication.length],['Replication failures',data.ReplicationFailures.length],['Collection issues',data.Errors.length]].map(x=>'<div class="card"><div class="muted">'+esc(x[0])+'</div><div class="metric">'+x[1]+'</div></div>').join('');
document.getElementById('healthSummary').textContent = !data.HealthIncluded ? 'Health collection not requested. Run with -IncludeHealth.' : 'DNS unresolved/unknown: '+data.DNSChecks.filter(x=>x.Status!=='Resolved').length+' | SYSVOL/NETLOGON inaccessible or unknown: '+data.SYSVOLChecks.filter(x=>x.Status!=='Accessible').length+' | Replication controllers requiring attention: '+data.Health.filter(x=>x.ReplicationStatus==='Attention').length+' | Stale enabled computers: '+data.StaleComputers.length+' | Collection errors: '+data.Errors.length;
const sel=document.getElementById('section');sel.innerHTML=sections.map(s=>'<option>'+s+'</option>').join('');
function rows(){let q=document.getElementById('filter').value.toLowerCase();return (data[sel.value]||[]).filter(x=>JSON.stringify(x).toLowerCase().includes(q));}
function render(){let a=rows(),cols=[...new Set((data[sel.value]||[]).flatMap(x=>Object.keys(x)))];document.getElementById('table').innerHTML=cols.length?'<table><thead><tr>'+cols.map(c=>'<th>'+esc(c)+'</th>').join('')+'</tr></thead><tbody>'+a.map(x=>'<tr>'+cols.map(c=>'<td>'+esc(txt(x[c]))+'</td>').join('')+'</tr>').join('')+'</tbody></table>':'<p>No records collected for this section.</p>';}
sel.onchange=render;document.getElementById('filter').oninput=render;render();
document.getElementById('csv').onclick=()=>{let a=rows(),cols=[...new Set(a.flatMap(x=>Object.keys(x)))],quote=v=>'"'+txt(v).replace(/"/g,'""')+'"',csv=[cols.map(quote).join(','),...a.map(x=>cols.map(c=>quote(x[c])).join(','))].join('\r\n');let blob=new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8'}),url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download=sel.value+'.csv';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};
document.getElementById('issues').innerHTML=data.Errors.length?data.Errors.map(e=>'<p><strong>'+esc(e.Section)+'</strong>: '+esc(e.Error)+'</p>').join(''):'<p>No collection errors recorded. This does not guarantee complete discovery.</p>';
const svgNS='http://www.w3.org/2000/svg',root=document.createElementNS(svgNS,'svg');const sites=[...new Set(data.Sites.map(x=>x.Name).concat(data.DomainControllers.map(x=>x.Site||'Unknown site')))];const domains=data.Domains.map(x=>x.DNSRoot);let nodes=[{id:'forest',label:data.Forest.Name,x:400,y:35,type:'forest'}],edges=[];
domains.forEach((d,i)=>{let id='domain'+i,x=180+i*330;nodes.push({id,label:d,x,y:125,type:'domain'});edges.push(['forest',id]);let ds=data.DomainControllers.filter(dc=>dc.Domain===d),ss=[...new Set(ds.map(dc=>dc.Site||'Unknown site'))];ss.forEach((s,j)=>{let sid=id+'site'+j,sx=x+(j-(ss.length-1)/2)*170;nodes.push({id:sid,label:s,x:sx,y:220,type:'site'});edges.push([id,sid]);ds.filter(dc=>(dc.Site||'Unknown site')===s).forEach((dc,k)=>{let did=sid+'dc'+k;nodes.push({id:did,label:dc.Name,x:sx+(k-(ds.filter(z=>(z.Site||'Unknown site')===s).length-1)/2)*120,y:315,type:'dc'});edges.push([sid,did]);});});});
let min=Math.min(0,...nodes.map(n=>n.x-85)),max=Math.max(800,...nodes.map(n=>n.x+85)),offset=40-min;root.setAttribute('viewBox','0 0 '+(max-min+80)+' 385');root.setAttribute('width',max-min+80);root.setAttribute('height',385);
function el(tag,attrs,parent){let e=document.createElementNS(svgNS,tag);Object.entries(attrs).forEach(([k,v])=>e.setAttribute(k,v));parent.appendChild(e);return e;}
const byId=Object.fromEntries(nodes.map(n=>[n.id,n]));edges.forEach(([a,b])=>{let p=byId[a],q=byId[b];el('path',{d:`M ${p.x+offset} ${p.y+22} L ${q.x+offset} ${q.y-22}`,stroke:'#53769e','stroke-width':1.5,fill:'none'},root)});
nodes.forEach(n=>{let color={forest:'#2563eb',domain:'#0f766e',site:'#6d28d9',dc:'#1d4ed8'}[n.type];el('rect',{x:n.x+offset-79,y:n.y-22,width:158,height:44,rx:8,fill:color},root);let t=el('text',{x:n.x+offset,y:n.y+4,'text-anchor':'middle','font-size':11,fill:'white'},root);t.textContent=n.label.length>24?n.label.slice(0,21)+'...':n.label;let title=el('title',{},t);title.textContent=n.label;});document.getElementById('diagram').appendChild(root);
// Replication map uses observed partner records; no assumed connectivity.
const net=document.createElementNS(svgNS,'svg');const dcList=data.DomainControllers;const siteNames=[...new Set(data.Sites.map(s=>s.Name).concat(dcList.map(d=>d.Site||'Unknown site')))];
const count=Math.max(1,dcList.length+siteNames.length),radius=Math.max(180,count*19),cx=radius+115,cy=radius+100;net.setAttribute('viewBox',`0 0 ${cx*2} ${cy*2}`);net.setAttribute('width',cx*2);net.setAttribute('height',cy*2);
const all=[...siteNames.map(s=>({id:'site:'+s,name:s,type:'site'})),...dcList.map(d=>({id:'dc:'+d.HostName,name:d.Name,type:'dc',obj:d}))];const coords={};all.forEach((n,i)=>{let a=2*Math.PI*i/all.length-Math.PI/2;coords[n.id]={x:cx+radius*Math.cos(a),y:cy+radius*Math.sin(a)};});
const normalize=v=>String(v||'').toLowerCase().replace(/^cn=/,'').split(',')[0];
const findDC=v=>dcList.find(d=>normalize(v)===normalize(d.HostName)||normalize(v)===normalize(d.Name)||normalize(v).split('.')[0]===normalize(d.Name));
const drawEdge=(a,b,color,dash)=>{if(!coords[a]||!coords[b]||a===b)return;let p=coords[a],q=coords[b];el('line',{x1:p.x,y1:p.y,x2:q.x,y2:q.y,stroke:color,'stroke-width':2,'stroke-dasharray':dash||'none',opacity:.7},net)};
dcList.forEach(d=>drawEdge('site:'+(d.Site||'Unknown site'),'dc:'+d.HostName,'#64748b','4 5'));
(data.SiteLinks||[]).forEach(link=>{let names=(link.SitesIncluded||[]).map(v=>String(v).match(/CN=([^,]+)/i)?.[1]||String(v));for(let i=0;i<names.length;i++)for(let j=i+1;j<names.length;j++)drawEdge('site:'+names[i],'site:'+names[j],'#a78bfa','8 4');});
const seen=new Set();(data.Replication||[]).forEach(r=>{let a=findDC(r.Server),b=findDC(r.Partner);if(!a||!b)return;let key=[a.HostName,b.HostName].sort().join('|');if(seen.has(key))return;seen.add(key);let failed=(data.Replication||[]).some(z=>findDC(z.Server)?.HostName===a.HostName&&findDC(z.Partner)?.HostName===b.HostName&&Number(z.LastReplicationResult)!==0);drawEdge('dc:'+a.HostName,'dc:'+b.HostName,failed?'#ef4444':'#22c55e');});
all.forEach(n=>{let p=coords[n.id],g=el('g',{style:'cursor:pointer'},net);el('circle',{cx:p.x,cy:p.y,r:n.type==='site'?32:26,fill:n.type==='site'?'#6d28d9':'#1d4ed8',stroke:'#93c5fd','stroke-width':1.5},g);let t=el('text',{x:p.x,y:p.y+43,'text-anchor':'middle','font-size':12,fill:'#dbeafe'},g);t.textContent=n.name.length>23?n.name.slice(0,20)+'...':n.name;g.addEventListener('click',()=>{let records=n.type==='site'?{Site:n.name,Controllers:dcList.filter(d=>d.Site===n.name),SiteLinks:data.SiteLinks.filter(l=>JSON.stringify(l.SitesIncluded).includes(n.name))}:{Controller:n.obj,Connectivity:data.DCStatus.find(d=>d.HostName===n.obj.HostName),Replication:data.Replication.filter(r=>normalize(r.Server).includes(normalize(n.obj.Name))),Failures:data.ReplicationFailures.filter(r=>normalize(r.Server).includes(normalize(n.obj.Name)))};document.getElementById('detail').textContent=JSON.stringify(records,null,2);document.getElementById('detail').style.whiteSpace='pre-wrap';});});
document.getElementById('network').appendChild(net);
const legend=document.createElement('p');legend.textContent='Green: observed successful replication · Red: observed replication error · Purple dashed: configured site link · Gray dashed: site membership. Missing edges mean not discovered, not necessarily absent.';document.getElementById('network').appendChild(legend);
</script></body></html>
'@
$html=$html.Replace('__JSON__',$safeJson)
$htmlPath=Join-Path $OutputPath 'AD-Infrastructure.html'
[System.IO.File]::WriteAllText($htmlPath,$html,[System.Text.UTF8Encoding]::new($false))
Write-Host "HTML report: $htmlPath" -ForegroundColor Green
Write-Host "JSON inventory: $jsonPath" -ForegroundColor Green
