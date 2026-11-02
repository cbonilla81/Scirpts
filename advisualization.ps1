<#
     AAAAA       DDDDDD
    AA   AA      DD   DD
   AA     AA     DD    DD
   AAAAAAAAA     DD    DD
   AA     AA     DD   DD
   AA     AA     DDDDDD

                         AD ASSESSMENT

.SYNOPSIS
    Discovers Active Directory forest infrastructure and creates an HTML report.

.DESCRIPTION
    Collects forest and domain details, domain controllers, FSMO role holders,
    sites, subnets, site links, trusts, and organizational units. The resulting
    report is a self-contained HTML file and includes a forest/domain/DC diagram.
    This script only reads Active Directory data.

.PARAMETER OutputPath
    Destination for the generated HTML report.

.PARAMETER Server
    Optional domain controller used for the initial forest and domain lookup.
    The script discovers suitable controllers for the remaining domains.

.PARAMETER OpenReport
    Open the generated report in the default browser.

.EXAMPLE
    .\advisualization.ps1

.EXAMPLE
    .\advisualization.ps1 -Server dc01.contoso.com -OutputPath C:\Reports\AD.html -OpenReport
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path -Path (Get-Location).Path -ChildPath 'AD-Infrastructure-Report.html'),
    [string]$Server,
    [switch]$OpenReport
)

$ErrorActionPreference = 'Stop'

try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    throw "The ActiveDirectory PowerShell module is required. Install RSAT Active Directory tools and retry. Details: $($_.Exception.Message)"
}

Write-Host 'Discovering the Active Directory forest...'
$forestParameters = @{ ErrorAction = 'Stop' }
if ($Server) {
    $forestParameters.Server = $Server
}
$forest = Get-ADForest @forestParameters

$configurationServer = $forest.RootDomain

$domains = [System.Collections.Generic.List[object]]::new()
$domainControllers = [System.Collections.Generic.List[object]]::new()
$organizationalUnits = [System.Collections.Generic.List[object]]::new()
$trusts = [System.Collections.Generic.List[object]]::new()
$collectionErrors = [System.Collections.Generic.List[string]]::new()

$domainNames = @($forest.Domains | Sort-Object -Unique)
if ($domainNames -notcontains $forest.RootDomain) {
    $domainNames += $forest.RootDomain
}

foreach ($domainName in $domainNames) {
    Write-Host "Discovering domain $domainName..."
    try {
        $domain = Get-ADDomain -Identity $domainName -Server $domainName -ErrorAction Stop
        $domainControllersForDomain = @(Get-ADDomainController -Filter * -Server $domainName -ErrorAction Stop)

        $domains.Add([PSCustomObject]@{
            DNSRoot                   = $domain.DNSRoot
            NetBIOSName               = $domain.NetBIOSName
            ParentDomain              = $domain.ParentDomain
            DomainMode                = [string]$domain.DomainMode
            DistinguishedName         = $domain.DistinguishedName
            PDCEmulator               = $domain.PDCEmulator
            RIDMaster                 = $domain.RIDMaster
            InfrastructureMaster      = $domain.InfrastructureMaster
            DomainControllerCount     = $domainControllersForDomain.Count
        })

        foreach ($controller in $domainControllersForDomain) {
            $domainControllers.Add([PSCustomObject]@{
                HostName        = $controller.HostName
                Domain          = $domain.DNSRoot
                Site            = $controller.Site
                IPv4Address     = $controller.IPv4Address
                OperatingSystem = $controller.OperatingSystem
                IsGlobalCatalog = [bool]$controller.IsGlobalCatalog
                IsReadOnly      = [bool]$controller.IsReadOnly
                Enabled         = [bool]$controller.Enabled
            })
        }

        $ous = @(Get-ADOrganizationalUnit -Filter * -Server $domainName -Properties Description -ErrorAction Stop)
        foreach ($ou in $ous) {
            $parentDN = ''
            $separatorIndex = $ou.DistinguishedName.IndexOf(',')
            if ($separatorIndex -ge 0) {
                $parentDN = $ou.DistinguishedName.Substring($separatorIndex + 1)
            }

            $organizationalUnits.Add([PSCustomObject]@{
                Name              = $ou.Name
                DistinguishedName = $ou.DistinguishedName
                ParentDN          = $parentDN
                Domain            = $domain.DNSRoot
                Description       = $ou.Description
            })
        }

        $domainTrusts = @(Get-ADTrust -Filter * -Server $domainName -ErrorAction Stop)
        foreach ($trust in $domainTrusts) {
            $trusts.Add([PSCustomObject]@{
                Source                   = $domain.DNSRoot
                Target                   = $trust.Target
                Direction                = [string]$trust.Direction
                TrustType                = [string]$trust.TrustType
                ForestTransitive         = [bool]$trust.ForestTransitive
                SelectiveAuthentication  = [bool]$trust.SelectiveAuthentication
                SIDFilteringForestAware  = [bool]$trust.SIDFilteringForestAware
                SIDFilteringQuarantined  = [bool]$trust.SIDFilteringQuarantined
            })
        }
    }
    catch {
        $message = "Could not completely discover domain '$domainName': $($_.Exception.Message)"
        $collectionErrors.Add($message)
        Write-Warning $message
    }
}

