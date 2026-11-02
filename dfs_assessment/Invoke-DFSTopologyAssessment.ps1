#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Get-Location) 'DFSAssessment'),
    [string[]]$NamespaceRoots,
    [switch]$SkipBacklog,
    [int]$MaxBacklogChecks = 150
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$warnings = New-Object System.Collections.Generic.List[object]
function Add-Warning([string]$Area,[string]$Message) {
    $warnings.Add([pscustomobject]@{ Area=$Area; Message=$Message })
    Write-Warning "[$Area] $Message"
}
function Safe-Run([string]$Area,[scriptblock]$Action) {
    try { @(& $Action) } catch { Add-Warning $Area $_.Exception.Message; @() }
}
foreach ($module in @('DFSN','DFSR')) {
    try { Import-Module $module -ErrorAction Stop }
    catch { Add-Warning $module "Module unavailable: $($_.Exception.Message)" }
}
$roots = @()
if ($NamespaceRoots -and $NamespaceRoots.Count -gt 0) {
    foreach ($root in $NamespaceRoots) {
        $roots += Safe-Run "Root $root" { Get-DfsnRoot -Path $root -ErrorAction Stop }
    }
} elseif (Get-Command Get-DfsnRoot -ErrorAction SilentlyContinue) {
    $roots = @(Safe-Run 'DFS roots' { Get-DfsnRoot -ErrorAction Stop })
}
$rootTargets = @(); $folders = @(); $folderTargets = @()
foreach ($root in $roots) {
    $path = [string]$root.Path
    $rootTargets += Safe-Run "Root targets $path" { Get-DfsnRootTarget -Path $path -ErrorAction Stop |
        Select-Object @{n='RootPath';e={$path}},Path,TargetPath,State }
    $theseFolders = @(Safe-Run "Folders $path" { Get-DfsnFolder -Path ($path.TrimEnd('\') + '\*') -ErrorAction Stop })
    $folders += $theseFolders | Select-Object Path,State,TimeToLive
    foreach ($folder in $theseFolders) {
        $folderPath = [string]$folder.Path
        $folderTargets += Safe-Run "Folder targets $folderPath" { Get-DfsnFolderTarget -Path $folderPath -ErrorAction Stop |
            Select-Object @{n='FolderPath';e={$folderPath}},Path,TargetPath,State }
    }
}
$groups = @(); $members = @(); $connections = @(); $replicatedFolders = @(); $memberships = @()
if (Get-Command Get-DfsReplicationGroup -ErrorAction SilentlyContinue) {
    $groups = @(Safe-Run 'DFSR groups' { Get-DfsReplicationGroup -ErrorAction Stop })
    foreach ($group in $groups) {
        $name = [string]$group.GroupName
        $members += Safe-Run "Members $name" { Get-DfsrMember -GroupName $name -ErrorAction Stop |
            Select-Object GroupName,ComputerName,DnsName,DomainName }
        $connections += Safe-Run "Connections $name" { Get-DfsrConnection -GroupName $name -ErrorAction Stop |
            Select-Object GroupName,SourceComputerName,DestinationComputerName,Enabled,ConnectionType }
        $replicatedFolders += Safe-Run "Replicated folders $name" { Get-DfsReplicatedFolder -GroupName $name -ErrorAction Stop |
            Select-Object GroupName,FolderName,Description,State }
        $memberships += Safe-Run "Memberships $name" { Get-DfsrMembership -GroupName $name -ErrorAction Stop |
            Select-Object GroupName,FolderName,ComputerName,ContentPath,StagingPath,StagingPathQuotaInMB,Enabled,ReadOnly,PrimaryMember }
    }
}
$backlogs = @(); $checks = 0
if (-not $SkipBacklog -and (Get-Command Get-DfsrBacklog -ErrorAction SilentlyContinue)) {
    foreach ($connection in $connections) {
        if ($connection.Enabled -eq $false) { continue }
        foreach ($folder in @($replicatedFolders | Where-Object { $_.GroupName -eq $connection.GroupName })) {
            if ($checks -ge $MaxBacklogChecks) { break }
            $checks++
            $groupName = [string]$connection.GroupName
            $folderName = [string]$folder.FolderName
            $src = [string]$connection.SourceComputerName
            $dst = [string]$connection.DestinationComputerName
            try {
                $raw = @(Get-DfsrBacklog -GroupName $groupName -FolderName $folderName -SourceComputerName $src -DestinationComputerName $dst -ErrorAction Stop 4>&1)
                $summary = ($raw | Out-String).Trim()
                $count = $null
                if ($summary -match '(?i)backlog\s+count\s*:\s*(\d+)') { $count = [int]$Matches[1] }
                $backlogs += [pscustomobject]@{ GroupName=$groupName; FolderName=$folderName; Source=$src; Destination=$dst; BacklogCount=$count; Status='Queried'; Detail=$summary.Substring(0,[Math]::Min($summary.Length,400)) }
            } catch {
                $backlogs += [pscustomobject]@{ GroupName=$groupName; FolderName=$folderName; Source=$src; Destination=$dst; BacklogCount=$null; Status='Failed'; Detail=$_.Exception.Message }
                Add-Warning 'Backlog' "$groupName/$folderName $src -> $dst : $($_.Exception.Message)"
            }
        }
        if ($checks -ge $MaxBacklogChecks) { break }
    }
    if ($checks -ge $MaxBacklogChecks) { Add-Warning 'Backlog' "Stopped at MaxBacklogChecks=$MaxBacklogChecks; results may be incomplete." }
}
$report = [ordered]@{
    GeneratedAt=(Get-Date).ToString('o'); Computer=$env:COMPUTERNAME
    Roots=@($roots | Select-Object Path,Type,State,Description)
    RootTargets=@($rootTargets); Folders=@($folders); FolderTargets=@($folderTargets)
    ReplicationGroups=@($groups | Select-Object GroupName,DomainName,Description)
    Members=@($members); Connections=@($connections)
    ReplicatedFolders=@($replicatedFolders); Memberships=@($memberships)
    Backlogs=@($backlogs); Warnings=@($warnings)
}
$json = ConvertTo-Json -InputObject $report -Depth 12 -Compress
$jsonPath = Join-Path $OutputDirectory 'DFS-Assessment.json'
[System.IO.File]::WriteAllText($jsonPath, $json, [System.Text.UTF8Encoding]::new($false))
# Encode JSON as base64 to prevent HTML/script injection from discovered names and paths.
$payload = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
$html = @'
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>DFS Infrastructure Assessment</title>
<style>
:root{font-family:Segoe UI,Arial,sans-serif;color:#17283c;background:#f3f6fb}*{box-sizing:border-box}body{margin:0}.hero{background:linear-gradient(120deg,#102c51,#1c76a2);color:#fff;padding:32px 5%}.hero h1{margin:0;font-size:30px}.hero p{opacity:.85}.wrap{max-width:1400px;margin:auto;padding:24px}.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:14px}.card,.panel{background:white;border:1px solid #dce5ef;border-radius:13px;padding:20px;box-shadow:0 4px 14px #152f4b09}.num{font-size:30px;font-weight:750;color:#166b9b}.muted{color:#607489;font-size:13px}.panel{margin-top:20px;overflow:auto}.panel h2{margin-top:0}.controls{display:flex;gap:10px;flex-wrap:wrap;align-items:center}button,input,select{padding:10px;border:1px solid #cbd8e4;border-radius:8px;background:#fff}button{cursor:pointer}button.active{background:#176b99;color:#fff}table{border-collapse:collapse;width:100%;font-size:13px}th,td{padding:10px;border-bottom:1px solid #e5ebf2;text-align:left;vertical-align:top;overflow-wrap:anywhere}th{background:#edf3f8;position:sticky;top:0}svg{width:100%;height:auto;min-height:240px}svg text{font-family:Segoe UI,Arial,sans-serif}.notice{border-left:4px solid #d6921c;background:#fff8e9;padding:12px;margin:12px 0}#graph{overflow:auto}#graph svg{min-width:750px}footer{padding:30px;color:#607489;text-align:center}
</style></head><body><header class="hero"><h1>DFS Infrastructure Assessment</h1><p>Namespace topology • Replication configuration • Backlog sampling • Discovery warnings</p><div id="meta"></div></header><main class="wrap"><div id="cards" class="cards"></div><section class="panel"><h2>Topology visualization</h2><div class="controls"><button class="active" data-mode="namespace">Namespace targets</button><button data-mode="replication">DFSR connections</button><span class="muted">Logical configuration, not a network map or proof of active replication</span></div><div id="graph"></div></section><section class="panel"><h2>Inventory and findings</h2><div class="controls"><select id="dataset"></select><input id="filter" placeholder="Filter table rows" aria-label="Filter table rows"><button id="export">Export visible rows (CSV)</button></div><p id="rowCount" class="muted"></p><div id="table"></div></section><section class="panel"><h2>Assessment guidance</h2><div id="findings"></div></section></main><footer>Read-only DFS discovery • Point-in-time assessment • Review warnings before operational decisions</footer>
<script>
const data=JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('__PAYLOAD__'),c=>c.charCodeAt(0))));
const datasets=['Roots','RootTargets','Folders','FolderTargets','ReplicationGroups','Members','Connections','ReplicatedFolders','Memberships','Backlogs','Warnings'];
const el=id=>document.getElementById(id);const str=v=>v===null||v===undefined?'':String(v);
function node(tag,txt){let n=document.createElement(tag);n.textContent=str(txt);return n}
function summary(){el('meta').textContent=`Generated ${data.GeneratedAt} on ${data.Computer}`;const cards=[['Namespaces',data.Roots.length],['Namespace folders',data.Folders.length],['Folder targets',data.FolderTargets.length],['Replication groups',data.ReplicationGroups.length],['DFSR connections',data.Connections.length],['Warnings',data.Warnings.length]];for(const [label,value] of cards){let c=node('div','');c.className='card';let n=node('div',value);n.className='num';let l=node('div',label);l.className='muted';c.append(n,l);el('cards').append(c)}}
let current=[];function table(){let key=el('dataset').value;let q=el('filter').value.toLowerCase();current=(data[key]||[]).filter(x=>JSON.stringify(x).toLowerCase().includes(q));el('rowCount').textContent=`${current.length} of ${data[key].length} rows`;let container=el('table');container.replaceChildren();if(!current.length){container.append(node('p','No matching records.'));return}let cols=[...new Set(current.flatMap(Object.keys))];let t=document.createElement('table'),h=document.createElement('tr');cols.forEach(c=>h.append(node('th',c)));t.append(h);for(let r of current.slice(0,3000)){let tr=document.createElement('tr');cols.forEach(c=>tr.append(node('td',r[c])));t.append(tr)}container.append(t);if(current.length>3000)container.append(node('p','Showing first 3,000 rows; CSV exports all filtered rows.'))}
function csv(){let cols=[...new Set(current.flatMap(Object.keys))];let quote=x=>'"'+str(x).replace(/"/g,'""')+'"';let lines=[cols.map(quote).join(','),...current.map(r=>cols.map(c=>quote(r[c])).join(','))];let url=URL.createObjectURL(new Blob(['\ufeff'+lines.join('\r\n')],{type:'text/csv;charset=utf-8'}));let a=document.createElement('a');a.href=url;a.download='DFS-'+el('dataset').value+'.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)}
const NS='http://www.w3.org/2000/svg';function shape(svg,tag,attrs,txt){let x=document.createElementNS(NS,tag);for(let [k,v] of Object.entries(attrs))x.setAttribute(k,v);if(txt!==undefined)x.textContent=txt;svg.append(x);return x}
function graph(mode){let edges=[],names=new Set();if(mode==='namespace'){for(let x of data.RootTargets){let a=x.RootPath,b=x.TargetPath;if(a&&b){names.add(a);names.add(b);edges.push([a,b])}}for(let x of data.FolderTargets){let a=x.FolderPath,b=x.TargetPath;if(a&&b){names.add(a);names.add(b);edges.push([a,b])}}}else{for(let x of data.Connections){let a=x.SourceComputerName,b=x.DestinationComputerName;if(a&&b){names.add(a);names.add(b);edges.push([a,b])}}}let list=[...names].slice(0,110),index=new Map(list.map((x,i)=>[x,i]));let h=Math.max(290,Math.ceil(list.length/4)*92+55),svg=document.createElementNS(NS,'svg');svg.setAttribute('viewBox',`0 0 1000 ${h}`);svg.setAttribute('role','img');svg.setAttribute('aria-label',mode+' topology');let pos=i=>({x:130+(i%4)*245,y:48+Math.floor(i/4)*92});for(let [a,b] of edges){if(!index.has(a)||!index.has(b))continue;let p=pos(index.get(a)),q=pos(index.get(b));shape(svg,'line',{x1:p.x,y1:p.y,x2:q.x,y2:q.y,stroke:'#90a7bd','stroke-width':1.4})}list.forEach((name,i)=>{let p=pos(i);shape(svg,'rect',{x:p.x-108,y:p.y-20,width:216,height:43,rx:8,fill:mode==='namespace'?'#e1f2ff':'#e5f7ef',stroke:mode==='namespace'?'#2a7aaf':'#25926a'});let label=name.length>29?name.slice(0,26)+'…':name;let text=shape(svg,'text',{x:p.x,y:p.y+4,'text-anchor':'middle','font-size':12,fill:'#1b334c'},label);let title=document.createElementNS(NS,'title');title.textContent=name;text.append(title)});el('graph').replaceChildren(svg);if(names.size>110)el('graph').append(node('p','Diagram limited to first 110 nodes. Full inventory is available in tables and JSON.'));if(!list.length)el('graph').append(node('p','No topology edges discovered. Check permissions and discovery warnings.'))}
function findings(){let f=el('findings');let checks=[];if(data.Warnings.length)checks.push(`${data.Warnings.length} discovery or query warning(s). Check the Warnings table.`);if(data.Connections.some(x=>x.Enabled===false))checks.push('Disabled DFSR connections were detected.');if(data.Memberships.some(x=>x.Enabled===false))checks.push('Disabled DFSR memberships were detected.');if(data.Backlogs.some(x=>x.Status==='Failed'))checks.push('One or more DFSR backlog queries failed; unknown does not mean healthy.');if(data.Backlogs.some(x=>typeof x.BacklogCount==='number'&&x.BacklogCount>0))checks.push('Nonzero replication backlog was observed on one or more sampled connections.');if(!data.Roots.length)checks.push('No namespace roots discovered; confirm module availability, permissions and domain context.');if(!data.ReplicationGroups.length)checks.push('No DFSR groups discovered; this can also mean DFSR is not used or is inaccessible.');if(!checks.length)checks.push('No flagged conditions in collected configuration. This is not a comprehensive DFS health certification.');for(let x of checks){let d=node('div',x);d.className='notice';f.append(d)}}
summary();for(let key of datasets){let o=node('option',`${key} (${data[key].length})`);o.value=key;el('dataset').append(o)}el('dataset').value='FolderTargets';el('dataset').addEventListener('change',table);el('filter').addEventListener('input',table);el('export').addEventListener('click',csv);document.querySelectorAll('[data-mode]').forEach(b=>b.addEventListener('click',()=>{document.querySelectorAll('[data-mode]').forEach(x=>x.classList.remove('active'));b.classList.add('active');graph(b.dataset.mode)}));table();graph('namespace');findings();
</script></body></html>
'@
$html = $html.Replace('__PAYLOAD__',$payload)
$htmlPath = Join-Path $OutputDirectory 'DFS-Assessment.html'
[System.IO.File]::WriteAllText($htmlPath,$html,[System.Text.UTF8Encoding]::new($false))
Write-Host "HTML report: $htmlPath" -ForegroundColor Green
Write-Host "JSON inventory: $jsonPath" -ForegroundColor Green