if ($domains.Count -eq 0) {
    throw 'No domains could be discovered. Verify connectivity, credentials, and Active Directory permissions.'
}

Write-Host 'Discovering forest sites, subnets, and site links...'
try {
    $sites = @(Get-ADReplicationSite -Filter * -Server $configurationServer -ErrorAction Stop | ForEach-Object {
        [PSCustomObject]@{
            Name        = $_.Name
            Description = $_.Description
            Location    = $_.Location
        }
    })

    $subnets = @(Get-ADReplicationSubnet -Filter * -Server $configurationServer -ErrorAction Stop | ForEach-Object {
        $siteDN = [string]$_.Site
        $siteName = $siteDN
        if ($siteDN -match '^CN=([^,]+),') {
            $siteName = $Matches[1]
        }
        [PSCustomObject]@{
            Name     = $_.Name
            Site     = $siteName
            SiteDN   = $siteDN
        }
    })

    $siteLinks = @(Get-ADReplicationSiteLink -Filter * -Server $configurationServer -ErrorAction Stop | ForEach-Object {
        $includedSites = @($_.SitesIncluded | ForEach-Object {
            $siteDN = [string]$_
            if ($siteDN -match '^CN=([^,]+),') {
                $Matches[1]
            }
            else {
                $siteDN
            }
        })
        [PSCustomObject]@{
            Name                           = $_.Name
            Sites                          = $includedSites
            Cost                           = $_.Cost
            ReplicationFrequencyInMinutes  = $_.ReplicationFrequencyInMinutes
            InterSiteTopologyGenerator     = $_.InterSiteTopologyGenerator
        }
    })
}
catch {
    $message = "Could not completely discover forest site topology: $($_.Exception.Message)"
    $collectionErrors.Add($message)
    Write-Warning $message
    $sites = @()
    $subnets = @()
    $siteLinks = @()
}

$fsmoroles = @(
    [PSCustomObject]@{ Role = 'Schema Master'; Scope = 'Forest'; Holder = $forest.SchemaMaster }
    [PSCustomObject]@{ Role = 'Domain Naming Master'; Scope = 'Forest'; Holder = $forest.DomainNamingMaster }
)
foreach ($domain in $domains) {
    $fsmoroles += @(
        [PSCustomObject]@{ Role = 'PDC Emulator'; Scope = $domain.DNSRoot; Holder = $domain.PDCEmulator }
        [PSCustomObject]@{ Role = 'RID Master'; Scope = $domain.DNSRoot; Holder = $domain.RIDMaster }
        [PSCustomObject]@{ Role = 'Infrastructure Master'; Scope = $domain.DNSRoot; Holder = $domain.InfrastructureMaster }
    )
}

$reportData = [PSCustomObject]@{
    GeneratedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')
    Forest      = [PSCustomObject]@{
        Name                 = $forest.Name
        RootDomain           = $forest.RootDomain
        ForestMode           = [string]$forest.ForestMode
        Domains              = @($domains)
        Sites                = @($sites)
        Subnets              = @($subnets)
        SiteLinks            = @($siteLinks)
        DomainControllers    = @($domainControllers)
        FSMORoles            = @($fsmoroles)
        Trusts               = @($trusts)
        OrganizationalUnits  = @($organizationalUnits)
        Errors               = @($collectionErrors)
    }
}

$json = ConvertTo-Json -InputObject $reportData -Depth 8 -Compress
$json = $json.Replace('&', '\u0026').Replace('<', '\u003c').Replace('>', '\u003e')

$html = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Active Directory Infrastructure Report</title>
<style>
:root{color-scheme:light;--ink:#172b4d;--muted:#5e6c84;--line:#dfe4ec;--blue:#174ea6;--pale:#f4f7fb;--orange:#d97706}
*{box-sizing:border-box}body{margin:0;background:#f5f7fa;color:var(--ink);font:14px/1.5 "Segoe UI",Arial,sans-serif}
header{padding:28px max(24px,calc((100vw - 1440px)/2));background:#123b67;color:#fff}
header h1{margin:0 0 4px;font-size:26px}header p{margin:0;color:#d8e7f8}
main{max-width:1440px;margin:22px auto;padding:0 24px 40px}
.summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-bottom:20px}
.metric,.panel{background:white;border:1px solid var(--line);border-radius:9px;box-shadow:0 2px 7px #102b4d0a}
.metric{padding:15px 17px}.metric strong{display:block;font-size:25px;color:var(--blue)}.metric span{color:var(--muted)}
.panel{padding:18px 20px;margin:14px 0}.panel h2{margin:0 0 14px;font-size:18px}.subtle{color:var(--muted)}
.diagram-scroll{overflow-x:auto;background:var(--pale);border-radius:7px;padding:12px}.diagram-scroll svg{display:block;max-width:none}
.legend{font-size:12px;color:var(--muted);margin-top:8px}
.tabs{display:flex;flex-wrap:wrap;gap:7px;margin:12px 0}.tabs button{border:1px solid var(--line);border-radius:6px;background:#fff;color:var(--ink);padding:8px 12px;cursor:pointer}
.tabs button[aria-selected=true]{background:var(--blue);border-color:var(--blue);color:#fff}
.tab-content[hidden]{display:none}.table-wrap{overflow:auto}table{width:100%;border-collapse:collapse;min-width:620px}th,td{text-align:left;padding:9px 10px;border-bottom:1px solid var(--line);vertical-align:top}th{background:var(--pale);color:#334563;position:sticky;top:0}
input[type=search]{width:min(100%,380px);padding:9px 11px;border:1px solid #b7c2d0;border-radius:6px;margin-bottom:10px}
.tree{list-style:none;margin:0;padding-left:18px}.tree li{margin:4px 0}.tree details{margin:3px 0}.tree summary{cursor:pointer}.badge{display:inline-block;background:#eaf1fc;color:#234a83;border-radius:12px;padding:1px 8px;font-size:12px;margin-left:5px}
.notice{padding:11px 14px;border-left:4px solid var(--orange);background:#fff7e6;margin:12px 0;border-radius:3px}.notice.error{border-color:#b42318;background:#fff0ef}
footer{color:var(--muted);text-align:center;padding:20px;font-size:12px}
@media(max-width:650px){main{padding:0 12px 24px}.panel{padding:14px}.summary{grid-template-columns:repeat(2,minmax(0,1fr))}}
</style>
</head>
<body>
<header><h1>Active Directory Infrastructure</h1><p id="subtitle">Forest discovery report</p></header>
<main>
<div id="notices"></div>
<section class="summary" id="summary"></section>
<section class="panel"><h2>Forest and domain controller topology</h2><div class="diagram-scroll"><svg id="topology" role="img" aria-label="Forest, domains, and domain controllers"></svg></div><div class="legend">Domain controller cards show site, IPv4 address, and global catalog status where available.</div></section>
<section class="panel"><h2>Infrastructure inventory</h2>
<div class="tabs" role="tablist" aria-label="Infrastructure data">
<button role="tab" aria-selected="true" data-tab="sites">Sites &amp; subnets</button><button role="tab" aria-selected="false" data-tab="links">Site links</button><button role="tab" aria-selected="false" data-tab="trusts">Trusts</button><button role="tab" aria-selected="false" data-tab="fsmo">FSMO roles</button><button role="tab" aria-selected="false" data-tab="ous">Organizational units</button>
</div>
<section class="tab-content" id="tab-sites" role="tabpanel"></section><section class="tab-content" id="tab-links" role="tabpanel" hidden></section><section class="tab-content" id="tab-trusts" role="tabpanel" hidden></section><section class="tab-content" id="tab-fsmo" role="tabpanel" hidden></section><section class="tab-content" id="tab-ous" role="tabpanel" hidden></section>
</section>
<footer>Generated <span id="generated"></span>. This report is a point-in-time snapshot.</footer>
</main>
<script id="report-data" type="application/json">__DATA__</script>
<script>
(() => {
  "use strict";
  const report = JSON.parse(document.getElementById("report-data").textContent);
  const forest = report.Forest;
  const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, char => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[char]));
  const rows = (headers, data) => {
    if (!data.length) return '<p class="subtle">No records found.</p>';
    return `<div class="table-wrap"><table><thead><tr>${headers.map(h => `<th>${escapeHtml(h.label)}</th>`).join("")}</tr></thead><tbody>${data.map(row => `<tr>${headers.map(h => `<td>${escapeHtml(typeof h.value === "function" ? h.value(row) : row[h.value])}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`;
  };
  document.getElementById("subtitle").textContent = `${forest.Name} · Root domain: ${forest.RootDomain} · Forest mode: ${forest.ForestMode}`;
  document.getElementById("generated").textContent = report.GeneratedAt;
  document.getElementById("summary").innerHTML = [
    ["Domains", forest.Domains.length], ["Domain controllers", forest.DomainControllers.length],
    ["Sites", forest.Sites.length], ["Subnets", forest.Subnets.length],
    ["Site links", forest.SiteLinks.length], ["Organizational units", forest.OrganizationalUnits.length]
  ].map(([label, value]) => `<div class="metric"><strong>${value}</strong><span>${label}</span></div>`).join("");
  const notices = document.getElementById("notices");
  if (forest.Errors.length) notices.innerHTML = `<div class="notice error"><strong>Partial discovery:</strong><ul>${forest.Errors.map(e => `<li>${escapeHtml(e)}</li>`).join("")}</ul></div>`;

  const svg = document.getElementById("topology");
  const ns = "http://www.w3.org/2000/svg";
  const node = (name, attrs, parent = svg) => {
    const el = document.createElementNS(ns, name);
    Object.entries(attrs).forEach(([key, value]) => el.setAttribute(key, value));
    parent.appendChild(el);
    return el;
  };
  const addText = (parent, x, y, text, size = 13, weight = "400", color = "#172b4d") => {
    const el = node("text", {x, y, "font-size": size, "font-weight": weight, fill: color}, parent);
    el.textContent = text;
    return el;
  };
  const domains = forest.Domains;
  const cardWidth = 258, gap = 22, cardHeight = 206, left = 28, top = 145;
  const width = Math.max(680, left * 2 + domains.length * cardWidth + Math.max(0, domains.length - 1) * gap);
  const height = top + cardHeight + 30;
  svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
  svg.setAttribute("width", width);
  svg.setAttribute("height", height);
  const rootX = width / 2 - 150, rootY = 20;
  domains.forEach((domain, index) => {
    const x = left + index * (cardWidth + gap) + cardWidth / 2;
    node("path", {d: `M ${width / 2} 84 V 112 H ${x} V ${top}`, fill: "none", stroke: "#91a2b8", "stroke-width": 2});
  });
  node("rect", {x: rootX, y: rootY, width: 300, height: 64, rx: 9, fill: "#174ea6"});
  addText(svg, width / 2, 47, `Forest: ${forest.Name}`, 16, "600", "#ffffff").setAttribute("text-anchor", "middle");
  addText(svg, width / 2, 68, `Root: ${forest.RootDomain}`, 12, "400", "#e8f0fe").setAttribute("text-anchor", "middle");
  domains.forEach((domain, index) => {
    const x = left + index * (cardWidth + gap), y = top;
    node("rect", {x, y, width: cardWidth, height: cardHeight, rx: 8, fill: "#ffffff", stroke: "#9aabc0", "stroke-width": 1.5});
    node("path", {d: `M ${x} ${y + 51} H ${x + cardWidth}`, stroke: "#dfe4ec"});
    addText(svg, x + 12, y + 27, domain.DNSRoot, 13, "600");
    addText(svg, x + 12, y + 44, `${domain.NetBIOSName} · ${domain.DomainMode}`, 10, "400", "#5e6c84");
    const controllers = forest.DomainControllers.filter(dc => dc.Domain === domain.DNSRoot);
    addText(svg, x + 12, y + 72, `Domain controllers (${controllers.length})`, 11, "600", "#334563");
    const visible = controllers.slice(0, 6);
    visible.forEach((dc, dcIndex) => {
      const shortName = dc.HostName || "(unknown host)";
      const details = [dc.Site, dc.IPv4Address, dc.IsGlobalCatalog ? "GC" : ""].filter(Boolean).join(" · ");
      addText(svg, x + 14, y + 94 + dcIndex * 17, `- ${shortName}`, 10);
      if (details) addText(svg, x + 22, y + 106 + dcIndex * 17, details, 9, "400", "#5e6c84");
    });
    if (controllers.length > visible.length) addText(svg, x + 12, y + cardHeight - 10, `...and ${controllers.length - visible.length} more`, 10, "400", "#5e6c84");
    if (!controllers.length) addText(svg, x + 12, y + 96, "No controller details collected", 10, "400", "#5e6c84");
  });

  const siteData = forest.Sites.map(site => {
    const subnets = forest.Subnets.filter(subnet => subnet.Site === site.Name).map(subnet => subnet.Name).join(", ");
    const controllers = forest.DomainControllers.filter(dc => dc.Site === site.Name).map(dc => dc.HostName).join(", ");
    return {Name: site.Name, Location: site.Location, Subnets: subnets, DomainControllers: controllers};
  });
  const knownSites = new Set(forest.Sites.map(site => site.Name));
  const unassignedSubnets = forest.Subnets.filter(subnet => !knownSites.has(subnet.Site));
  if (unassignedSubnets.length) {
    siteData.push({Name:"Unassigned subnets", Location:"", Subnets:unassignedSubnets.map(subnet => subnet.Name).join(", "), DomainControllers:""});
  }
  document.getElementById("tab-sites").innerHTML = rows([
    {label:"Site", value:"Name"}, {label:"Location", value:"Location"},
    {label:"Subnets", value:"Subnets"}, {label:"Domain controllers", value:"DomainControllers"}
  ], siteData);
  document.getElementById("tab-links").innerHTML = rows([
    {label:"Site link", value:"Name"}, {label:"Sites", value:r => (r.Sites || []).join(", ")},
    {label:"Cost", value:"Cost"}, {label:"Replication interval (minutes)", value:"ReplicationFrequencyInMinutes"}
  ], forest.SiteLinks);
  document.getElementById("tab-trusts").innerHTML = rows([
    {label:"Source domain", value:"Source"}, {label:"Target", value:"Target"},
    {label:"Direction", value:"Direction"}, {label:"Type", value:"TrustType"},
    {label:"Forest transitive", value:r => r.ForestTransitive ? "Yes" : "No"},
    {label:"Selective authentication", value:r => r.SelectiveAuthentication ? "Yes" : "No"}
  ], forest.Trusts);
  document.getElementById("tab-fsmo").innerHTML = rows([
    {label:"Role", value:"Role"}, {label:"Scope", value:"Scope"}, {label:"Holder", value:"Holder"}
  ], forest.FSMORoles);

  const ouTab = document.getElementById("tab-ous");
  const ouGroups = new Map();
  forest.OrganizationalUnits.forEach(ou => {
    const key = ou.Domain;
    if (!ouGroups.has(key)) ouGroups.set(key, []);
    ouGroups.get(key).push(ou);
  });
  if (!forest.OrganizationalUnits.length) {
    ouTab.innerHTML = '<p class="subtle">No organizational units found.</p>';
  } else {
    ouTab.innerHTML = '<input type="search" id="ou-search" placeholder="Filter organizational units by name or domain"><div id="ou-tree"></div>';
    const renderTree = filter => {
      const normalized = filter.toLowerCase();
      const sections = [];
      ouGroups.forEach((ous, domainName) => {
        const included = ous.filter(ou => `${ou.Name} ${ou.Domain} ${ou.DistinguishedName}`.toLowerCase().includes(normalized));
        if (!included.length) return;
        const visibleDns = new Set(included.map(ou => ou.DistinguishedName));
        const byParent = new Map();
        included.forEach(ou => {
          const parentKey = visibleDns.has(ou.ParentDN) ? ou.ParentDN : "";
          if (!byParent.has(parentKey)) byParent.set(parentKey, []);
          byParent.get(parentKey).push(ou);
        });
        const build = parentDN => {
          const children = byParent.get(parentDN) || [];
          if (!children.length) return "";
          return `<ul class="tree">${children.map(ou => `<li><details ${filter ? "open" : ""}><summary>${escapeHtml(ou.Name)}<span class="badge">${escapeHtml(ou.Domain)}</span></summary><div class="subtle">${escapeHtml(ou.DistinguishedName)}</div>${ou.Description ? `<div>${escapeHtml(ou.Description)}</div>` : ""}${build(ou.DistinguishedName)}</details></li>`).join("")}</ul>`;
        };
        sections.push(`<details open><summary><strong>${escapeHtml(domainName)}</strong><span class="badge">${included.length} OUs</span></summary>${build("")}</details>`);
      });
      document.getElementById("ou-tree").innerHTML = sections.join("") || '<p class="subtle">No matching organizational units.</p>';
    };
    renderTree("");
    document.getElementById("ou-search").addEventListener("input", event => renderTree(event.target.value));
  }

  document.querySelectorAll(".tabs [role=tab]").forEach(button => {
    button.addEventListener("click", () => {
      document.querySelectorAll(".tabs [role=tab]").forEach(tab => tab.setAttribute("aria-selected", String(tab === button)));
      document.querySelectorAll(".tab-content").forEach(panel => { panel.hidden = panel.id !== `tab-${button.dataset.tab}`; });
    });
  });
})();
</script>
</body>
</html>
'@

$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = [System.IO.Path]::GetDirectoryName($outputFullPath)
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force -ErrorAction Stop | Out-Null
}
$html = $html.Replace('__DATA__', $json)
[System.IO.File]::WriteAllText($outputFullPath, $html, [System.Text.UTF8Encoding]::new($false))

Write-Host "Report created: $outputFullPath"
if ($collectionErrors.Count -gt 0) {
    Write-Warning "The report contains partial-discovery warnings ($($collectionErrors.Count)). Review the report's notices section."
}
if ($OpenReport) {
    Start-Process -FilePath $outputFullPath
}